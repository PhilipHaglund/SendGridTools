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

Describe 'Get-SGSuppressionGroup request' {
    BeforeEach {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001; name = 'group-placeholder'; is_default = $false })
        }
    }

    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Sends one Get to asm/groups with no body' {
        InModuleScope SendGridTools {
            $null = Get-SGSuppressionGroup

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Get'
            $Calls[0].Uri.AbsoluteUri | Should -BeExactly 'https://api.sendgrid.com/v3/asm/groups'
            $Calls[0].BodyPassed | Should -BeFalse
            $Calls[0].Headers.ContainsKey('on-behalf-of') | Should -BeFalse
        }
    }

    It 'Adds the id to the path for -GroupId' {
        InModuleScope SendGridTools {
            $null = Get-SGSuppressionGroup -GroupId 1001

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Uri.AbsoluteUri | Should -BeExactly 'https://api.sendgrid.com/v3/asm/groups/1001'
        }
    }

    It 'Makes one call per id piped in' {
        InModuleScope SendGridTools {
            $null = 1001, 1002 | Get-SGSuppressionGroup

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 2
            $Calls[0].Uri.AbsoluteUri | Should -BeExactly 'https://api.sendgrid.com/v3/asm/groups/1001'
            $Calls[1].Uri.AbsoluteUri | Should -BeExactly 'https://api.sendgrid.com/v3/asm/groups/1002'
        }
    }

    It 'Binds the Id property of a piped object to GroupId' {
        InModuleScope SendGridTools {
            $null = [pscustomobject]@{ Id = 1001 } | Get-SGSuppressionGroup

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Uri.AbsoluteUri | Should -BeExactly 'https://api.sendgrid.com/v3/asm/groups/1001'
        }
    }

    It 'Sends -OnBehalfOf as the on-behalf-of header' {
        InModuleScope SendGridTools {
            $null = Get-SGSuppressionGroup -OnBehalfOf 'subuser-placeholder'

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Headers['on-behalf-of'] | Should -BeExactly 'subuser-placeholder'
        }
    }

    It 'Sends -OnBehalfOf on every piped call' {
        InModuleScope SendGridTools {
            $null = 1001, 1002 | Get-SGSuppressionGroup -OnBehalfOf 'subuser-placeholder'

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 2
            $Calls[0].Headers['on-behalf-of'] | Should -BeExactly 'subuser-placeholder'
            $Calls[1].Headers['on-behalf-of'] | Should -BeExactly 'subuser-placeholder'
        }
    }

    It 'Returns the answer with title-case property names' {
        InModuleScope SendGridTools {
            $Result = Get-SGSuppressionGroup -GroupId 1001

            $Result.Id | Should -Be 1001
            $Result.Name | Should -BeExactly 'group-placeholder'
            $Result.IsDefault | Should -BeFalse
        }
    }

    It 'Wraps a SendGrid error with the cause' {
        InModuleScope SendGridTools {
            Set-SgtNetworkStub -Throw (New-SgtErrorRecord -Message 'http failure' -Details '{"errors":[{"message":"bad request"}]}')
            $Caught = $null
            try { $null = Get-SGSuppressionGroup } catch { $Caught = $_ }

            $Caught | Should -Not -BeNullOrEmpty
            $Caught.Exception.Message | Should -BeLike 'Failed to retrieve suppression group(s). SendGrid Error*bad request*'
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
