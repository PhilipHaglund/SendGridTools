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

Describe 'Get-SGSuppression request' {
    BeforeEach {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ suppressions = @([pscustomobject]@{ name = 'group-placeholder'; id = 1001; suppressed = $true }) })
        }
    }

    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Sends one Get to asm/suppressions with no body' {
        InModuleScope SendGridTools {
            $null = Get-SGSuppression

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Get'
            $Calls[0].Uri.AbsoluteUri | Should -BeExactly 'https://api.sendgrid.com/v3/asm/suppressions'
            $Calls[0].BodyPassed | Should -BeFalse
            $Calls[0].Headers.ContainsKey('on-behalf-of') | Should -BeFalse
        }
    }

    It 'Sends only the bare address in the path when -EmailAddress has a display name' {
        InModuleScope SendGridTools {
            $null = Get-SGSuppression -EmailAddress 'Name <one@example.com>'

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Uri.AbsoluteUri | Should -BeExactly 'https://api.sendgrid.com/v3/asm/suppressions/one@example.com'
        }
    }

    It 'Takes the address as the first positional argument' {
        InModuleScope SendGridTools {
            $null = Get-SGSuppression 'two@example.com'

            $Calls = Get-SgtNetworkCall
            $Calls[0].Uri.AbsoluteUri | Should -BeExactly 'https://api.sendgrid.com/v3/asm/suppressions/two@example.com'
        }
    }

    It 'Treats a MailAddress value like the same text' {
        InModuleScope SendGridTools {
            $null = Get-SGSuppression -EmailAddress ([System.Net.Mail.MailAddress]::new('Name <one@example.com>'))

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Uri.AbsoluteUri | Should -BeExactly 'https://api.sendgrid.com/v3/asm/suppressions/one@example.com'
        }
    }

    It 'Sends -OnBehalfOf as the on-behalf-of header' {
        InModuleScope SendGridTools {
            $null = Get-SGSuppression -EmailAddress 'one@example.com' -OnBehalfOf 'subuser-placeholder'

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Headers['on-behalf-of'] | Should -BeExactly 'subuser-placeholder'
        }
    }

    It 'Unwraps the suppressions list and returns each entry with title-case property names' {
        InModuleScope SendGridTools {
            Set-SgtNetworkStub -Response ([pscustomobject]@{ suppressions = @(
                        [pscustomobject]@{ name = 'group-placeholder'; id = 1001; suppressed = $true },
                        [pscustomobject]@{ name = 'other-placeholder'; id = 1002; suppressed = $false }
                    ) })
            $Result = @(Get-SGSuppression)

            $Result.Count | Should -Be 2
            $Result[0].Name | Should -BeExactly 'group-placeholder'
            $Result[0].Id | Should -Be 1001
            $Result[0].Suppressed | Should -BeTrue
            $Result[1].Name | Should -BeExactly 'other-placeholder'
            $Result[1].Suppressed | Should -BeFalse
        }
    }

    It 'Wraps a SendGrid error with the cause' {
        InModuleScope SendGridTools {
            Set-SgtNetworkStub -Throw (New-SgtErrorRecord -Message 'http failure' -Details '{"errors":[{"message":"bad request"}]}')
            $Caught = $null
            try { $null = Get-SGSuppression } catch { $Caught = $_ }

            $Caught | Should -Not -BeNullOrEmpty
            $Caught.Exception.Message | Should -BeLike 'Failed to retrieve suppressions. SendGrid Error*bad request*'
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
