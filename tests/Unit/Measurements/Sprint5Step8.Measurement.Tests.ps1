BeforeDiscovery {
    # The eight Get commands of step 8, each with the parameter that selects one object and a made-up valid value.
    $script:M8Command = @(
        @{ Command = 'Get-SGApiKey'; Param = 'ApiKeyId'; Valid = 'key-id-1' }
        @{ Command = 'Get-SGTeammate'; Param = 'Username'; Valid = 'sgt-test-user' }
        @{ Command = 'Get-SGAlert'; Param = 'AlertId'; Valid = '1001' }
        @{ Command = 'Get-SGBlock'; Param = 'EmailAddress'; Valid = 'user@example.com' }
        @{ Command = 'Get-SGBounce'; Param = 'EmailAddress'; Valid = 'user@example.com' }
        @{ Command = 'Get-SGGlobalSuppression'; Param = 'EmailAddress'; Valid = 'user@example.com' }
        @{ Command = 'Get-SGInvalidEmail'; Param = 'EmailAddress'; Valid = 'user@example.com' }
        @{ Command = 'Get-SGSpamReport'; Param = 'EmailAddress'; Valid = 'user@example.com' }
    )
    $script:M8EmptyCase = foreach ($Entry in $script:M8Command) {
        $P = $Entry.Param
        @{ Command = $Entry.Command; Case = "-$P `$null"; Splat = @{ $P = $null }; Pipe = $false; PipeInput = $null }
        @{ Command = $Entry.Command; Case = "-$P ''"; Splat = @{ $P = '' }; Pipe = $false; PipeInput = $null }
        @{ Command = $Entry.Command; Case = "-$P @()"; Splat = @{ $P = @() }; Pipe = $false; PipeInput = $null }
        @{ Command = $Entry.Command; Case = "-$P @('')"; Splat = @{ $P = @('') }; Pipe = $false; PipeInput = $null }
        @{ Command = $Entry.Command; Case = "piped value ''"; Splat = @{}; Pipe = $true; PipeInput = @('') }
        @{ Command = $Entry.Command; Case = "piped by property $P ''"; Splat = @{}; Pipe = $true; PipeInput = @([pscustomobject]@{ $P = '' }) }
        @{ Command = $Entry.Command; Case = "piped by property $P `$null"; Splat = @{}; Pipe = $true; PipeInput = @([pscustomobject]@{ $P = $null }) }
    }
    $script:M8ValidCase = foreach ($Entry in $script:M8Command) {
        @{ Command = $Entry.Command; Case = "-$($Entry.Param) '$($Entry.Valid)'"; Splat = @{ $Entry.Param = $Entry.Valid } }
    }
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/NetworkTripwire.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/SessionHelpers.ps1')
    # Import once per run: in Windows PowerShell 5.1 a class stays bound to the first loaded module instance.
    if (-not (Get-Module -Name SendGridTools)) {
        Get-Module -Name SendGridTools -ListAvailable | Select-Object -First 1 | Import-Module -ErrorAction Stop
    }
    Enable-SgtNetworkTripwire
    Assert-SgtNetworkTripwireActive
    Install-SgtSessionHelper
    $script:Cred = [pscredential]::new('apikey', (ConvertTo-SecureString -String 'test-key-not-real' -AsPlainText -Force))

    # One text per logged call: the method, the path and the query that would go on the wire.
    function script:Get-SgtM8Request {
        param([object[]]$Calls)
        if ($Calls.Count -eq 0) { return 'requests 0' }
        $Parts = foreach ($Call in $Calls) {
            $Uri = [uri]$Call.Uri
            'method {0} path {1} query {2}' -f $Call.Method, $Uri.AbsolutePath, $(if ($Uri.Query) { $Uri.Query } else { 'none' })
        }
        'requests {0}; {1}' -f $Calls.Count, ($Parts -join ' | ')
    }

    function script:Get-SgtM8Error {
        param([object[]]$Caught)
        if ($Caught.Count -eq 0) { return 'errors 0' }
        $Parts = foreach ($Item in $Caught) {
            '{0} ({1})' -f $Item.Exception.GetType().FullName, $Item.FullyQualifiedErrorId
        }
        'errors {0}; {1}' -f $Caught.Count, ($Parts -join ' | ')
    }

    # Runs the command in module scope with one made-up object as answer. A terminating error is caught, and the
    # error stream is read with 2>&1: an error from binding piped input reaches only that stream.
    function script:Invoke-SgtM8Case {
        param([string]$Command, [hashtable]$Splat, [object[]]$PipeInput, [switch]$Pipe)
        InModuleScope SendGridTools -Parameters @{ Command = $Command; Splat = $Splat; PipeInput = $PipeInput; Pipe = [bool]$Pipe } {
            Set-SgtNetworkStub -Response @([pscustomobject]@{ api_key_id = 'key-id-1'; id = 1001; email = 'user@example.com'; name = 'sgt-test-item' })
            $Caught = [System.Collections.Generic.List[object]]::new()
            $Stream = @()
            try {
                if ($Pipe) {
                    $Stream = @($PipeInput | & $Command @Splat -ErrorAction Continue 2>&1)
                }
                else {
                    $Stream = @(& $Command @Splat -ErrorAction Continue 2>&1)
                }
            }
            catch { $Caught.Add($_) }
            foreach ($E in @($Stream | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })) { $Caught.Add($E) }
            $Out = @($Stream | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })
            @{ Calls = @(Get-SgtNetworkCall)[0]; Caught = $Caught.ToArray(); OutCount = $Out.Count }
        }
    }

    function script:Format-SgtM8Case {
        param($Result)
        '{0}; output {1}; {2}' -f (Get-SgtM8Request -Calls $Result.Calls), $Result.OutCount, (Get-SgtM8Error -Caught $Result.Caught)
    }
}

