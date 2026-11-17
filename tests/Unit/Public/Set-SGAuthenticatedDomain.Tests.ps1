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

Describe 'Set-SGAuthenticatedDomain request' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Patches the one domain it is given with the default flag' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = Set-SGAuthenticatedDomain -UniqueId '1001' -SetDefault -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Patch'
            "$($Calls[0].Uri)" | Should -BeLike '*/whitelabel/domains/1001'
            $Sent = $Calls[0].Body | ConvertFrom-Json
            @($Sent.PSObject.Properties.Name | Sort-Object) | Should -Be @('default')
            $Sent.default | Should -BeTrue
        }
    }

    It 'Patches each domain it is given with the custom SPF flag' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = Set-SGAuthenticatedDomain -UniqueId '1001', '1002' -SetCustomSPF -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 2
            $Calls[0].Method | Should -Be 'Patch'
            "$($Calls[0].Uri)" | Should -BeLike '*/whitelabel/domains/1001'
            $Calls[1].Method | Should -Be 'Patch'
            "$($Calls[1].Uri)" | Should -BeLike '*/whitelabel/domains/1002'
            foreach ($Call in $Calls) {
                $Sent = $Call.Body | ConvertFrom-Json
                @($Sent.PSObject.Properties.Name | Sort-Object) | Should -Be @('custom_spf')
                $Sent.custom_spf | Should -BeTrue
            }
        }
    }

    It 'Sends nothing under WhatIf' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = Set-SGAuthenticatedDomain -UniqueId '1001', '1002' -SetDefault -WhatIf

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 0
        }
    }

    It 'Patches the domain given through the pipeline as <Name>' -ForEach @(
        @{ Name = 'strings'; Ids = @('1001', '1002'); Expected = @('1001', '1002') }
        @{ Name = 'an integer'; Ids = @(1001); Expected = @('1001') }
        @{ Name = 'an object with an Id property'; Ids = @([pscustomobject]@{ Id = 1001 }); Expected = @('1001') }
    ) {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Ids = $Ids; Expected = $Expected } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = $Ids | Set-SGAuthenticatedDomain -SetDefault -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be $Expected.Count
            for ($i = 0; $i -lt $Expected.Count; $i++) {
                $Calls[$i].Method | Should -Be 'Patch'
                "$($Calls[$i].Uri)" | Should -BeLike "*/whitelabel/domains/$($Expected[$i])"
                $Sent = $Calls[$i].Body | ConvertFrom-Json
                $Sent.default | Should -BeTrue
            }
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
