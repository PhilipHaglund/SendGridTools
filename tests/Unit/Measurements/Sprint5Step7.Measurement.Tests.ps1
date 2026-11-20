BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/NetworkTripwire.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/SessionHelpers.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/PromptCountingHost.ps1')
    # Import once per run: in Windows PowerShell 5.1 a class stays bound to the first loaded module instance.
    if (-not (Get-Module -Name SendGridTools)) {
        Get-Module -Name SendGridTools -ListAvailable | Select-Object -First 1 | Import-Module -ErrorAction Stop
    }
    Enable-SgtNetworkTripwire
    Assert-SgtNetworkTripwireActive
    Install-SgtSessionHelper
    $script:Cred = [pscredential]::new('apikey', (ConvertTo-SecureString -String 'test-key-not-real' -AsPlainText -Force))
    $script:PlainFixture = Join-Path -Path $PSScriptRoot -ChildPath '../Fixtures/subusers-page.json'

    # One text per logged call: the method, the path and the query that would go on the wire.
    function script:Get-SgtM7Request {
        param([object[]]$Calls)
        if ($Calls.Count -eq 0) { return 'requests 0' }
        $Parts = foreach ($Call in $Calls) {
            $Uri = [uri]$Call.Uri
            'method {0} path {1} query {2}' -f $Call.Method, $Uri.AbsolutePath, $(if ($Uri.Query) { $Uri.Query } else { 'none' })
        }
        'requests {0}; {1}' -f $Calls.Count, ($Parts -join ' | ')
    }

    function script:Get-SgtM7Error {
        param([object[]]$Caught)
        if ($Caught.Count -eq 0) { return 'errors 0' }
        $Parts = foreach ($Item in $Caught) {
            '{0} ({1})' -f $Item.Exception.GetType().FullName, $Item.FullyQualifiedErrorId
        }
        'errors {0}; {1}' -f $Caught.Count, ($Parts -join ' | ')
    }

    # Runs Get-SGSubuser in module scope with the recorded page as answer. A terminating error is caught, and
    # the error stream is read with 2>&1: an error from binding piped input reaches only that stream, not
    # -ErrorVariable. Warnings are kept.
    function script:Invoke-SgtM7Case {
        param([hashtable]$Splat, [object[]]$PipeInput, [switch]$Pipe)
        InModuleScope SendGridTools -Parameters @{ Fixture = $script:PlainFixture; Splat = $Splat; PipeInput = $PipeInput; Pipe = [bool]$Pipe } {
            Set-SgtNetworkStub -Response (Get-Content -LiteralPath $Fixture -Raw | ConvertFrom-Json)
            $Caught = [System.Collections.Generic.List[object]]::new()
            $Warned = $null
            $Stream = @()
            try {
                if ($Pipe) {
                    $Stream = @($PipeInput | Get-SGSubuser @Splat -Confirm:$false -ErrorAction Continue -WarningVariable Warned -WarningAction SilentlyContinue 2>&1)
                }
                else {
                    $Stream = @(Get-SGSubuser @Splat -Confirm:$false -ErrorAction Continue -WarningVariable Warned -WarningAction SilentlyContinue 2>&1)
                }
            }
            catch { $Caught.Add($_) }
            foreach ($E in @($Stream | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })) { $Caught.Add($E) }
            $Out = @($Stream | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })
            @{ Calls = @(Get-SgtNetworkCall)[0]; Caught = $Caught.ToArray(); Warned = @($Warned); OutCount = $Out.Count }
        }
    }

    function script:Format-SgtM7Case {
        param($Result)
        $WarningText = if ($Result.Warned.Count) { (@($Result.Warned | ForEach-Object { "$_" }) -join ' | ') } else { 'none' }
        '{0}; output {1}; warnings {2}; warning text {3}; {4}' -f (Get-SgtM7Request -Calls $Result.Calls), $Result.OutCount,
            $Result.Warned.Count, $WarningText, (Get-SgtM7Error -Caught $Result.Caught)
    }
}

AfterAll {
    Uninstall-SgtSessionHelper
    Disable-SgtNetworkTripwire
}

