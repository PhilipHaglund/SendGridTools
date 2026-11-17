BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Support/NetworkTripwire.ps1')
    # Import once per run: in Windows PowerShell 5.1 a class stays bound to the first loaded module instance.
    if (-not (Get-Module -Name SendGridTools)) {
        Get-Module -Name SendGridTools -ListAvailable | Select-Object -First 1 | Import-Module -ErrorAction Stop
    }
    $script:Cred = [pscredential]::new('apikey', (ConvertTo-SecureString -String 'test-key-not-real' -AsPlainText -Force))
}

AfterAll {
    Disable-SgtNetworkTripwire
}

Describe 'Network tripwire helper' {
    BeforeEach {
        Enable-SgtNetworkTripwire
    }
    AfterEach {
        Disable-SgtNetworkTripwire
    }

    It 'Throws and records Invoke-RestMethod when a session class calls it unmocked' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            { [SendGridSession]::new().Connect($Cred) } | Should -Throw '*Unmocked network call*'
        }
        Get-SgtUnmockedNetworkCall | Should -Contain 'Invoke-RestMethod'
    }

    It 'Records a direct Invoke-WebRequest the same way' {
        { Invoke-WebRequest -Uri 'https://example.com' } | Should -Throw '*Unmocked network call*'
        Get-SgtUnmockedNetworkCall | Should -Contain 'Invoke-WebRequest'
    }

    It 'Lets a mock win and records nothing' {
        Mock -CommandName Invoke-RestMethod -ModuleName SendGridTools -MockWith { 'mocked' }
        InModuleScope SendGridTools {
            Invoke-RestMethod -Uri 'https://example.com'
        } | Should -Be 'mocked'
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }

    It 'Lets a stub answer a class call, logs it and records nothing as unmocked' {
        $global:SgtNetworkStub = { 'stubbed' }
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            { [SendGridSession]::new().Connect($Cred) } | Should -Not -Throw
        }
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
        @($global:SgtNetworkCall).Count | Should -Be 1
        $global:SgtNetworkCall[0].Uri.AbsoluteUri | Should -Be 'https://api.sendgrid.com/v3/scopes'
    }

    It 'Removes the functions and the variable when disabled' {
        Disable-SgtNetworkTripwire
        Test-Path -Path 'Function:\Invoke-RestMethod' | Should -BeFalse
        Test-Path -Path 'Function:\Invoke-WebRequest' | Should -BeFalse
        Test-Path -Path 'Variable:\global:SgtUnmockedNetworkCall' | Should -BeFalse
    }
}

Describe 'Static rule for every unit test file' {
    BeforeDiscovery {
        $UnitRoot = $PSScriptRoot
        $script:Files = @(
            Get-ChildItem -Path $UnitRoot -Filter '*.Tests.ps1' -Recurse -File |
                Where-Object { $_.Name -ne 'NetworkTripwire.Tests.ps1' } |
                ForEach-Object { @{ Path = $_.FullName; Name = $_.FullName.Substring($UnitRoot.Length).TrimStart('\', '/') } }
        )
    }

    It 'Uses the tripwire in <Name>' -ForEach $script:Files {
        $Ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
        $Commands = $Ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) |
            ForEach-Object { $_.GetCommandName() } | Where-Object { $_ }
        $Commands | Should -Contain 'Enable-SgtNetworkTripwire'
        $Commands | Should -Contain 'Disable-SgtNetworkTripwire'
        $Commands | Should -Contain 'Get-SgtUnmockedNetworkCall'
    }
}
