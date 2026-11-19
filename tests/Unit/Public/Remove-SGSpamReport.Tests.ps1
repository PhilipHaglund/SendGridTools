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

Describe 'Remove-SGSpamReport request and error message' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Sends one Delete to suppression/spam_reports/one%40example.com for an address' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = Remove-SGSpamReport -EmailAddress 'one@example.com' -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Delete'
            $Calls[0].Uri.AbsoluteUri | Should -BeLike '*/suppression/spam_reports/one%40example.com'
        }
    }

    It 'Names the reason in the error message when the request fails' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Throw ([System.Exception]::new('sgt-test-transport-text'))

            $Caught = $null
            try {
                $null = Remove-SGSpamReport -EmailAddress 'one@example.com' -Confirm:$false
            } catch {
                $Caught = $_
            }

            $Caught | Should -Not -BeNullOrEmpty
            $Caught.Exception.Message | Should -BeExactly 'Failed to remove email address "one@example.com" from SendGrid spam report. Unable to query SendGrid: sgt-test-transport-text'
        }
    }
}

Describe 'Remove-SGSpamReport encodes the address in the path (D51)' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Encodes <Address> in the path' -ForEach @(
        @{ Address = 'a+b@example.com'; Expected = 'https://api.sendgrid.com/v3/suppression/spam_reports/a%2Bb%40example.com' }
        @{ Address = 'one#tag@example.com'; Expected = 'https://api.sendgrid.com/v3/suppression/spam_reports/one%23tag%40example.com' }
        @{ Address = 'one/tag@example.com'; Expected = 'https://api.sendgrid.com/v3/suppression/spam_reports/one%2Ftag%40example.com' }
    ) {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Address = $Address; Expected = $Expected } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = Remove-SGSpamReport -EmailAddress $Address -Confirm:$false

            $Calls = @(Get-SgtNetworkCall)
            $Calls.Count | Should -Be 1
            $Calls[0].Uri.AbsoluteUri | Should -BeExactly $Expected
            $Calls[0].Uri.Segments.Count | Should -Be 5
        }
    }
}

Describe 'Remove-SGSpamReport rejects an object without an address (D64)' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Throws and sends nothing for <Name>' -ForEach @(
        @{ Name = 'an object without Email'; Value = ([pscustomobject]@{ Name = 'placeholder' }) }
        @{ Name = 'an object with an empty Email'; Value = ([pscustomobject]@{ Email = '' }) }
        @{ Name = 'an object with a null Email'; Value = ([pscustomobject]@{ Email = $null }) }
    ) {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Value = $Value } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $Caught = $null
            try {
                $null = $Value | Remove-SGSpamReport -Confirm:$false -ErrorAction Stop
            } catch {
                $Caught = $_
            }

            $Caught | Should -Not -BeNullOrEmpty
            $Caught.Exception.Message | Should -BeExactly 'InputObject has no Email property; pass an email address or an object with an Email property.'
            (Get-SgtNetworkCall).Count | Should -Be 0
        }
    }

    It 'Sends one Delete for a piped string' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = 'a+b@example.com' | Remove-SGSpamReport -Confirm:$false -ErrorAction Stop

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Delete'
            $Calls[0].Uri.AbsoluteUri | Should -BeLike '*/spam_reports/a%2Bb%40example.com'
        }
    }

    It 'Sends one Delete for a piped object with Email' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = [pscustomobject]@{ Email = 'a+b@example.com' } | Remove-SGSpamReport -Confirm:$false -ErrorAction Stop

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Delete'
            $Calls[0].Uri.AbsoluteUri | Should -BeLike '*/spam_reports/a%2Bb%40example.com'
        }
    }

    It 'Throws and sends nothing for a piped int' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $Caught = $null
            try {
                $null = 42 | Remove-SGSpamReport -Confirm:$false -ErrorAction Stop
            } catch {
                $Caught = $_
            }

            $Caught | Should -Not -BeNullOrEmpty
            $Caught.Exception.Message | Should -BeExactly 'Failed to convert InputObject to an email address.'
            (Get-SgtNetworkCall).Count | Should -Be 0
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}