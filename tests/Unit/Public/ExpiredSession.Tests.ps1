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

# D168 through the public commands: an expired session keeps saying so on every command.

Describe 'Public commands after the session expired (D168)' {
    BeforeEach {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 2
            Set-SgtNetworkStub -Response ([pscustomobject]@{ scopes = @('scopes.read') })
        }
    }

    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Says expired on the first and on the second command' {
        InModuleScope SendGridTools {
            { Get-SGPermissionScopes -ErrorAction Stop } | Should -Throw -ExpectedMessage '*The SendGrid session has expired. Run Connect-SendGrid -Force to reconnect.'
            { Get-SGPermissionScopes -ErrorAction Stop } | Should -Throw -ExpectedMessage '*The SendGrid session has expired. Run Connect-SendGrid -Force to reconnect.'
            (Get-SgtNetworkCall).Count | Should -Be 0
        }
    }

    It 'Says expired for a command that uses on-behalf-of after the session expired' {
        InModuleScope SendGridTools {
            { Get-SGPermissionScopes -ErrorAction Stop } | Should -Throw -ExpectedMessage '*The SendGrid session has expired.*'
            { Get-SGSuppressionGroup -OnBehalfOf 'subuser-placeholder' -ErrorAction Stop } | Should -Throw -ExpectedMessage '*The SendGrid session has expired. Run Connect-SendGrid -Force to reconnect.'
            (Get-SgtNetworkCall).Count | Should -Be 0
        }
    }

    It 'Says expired for a command that sends a body after the session expired' {
        InModuleScope SendGridTools {
            { Get-SGPermissionScopes -ErrorAction Stop } | Should -Throw -ExpectedMessage '*The SendGrid session has expired.*'
            { New-SGSuppressionGroup -Name 'group-placeholder' -Description 'Placeholder group for a test.' -Confirm:$false -ErrorAction Stop } | Should -Throw -ExpectedMessage '*The SendGrid session has expired. Run Connect-SendGrid -Force to reconnect.'
            (Get-SgtNetworkCall).Count | Should -Be 0
        }
    }

    It 'Says connect first after Disconnect-SendGrid' {
        InModuleScope SendGridTools {
            { Get-SGPermissionScopes -ErrorAction Stop } | Should -Throw -ExpectedMessage '*The SendGrid session has expired.*'
            Disconnect-SendGrid -Confirm:$false
            { Get-SGPermissionScopes -ErrorAction Stop } | Should -Throw -ExpectedMessage '*You must call the Connect-SendGrid cmdlet before calling any other cmdlets.'
            (Get-SgtNetworkCall).Count | Should -Be 0
        }
    }

    It 'Returns data again after Connect-SendGrid with a credential' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            { Get-SGPermissionScopes -ErrorAction Stop } | Should -Throw -ExpectedMessage '*The SendGrid session has expired.*'
            Connect-SendGrid -Credential $Cred -Confirm:$false
            $Result = Get-SGPermissionScopes -ErrorAction Stop
            @($Result).Count | Should -BeGreaterThan 0
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
