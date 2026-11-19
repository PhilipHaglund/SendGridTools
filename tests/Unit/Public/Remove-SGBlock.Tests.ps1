BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/NetworkTripwire.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/SessionHelpers.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/PromptCountingHost.ps1')
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

Describe 'Remove-SGBlock request and error message' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Sends one Delete to suppression/blocks/one%40example.com for an address' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = Remove-SGBlock -EmailAddress 'one@example.com' -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Delete'
            $Calls[0].Uri.AbsoluteUri | Should -BeLike '*/suppression/blocks/one%40example.com'
        }
    }

    It 'Names the reason in the error message when the request fails' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Throw ([System.Exception]::new('sgt-test-transport-text'))

            $Caught = $null
            try {
                $null = Remove-SGBlock -EmailAddress 'one@example.com' -Confirm:$false
            } catch {
                $Caught = $_
            }

            $Caught | Should -Not -BeNullOrEmpty
            $Caught.Exception.Message | Should -BeExactly 'Failed to remove SendGrid block "one@example.com". Unable to query SendGrid: sgt-test-transport-text'
        }
    }
}

Describe 'Remove-SGBlock encodes the address in the path (D51)' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Encodes <Address> in the path' -ForEach @(
        @{ Address = 'a+b@example.com'; Expected = 'https://api.sendgrid.com/v3/suppression/blocks/a%2Bb%40example.com' }
        @{ Address = 'one#tag@example.com'; Expected = 'https://api.sendgrid.com/v3/suppression/blocks/one%23tag%40example.com' }
        @{ Address = 'one/tag@example.com'; Expected = 'https://api.sendgrid.com/v3/suppression/blocks/one%2Ftag%40example.com' }
    ) {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Address = $Address; Expected = $Expected } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = Remove-SGBlock -EmailAddress $Address -Confirm:$false

            $Calls = @(Get-SgtNetworkCall)
            $Calls.Count | Should -Be 1
            $Calls[0].Uri.AbsoluteUri | Should -BeExactly $Expected
            $Calls[0].Uri.Segments.Count | Should -Be 5
        }
    }
}

Describe 'Remove-SGBlock says block' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Names the blocks list in the -DeleteAll error message' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Throw ([System.Exception]::new('sgt-test-transport-text'))

            $Caught = $null
            try {
                $null = Remove-SGBlock -DeleteAll -Confirm:$false
            } catch {
                $Caught = $_
            }

            $Caught | Should -Not -BeNullOrEmpty
            $Caught.Exception.Message | Should -BeExactly 'Failed to remove all SendGrid blocks. Unable to query SendGrid: sgt-test-transport-text'
        }
    }

    It 'Shows block and the address as given under -WhatIf with -EmailAddress' {
        $Run = Invoke-SgtInCountingHost -Script 'Remove-SGBlock -EmailAddress ''a+b@example.com'' -WhatIf'

        @($Run.HostLine).Count | Should -Be 1
        ($Run.HostLine -join "`n") | Should -BeLike '*Remove block with email address a+b@example.com*'
        ($Run.HostLine -join "`n") | Should -Not -Match 'bounce'
        $Run.PromptCount | Should -Be 0
        $Run.NetworkCallCount | Should -Be 0
        $Run.UnmockedCall | Should -BeNullOrEmpty
    }

    It 'Shows block under -WhatIf with -DeleteAll' {
        $Run = Invoke-SgtInCountingHost -Script 'Remove-SGBlock -DeleteAll -WhatIf'

        @($Run.HostLine).Count | Should -Be 1
        ($Run.HostLine -join "`n") | Should -BeLike '*Remove all blocks from SendGrid*'
        ($Run.HostLine -join "`n") | Should -Not -Match 'bounce'
        $Run.PromptCount | Should -Be 0
        $Run.NetworkCallCount | Should -Be 0
        $Run.UnmockedCall | Should -BeNullOrEmpty
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}