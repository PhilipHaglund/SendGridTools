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
    $script:PlainFixture = Join-Path -Path $PSScriptRoot -ChildPath '../Fixtures/subusers-page.json'
    $script:RegionFixture = Join-Path -Path $PSScriptRoot -ChildPath '../Fixtures/subusers-include-region-page.json'
}

AfterAll {
    Uninstall-SgtSessionHelper
    Disable-SgtNetworkTripwire
}

Describe 'Get-SGSubuser region' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Fixtures match the recorded structure' {
        $Plain = Get-Content -LiteralPath $script:PlainFixture -Raw | ConvertFrom-Json
        $Region = Get-Content -LiteralPath $script:RegionFixture -Raw | ConvertFrom-Json
        (@($Plain[0].PSObject.Properties.Name | Sort-Object) -join ',') | Should -Be 'disabled,email,id,username'
        (@($Region[0].PSObject.Properties.Name | Sort-Object) -join ',') | Should -Be 'disabled,email,id,region,username'
    }

    It 'Sends the plain request without parameters and adds no Region property' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Plain = $script:PlainFixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response (Get-Content -LiteralPath $Plain -Raw | ConvertFrom-Json)

            $Out = @(Get-SGSubuser -Confirm:$false)

            $Calls = @(Get-SgtNetworkCall)[0]
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Get'
            "$($Calls[0].Uri)" | Should -Be 'https://api.sendgrid.com/v3/subusers'
            "$($Calls[0].Uri)" | Should -Not -Match 'include_region|region='
            $Out.Count | Should -Be 2
            foreach ($Object in $Out) { $Object.PSObject.Properties.Name | Should -Not -Contain 'Region' }
        }
    }

    It 'Adds include_region and returns Region with -IncludeRegion' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:RegionFixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response (Get-Content -LiteralPath $Fixture -Raw | ConvertFrom-Json)

            $Out = @(Get-SGSubuser -IncludeRegion -Confirm:$false)

            $Calls = @(Get-SgtNetworkCall)[0]
            $Calls.Count | Should -Be 1
            "$($Calls[0].Uri)" | Should -Be 'https://api.sendgrid.com/v3/subusers?include_region=true'
            foreach ($Object in $Out) { $Object.PSObject.Properties.Name | Should -Contain 'Region' }
            @($Out.Region) | Should -Be @('global', 'eu')
        }
    }

    It 'Sends region=<Expected> for -Region <Value>' -TestCases @(
        @{ Value = 'All'; Expected = 'all' }
        @{ Value = 'Global'; Expected = 'global' }
        @{ Value = 'EU'; Expected = 'eu' }
    ) {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:RegionFixture; Value = $Value; Expected = $Expected } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response (Get-Content -LiteralPath $Fixture -Raw | ConvertFrom-Json)

            $null = Get-SGSubuser -Region $Value -Confirm:$false

            $Calls = @(Get-SgtNetworkCall)[0]
            $Calls.Count | Should -Be 1
            "$($Calls[0].Uri)" | Should -Be "https://api.sendgrid.com/v3/subusers?include_region=true&region=$Expected"
        }
    }

    It 'Lower-cases the region value typed in lower case' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:RegionFixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response (Get-Content -LiteralPath $Fixture -Raw | ConvertFrom-Json)

            $null = Get-SGSubuser -Region eu -Confirm:$false

            "$((@(Get-SgtNetworkCall)[0])[0].Uri)" | Should -Be 'https://api.sendgrid.com/v3/subusers?include_region=true&region=eu'
        }
    }

    It 'Adds include_region only once with -IncludeRegion and -Region' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:RegionFixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response (Get-Content -LiteralPath $Fixture -Raw | ConvertFrom-Json)

            $null = Get-SGSubuser -IncludeRegion -Region EU -Confirm:$false

            $Uri = "$((@(Get-SgtNetworkCall)[0])[0].Uri)"
            $Uri | Should -Be 'https://api.sendgrid.com/v3/subusers?include_region=true&region=eu'
            ([regex]::Matches($Uri, 'include_region=true')).Count | Should -Be 1
        }
    }

    It 'Keeps limit and offset first and appends the region query' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:RegionFixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response (Get-Content -LiteralPath $Fixture -Raw | ConvertFrom-Json)

            $null = Get-SGSubuser -Limit 2 -Offset 4 -Confirm:$false
            "$((@(Get-SgtNetworkCall)[0])[0].Uri)" | Should -Be 'https://api.sendgrid.com/v3/subusers?limit=2&offset=4'

            Set-SgtNetworkStub -Response (Get-Content -LiteralPath $Fixture -Raw | ConvertFrom-Json)
            $null = Get-SGSubuser -Limit 2 -Offset 4 -IncludeRegion -Confirm:$false
            "$((@(Get-SgtNetworkCall)[0])[0].Uri)" | Should -Be 'https://api.sendgrid.com/v3/subusers?limit=2&offset=4&include_region=true'

            Set-SgtNetworkStub -Response (Get-Content -LiteralPath $Fixture -Raw | ConvertFrom-Json)
            $null = Get-SGSubuser -Limit 2 -Offset 4 -Region Global -Confirm:$false
            "$((@(Get-SgtNetworkCall)[0])[0].Uri)" | Should -Be 'https://api.sendgrid.com/v3/subusers?limit=2&offset=4&include_region=true&region=global'
        }
    }

    It 'Sends no region query and no warning for a single Subuser alone' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:RegionFixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response (Get-Content -LiteralPath $Fixture -Raw | ConvertFrom-Json)

            $null = Get-SGSubuser -Username sgt-test-subuser-1 -Confirm:$false -WarningVariable Warned -WarningAction SilentlyContinue

            "$((@(Get-SgtNetworkCall)[0])[0].Uri)" | Should -Be 'https://api.sendgrid.com/v3/subusers/sgt-test-subuser-1'
            @($Warned).Count | Should -Be 0
        }
    }

    It 'Sends no warning for -IncludeRegion alone' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:RegionFixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response (Get-Content -LiteralPath $Fixture -Raw | ConvertFrom-Json)

            $null = Get-SGSubuser -IncludeRegion -Confirm:$false -WarningVariable Warned -WarningAction SilentlyContinue

            @($Warned).Count | Should -Be 0
        }
    }

    It 'Sends no region query and warns once for a single Subuser with <Name>' -TestCases @(
        @{ Name = '-IncludeRegion'; Splat = @{ IncludeRegion = $true } }
        @{ Name = '-Region EU'; Splat = @{ Region = 'EU' } }
    ) {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:RegionFixture; Splat = $Splat } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response (Get-Content -LiteralPath $Fixture -Raw | ConvertFrom-Json)

            $null = Get-SGSubuser -Username sgt-test-subuser-1 @Splat -Confirm:$false -WarningVariable Warned -WarningAction SilentlyContinue

            $Calls = @(Get-SgtNetworkCall)[0]
            $Calls.Count | Should -Be 1
            "$($Calls[0].Uri)" | Should -Be 'https://api.sendgrid.com/v3/subusers/sgt-test-subuser-1'
            @($Warned).Count | Should -Be 1
            "$($Warned[0])" | Should -Match 'single subuser'
            "$($Warned[0])" | Should -Not -Match 'sgt-test-subuser'
        }
    }

    It 'Rejects a region outside All, Global and EU and makes no call' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:RegionFixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response (Get-Content -LiteralPath $Fixture -Raw | ConvertFrom-Json)

            { Get-SGSubuser -Region US -Confirm:$false } | Should -Throw -ErrorId 'ParameterArgumentValidationError*'
            @(Get-SgtNetworkCall)[0].Count | Should -Be 0
        }
    }

    It 'Warns once, not once per piped object, and sends no region query for piped Usernames' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:RegionFixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response (Get-Content -LiteralPath $Fixture -Raw | ConvertFrom-Json)

            $null = @(
                [pscustomobject]@{ Username = 'sgt-test-subuser-1' }
                [pscustomobject]@{ Username = 'sgt-test-subuser-2' }
            ) | Get-SGSubuser -IncludeRegion -Confirm:$false -WarningVariable Warned -WarningAction SilentlyContinue

            $Calls = @(Get-SgtNetworkCall)[0]
            $Calls.Count | Should -Be 2
            foreach ($Call in $Calls) { "$($Call.Uri)" | Should -Not -Match '\?' }
            @($Warned).Count | Should -Be 1
        }
    }

    It 'Does not bind Region from a piped object' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:RegionFixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response (Get-Content -LiteralPath $Fixture -Raw | ConvertFrom-Json)

            $null = [pscustomobject]@{ Username = 'sgt-test-subuser-1'; Region = 'eu' } | Get-SGSubuser -Confirm:$false

            $Calls = @(Get-SgtNetworkCall)[0]
            $Calls.Count | Should -Be 1
            "$($Calls[0].Uri)" | Should -Be 'https://api.sendgrid.com/v3/subusers/sgt-test-subuser-1'
            "$($Calls[0].Uri)" | Should -Not -Match '\?'
        }
    }

    It 'Uses the EU host on an EU session' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:RegionFixture } {
            $script:Session = [SendGridSession]::new([uri]'https://api.eu.sendgrid.com/v3')
            $script:Session._Credential = $Cred
            $script:Session._Connected = $true
            $script:Session._CreateDateTime = Get-Date
            Set-SgtNetworkStub -Response (Get-Content -LiteralPath $Fixture -Raw | ConvertFrom-Json)

            $null = Get-SGSubuser -Region EU -Confirm:$false

            $Calls = @(Get-SgtNetworkCall)[0]
            $Calls.Count | Should -Be 1
            ([uri]"$($Calls[0].Uri)").Host | Should -Be 'api.eu.sendgrid.com'
            "$($Calls[0].Uri)" | Should -Be 'https://api.eu.sendgrid.com/v3/subusers?include_region=true&region=eu'
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
