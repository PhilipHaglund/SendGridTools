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

Describe 'Set-SGSuppressionGroup request' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Sends one Patch per id given through the pipeline as <Name>' -ForEach @(
        @{ Name = 'integers'; Items = @(1001, 1002); Expected = @('1001', '1002') }
        @{ Name = 'strings'; Items = @('1001', '1002'); Expected = @('1001', '1002') }
        @{ Name = 'objects with an Id property'; Items = @([pscustomobject]@{ Id = 1001 }, [pscustomobject]@{ Id = 1002 }); Expected = @('1001', '1002') }
    ) {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Items = $Items; Expected = $Expected } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = $Items | Set-SGSuppressionGroup -Name 'name-placeholder' -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be $Expected.Count
            for ($i = 0; $i -lt $Expected.Count; $i++) {
                $Calls[$i].Method | Should -Be 'Patch'
                "$($Calls[$i].Uri)" | Should -BeLike "*/asm/groups/$($Expected[$i])"
            }
        }
    }

    It 'Sends one request for -UniqueId 1001' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = Set-SGSuppressionGroup -UniqueId 1001 -Name 'name-placeholder' -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Patch'
            "$($Calls[0].Uri)" | Should -BeLike '*/asm/groups/1001'
        }
    }

    It 'Sends nothing for a piped object it cannot read as an id (<Name>)' -ForEach @(
        @{ Name = 'an object without Id'; Item = [pscustomobject]@{ Name = 'x' } }
        @{ Name = 'a non-numeric string'; Item = 'abc' }
    ) {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Item = $Item } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            { $Item | Set-SGSuppressionGroup -Confirm:$false } | Should -Throw

            Get-SgtNetworkCall | Should -BeNullOrEmpty
        }
    }

    It 'Sends nothing under WhatIf with piped ids' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = 1001, 1002 | Set-SGSuppressionGroup -Name 'name-placeholder' -WhatIf

            Get-SgtNetworkCall | Should -BeNullOrEmpty
        }
    }

    It 'Sends only the description when only -Description is given' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = Set-SGSuppressionGroup -UniqueId 1001 -Description 'desc-placeholder' -Confirm:$false

            $Sent = (Get-SgtNetworkCall)[0].Body | ConvertFrom-Json
            @($Sent.PSObject.Properties.Name) | Should -Be @('description')
            $Sent.description | Should -Be 'desc-placeholder'
        }
    }

    It 'Sends name, description and is_default when all are given' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = Set-SGSuppressionGroup -UniqueId 1001 -Name 'name-placeholder' -Description 'desc-placeholder' -IsDefault:$false -Confirm:$false

            $Sent = (Get-SgtNetworkCall)[0].Body | ConvertFrom-Json
            @($Sent.PSObject.Properties.Name | Sort-Object) | Should -Be @('description', 'is_default', 'name')
            $Sent.name | Should -Be 'name-placeholder'
            $Sent.description | Should -Be 'desc-placeholder'
            $Sent.is_default | Should -BeFalse
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
