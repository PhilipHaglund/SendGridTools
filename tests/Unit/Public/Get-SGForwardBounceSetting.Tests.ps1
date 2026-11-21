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
}

AfterAll {
    Uninstall-SgtSessionHelper
    Disable-SgtNetworkTripwire
}

Describe 'Get-SGForwardBounceSetting request' {
    BeforeEach {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ enabled = $true; email = 'forward@example.com' })
        }
    }

    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Sends one Get to mail_settings/forward_bounce with no body' {
        InModuleScope SendGridTools {
            $null = Get-SGForwardBounceSetting

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Get'
            $Calls[0].Uri.AbsoluteUri | Should -BeExactly 'https://api.sendgrid.com/v3/mail_settings/forward_bounce'
            $Calls[0].BodyPassed | Should -BeFalse
            $Calls[0].Headers.ContainsKey('on-behalf-of') | Should -BeFalse
        }
    }

    It 'Sends -OnBehalfOf as the on-behalf-of header' {
        InModuleScope SendGridTools {
            $null = Get-SGForwardBounceSetting -OnBehalfOf 'subuser-placeholder'

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Headers['on-behalf-of'] | Should -BeExactly 'subuser-placeholder'
        }
    }

    It 'Returns the answer with title-case property names' {
        InModuleScope SendGridTools {
            $Result = Get-SGForwardBounceSetting

            $Result.Enabled | Should -BeTrue
            $Result.Email | Should -BeExactly 'forward@example.com'
        }
    }

    It 'Wraps a SendGrid error with the cause' {
        InModuleScope SendGridTools {
            Set-SgtNetworkStub -Throw (New-SgtErrorRecord -Message 'http failure' -Details '{"errors":[{"message":"bad request"}]}')
            $Caught = $null
            try { $null = Get-SGForwardBounceSetting } catch { $Caught = $_ }

            $Caught | Should -Not -BeNullOrEmpty
            $Caught.Exception.Message | Should -BeLike 'Failed to retrieve SendGrid forward bounce settings. SendGrid Error*bad request*'
            $Caught.Exception.InnerException | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
