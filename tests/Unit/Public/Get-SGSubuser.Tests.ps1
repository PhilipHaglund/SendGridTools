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

            "$((@(Get-SgtNetworkCall)[0])[0].Uri)" | Should -Be 'https://api.sendgrid.com/v3/subusers?username=sgt-test-subuser-1'
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
            "$($Calls[0].Uri)" | Should -Be 'https://api.sendgrid.com/v3/subusers?username=sgt-test-subuser-1'
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
            foreach ($Call in $Calls) { "$($Call.Uri)" | Should -Not -Match 'region' }
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
            "$($Calls[0].Uri)" | Should -Be 'https://api.sendgrid.com/v3/subusers?username=sgt-test-subuser-1'
            "$($Calls[0].Uri)" | Should -Not -Match 'region'
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

Describe 'Get-SGSubuser -Username lookup' {
    BeforeEach {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Plain = $script:PlainFixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response (Get-Content -LiteralPath $Plain -Raw | ConvertFrom-Json)
        }
    }

    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Sends the username as the documented filter' {
        InModuleScope SendGridTools {
            $null = Get-SGSubuser -Username sgt-test-subuser-1 -Confirm:$false

            $Calls = @(Get-SgtNetworkCall)[0]
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Get'
            ([uri]$Calls[0].Uri).AbsoluteUri | Should -Be 'https://api.sendgrid.com/v3/subusers?username=sgt-test-subuser-1'
        }
    }

    It 'Sends neither limit nor offset with -Username, and warns' {
        InModuleScope SendGridTools {
            $Text = "SendGrid's username filter also returns names that start with the value: -Limit and -Offset apply only when -Username is not given."

            $null = Get-SGSubuser -Username sgt-test-subuser-1 -Limit 2 -Offset 1 -Confirm:$false -WarningVariable Warned -WarningAction SilentlyContinue
            $Calls = @(Get-SgtNetworkCall)[0]
            $Calls.Count | Should -Be 1
            ([uri]$Calls[0].Uri).AbsoluteUri | Should -Be 'https://api.sendgrid.com/v3/subusers?username=sgt-test-subuser-1'
            @($Warned).Count | Should -Be 1
            "$($Warned[0])" | Should -Be $Text

            Reset-SgtNetworkStub
            Set-SgtNetworkStub -Response @()
            $null = Get-SGSubuser -Username sgt-test-subuser-1 -Limit 2 -Confirm:$false -WarningVariable Warned -WarningAction SilentlyContinue
            $Calls = @(Get-SgtNetworkCall)[0]
            $Calls.Count | Should -Be 1
            ([uri]$Calls[0].Uri).AbsoluteUri | Should -Be 'https://api.sendgrid.com/v3/subusers?username=sgt-test-subuser-1'
            @($Warned).Count | Should -Be 1
            "$($Warned[0])" | Should -Be $Text

            Reset-SgtNetworkStub
            Set-SgtNetworkStub -Response @()
            $null = Get-SGSubuser -Username sgt-test-subuser-1 -Offset 1 -Confirm:$false -WarningVariable Warned -WarningAction SilentlyContinue
            $Calls = @(Get-SgtNetworkCall)[0]
            $Calls.Count | Should -Be 1
            ([uri]$Calls[0].Uri).AbsoluteUri | Should -Be 'https://api.sendgrid.com/v3/subusers?username=sgt-test-subuser-1'
            @($Warned).Count | Should -Be 1
            "$($Warned[0])" | Should -Be $Text
        }
    }

    It 'Encodes <Name> in the username' -TestCases @(
        @{ Name = '+'; Char = '+'; Encoded = '%2B' }
        @{ Name = '/'; Char = '/'; Encoded = '%2F' }
        @{ Name = '#'; Char = '#'; Encoded = '%23' }
        @{ Name = '?'; Char = '?'; Encoded = '%3F' }
        @{ Name = '&'; Char = '&'; Encoded = '%26' }
        @{ Name = 'a space'; Char = ' '; Encoded = '%20' }
    ) {
        InModuleScope SendGridTools -Parameters @{ Char = $Char; Encoded = $Encoded } {
            $null = Get-SGSubuser -Username "a${Char}b" -Confirm:$false

            $Calls = @(Get-SgtNetworkCall)[0]
            $Calls.Count | Should -Be 1
            $Sent = [uri]$Calls[0].Uri
            $Sent.AbsolutePath | Should -Be '/v3/subusers'
            $Sent.Query | Should -Be "?username=a${Encoded}b"
            $Sent.Fragment | Should -BeNullOrEmpty
        }
    }

    It 'Encodes every character in one name and sends neither limit nor offset' {
        InModuleScope SendGridTools {
            $null = Get-SGSubuser -Username 'a b+c/d#e' -Limit 2 -Offset 1 -Confirm:$false -WarningAction SilentlyContinue

            $Calls = @(Get-SgtNetworkCall)[0]
            $Calls.Count | Should -Be 1
            $Sent = [uri]$Calls[0].Uri
            $Sent.AbsolutePath | Should -Be '/v3/subusers'
            $Sent.Query | Should -Be '?username=a%20b%2Bc%2Fd%23e'
            $Sent.Fragment | Should -BeNullOrEmpty
        }
    }

    It 'Sends one request per piped name <Case>' -TestCases @(
        @{ Case = 'as strings'; ByProperty = $false }
        @{ Case = 'by property'; ByProperty = $true }
    ) {
        InModuleScope SendGridTools -Parameters @{ ByProperty = $ByProperty } {
            $Names = @('a b+c/d#e', 'f?g&h')
            if ($ByProperty) {
                $Names | ForEach-Object { [pscustomobject]@{ Username = $_ } } | Get-SGSubuser -Confirm:$false | Out-Null
            }
            else {
                $Names | Get-SGSubuser -Confirm:$false | Out-Null
            }

            $Calls = @(Get-SgtNetworkCall)[0]
            $Calls.Count | Should -Be 2
            ([uri]$Calls[0].Uri).AbsolutePath | Should -Be '/v3/subusers'
            ([uri]$Calls[1].Uri).AbsolutePath | Should -Be '/v3/subusers'
            ([uri]$Calls[0].Uri).Query | Should -Be '?username=a%20b%2Bc%2Fd%23e'
            ([uri]$Calls[1].Uri).Query | Should -Be '?username=f%3Fg%26h'
        }
    }

    It 'Returns nothing and no error for an empty list' {
        InModuleScope SendGridTools {
            Reset-SgtNetworkStub
            Set-SgtNetworkStub -Response @()

            $script:Out = @('unset')
            { $script:Out = @(Get-SGSubuser -Username sgt-s55-missing -ErrorAction Stop -Confirm:$false) } | Should -Not -Throw

            @($script:Out).Count | Should -Be 0
            @(Get-SgtNetworkCall)[0].Count | Should -Be 1
        }
    }

    It 'Returns only the matching Subuser from the recorded page' {
        InModuleScope SendGridTools {
            $Out = @(Get-SGSubuser -Username sgt-test-subuser-1 -Confirm:$false)

            $Out.Count | Should -Be 1
            $Out[0].Username | Should -Be 'sgt-test-subuser-1'
        }
    }

    It 'Returns only the Subuser whose username equals the value, not one that starts with it' {
        InModuleScope SendGridTools {
            Reset-SgtNetworkStub
            Set-SgtNetworkStub -Response @(
                [pscustomobject]@{ username = 'sgt-test-abc'; id = 2001; email = '<address>'; disabled = $false }
                [pscustomobject]@{ username = 'sgt-test-abcd'; id = 2002; email = '<address>'; disabled = $false }
            )

            $Out = @(Get-SGSubuser -Username 'sgt-test-abc' -Confirm:$false)

            $Out.Count | Should -Be 1
            $Out[0].Username | Should -Be 'sgt-test-abc'
            $Calls = @(Get-SgtNetworkCall)[0]
            $Calls.Count | Should -Be 1
            "$($Calls[0].Uri)" | Should -Be 'https://api.sendgrid.com/v3/subusers?username=sgt-test-abc'
        }
    }

    It 'Compares the username without regard to case' {
        InModuleScope SendGridTools {
            Reset-SgtNetworkStub
            Set-SgtNetworkStub -Response @(
                [pscustomobject]@{ username = 'SGT-Test-ABC'; id = 2001; email = '<address>'; disabled = $false }
                [pscustomobject]@{ username = 'sgt-test-abcd'; id = 2002; email = '<address>'; disabled = $false }
            )

            $Out = @(Get-SGSubuser -Username 'sgt-test-abc' -Confirm:$false)

            $Out.Count | Should -Be 1
            $Out[0].Username | Should -Be 'SGT-Test-ABC'
        }
    }

    It 'Compares the username as text, not as a wildcard pattern' {
        InModuleScope SendGridTools {
            Reset-SgtNetworkStub
            Set-SgtNetworkStub -Response @(
                [pscustomobject]@{ username = 'sgt-test-abc'; id = 2001; email = '<address>'; disabled = $false }
                [pscustomobject]@{ username = 'sgt-test-*'; id = 2002; email = '<address>'; disabled = $false }
            )

            $Out = @(Get-SGSubuser -Username 'sgt-test-*' -Confirm:$false)

            $Out.Count | Should -Be 1
            $Out[0].Username | Should -Be 'sgt-test-*'
        }
    }

    It 'Returns nothing and no error when SendGrid returns only other usernames' {
        InModuleScope SendGridTools {
            Reset-SgtNetworkStub
            Set-SgtNetworkStub -Response @(
                [pscustomobject]@{ username = 'sgt-test-abcd'; id = 2002; email = '<address>'; disabled = $false }
            )

            # With -ErrorAction Stop an error would end the test here.
            $Out = @(Get-SGSubuser -Username 'sgt-test-abc' -ErrorAction Stop -Confirm:$false)

            $Out.Count | Should -Be 0
        }
    }

    It 'Returns each piped name only its own Subuser' {
        InModuleScope SendGridTools {
            Reset-SgtNetworkStub
            Set-SgtNetworkStub -Response @(
                [pscustomobject]@{ username = 'sgt-test-abc'; id = 2001; email = '<address>'; disabled = $false }
                [pscustomobject]@{ username = 'sgt-test-abcd'; id = 2002; email = '<address>'; disabled = $false }
            )

            $Out = @('sgt-test-abc', 'sgt-test-abcd' | Get-SGSubuser -Confirm:$false)

            $Out.Count | Should -Be 2
            $Out[0].Username | Should -Be 'sgt-test-abc'
            $Out[1].Username | Should -Be 'sgt-test-abcd'
            @(Get-SgtNetworkCall)[0].Count | Should -Be 2
        }
    }

    It 'Returns every object unchanged without -Username' {
        InModuleScope SendGridTools {
            Reset-SgtNetworkStub
            Set-SgtNetworkStub -Response @(
                [pscustomobject]@{ username = 'sgt-test-abc'; id = 2001; email = '<address>'; disabled = $false }
                [pscustomobject]@{ username = 'sgt-test-abcd'; id = 2002; email = '<address>'; disabled = $false }
            )

            $Out = @(Get-SGSubuser -Confirm:$false)

            $Out.Count | Should -Be 2
            $Out[0].Username | Should -Be 'sgt-test-abc'
            $Out[1].Username | Should -Be 'sgt-test-abcd'
            "$((@(Get-SgtNetworkCall)[0])[0].Uri)" | Should -Be 'https://api.sendgrid.com/v3/subusers'

            Reset-SgtNetworkStub
            Set-SgtNetworkStub -Response @(
                [pscustomobject]@{ username = 'sgt-test-abc'; id = 2001; email = '<address>'; disabled = $false }
                [pscustomobject]@{ username = 'sgt-test-abcd'; id = 2002; email = '<address>'; disabled = $false }
            )
            $Limited = @(Get-SGSubuser -Limit 2 -Confirm:$false)
            $Limited.Count | Should -Be 2
        }
    }

    It 'Warns once, not once per piped name, and sends neither limit nor offset' {
        InModuleScope SendGridTools {
            Reset-SgtNetworkStub
            Set-SgtNetworkStub -Response @()

            $null = 'sgt-test-abc', 'sgt-test-abcd' | Get-SGSubuser -Limit 1 -Offset 1 -Confirm:$false -WarningVariable Warned -WarningAction SilentlyContinue

            $Calls = @(Get-SgtNetworkCall)[0]
            $Calls.Count | Should -Be 2
            "$($Calls[0].Uri)" | Should -Be 'https://api.sendgrid.com/v3/subusers?username=sgt-test-abc'
            "$($Calls[1].Uri)" | Should -Be 'https://api.sendgrid.com/v3/subusers?username=sgt-test-abcd'
            @($Warned).Count | Should -Be 1
            "$($Warned[0])" | Should -Be "SendGrid's username filter also returns names that start with the value: -Limit and -Offset apply only when -Username is not given."
            "$($Warned[0])" | Should -Not -Match 'sgt-test'
        }
    }

    It 'Gives the paging warning and the region warning once each' {
        InModuleScope SendGridTools {
            $null = Get-SGSubuser -Username sgt-test-subuser-1 -Limit 1 -IncludeRegion -Confirm:$false -WarningVariable Warned -WarningAction SilentlyContinue

            $Calls = @(Get-SgtNetworkCall)[0]
            $Calls.Count | Should -Be 1
            "$($Calls[0].Uri)" | Should -Be 'https://api.sendgrid.com/v3/subusers?username=sgt-test-subuser-1'
            @($Warned).Count | Should -Be 2
            @($Warned | ForEach-Object { "$_" }) | Should -Contain "SendGrid's username filter also returns names that start with the value: -Limit and -Offset apply only when -Username is not given."
            @($Warned | Where-Object { "$_" -match 'single subuser' }).Count | Should -Be 1
        }
    }

    It 'Sends limit and offset as before without -Username, and does not warn' {
        InModuleScope SendGridTools {
            $null = Get-SGSubuser -Limit 2 -Offset 4 -Confirm:$false -WarningVariable Warned -WarningAction SilentlyContinue

            $Calls = @(Get-SgtNetworkCall)[0]
            $Calls.Count | Should -Be 1
            "$($Calls[0].Uri)" | Should -Be 'https://api.sendgrid.com/v3/subusers?limit=2&offset=4'
            @($Warned).Count | Should -Be 0
        }
    }

    It 'Gives no paging warning with -Username alone' {
        InModuleScope SendGridTools {
            $null = Get-SGSubuser -Username sgt-test-subuser-1 -Confirm:$false -WarningVariable Warned -WarningAction SilentlyContinue

            @($Warned).Count | Should -Be 0
        }
    }
}