# Sprint 5 step 7 measurements (M1-M5). Each It writes one MEASURE line with command names, counts, made-up values,
# error types, warning text and True/False only, and asserts nothing about the measured value, so the same file
# measures any version of the module. Invoke-RestMethod is answered by the tripwire's stub, which logs the Uri.
Describe 'Sprint 5 step 7 measurements' {
    BeforeEach {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
        }
    }
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'M1: the request for an empty name <Case>' -ForEach @(
        @{ Case = "-Username ''"; Splat = @{ Username = '' }; Pipe = $false; PipeInput = $null }
        @{ Case = '-Username $null'; Splat = @{ Username = $null }; Pipe = $false; PipeInput = $null }
        @{ Case = "piped by property Username ''"; Splat = @{}; Pipe = $true; PipeInput = @([pscustomobject]@{ Username = '' }) }
        @{ Case = "piped by property Username '' then 'sgt-test-abc'"; Splat = @{}; Pipe = $true; PipeInput = @([pscustomobject]@{ Username = '' }, [pscustomobject]@{ Username = 'sgt-test-abc' }) }
    ) {
        $Result = Invoke-SgtM7Case -Splat $Splat -PipeInput $PipeInput -Pipe:$Pipe
        $Text = Format-SgtM7Case -Result $Result
        Write-Host ('MEASURE M1 [{0} {1}] {2}: {3}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Case, $Text)
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
        $Text | Should -Not -BeNullOrEmpty
    }

    It 'M2: the request for <Case>' -ForEach @(
        @{ Case = '-Limit 0'; Splat = @{ Limit = 0 } }
        @{ Case = '-Limit -1'; Splat = @{ Limit = -1 } }
        @{ Case = '-Offset 0'; Splat = @{ Offset = 0 } }
        @{ Case = '-Offset -1'; Splat = @{ Offset = -1 } }
    ) {
        $Result = Invoke-SgtM7Case -Splat $Splat
        $Text = Format-SgtM7Case -Result $Result
        Write-Host ('MEASURE M2 [{0} {1}] {2}: {3}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Case, $Text)
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
        $Text | Should -Not -BeNullOrEmpty
    }

    It 'M3: the request and warnings for <Case>' -ForEach @(
        @{ Case = "-Username 'sgt-test-abc' -Limit 1 -Offset 1"; Splat = @{ Username = 'sgt-test-abc'; Limit = 1; Offset = 1 }; Pipe = $false; PipeInput = $null }
        @{ Case = "two piped names 'sgt-test-abc' 'sgt-test-abcd' with -Limit 1 -Offset 1"; Splat = @{ Limit = 1; Offset = 1 }; Pipe = $true; PipeInput = @('sgt-test-abc', 'sgt-test-abcd') }
    ) {
        $Result = Invoke-SgtM7Case -Splat $Splat -PipeInput $PipeInput -Pipe:$Pipe
        $Text = Format-SgtM7Case -Result $Result
        Write-Host ('MEASURE M3 [{0} {1}] {2}: {3}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Case, $Text)
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
        $Text | Should -Not -BeNullOrEmpty
    }

    It 'M4: the ShouldProcess target <Case>' -ForEach @(
        @{ Case = 'without -Username'; Script = 'Get-SGSubuser -WhatIf' }
        @{ Case = "with -Username 'sgt-test-abc'"; Script = 'Get-SGSubuser -Username ''sgt-test-abc'' -WhatIf' }
    ) {
        $Run = Invoke-SgtInCountingHost -Script $Script
        $WhatIf = @($Run.HostLine | Where-Object { $_ -like 'What if:*' })
        $Line = if ($WhatIf.Count) { $WhatIf -join ' | ' } else { 'none' }
        $Text = 'what-if lines {0}; line {1}; names the value {2}; prompts {3}; requests {4}; threw {5}' -f $WhatIf.Count, $Line,
            ($Line -match 'sgt-test-abc'), $Run.PromptCount, $Run.NetworkCallCount, $Run.Threw
        Write-Host ('MEASURE M4 [{0} {1}] {2}: {3}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Case, $Text)
        $Run.UnmockedCall | Should -BeNullOrEmpty
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
        $Text | Should -Not -BeNullOrEmpty
    }

    It 'M5: the request without parameters' {
        $Result = Invoke-SgtM7Case -Splat @{}
        $Text = Format-SgtM7Case -Result $Result
        Write-Host ('MEASURE M5 [{0} {1}] no parameters: {2}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Text)
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
        $Text | Should -Not -BeNullOrEmpty
    }

    It 'M5: the description and parameter help' {
        $Help = Get-Help -Name Get-SGSubuser
        $Description = (@($Help.description | ForEach-Object { $_.Text }) -join ' ') -replace '\s+', ' '
        $ParamText = foreach ($Name in 'Username', 'Limit', 'Offset') {
            $P = (@((Get-Help -Name Get-SGSubuser -Parameter $Name).description | ForEach-Object { $_.Text }) -join ' ') -replace '\s+', ' '
            '{0} says "without -Username" {1}; {0} says empty refused {2}' -f $Name, ($P -match 'without -Username|not given|only when -Username'), ($P -match 'empty')
        }
        $Text = 'description says disabled not shown {0}; says list includes disabled {1}; {2}' -f ($Description -match "won't display disabled"),
            ($Description -match 'includes disabled'), ($ParamText -join '; ')
        Write-Host ('MEASURE M5 [{0} {1}] help: {2}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Text)
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
        $Text | Should -Not -BeNullOrEmpty
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
