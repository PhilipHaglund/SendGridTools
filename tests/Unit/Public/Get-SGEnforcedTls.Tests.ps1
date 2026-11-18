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
    $script:Fixture = Get-Content -Raw -Path (Join-Path -Path $PSScriptRoot -ChildPath '../Fixtures/user-settings-enforced-tls.json') | ConvertFrom-Json
}

AfterAll {
    Uninstall-SgtSessionHelper
    Disable-SgtNetworkTripwire
}

Describe 'Get-SGEnforcedTls request' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Sends one Get to user/settings/enforced_tls without a body' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:Fixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response $Fixture

            $null = Get-SGEnforcedTls

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Get'
            "$($Calls[0].Uri)" | Should -BeLike '*/v3/user/settings/enforced_tls'
            $Calls[0].BodyPassed | Should -BeFalse
        }
    }

    It 'Returns RequireTls, RequireValidCert and Version from the response' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:Fixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response $Fixture

            $Out = @(Get-SGEnforcedTls)

            $Out.Count | Should -Be 1
            @($Out[0].PSObject.Properties.Name | Sort-Object) | Should -Be @('RequireTls', 'RequireValidCert', 'Version')
            $Out[0].RequireTls | Should -BeFalse
            $Out[0].RequireValidCert | Should -BeFalse
            $Out[0].Version | Should -Be 0
        }
    }

    It 'Returns the values that were set' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ require_tls = $true; require_valid_cert = $true; version = 1.2 })

            $Out = Get-SGEnforcedTls

            $Out.RequireTls | Should -BeTrue
            $Out.RequireValidCert | Should -BeTrue
            $Out.Version | Should -Be 1.2
        }
    }

    It 'Sends -OnBehalfOf as the on-behalf-of header' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:Fixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response $Fixture

            $null = Get-SGEnforcedTls -OnBehalfOf 'subuser-placeholder'

            $Calls = Get-SgtNetworkCall
            $Calls[0].Headers['on-behalf-of'] | Should -Be 'subuser-placeholder'
        }
    }

    It 'Wraps an API error' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Throw (New-SgtErrorRecord -Message 'boom')

            { Get-SGEnforcedTls } | Should -Throw 'Failed to retrieve SendGrid Enforced TLS settings.*'
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
