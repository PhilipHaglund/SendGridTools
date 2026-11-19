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

Describe 'Remove-SGGlobalSuppression request' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Sends one Delete per address given through the pipeline as <Name>' -ForEach @(
        @{ Name = 'strings'; Items = @('one@example.com', 'two@example.com') }
        @{ Name = 'objects with an Email property'; Items = @([pscustomobject]@{ Email = 'one@example.com' }, [pscustomobject]@{ Email = 'two@example.com' }) }
    ) {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Items = $Items } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = $Items | Remove-SGGlobalSuppression -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 2
            $Calls[0].Method | Should -Be 'Delete'
            $Calls[0].Uri.AbsoluteUri | Should -BeLike '*/suppression/unsubscribes/one%40example.com'
            $Calls[1].Uri.AbsoluteUri | Should -BeLike '*/suppression/unsubscribes/two%40example.com'
        }
    }

    It 'Sends one Delete per address given with -EmailAddress' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = Remove-SGGlobalSuppression -EmailAddress 'one@example.com', 'two@example.com' -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 2
            $Calls[0].Uri.AbsoluteUri | Should -BeLike '*/suppression/unsubscribes/one%40example.com'
            $Calls[1].Uri.AbsoluteUri | Should -BeLike '*/suppression/unsubscribes/two%40example.com'
        }
    }

    It 'Sends the bare address for an address with a display name' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = Remove-SGGlobalSuppression -EmailAddress 'Name Placeholder <one@example.com>' -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Uri.AbsoluteUri | Should -BeLike '*/suppression/unsubscribes/one%40example.com'
        }
    }

    It 'Sends nothing for a piped object it cannot read as an address (<Name>)' -ForEach @(
        @{ Name = 'an object without Email'; Item = [pscustomobject]@{ Id = 1001 } }
        @{ Name = 'a string that is not an address'; Item = 'not-an-address' }
    ) {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Item = $Item } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            { $Item | Remove-SGGlobalSuppression -Confirm:$false } | Should -Throw

            Get-SgtNetworkCall | Should -BeNullOrEmpty
        }
    }

    It 'Sends nothing under WhatIf with piped addresses' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = 'one@example.com', 'two@example.com' | Remove-SGGlobalSuppression -WhatIf

            Get-SgtNetworkCall | Should -BeNullOrEmpty
        }
    }
}

Describe 'Remove-SGGlobalSuppression encodes the address in the path (D22)' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Encodes <Name> in the path' -ForEach @(
        @{ Name = 'a plus sign'; Address = 'one+tag@example.com'; Expected = 'https://api.sendgrid.com/v3/suppression/unsubscribes/one%2Btag%40example.com' }
        @{ Name = 'a number sign'; Address = 'one#tag@example.com'; Expected = 'https://api.sendgrid.com/v3/suppression/unsubscribes/one%23tag%40example.com' }
        @{ Name = 'a question mark'; Address = 'one?tag@example.com'; Expected = 'https://api.sendgrid.com/v3/suppression/unsubscribes/one%3Ftag%40example.com' }
        @{ Name = 'a slash'; Address = 'one/tag@example.com'; Expected = 'https://api.sendgrid.com/v3/suppression/unsubscribes/one%2Ftag%40example.com' }
    ) {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Address = $Address; Expected = $Expected } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = Remove-SGGlobalSuppression -EmailAddress $Address -Confirm:$false

            $Calls = @(Get-SgtNetworkCall)
            $Calls.Count | Should -Be 1
            $Calls[0].Uri.AbsoluteUri | Should -BeExactly $Expected
            $Calls[0].Uri.Fragment | Should -BeNullOrEmpty
            $Calls[0].Uri.Query | Should -BeNullOrEmpty
            $Calls[0].Uri.Segments.Count | Should -Be 5
        }
    }

    It 'Shows the address as given in the error message' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Throw ([System.Exception]::new('sgt-test-transport-text'))

            $Thrown = $null
            try {
                $null = Remove-SGGlobalSuppression -EmailAddress 'one+tag@example.com' -Confirm:$false
            }
            catch {
                $Thrown = $_
            }

            $Thrown | Should -Not -BeNullOrEmpty
            $Thrown.Exception.Message | Should -BeExactly 'Failed to remove email address "one+tag@example.com" from global suppressions list. Unable to query SendGrid: sgt-test-transport-text'
        }
    }

    It 'Shows the address as given under -WhatIf' {
        $Run = Invoke-SgtInCountingHost -Script 'Remove-SGGlobalSuppression -EmailAddress ''one+tag@example.com'' -WhatIf'

        ($Run.HostLine -join "`n") | Should -BeLike '*Remove email address one+tag@example.com from global suppressions list.*'
        ($Run.HostLine -join "`n") | Should -Not -Match '%2B'
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
