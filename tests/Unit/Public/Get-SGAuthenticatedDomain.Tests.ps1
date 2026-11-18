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
    $script:Fixture = Join-Path -Path $PSScriptRoot -ChildPath '../Fixtures/whitelabel-domains-page.json'
}

AfterAll {
    Uninstall-SgtSessionHelper
    Disable-SgtNetworkTripwire
}

Describe 'Get-SGAuthenticatedDomain list paging' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    # The DynamicParam also lists the domains (one call without limit, before it pages too), so only calls that carry limit= are counted.

    It 'Reads two pages and returns every domain' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:Fixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            $Items = @(New-SgtFixtureItem -Kind Domain -Count 51 -Path $Fixture)
            Set-SgtPagedNetworkStub -Items $Items -Shape List

            $Out = @(Get-SGAuthenticatedDomain -Confirm:$false)

            $Out.Count | Should -Be 51
            @($Out.Id) | Should -Be @($Items.id | ForEach-Object { "$_" })
            @($Out.Id | Select-Object -Unique).Count | Should -Be 51
            $ListCalls = @(Get-SgtListCall)
            @($ListCalls | ForEach-Object { [int][regex]::Match("$($_.Uri)", 'offset=(\d+)').Groups[1].Value }) | Should -Be @(Get-SgtExpectedOffset -Count 51)
            foreach ($Call in $ListCalls) { "$($Call.Uri)" | Should -Match '[?&]limit=50(&|$)' }
        }
    }

    It 'Stops after a short page' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:Fixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtPagedNetworkStub -Items @(New-SgtFixtureItem -Kind Domain -Count 51 -Path $Fixture) -Shape List

            $null = Get-SGAuthenticatedDomain -Confirm:$false

            @(Get-SgtListCall).Count | Should -Be 2
        }
    }

    It 'Reads three pages' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:Fixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtPagedNetworkStub -Items @(New-SgtFixtureItem -Kind Domain -Count 120 -Path $Fixture) -Shape List

            $Out = @(Get-SGAuthenticatedDomain -Confirm:$false)

            $Out.Count | Should -Be 120
            $ListCalls = @(Get-SgtListCall)
            @($ListCalls | ForEach-Object { [int][regex]::Match("$($_.Uri)", 'offset=(\d+)').Groups[1].Value }) | Should -Be @(0, 50, 100)
        }
    }

    It 'Reads one page' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:Fixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtPagedNetworkStub -Items @(New-SgtFixtureItem -Kind Domain -Count 7 -Path $Fixture) -Shape List

            $Out = @(Get-SGAuthenticatedDomain -Confirm:$false)

            $Out.Count | Should -Be 7
            $ListCalls = @(Get-SgtListCall)
            $ListCalls.Count | Should -Be 1
            "$($ListCalls[0].Uri)" | Should -Match 'offset=0'
        }
    }

    # Pre-existing and outside this task: with no domains at all the DynamicParam builds a ValidateSet from a null list and
    # the call fails before the process block runs. The empty-list path of the paging itself is covered for API keys.
    It 'Returns nothing for an empty list' -Skip:$true {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtPagedNetworkStub -Items @() -Shape List

            $Out = @(Get-SGAuthenticatedDomain -Confirm:$false -ErrorAction Stop)

            $Out.Count | Should -Be 0
            @(Get-SgtListCall).Count | Should -Be 1
        }
    }

    It 'Asks once more after a full last page' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:Fixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtPagedNetworkStub -Items @(New-SgtFixtureItem -Kind Domain -Count 50 -Path $Fixture) -Shape List

            $Out = @(Get-SGAuthenticatedDomain -Confirm:$false)

            $Out.Count | Should -Be 50
            $ListCalls = @(Get-SgtListCall)
            @($ListCalls | ForEach-Object { [int][regex]::Match("$($_.Uri)", 'offset=(\d+)').Groups[1].Value }) | Should -Be @(0, 50)
        }
    }

    It 'Stops when the server ignores offset' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:Fixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtPagedNetworkStub -Items @(New-SgtFixtureItem -Kind Domain -Count 60 -Path $Fixture) -Shape List -IgnoreOffset

            $Out = @(Get-SGAuthenticatedDomain -Confirm:$false)

            $Out.Count | Should -Be 50
            @($Out.Id | Select-Object -Unique).Count | Should -Be 50
            $ListCalls = @(Get-SgtListCall)
            @($ListCalls | ForEach-Object { [int][regex]::Match("$($_.Uri)", 'offset=(\d+)').Groups[1].Value }) | Should -Be @(0, 50)
        }
    }

    It 'Sends the on-behalf-of header on every page' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:Fixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtPagedNetworkStub -Items @(New-SgtFixtureItem -Kind Domain -Count 51 -Path $Fixture) -Shape List

            $null = Get-SGAuthenticatedDomain -OnBehalfOf 'user-placeholder' -Confirm:$false

            $ListCalls = @(Get-SgtListCall)
            $ListCalls.Count | Should -Be 2
            foreach ($Call in $ListCalls) { $Call.Headers['on-behalf-of'] | Should -Be 'user-placeholder' }
        }
    }

    It 'Keeps the output shape' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:Fixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtPagedNetworkStub -Items @(New-SgtFixtureItem -Kind Domain -Count 51 -Path $Fixture) -Shape List

            $Out = @(Get-SGAuthenticatedDomain -Confirm:$false)
            $Expected = @(Invoke-SendGrid -Method Get -Namespace 'whitelabel/domains' -CallingCmdlet 'Get-SGAuthenticatedDomain')
            $ExpectedNames = @($Expected[0].PSObject.Properties.Name | Sort-Object)

            $Expected.Count | Should -Be 51
            foreach ($Object in $Out) {
                $Object.PSObject.TypeNames | Should -Contain 'SendGridTools.Get.SGAuthenticatedDomain'
                @($Object.PSObject.Properties.Name | Sort-Object) | Should -Be $ExpectedNames
            }
        }
    }

    It 'Pages with ShowDNS' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:Fixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtPagedNetworkStub -Items @(New-SgtFixtureItem -Kind Domain -Count 51 -Path $Fixture) -Shape List

            $Out = @(Get-SGAuthenticatedDomain -ShowDNS -Confirm:$false)

            $Out.Count | Should -Be 51
            foreach ($Object in $Out) { $Object.PSObject.TypeNames | Should -Not -Contain 'SendGridTools.Get.SGAuthenticatedDomain' }
            @(Get-SgtListCall).Count | Should -Be 2
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
