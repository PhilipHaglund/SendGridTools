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

Describe 'Add-SGEmailAddressToSuppressionGroup request' {
    BeforeEach {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ recipient_emails = @('one@example.com') })
        }
    }

    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Sends one Post with the bare addresses as recipient_emails' {
        InModuleScope SendGridTools {
            $null = Add-SGEmailAddressToSuppressionGroup -UniqueId 1001 -EmailAddresses 'one@example.com', 'Name <two@example.com>' -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Post'
            $Calls[0].Uri.AbsoluteUri | Should -BeExactly 'https://api.sendgrid.com/v3/asm/groups/1001/suppressions'
            $Sent = $Calls[0].Body | ConvertFrom-Json
            @($Sent.PSObject.Properties.Name) | Should -Be @('recipient_emails')
            @($Sent.recipient_emails) | Should -Be @('one@example.com', 'two@example.com')
        }
    }

    It 'Makes one call per id piped in' {
        InModuleScope SendGridTools {
            $null = 1001, 1002 | Add-SGEmailAddressToSuppressionGroup -EmailAddresses 'one@example.com' -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 2
            $Calls[0].Uri.AbsoluteUri | Should -BeExactly 'https://api.sendgrid.com/v3/asm/groups/1001/suppressions'
            $Calls[1].Uri.AbsoluteUri | Should -BeExactly 'https://api.sendgrid.com/v3/asm/groups/1002/suppressions'
        }
    }

    It 'Sends -OnBehalfOf on every piped call' {
        InModuleScope SendGridTools {
            $null = 1001, 1002 | Add-SGEmailAddressToSuppressionGroup -EmailAddresses 'one@example.com' -OnBehalfOf 'subuser-placeholder' -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 2
            $Calls[0].Headers['on-behalf-of'] | Should -BeExactly 'subuser-placeholder'
            $Calls[1].Headers['on-behalf-of'] | Should -BeExactly 'subuser-placeholder'
        }
    }

    It 'Sends no on-behalf-of header without -OnBehalfOf' {
        InModuleScope SendGridTools {
            $null = Add-SGEmailAddressToSuppressionGroup -UniqueId 1001 -EmailAddresses 'one@example.com' -Confirm:$false

            (Get-SgtNetworkCall)[0].Headers.ContainsKey('on-behalf-of') | Should -BeFalse
        }
    }

    It 'Sends nothing under WhatIf' {
        InModuleScope SendGridTools {
            $null = Add-SGEmailAddressToSuppressionGroup -UniqueId 1001 -EmailAddresses 'one@example.com' -WhatIf

            Get-SgtNetworkCall | Should -BeNullOrEmpty
        }
    }

    It 'Resolves the alias Add-SGSuppression to the command' {
        (Get-Command -Name 'Add-SGSuppression').ResolvedCommand.Name | Should -BeExactly 'Add-SGEmailAddressToSuppressionGroup'
    }

    It 'Wraps a SendGrid error with the cause' {
        InModuleScope SendGridTools {
            Set-SgtNetworkStub -Throw (New-SgtErrorRecord -Message 'http failure' -Details '{"errors":[{"message":"bad request"}]}')
            $Caught = $null
            try { $null = Add-SGEmailAddressToSuppressionGroup -UniqueId 1001 -EmailAddresses 'one@example.com' -Confirm:$false } catch { $Caught = $_ }

            $Caught | Should -Not -BeNullOrEmpty
            $Caught.Exception.Message | Should -BeLike 'Failed to add email addresses to suppression group. *bad request*'
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
