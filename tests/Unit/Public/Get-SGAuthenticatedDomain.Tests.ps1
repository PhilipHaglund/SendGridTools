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

    # The DynamicParam pages the same list before the process block does, so a plain call makes the page sequence twice. Only calls that carry limit= are counted.

    It 'Fixtures match the recorded structure' {
        function Get-PropertyPath ($Object, $Prefix) {
            foreach ($Property in $Object.PSObject.Properties) {
                $Path = if ($Prefix) { "$Prefix.$($Property.Name)" } else { $Property.Name }
                if ($Property.Value -is [System.Management.Automation.PSCustomObject]) { Get-PropertyPath -Object $Property.Value -Prefix $Path } else { $Path }
            }
        }
        $Parsed = Get-Content -LiteralPath $script:Fixture -Raw | ConvertFrom-Json
        # Windows PowerShell 5.1 returns a JSON array as one object; enumerate it through the pipeline to get the first element in both editions.
        $Element = @($Parsed | ForEach-Object { $_ })[0]
        $Expected = @('id', 'user_id', 'subdomain', 'domain', 'username', 'ips', 'custom_spf', 'default', 'legacy', 'automatic_security', 'valid', 'last_validation_attempt_at') +
            @(foreach ($Block in 'mail_cname', 'dkim1', 'dkim2') { foreach ($Field in 'valid', 'type', 'host', 'data') { "dns.$Block.$Field" } })
        @(Get-PropertyPath -Object $Element | Sort-Object) | Should -Be @($Expected | Sort-Object)
    }

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
            @($ListCalls | ForEach-Object { [int][regex]::Match("$($_.Uri)", 'offset=(\d+)').Groups[1].Value }) | Should -Be @(Get-SgtExpectedOffset -Count 51; Get-SgtExpectedOffset -Count 51)
            foreach ($Call in $ListCalls) { "$($Call.Uri)" | Should -Match '[?&]limit=50(&|$)' }
        }
    }

    It 'Stops after a short page' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:Fixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtPagedNetworkStub -Items @(New-SgtFixtureItem -Kind Domain -Count 51 -Path $Fixture) -Shape List

            $null = Get-SGAuthenticatedDomain -Confirm:$false

            @(Get-SgtListCall).Count | Should -Be 4
        }
    }

    It 'Reads three pages' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:Fixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtPagedNetworkStub -Items @(New-SgtFixtureItem -Kind Domain -Count 120 -Path $Fixture) -Shape List

            $Out = @(Get-SGAuthenticatedDomain -Confirm:$false)

            $Out.Count | Should -Be 120
            $ListCalls = @(Get-SgtListCall)
            @($ListCalls | ForEach-Object { [int][regex]::Match("$($_.Uri)", 'offset=(\d+)').Groups[1].Value }) | Should -Be @(0, 50, 100, 0, 50, 100)
        }
    }

    It 'Reads one page' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:Fixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtPagedNetworkStub -Items @(New-SgtFixtureItem -Kind Domain -Count 7 -Path $Fixture) -Shape List

            $Out = @(Get-SGAuthenticatedDomain -Confirm:$false)

            $Out.Count | Should -Be 7
            $ListCalls = @(Get-SgtListCall)
            $ListCalls.Count | Should -Be 2
            foreach ($Call in $ListCalls) { "$($Call.Uri)" | Should -Match 'offset=0' }
        }
    }

    It 'Returns nothing for an empty list' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtPagedNetworkStub -Items @() -Shape List

            $Out = @(Get-SGAuthenticatedDomain -Confirm:$false -ErrorAction Stop)

            $Out.Count | Should -Be 0
            @(Get-SgtListCall).Count | Should -Be 2
        }
    }

    It 'Offers no DomainName when there are no domains' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtPagedNetworkStub -Items @() -Shape List

            { Get-SGAuthenticatedDomain -DomainName 'x' -Confirm:$false } | Should -Throw
            $Out = @(Get-SGAuthenticatedDomain -Confirm:$false -ErrorAction Stop)
            $Out.Count | Should -Be 0
        }
    }

    It 'Asks once more after a full last page' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:Fixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtPagedNetworkStub -Items @(New-SgtFixtureItem -Kind Domain -Count 50 -Path $Fixture) -Shape List

            $Out = @(Get-SGAuthenticatedDomain -Confirm:$false)

            $Out.Count | Should -Be 50
            $ListCalls = @(Get-SgtListCall)
            @($ListCalls | ForEach-Object { [int][regex]::Match("$($_.Uri)", 'offset=(\d+)').Groups[1].Value }) | Should -Be @(0, 50, 0, 50)
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
            @($ListCalls | ForEach-Object { [int][regex]::Match("$($_.Uri)", 'offset=(\d+)').Groups[1].Value }) | Should -Be @(0, 50, 0, 50)
        }
    }

    It 'Sends the on-behalf-of header on every page' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:Fixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtPagedNetworkStub -Items @(New-SgtFixtureItem -Kind Domain -Count 51 -Path $Fixture) -Shape List

            $null = Get-SGAuthenticatedDomain -OnBehalfOf 'user-placeholder' -Confirm:$false

            $ListCalls = @(Get-SgtListCall)
            $ListCalls.Count | Should -Be 4
            # The first two calls are the DynamicParam's (it has never sent the header); the last two are the process block's pages.
            foreach ($Call in $ListCalls[2..3]) { $Call.Headers['on-behalf-of'] | Should -Be 'user-placeholder' }
        }
    }

    It 'Finds a domain on the second page by DomainName' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:Fixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtPagedNetworkStub -Items @(New-SgtFixtureItem -Kind Domain -Count 51 -Path $Fixture) -Shape List

            $Out = @(Get-SGAuthenticatedDomain -DomainName 'domain-51.example.com' -Confirm:$false)

            $ListCalls = @(Get-SgtListCall)
            @($ListCalls | ForEach-Object { [int][regex]::Match("$($_.Uri)", 'offset=(\d+)').Groups[1].Value }) | Should -Be @(0, 50)
            $Last = @(Get-SgtNetworkCall)[0][-1]
            "$($Last.Uri)" | Should -BeLike '*/whitelabel/domains/1051'
            "$($Last.Uri)" | Should -Not -Match 'limit='
            $Out.Count | Should -Be 1
            $Out[0].Domain | Should -Be 'domain-51.example.com'
        }
    }

    It 'Gets each id with one call and no paging' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:Fixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtPagedNetworkStub -Items @(New-SgtFixtureItem -Kind Domain -Count 51 -Path $Fixture) -Shape List

            $Out = @(Get-SGAuthenticatedDomain -Id '1001', '1002' -Confirm:$false)

            $Out.Count | Should -Be 2
            $Calls = @(Get-SgtNetworkCall)[0]
            $Calls.Count | Should -Be 2
            "$($Calls[0].Uri)" | Should -BeLike '*/whitelabel/domains/1001'
            "$($Calls[1].Uri)" | Should -BeLike '*/whitelabel/domains/1002'
            foreach ($Call in $Calls) { "$($Call.Uri)" | Should -Not -Match 'limit=|offset=' }
        }
    }

    It 'Gets an id given through the UniqueId alias with one call' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:Fixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtPagedNetworkStub -Items @(New-SgtFixtureItem -Kind Domain -Count 51 -Path $Fixture) -Shape List

            $Out = @(Get-SGAuthenticatedDomain -UniqueId '1003' -Confirm:$false)

            $Out.Count | Should -Be 1
            $Calls = @(Get-SgtNetworkCall)[0]
            $Calls.Count | Should -Be 1
            "$($Calls[0].Uri)" | Should -BeLike '*/whitelabel/domains/1003'
            "$($Calls[0].Uri)" | Should -Not -Match 'limit=|offset='
        }
    }

    It 'Gets piped ids with one call each after the DomainName list' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:Fixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtPagedNetworkStub -Items @(New-SgtFixtureItem -Kind Domain -Count 51 -Path $Fixture) -Shape List

            # The DynamicParam runs before the pipeline binds Id, so it pages the list once (two calls) before the id call.
            $Out = @('1001' | Get-SGAuthenticatedDomain -Confirm:$false)

            $Out.Count | Should -Be 1
            $Calls = @(Get-SgtNetworkCall)[0]
            $Calls.Count | Should -Be 3
            @($Calls[0..1] | ForEach-Object { [int][regex]::Match("$($_.Uri)", 'offset=(\d+)').Groups[1].Value }) | Should -Be @(0, 50)
            "$($Calls[2].Uri)" | Should -BeLike '*/whitelabel/domains/1001'
            "$($Calls[2].Uri)" | Should -Not -Match 'limit=|offset='
        }
    }

    It 'Fails as before without a session' {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
            { Get-SGAuthenticatedDomain -DomainName 'x' -Confirm:$false } | Should -Throw -ExpectedMessage '*Connect-SendGrid*'
            @(Get-SgtNetworkCall)[0].Count | Should -Be 0
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
            @(Get-SgtListCall).Count | Should -Be 4
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