Describe 'Get-SGSubuser refuses an empty -Username and limits -Limit and -Offset (D109)' {
    BeforeEach {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Plain = $script:PlainFixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response (Get-Content -LiteralPath $Plain -Raw | ConvertFrom-Json)
        }
    }

    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Refuses <Case> at binding and makes no call' -TestCases @(
        @{ Case = "-Username ''"; Splat = @{ Username = '' } }
        @{ Case = '-Username $null'; Splat = @{ Username = $null } }
        @{ Case = '-Limit 0'; Splat = @{ Limit = 0 } }
        @{ Case = '-Limit -1'; Splat = @{ Limit = -1 } }
        @{ Case = '-Offset -1'; Splat = @{ Offset = -1 } }
    ) {
        InModuleScope SendGridTools -Parameters @{ Splat = $Splat } {
            { Get-SGSubuser @Splat -Confirm:$false } | Should -Throw -ErrorId 'ParameterArgumentValidationError*'
            @(Get-SgtNetworkCall)[0].Count | Should -Be 0
        }
    }

    It 'Refuses an empty name from the pipeline <Case> and makes no call' -TestCases @(
        @{ Case = 'as a string'; ByProperty = $false }
        @{ Case = 'by property Username'; ByProperty = $true }
    ) {
        InModuleScope SendGridTools -Parameters @{ ByProperty = $ByProperty } {
            # A pipeline binding error is written to the error stream and is not collected by -ErrorVariable.
            if ($ByProperty) {
                $Streams = @([pscustomobject]@{ Username = '' } | Get-SGSubuser -Confirm:$false 2>&1)
            }
            else {
                $Streams = @('' | Get-SGSubuser -Confirm:$false 2>&1)
            }
            $Errs = @($Streams | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })

            @($Errs).Count | Should -Be 1
            "$($Errs[0].FullyQualifiedErrorId)" | Should -BeLike 'ParameterArgumentValidationError*'
            @(Get-SgtNetworkCall)[0].Count | Should -Be 0
        }
    }

    It 'Sends only the other name when an empty name comes first in the pipeline' {
        InModuleScope SendGridTools {
            $Streams = @([pscustomobject]@{ Username = '' }, [pscustomobject]@{ Username = 'sgt-test-subuser-1' } |
                    Get-SGSubuser -Confirm:$false 2>&1)
            $Errs = @($Streams | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })

            @($Errs).Count | Should -Be 1
            $Calls = @(Get-SgtNetworkCall)[0]
            $Calls.Count | Should -Be 1
            ([uri]$Calls[0].Uri).AbsoluteUri | Should -Be 'https://api.sendgrid.com/v3/subusers?username=sgt-test-subuser-1'
        }
    }

    It 'Sends offset=0 for -Offset 0' {
        InModuleScope SendGridTools {
            $null = Get-SGSubuser -Offset 0 -Confirm:$false

            $Calls = @(Get-SgtNetworkCall)[0]
            $Calls.Count | Should -Be 1
            ([uri]$Calls[0].Uri).AbsoluteUri | Should -Be 'https://api.sendgrid.com/v3/subusers?offset=0'
        }
    }

    It 'Sends limit=1 and offset=0 for -Limit 1 -Offset 0' {
        InModuleScope SendGridTools {
            $null = Get-SGSubuser -Limit 1 -Offset 0 -Confirm:$false

            $Calls = @(Get-SgtNetworkCall)[0]
            $Calls.Count | Should -Be 1
            ([uri]$Calls[0].Uri).AbsoluteUri | Should -Be 'https://api.sendgrid.com/v3/subusers?limit=1&offset=0'
        }
    }

    It 'Sends the same request as before without parameters' {
        InModuleScope SendGridTools {
            $null = Get-SGSubuser -Confirm:$false

            $Calls = @(Get-SgtNetworkCall)[0]
            $Calls.Count | Should -Be 1
            ([uri]$Calls[0].Uri).AbsoluteUri | Should -Be 'https://api.sendgrid.com/v3/subusers'
        }
    }
}

