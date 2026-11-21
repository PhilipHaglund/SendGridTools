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

Describe 'New-SGSuppressionGroup request' {
    BeforeEach {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001; name = 'group-placeholder'; description = 'desc-placeholder'; is_default = $false })
        }
    }

    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Sends one Post to asm/groups with name, description and is_default false' {
        InModuleScope SendGridTools {
            $null = New-SGSuppressionGroup -Name 'group-placeholder' -Description 'desc-placeholder' -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Post'
            $Calls[0].Uri.AbsoluteUri | Should -BeExactly 'https://api.sendgrid.com/v3/asm/groups'
            $Sent = $Calls[0].Body | ConvertFrom-Json
            @($Sent.PSObject.Properties.Name | Sort-Object) | Should -Be @('description', 'is_default', 'name')
            $Sent.name | Should -BeExactly 'group-placeholder'
            $Sent.description | Should -BeExactly 'desc-placeholder'
            $Sent.is_default | Should -BeFalse
        }
    }

    It 'Sends is_default true for -IsDefault' {
        InModuleScope SendGridTools {
            $null = New-SGSuppressionGroup -Name 'group-placeholder' -Description 'desc-placeholder' -IsDefault -Confirm:$false

            $Sent = (Get-SgtNetworkCall)[0].Body | ConvertFrom-Json
            $Sent.is_default | Should -BeTrue
        }
    }

    It 'Makes one call per name piped in' {
        InModuleScope SendGridTools {
            $null = 'group-a', 'group-b' | New-SGSuppressionGroup -Description 'desc-placeholder' -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 2
            ($Calls[0].Body | ConvertFrom-Json).name | Should -BeExactly 'group-a'
            ($Calls[1].Body | ConvertFrom-Json).name | Should -BeExactly 'group-b'
        }
    }

    It 'Sends -OnBehalfOf as the on-behalf-of header' {
        InModuleScope SendGridTools {
            $null = New-SGSuppressionGroup -Name 'group-placeholder' -Description 'desc-placeholder' -OnBehalfOf 'subuser-placeholder' -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Headers['on-behalf-of'] | Should -BeExactly 'subuser-placeholder'
        }
    }

    It 'Sends no on-behalf-of header without -OnBehalfOf' {
        InModuleScope SendGridTools {
            $null = New-SGSuppressionGroup -Name 'group-placeholder' -Description 'desc-placeholder' -Confirm:$false

            (Get-SgtNetworkCall)[0].Headers.ContainsKey('on-behalf-of') | Should -BeFalse
        }
    }

    It 'Sends nothing under WhatIf' {
        InModuleScope SendGridTools {
            $null = New-SGSuppressionGroup -Name 'group-placeholder' -Description 'desc-placeholder' -WhatIf

            Get-SgtNetworkCall | Should -BeNullOrEmpty
        }
    }

    It 'Returns the answer of the call' {
        InModuleScope SendGridTools {
            $Result = New-SGSuppressionGroup -Name 'group-placeholder' -Description 'desc-placeholder' -Confirm:$false

            $Result.id | Should -Be 1001
            $Result.name | Should -BeExactly 'group-placeholder'
            $Result.description | Should -BeExactly 'desc-placeholder'
            $Result.is_default | Should -BeFalse
        }
    }

    It 'Wraps a SendGrid error with the cause' {
        InModuleScope SendGridTools {
            Set-SgtNetworkStub -Throw (New-SgtErrorRecord -Message 'http failure' -Details '{"errors":[{"message":"bad request"}]}')
            $Caught = $null
            try { $null = New-SGSuppressionGroup -Name 'group-placeholder' -Description 'desc-placeholder' -Confirm:$false } catch { $Caught = $_ }

            $Caught | Should -Not -BeNullOrEmpty
            $Caught.Exception.Message | Should -BeLike 'Failed to create a new suppression group. *bad request*'
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
