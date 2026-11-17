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
            "$($Calls[0].Uri)" | Should -BeLike '*/suppression/unsubscribes/one@example.com'
            "$($Calls[1].Uri)" | Should -BeLike '*/suppression/unsubscribes/two@example.com'
        }
    }

    It 'Sends one Delete per address given with -EmailAddress' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = Remove-SGGlobalSuppression -EmailAddress 'one@example.com', 'two@example.com' -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 2
            "$($Calls[0].Uri)" | Should -BeLike '*/suppression/unsubscribes/one@example.com'
            "$($Calls[1].Uri)" | Should -BeLike '*/suppression/unsubscribes/two@example.com'
        }
    }

    It 'Sends the bare address for an address with a display name' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = Remove-SGGlobalSuppression -EmailAddress 'Name Placeholder <one@example.com>' -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            "$($Calls[0].Uri)" | Should -BeLike '*/suppression/unsubscribes/one@example.com'
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

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
