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
    $script:PlainFixture = Join-Path -Path $PSScriptRoot -ChildPath '../Fixtures/subusers-page.json'

    # One text per logged call: the path and query that would go on the wire, and the fragment that would not.
    function script:Get-SgtM5Request {
        param([object[]]$Calls)
        if ($Calls.Count -eq 0) { return 'requests 0' }
        $Parts = foreach ($Call in $Calls) {
            $Uri = [uri]$Call.Uri
            'method {0} path {1} query {2} fragment {3}' -f $Call.Method, $Uri.AbsolutePath, $(if ($Uri.Query) { $Uri.Query } else { 'none' }), $(if ($Uri.Fragment) { $Uri.Fragment } else { 'none' })
        }
        'requests {0}; {1}' -f $Calls.Count, ($Parts -join ' | ')
    }

    function script:Get-SgtM5Error {
        param($Caught)
        if ($null -eq $Caught) { return 'threw False' }
        'threw True; error type {0}' -f $Caught.Exception.GetType().FullName
    }

    function script:Get-SgtM5HelpText {
        param([string]$Command)
        $Help = Get-Help -Name $Command -Parameter Username -ErrorAction Stop
        (@($Help.description | ForEach-Object { $_.Text }) -join ' ') -replace '\s+', ' '
    }
}

AfterAll {
    Uninstall-SgtSessionHelper
    Disable-SgtNetworkTripwire
}

# Sprint 5 step 5 measurements (M1-M4). Each It writes one MEASURE line with command names, counts, made-up values,
# error types and True/False only, and asserts nothing about the measured value, so the same file measures any version
# of the module. Invoke-RestMethod is answered by the tripwire's stub, which logs the Uri.
Describe 'Sprint 5 step 5 measurements' {
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

    It 'M1: the request for -Username <Name> <Case>' -ForEach @(
        @{ Name = "'a b+c/d#e'"; Case = 'alone'; Splat = @{ Username = 'a b+c/d#e' } }
        @{ Name = "'a b+c/d#e'"; Case = 'with -Limit 2 -Offset 1'; Splat = @{ Username = 'a b+c/d#e'; Limit = 2; Offset = 1 } }
    ) {
        $Result = InModuleScope SendGridTools -Parameters @{ Fixture = $script:PlainFixture; Splat = $Splat } {
            Set-SgtNetworkStub -Response (Get-Content -LiteralPath $Fixture -Raw | ConvertFrom-Json)
            $Caught = $null
            $Out = @()
            try { $Out = @(Get-SGSubuser @Splat -Confirm:$false -ErrorAction Stop) } catch { $Caught = $_ }
            @{ Calls = @(Get-SgtNetworkCall)[0]; Caught = $Caught; OutCount = $Out.Count }
        }
        $Text = '{0}; output {1}; {2}' -f (Get-SgtM5Request -Calls $Result.Calls), $Result.OutCount, (Get-SgtM5Error $Result.Caught)
        Write-Host ('MEASURE M1 [{0} {1}] -Username {2} {3}: {4}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Name, $Case, $Text)
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
        $Text | Should -Not -BeNullOrEmpty
    }

    It 'M2: the requests for two names through the pipeline <Case>' -ForEach @(
        @{ Case = 'as strings'; ByProperty = $false }
        @{ Case = 'by property Username'; ByProperty = $true }
    ) {
        $Result = InModuleScope SendGridTools -Parameters @{ Fixture = $script:PlainFixture; ByProperty = $ByProperty } {
            Set-SgtNetworkStub -Response (Get-Content -LiteralPath $Fixture -Raw | ConvertFrom-Json)
            $Names = @('a b+c/d#e', 'f?g&h')
            $InputObject = if ($ByProperty) { $Names | ForEach-Object { [pscustomobject]@{ Username = $_ } } } else { $Names }
            $Caught = $null
            $Out = @()
            try { $Out = @($InputObject | Get-SGSubuser -Confirm:$false -ErrorAction Stop) } catch { $Caught = $_ }
            @{ Calls = @(Get-SgtNetworkCall)[0]; Caught = $Caught; OutCount = $Out.Count }
        }
        $Text = '{0}; output {1}; {2}' -f (Get-SgtM5Request -Calls $Result.Calls), $Result.OutCount, (Get-SgtM5Error $Result.Caught)
        Write-Host ('MEASURE M2 [{0} {1}] two names {2}: {3}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Case, $Text)
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
        $Text | Should -Not -BeNullOrEmpty
    }

    It 'M3: the request and warning for -Username with <Case>' -ForEach @(
        @{ Case = '-IncludeRegion'; Splat = @{ Username = 'a b+c/d#e'; IncludeRegion = $true } }
        @{ Case = '-Region EU'; Splat = @{ Username = 'a b+c/d#e'; Region = 'EU' } }
    ) {
        $Result = InModuleScope SendGridTools -Parameters @{ Fixture = $script:PlainFixture; Splat = $Splat } {
            Set-SgtNetworkStub -Response (Get-Content -LiteralPath $Fixture -Raw | ConvertFrom-Json)
            $Caught = $null
            $Warned = $null
            try { $null = Get-SGSubuser @Splat -Confirm:$false -ErrorAction Stop -WarningVariable Warned -WarningAction SilentlyContinue } catch { $Caught = $_ }
            @{ Calls = @(Get-SgtNetworkCall)[0]; Caught = $Caught; Warned = @($Warned) }
        }
        $WarningText = if ($Result.Warned.Count) { "$($Result.Warned[0])" } else { 'none' }
        $Text = '{0}; warnings {1}; warning names the value {2}; warning {3}; {4}' -f (Get-SgtM5Request -Calls $Result.Calls), $Result.Warned.Count,
            ($WarningText -match [regex]::Escape('a b+c')), $WarningText, (Get-SgtM5Error $Result.Caught)
        Write-Host ('MEASURE M3 [{0} {1}] -Username with {2}: {3}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Case, $Text)
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
        $Text | Should -Not -BeNullOrEmpty
    }

    It 'M4: the help for -Username in <Command>' -ForEach @(
        @{ Command = 'Get-SGSubuser' }
        @{ Command = 'New-SGSubuser' }
    ) {
        $Caught = $null
        $HelpText = 'none'
        try { $HelpText = Get-SgtM5HelpText -Command $Command } catch { $Caught = $_ }
        $Definition = (Get-Command -Name $Command).Definition
        $Text = 'help "{0}"; says ID {1}; says username {2}; source has "the ID of a specific Subuser" {3}; {4}' -f $HelpText,
            ($HelpText -match '\bID\b'), ($HelpText -match 'username'), ($Definition -match 'the ID of a specific Subuser'), (Get-SgtM5Error $Caught)
        Write-Host ('MEASURE M4 [{0} {1}] {2}: {3}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Command, $Text)
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
        $Text | Should -Not -BeNullOrEmpty
    }

    It 'M4: the spelling in the description of Get-SGSubuser' {
        $Description = (@((Get-Help -Name Get-SGSubuser).description | ForEach-Object { $_.Text }) -join ' ') -replace '\s+', ' '
        $Text = 'has "retrieve ing" {0}; has "wont" {1}; has "retrieving" {2}; has "won''t" {3}' -f ($Description -match 'retrieve ing'),
            ($Description -match '\bwont\b'), ($Description -match 'retrieving'), ($Description -match "won't")
        Write-Host ('MEASURE M4 [{0} {1}] Get-SGSubuser description: {2}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Text)
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
