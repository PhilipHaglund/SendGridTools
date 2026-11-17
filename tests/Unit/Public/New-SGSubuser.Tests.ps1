BeforeDiscovery {
    $script:Cases = @(
        @{ Label = 'a plain password'; Plain = 'subuser-password-not-real' }
        @{ Label = 'a password JSON must escape'; Plain = 'subuser-password-not-real "\ x' }
    )
}

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

Describe 'New-SGSubuser request' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Sends username, email, password and ips for <Label>' -ForEach $script:Cases {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Plain = $Plain } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ username = 'subuser-placeholder'; user_id = 1; email = 'subuser@example.invalid' })

            $null = New-SGSubuser -Username 'subuser-placeholder' -Email 'subuser@example.invalid' -Password (ConvertTo-SecureString -String $Plain -AsPlainText -Force) -Ips '192.0.2.10' -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Post'
            "$($Calls[0].Uri)" | Should -BeLike '*/subusers'
            $Sent = $Calls[0].Body | ConvertFrom-Json
            @($Sent.PSObject.Properties.Name | Sort-Object) | Should -Be @('email', 'ips', 'password', 'username')
            $Sent.password | Should -BeExactly $Plain
            $Sent.username | Should -Be 'subuser-placeholder'
            $Sent.email | Should -Be 'subuser@example.invalid'
            @($Sent.ips) | Should -Be @('192.0.2.10')
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
