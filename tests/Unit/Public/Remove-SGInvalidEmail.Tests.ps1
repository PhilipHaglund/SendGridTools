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

Describe 'Remove-SGInvalidEmail request and error message' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Sends one Delete to suppression/invalid_emails/one%40example.com for an address' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = Remove-SGInvalidEmail -EmailAddress 'one@example.com' -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Delete'
            $Calls[0].Uri.AbsoluteUri | Should -BeLike '*/suppression/invalid_emails/one%40example.com'
        }
    }

    It 'Names the reason in the error message when the request fails' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Throw ([System.Exception]::new('sgt-test-transport-text'))

            $Caught = $null
            try {
                $null = Remove-SGInvalidEmail -EmailAddress 'one@example.com' -Confirm:$false
            } catch {
                $Caught = $_
            }

            $Caught | Should -Not -BeNullOrEmpty
            $Caught.Exception.Message | Should -BeExactly 'Failed to remove SendGrid invalid email address "one@example.com". Unable to query SendGrid: sgt-test-transport-text'
        }
    }
}

Describe 'Remove-SGInvalidEmail encodes the address in the path (D51)' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Encodes <Address> in the path' -ForEach @(
        @{ Address = 'a+b@example.com'; Expected = 'https://api.sendgrid.com/v3/suppression/invalid_emails/a%2Bb%40example.com' }
        @{ Address = 'one#tag@example.com'; Expected = 'https://api.sendgrid.com/v3/suppression/invalid_emails/one%23tag%40example.com' }
        @{ Address = 'one/tag@example.com'; Expected = 'https://api.sendgrid.com/v3/suppression/invalid_emails/one%2Ftag%40example.com' }
    ) {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Address = $Address; Expected = $Expected } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = Remove-SGInvalidEmail -EmailAddress $Address -Confirm:$false

            $Calls = @(Get-SgtNetworkCall)
            $Calls.Count | Should -Be 1
            $Calls[0].Uri.AbsoluteUri | Should -BeExactly $Expected
            $Calls[0].Uri.Segments.Count | Should -Be 5
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}