AfterAll {
    Uninstall-SgtSessionHelper
    Disable-SgtNetworkTripwire
}

# Sprint 5 step 8 measurements (M1-M3). Each It writes one MEASURE line with command names, counts, made-up values,
# error types and True/False only, and asserts nothing about the measured value, so the same file measures any
# version of the module. Invoke-RestMethod is answered by the tripwire's stub, which logs the Uri.
Describe 'Sprint 5 step 8 measurements' {
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

    It 'M1: <Command> <Case>' -ForEach $script:M8EmptyCase {
        $Result = Invoke-SgtM8Case -Command $Command -Splat $Splat -PipeInput $PipeInput -Pipe:$Pipe
        $Text = Format-SgtM8Case -Result $Result
        $Listed = @($Result.Calls | Where-Object { ([uri]$_.Uri).Query -notmatch 'email=' -and ([uri]$_.Uri).AbsolutePath -match '/(api_keys|teammates|alerts|suppression/[a-z_]+)$' }).Count -gt 0
        Write-Host ('MEASURE M1 [{0} {1}] {2} {3}: {4}; asked for the whole list {5}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Command, $Case, $Text, $Listed)
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
        $Text | Should -Not -BeNullOrEmpty
    }

    It 'M2: <Command> <Case>' -ForEach $script:M8ValidCase {
        $Result = Invoke-SgtM8Case -Command $Command -Splat $Splat
        $Text = Format-SgtM8Case -Result $Result
        Write-Host ('MEASURE M2 [{0} {1}] {2} {3}: {4}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Command, $Case, $Text)
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
        $Text | Should -Not -BeNullOrEmpty
    }

    It 'M3: <Command> without parameters' -ForEach $script:M8ValidCase {
        $Result = Invoke-SgtM8Case -Command $Command -Splat @{}
        $Text = Format-SgtM8Case -Result $Result
        Write-Host ('MEASURE M3 [{0} {1}] {2} no parameters: {3}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Command, $Text)
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