Describe 'Get-SGSubuser help' {
    It 'Describes -Username as a username' {
        $Text = ((Get-Help Get-SGSubuser -Parameter Username).description.Text -join ' ') -replace '\s+', ' '
        $Text.Trim() | Should -Be 'Specifies the username of a specific Subuser to retrieve. If this parameter is not provided, all Subusers are retrieved. Only a Subuser whose username equals the value is returned.'
    }

    It 'Says that only an equal username is returned' {
        $Text = ((Get-Help Get-SGSubuser -Parameter Username).description.Text -join ' ') -replace '\s+', ' '
        $Text | Should -BeLike '*Only a Subuser whose username equals the value is returned.*'
        (Get-Command Get-SGSubuser).Definition | Should -BeLike '*# Specifies the username of a specific Subuser to retrieve. If this parameter is not provided, all Subusers are retrieved. Only a Subuser whose username equals the value is returned.*'
    }

    It 'Uses the same words in the comment above the parameter' {
        $Definition = (Get-Command Get-SGSubuser).Definition
        $Definition | Should -BeLike '*# Specifies the username of a specific Subuser to retrieve. If this parameter is not provided, all Subusers are retrieved.*'
        $Definition | Should -Not -Match 'the ID of a specific Subuser'
    }

    It 'Spells the description right' {
        $Text = ((Get-Help Get-SGSubuser).description.Text -join ' ') -replace '\s+', ' '
        $Text | Should -BeLike "*when retrieving all users it won't display disabled users*"
        $Text | Should -Not -Match 'retrieve ing'
        $Text | Should -Not -Match '\bwont\b'
    }

    It 'Keeps the alias Id on -Username' {
        (Get-Command Get-SGSubuser).Parameters['Username'].Aliases | Should -Contain 'Id'
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
