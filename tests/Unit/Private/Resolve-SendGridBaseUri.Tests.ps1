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
}

AfterAll {
    Uninstall-SgtSessionHelper
    Disable-SgtNetworkTripwire
}

Describe 'Resolve-SendGridBaseUri' {
    It 'Returns the global host by default and for -Region Global' {
        InModuleScope SendGridTools {
            (Resolve-SendGridBaseUri).AbsoluteUri | Should -Be 'https://api.sendgrid.com/v3'
            (Resolve-SendGridBaseUri -Region Global).AbsoluteUri | Should -Be 'https://api.sendgrid.com/v3'
        }
    }

    It 'Returns the EU host for -Region <Region>' -ForEach @(@{ Region = 'EU' }, @{ Region = 'eu' }) {
        InModuleScope SendGridTools -Parameters @{ Region = $Region } {
            (Resolve-SendGridBaseUri -Region $Region).AbsoluteUri | Should -Be 'https://api.eu.sendgrid.com/v3'
        }
    }

    It 'Normalises -BaseUri <In> to <Out>' -ForEach @(
        @{ In = 'https://api.eu.sendgrid.com'; Out = 'https://api.eu.sendgrid.com/v3' }
        @{ In = 'https://api.eu.sendgrid.com/'; Out = 'https://api.eu.sendgrid.com/v3' }
        @{ In = 'https://api.eu.sendgrid.com/v3'; Out = 'https://api.eu.sendgrid.com/v3' }
        @{ In = 'https://api.eu.sendgrid.com/v3/'; Out = 'https://api.eu.sendgrid.com/v3' }
        @{ In = 'https://proxy.example.com/sendgrid'; Out = 'https://proxy.example.com/sendgrid/v3' }
        @{ In = 'https://proxy.example.com:8443/v3'; Out = 'https://proxy.example.com:8443/v3' }
    ) {
        InModuleScope SendGridTools -Parameters @{ In = $In; Out = $Out } {
            $Result = Resolve-SendGridBaseUri -BaseUri ([uri]$In)
            $Result | Should -BeOfType [uri]
            $Result.ToString() | Should -Be $Out
        }
    }

    It 'Lets -BaseUri win over -Region' {
        InModuleScope SendGridTools {
            (Resolve-SendGridBaseUri -Region EU -BaseUri ([uri]'https://proxy.example.com/v3')).ToString() | Should -Be 'https://proxy.example.com/v3'
        }
    }

    It 'Throws for <In>' -ForEach @(
        @{ In = 'http://api.eu.sendgrid.com' }
        @{ In = 'ftp://example.com/v3' }
        @{ In = 'v3' }
        @{ In = 'https://user:pass@example.com' }
        @{ In = 'https://example.com/v3?x=1' }
        @{ In = 'https://example.com/v3#f' }
    ) {
        InModuleScope SendGridTools -Parameters @{ In = $In } {
            { Resolve-SendGridBaseUri -BaseUri ([uri]::new($In, [UriKind]::RelativeOrAbsolute)) } | Should -Throw 'The base URI*'
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
