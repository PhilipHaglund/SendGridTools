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
    $script:ListFixture = Join-Path -Path $PSScriptRoot -ChildPath '../Fixtures/ips-list.json'
    $script:PageFixture = Join-Path -Path $PSScriptRoot -ChildPath '../Fixtures/send-ips-page.json'
}

AfterAll {
    Uninstall-SgtSessionHelper
    Disable-SgtNetworkTripwire
}

Describe 'Get-SGIPAddress' {
    BeforeAll {
        # Builds -Count result objects from the first result element of the page fixture, with ip 192.0.2.<n>.
        InModuleScope SendGridTools {
            function Script:New-IpItem {
                param([string]$Path, [int]$Count, [int]$First = 1)
                $Json = (@((Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json).result)[0]) | ConvertTo-Json -Depth 6
                for ($n = $First; $n -lt ($First + $Count); $n++) {
                    $Item = $Json | ConvertFrom-Json
                    $Item.ip = "192.0.2.$n"
                    $Item
                }
            }
        }
    }

    AfterAll {
        InModuleScope SendGridTools {
            Remove-Item -Path 'Function:\New-IpItem' -ErrorAction SilentlyContinue
        }
    }

    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
        Remove-Variable -Name SgtTestCultureName -Scope Global -ErrorAction SilentlyContinue
    }

    It 'Fixtures match the recorded structure' {
        $List = Get-Content -LiteralPath $script:ListFixture -Raw | ConvertFrom-Json
        $Page = Get-Content -LiteralPath $script:PageFixture -Raw | ConvertFrom-Json
        (@($List[0].PSObject.Properties.Name | Sort-Object) -join ',') | Should -Be 'assigned_at,ip,pools,rdns,start_date,subusers,warmup,whitelabeled'
        (@($Page.PSObject.Properties.Name | Sort-Object) -join ',') | Should -Be '_metadata,result'
        (@($Page.result[0].PSObject.Properties.Name | Sort-Object) -join ',') | Should -Be 'added_at,ip,is_auto_warmup,is_enabled,is_leased,is_parent_assigned,pools,region,updated_at'
        $Next = @($Page._metadata.next_params.PSObject.Properties.Name)
        $Next | Should -Contain 'after_key'
        $Next | Should -Contain 'before_key'
        $Next | Should -Contain 'include_region'
    }

    It 'Sends the plain request without the switch and adds no Region property' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:ListFixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response (Get-Content -LiteralPath $Fixture -Raw | ConvertFrom-Json)

            $Out = @(Get-SGIPAddress)

            $Calls = @(Get-SgtNetworkCall)[0]
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Get'
            "$($Calls[0].Uri)" | Should -Be 'https://api.sendgrid.com/v3/ips'
            $Out.Count | Should -Be 1
            # Invoke-SendGrid keeps an empty array as a property with an empty value (D8).
            (@($Out[0].PSObject.Properties.Name | Sort-Object) -join ',') | Should -Be 'AssignedAt,Ip,Pools,Rdns,StartDate,Subusers,Warmup,Whitelabeled'
            $Out[0].PSObject.Properties.Name | Should -Not -Contain 'Region'
        }
    }

    It 'Reads send_ips/ips with include_region and returns the objects with -IncludeRegion' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:PageFixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response (Get-Content -LiteralPath $Fixture -Raw | ConvertFrom-Json)

            $Out = @(Get-SGIPAddress -IncludeRegion)

            $Calls = @(Get-SgtNetworkCall)[0]
            $Calls.Count | Should -Be 1
            "$($Calls[0].Uri)" | Should -Be 'https://api.sendgrid.com/v3/send_ips/ips?include_region=true'
            $Out.Count | Should -Be 2
            foreach ($Object in $Out) {
                (@($Object.PSObject.Properties.Name | Sort-Object) -join ',') | Should -Be 'AddedAt,Ip,IsAutoWarmup,IsEnabled,IsLeased,IsParentAssigned,Pools,Region,UpdatedAt'
                $Object.Region | Should -Be 'us'
                $Object.PSObject.Properties.Name | Should -Not -Contain 'Metadata'
                $Object.PSObject.Properties.Name | Should -Not -Contain '_metadata'
                $Object.PSObject.Properties.Name | Should -Not -Contain 'Result'
            }
            @($Out.Ip) | Should -Be @('192.0.2.1', '192.0.2.2')
        }
    }

    It 'Names the properties the way Invoke-SendGrid does' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:PageFixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response (Get-Content -LiteralPath $Fixture -Raw | ConvertFrom-Json)
            $Reference = @(Invoke-SendGrid -Method Get -Namespace 'send_ips/ips?include_region=true')
            Set-SgtNetworkStub -Response (Get-Content -LiteralPath $Fixture -Raw | ConvertFrom-Json)

            $Out = @(Get-SGIPAddress -IncludeRegion)

            $Reference.Count | Should -Be 2
            $Out.Count | Should -Be 2
            for ($i = 0; $i -lt $Reference.Count; $i++) {
                foreach ($Property in $Reference[$i].PSObject.Properties) {
                    $Out[$i].PSObject.Properties.Name | Should -Contain $Property.Name
                    # Both readers turn a whole number within Int32 under a time name into a date (D30, D52).
                    "$($Out[$i].($Property.Name))" | Should -Be "$($Property.Value)"
                }
                # Both readers keep an empty array (D8).
                $Reference[$i].PSObject.Properties.Name | Should -Contain 'Pools'
                $Out[$i].PSObject.Properties.Name | Should -Contain 'Pools'
                @($Out[$i].Pools).Count | Should -Be 0
            }
        }
    }

    It 'Names the properties of -IncludeRegion the same under the Turkish culture (D34)' {
        $global:SgtTestCultureName = 'tr-TR'
        # The module no longer calls Get-Culture. The mock stays: in Windows PowerShell 5.1 Get-Culture does not follow the thread culture, so only this mock turns the test red if (Get-Culture).TextInfo comes back.
        Mock -CommandName Get-Culture -ModuleName SendGridTools -MockWith { [System.Globalization.CultureInfo]::GetCultureInfo($global:SgtTestCultureName) }
        $Out = InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:PageFixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response (Get-Content -LiteralPath $Fixture -Raw | ConvertFrom-Json)
            $SavedCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
            try {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('tr-TR')
                @(Get-SGIPAddress -IncludeRegion)
            }
            finally {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $SavedCulture
            }
        }

        $Out.Count | Should -Be 2
        foreach ($Object in $Out) {
            (@($Object.PSObject.Properties.Name | Sort-Object) -join ',') | Should -BeExactly 'AddedAt,Ip,IsAutoWarmup,IsEnabled,IsLeased,IsParentAssigned,Pools,Region,UpdatedAt'
        }
    }

    It 'Follows after_key across two pages' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:PageFixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtCursorNetworkStub -Page @(
                @{ Items = @(New-IpItem -Path $Fixture -Count 2 -First 1); AfterKey = 'cursor-1' }
                @{ Items = @(New-IpItem -Path $Fixture -Count 1 -First 3); AfterKey = $null }
            )

            $Out = @(Get-SGIPAddress -IncludeRegion)

            $Calls = @(Get-SgtNetworkCall)[0]
            $Calls.Count | Should -Be 2
            @($Out.Ip) | Should -Be @('192.0.2.1', '192.0.2.2', '192.0.2.3')
            "$($Calls[0].Uri)" | Should -Be 'https://api.sendgrid.com/v3/send_ips/ips?include_region=true'
            "$($Calls[1].Uri)" | Should -Be 'https://api.sendgrid.com/v3/send_ips/ips?include_region=true&after_key=cursor-1'
        }
    }

    It 'Follows after_key across three pages' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:PageFixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtCursorNetworkStub -Page @(
                @{ Items = @(New-IpItem -Path $Fixture -Count 2 -First 1); AfterKey = 'cursor-1' }
                @{ Items = @(New-IpItem -Path $Fixture -Count 2 -First 3); AfterKey = 'cursor-2' }
                @{ Items = @(New-IpItem -Path $Fixture -Count 1 -First 5); AfterKey = $null }
            )

            $Out = @(Get-SGIPAddress -IncludeRegion)

            $Calls = @(Get-SgtNetworkCall)[0]
            $Calls.Count | Should -Be 3
            @($Out.Ip) | Should -Be @('192.0.2.1', '192.0.2.2', '192.0.2.3', '192.0.2.4', '192.0.2.5')
            "$($Calls[2].Uri)" | Should -BeLike '*&after_key=cursor-2'
        }
    }

    It 'Returns AddedAt and UpdatedAt as dates (D52)' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:PageFixture } {
            $Epoch = [datetime]::new(1970, 1, 1, 0, 0, 0, 0)
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            $Item = New-IpItem -Path $Fixture -Count 1 -First 1
            $Item.updated_at = 1700000000
            $Item.added_at = 1600000000
            Set-SgtCursorNetworkStub -Page @(@{ Items = @($Item); AfterKey = $null })

            $Out = @(Get-SGIPAddress -IncludeRegion)

            $Out.Count | Should -Be 1
            $Out[0].UpdatedAt | Should -BeOfType [datetime]
            $Out[0].UpdatedAt | Should -Be $Epoch.AddSeconds(1700000000)
            $Out[0].AddedAt | Should -BeOfType [datetime]
            $Out[0].AddedAt | Should -Be $Epoch.AddSeconds(1600000000)
        }
    }

    It 'Returns AddedAt as a number when it is outside Int32 (D52)' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:PageFixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            $Item = New-IpItem -Path $Fixture -Count 1 -First 1
            $Item.added_at = 3000000000
            Set-SgtCursorNetworkStub -Page @(@{ Items = @($Item); AfterKey = $null })

            $Out = @(Get-SGIPAddress -IncludeRegion)

            $Out.Count | Should -Be 1
            $Out[0].AddedAt | Should -Not -BeOfType [datetime]
            $Out[0].AddedAt | Should -Be 3000000000
        }
    }

    It 'Follows an after_key past a page without items' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:PageFixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtCursorNetworkStub -Page @(
                @{ Items = @(); AfterKey = 'cursor-1' }
                @{ Items = @(New-IpItem -Path $Fixture -Count 1 -First 1); AfterKey = $null }
            )

            $Out = @(Get-SGIPAddress -IncludeRegion)

            @(Get-SgtNetworkCall)[0].Count | Should -Be 2
            $Out.Count | Should -Be 1
        }
    }

    It 'Follows a numeric after_key' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:PageFixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtCursorNetworkStub -Page @(
                @{ Items = @(New-IpItem -Path $Fixture -Count 1 -First 1); AfterKey = 42 }
                @{ Items = @(New-IpItem -Path $Fixture -Count 1 -First 2); AfterKey = $null }
            )

            $Out = @(Get-SGIPAddress -IncludeRegion)

            $Calls = @(Get-SgtNetworkCall)[0]
            $Calls.Count | Should -Be 2
            $Out.Count | Should -Be 2
            "$($Calls[1].Uri)" | Should -BeLike '*&after_key=42'
        }
    }

    It 'Stops on an empty after_key without a warning' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:PageFixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtCursorNetworkStub -Page @(
                @{ Items = @(New-IpItem -Path $Fixture -Count 2 -First 1); AfterKey = '' }
            )

            $Out = @(Get-SGIPAddress -IncludeRegion -WarningVariable Warned -WarningAction SilentlyContinue)

            @(Get-SgtNetworkCall)[0].Count | Should -Be 1
            $Out.Count | Should -Be 2
            @($Warned).Count | Should -Be 0
        }
    }

    It 'Stops with one warning when an after_key comes a second time' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:PageFixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtCursorNetworkStub -Page @(
                @{ Items = @(New-IpItem -Path $Fixture -Count 1 -First 1); AfterKey = 'cursor-1' }
                @{ Items = @(New-IpItem -Path $Fixture -Count 1 -First 2); AfterKey = 'cursor-1' }
            )

            $Out = @(Get-SGIPAddress -IncludeRegion -WarningVariable Warned -WarningAction SilentlyContinue)

            @(Get-SgtNetworkCall)[0].Count | Should -Be 2
            $Out.Count | Should -Be 2
            @($Warned).Count | Should -Be 1
            "$($Warned[0])" | Should -Match 'same after_key'
        }
    }

    It 'Stops after 100 pages with one warning that leaks no key or address' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtCursorNetworkStub -Endless

            $Out = @(Get-SGIPAddress -IncludeRegion -WarningVariable Warned -WarningAction SilentlyContinue)

            @(Get-SgtNetworkCall)[0].Count | Should -Be 100
            $Out.Count | Should -Be 100
            @($Warned).Count | Should -Be 1
            "$($Warned[0])" | Should -Match 'after 100 pages'
            "$($Warned[0])" | Should -Not -Match 'cursor-'
            "$($Warned[0])" | Should -Not -Match '192\.0\.2\.'
        }
    }

    It 'Escapes an after_key that needs it' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:PageFixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtCursorNetworkStub -Page @(
                @{ Items = @(New-IpItem -Path $Fixture -Count 1 -First 1); AfterKey = 'a b/c+d' }
                @{ Items = @(New-IpItem -Path $Fixture -Count 1 -First 2); AfterKey = $null }
            )

            $Out = @(Get-SGIPAddress -IncludeRegion)

            $Calls = @(Get-SgtNetworkCall)[0]
            $Calls.Count | Should -Be 2
            $Out.Count | Should -Be 2
            # A [uri] shows %20 as a space in ToString, so read the escaped form.
            ([uri]$Calls[1].Uri).AbsoluteUri | Should -BeLike '*after_key=a%20b%2Fc%2Bd*'
        }
    }

    It 'Reads every page from the EU host on an EU session' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:PageFixture } {
            $script:Session = [SendGridSession]::new([uri]'https://api.eu.sendgrid.com/v3')
            $script:Session._Credential = $Cred
            $script:Session._Connected = $true
            $script:Session._CreateDateTime = Get-Date
            Set-SgtCursorNetworkStub -Page @(
                @{ Items = @(New-IpItem -Path $Fixture -Count 2 -First 1); AfterKey = 'cursor-1' }
                @{ Items = @(New-IpItem -Path $Fixture -Count 1 -First 3); AfterKey = $null }
            )

            $Out = @(Get-SGIPAddress -IncludeRegion)

            $Calls = @(Get-SgtNetworkCall)[0]
            $Calls.Count | Should -Be 2
            $Out.Count | Should -Be 3
            foreach ($Call in $Calls) {
                ([uri]"$($Call.Uri)").Host | Should -Be 'api.eu.sendgrid.com'
                "$($Call.Uri)" | Should -BeLike 'https://api.eu.sendgrid.com/v3/send_ips/ips?include_region=true*'
            }
        }
    }

    It 'Wraps a failed request in an error' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Throw (New-SgtErrorRecord -Message 'boom')

            { Get-SGIPAddress -IncludeRegion -ErrorAction Stop } | Should -Throw -ExpectedMessage '*Failed to retrieve SendGrid IPs*'
        }
    }

    It 'Throws and makes no call without a session' {
        InModuleScope SendGridTools {
            $script:Session = $null
            Set-SgtNetworkStub -Response ([pscustomobject]@{ result = @() })

            { Get-SGIPAddress -IncludeRegion -ErrorAction Stop } | Should -Throw -ExpectedMessage '*Connect-SendGrid*'
            @(Get-SgtNetworkCall)[0].Count | Should -Be 0
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
