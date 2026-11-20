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
    $script:Fixture = Join-Path -Path $PSScriptRoot -ChildPath '../Fixtures/api-keys-page.json'
}

AfterAll {
    Uninstall-SgtSessionHelper
    Disable-SgtNetworkTripwire
}

Describe 'Get-SGApiKey list paging' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Fixtures match the recorded structure' {
        $Document = Get-Content -LiteralPath $script:Fixture -Raw | ConvertFrom-Json
        @($Document.PSObject.Properties.Name) | Should -Be @('result')
        @($Document.result[0].PSObject.Properties.Name | Sort-Object) | Should -Be @('api_key_id', 'name')
    }

    It 'Reads two pages and returns every key' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:Fixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            $Items = @(New-SgtFixtureItem -Kind Key -Count 51 -Path $Fixture)
            Set-SgtPagedNetworkStub -Items $Items -Shape Result

            $Out = @(Get-SGApiKey -Confirm:$false)

            $Out.Count | Should -Be 51
            @($Out.ApiKeyId) | Should -Be @($Items.api_key_id)
            @($Out.ApiKeyId | Select-Object -Unique).Count | Should -Be 51
            $Calls = @(Get-SgtListCall)
            @($Calls | ForEach-Object { [int][regex]::Match("$($_.Uri)", 'offset=(\d+)').Groups[1].Value }) | Should -Be @(Get-SgtExpectedOffset -Count 51)
            foreach ($Call in $Calls) { "$($Call.Uri)" | Should -Match '[?&]limit=50(&|$)' }
        }
    }

    It 'Reads every page from the EU host on an EU session and never from the global host' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:Fixture } {
            $script:Session = [SendGridSession]::new([uri]'https://api.eu.sendgrid.com/v3')
            $script:Session._Credential = $Cred
            $script:Session._Connected = $true
            $script:Session._CreateDateTime = Get-Date
            $Items = @(New-SgtFixtureItem -Kind Key -Count 120 -Path $Fixture)
            Set-SgtPagedNetworkStub -Items $Items -Shape Result

            $Out = @(Get-SGApiKey -Confirm:$false)

            $Out.Count | Should -Be 120
            @($Out.ApiKeyId) | Should -Be @($Items.api_key_id)
            @(Get-SgtListCall | ForEach-Object { [int][regex]::Match("$($_.Uri)", 'offset=(\d+)').Groups[1].Value }) | Should -Be @(0, 50, 100)
            $Calls = @(Get-SgtNetworkCall)[0]
            $Calls.Count | Should -Be 3
            foreach ($Call in $Calls) {
                ([uri]"$($Call.Uri)").Host | Should -Be 'api.eu.sendgrid.com'
                "$($Call.Uri)" | Should -BeLike 'https://api.eu.sendgrid.com/v3/api_keys?limit=50&offset=*'
            }
        }
    }

    It 'Stops after a short page' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:Fixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtPagedNetworkStub -Items @(New-SgtFixtureItem -Kind Key -Count 51 -Path $Fixture) -Shape Result

            $null = Get-SGApiKey -Confirm:$false

            @(Get-SgtListCall).Count | Should -Be 2
        }
    }

    It 'Reads three pages' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:Fixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtPagedNetworkStub -Items @(New-SgtFixtureItem -Kind Key -Count 120 -Path $Fixture) -Shape Result

            $Out = @(Get-SGApiKey -Confirm:$false)

            $Out.Count | Should -Be 120
            @(Get-SgtListCall | ForEach-Object { [int][regex]::Match("$($_.Uri)", 'offset=(\d+)').Groups[1].Value }) | Should -Be @(0, 50, 100)
        }
    }

    It 'Reads one page' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:Fixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtPagedNetworkStub -Items @(New-SgtFixtureItem -Kind Key -Count 7 -Path $Fixture) -Shape Result

            $Out = @(Get-SGApiKey -Confirm:$false)

            $Out.Count | Should -Be 7
            $Calls = @(Get-SgtListCall)
            $Calls.Count | Should -Be 1
            "$($Calls[0].Uri)" | Should -Match 'offset=0'
        }
    }

    It 'Returns nothing for an empty list' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtPagedNetworkStub -Items @() -Shape Result

            $Out = @(Get-SGApiKey -Confirm:$false -ErrorAction Stop)

            $Out.Count | Should -Be 0
            @(Get-SgtListCall).Count | Should -Be 1
        }
    }

    It 'Asks once more after a full last page' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:Fixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtPagedNetworkStub -Items @(New-SgtFixtureItem -Kind Key -Count 50 -Path $Fixture) -Shape Result

            $Out = @(Get-SGApiKey -Confirm:$false)

            $Out.Count | Should -Be 50
            @(Get-SgtListCall | ForEach-Object { [int][regex]::Match("$($_.Uri)", 'offset=(\d+)').Groups[1].Value }) | Should -Be @(0, 50)
        }
    }

    It 'Stops when the server ignores offset' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:Fixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtPagedNetworkStub -Items @(New-SgtFixtureItem -Kind Key -Count 60 -Path $Fixture) -Shape Result -IgnoreOffset

            $Out = @(Get-SGApiKey -Confirm:$false)

            $Out.Count | Should -Be 50
            @($Out.ApiKeyId | Select-Object -Unique).Count | Should -Be 50
            @(Get-SgtListCall | ForEach-Object { [int][regex]::Match("$($_.Uri)", 'offset=(\d+)').Groups[1].Value }) | Should -Be @(0, 50)
        }
    }

    It 'Says in the verbose stream when a page brings nothing new, and only then' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:Fixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtPagedNetworkStub -Items @(New-SgtFixtureItem -Kind Key -Count 60 -Path $Fixture) -Shape Result -IgnoreOffset
            $Stream = @(Get-SGApiKey -Verbose -Confirm:$false 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $_.Message })
            @($Stream | Where-Object { $_ -like '*a page brought no new item*' }).Count | Should -Be 1

            Set-SgtPagedNetworkStub -Items @(New-SgtFixtureItem -Kind Key -Count 60 -Path $Fixture) -Shape Result
            $Stream = @(Get-SGApiKey -Verbose -Confirm:$false 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $_.Message })
            @($Stream | Where-Object { $_ -like '*a page brought no new item*' }).Count | Should -Be 0
        }
    }

    It 'Sends the on-behalf-of header on every page' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:Fixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtPagedNetworkStub -Items @(New-SgtFixtureItem -Kind Key -Count 51 -Path $Fixture) -Shape Result

            $null = Get-SGApiKey -OnBehalfOf 'user-placeholder' -Confirm:$false

            $Calls = @(Get-SgtListCall)
            $Calls.Count | Should -Be 2
            foreach ($Call in $Calls) { $Call.Headers['on-behalf-of'] | Should -Be 'user-placeholder' }
        }
    }

    It 'Gets each key id with one call and no paging' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:Fixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtPagedNetworkStub -Items @(New-SgtFixtureItem -Kind Key -Count 51 -Path $Fixture) -Shape Result

            $Out = @(Get-SGApiKey -ApiKeyId 'key-id-1', 'key-id-2' -Confirm:$false)

            $Out.Count | Should -Be 2
            $Calls = @(Get-SgtNetworkCall)[0]
            $Calls.Count | Should -Be 2
            "$($Calls[0].Uri)" | Should -BeLike '*/api_keys/key-id-1'
            "$($Calls[1].Uri)" | Should -BeLike '*/api_keys/key-id-2'
            foreach ($Call in $Calls) { "$($Call.Uri)" | Should -Not -Match 'limit=|offset=' }
        }
    }

    It 'Gets a key id from the pipeline with one call' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:Fixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtPagedNetworkStub -Items @(New-SgtFixtureItem -Kind Key -Count 51 -Path $Fixture) -Shape Result

            $Out = @('key-id-1' | Get-SGApiKey -Confirm:$false)

            $Out.Count | Should -Be 1
            $Calls = @(Get-SgtNetworkCall)[0]
            $Calls.Count | Should -Be 1
            "$($Calls[0].Uri)" | Should -BeLike '*/api_keys/key-id-1'
            "$($Calls[0].Uri)" | Should -Not -Match 'limit=|offset='
        }
    }

    It 'Keeps the output shape' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Fixture = $script:Fixture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtPagedNetworkStub -Items @(New-SgtFixtureItem -Kind Key -Count 51 -Path $Fixture) -Shape Result

            $Out = @(Get-SGApiKey -Confirm:$false)

            foreach ($Object in $Out) {
                @($Object.PSObject.Properties.Name | Sort-Object) | Should -Be @('ApiKeyId', 'Name')
            }
        }
    }
}

Describe 'Get-SGApiKey refuses an empty -ApiKeyId (D116)' {
    BeforeEach {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ result = @([pscustomobject]@{ api_key_id = 'key-id-1'; name = 'sgt-test-key-1' }) })
        }
    }

    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Refuses <Case> at binding and makes no call' -TestCases @(
        @{ Case = '$null'; Splat = @{ ApiKeyId = $null } }
        @{ Case = '@()'; Splat = @{ ApiKeyId = @() } }
        @{ Case = "''"; Splat = @{ ApiKeyId = '' } }
        @{ Case = "@('')"; Splat = @{ ApiKeyId = @('') } }
    ) {
        InModuleScope SendGridTools -Parameters @{ Splat = $Splat } {
            { Get-SGApiKey @Splat -Confirm:$false } | Should -Throw -ErrorId 'ParameterArgumentValidationError*'
            @(Get-SgtNetworkCall)[0].Count | Should -Be 0
        }
    }

    It 'Refuses an empty value from the pipeline <Case> and makes no call' -TestCases @(
        @{ Case = 'as a string'; ByProperty = $false }
        @{ Case = 'by property ApiKeyId'; ByProperty = $true }
    ) {
        InModuleScope SendGridTools -Parameters @{ ByProperty = $ByProperty } {
            # A pipeline binding error follows the caller's preference, not -ErrorAction; CI's pwsh shell sets Stop.
            $ErrorActionPreference = 'Continue'
            if ($ByProperty) {
                $Streams = @([pscustomobject]@{ ApiKeyId = '' } | Get-SGApiKey -Confirm:$false 2>&1)
            }
            else {
                $Streams = @('' | Get-SGApiKey -Confirm:$false 2>&1)
            }
            $Errs = @($Streams | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })

            @($Errs).Count | Should -Be 1
            "$($Errs[0].FullyQualifiedErrorId)" | Should -BeLike 'ParameterArgument*'
            @(Get-SgtNetworkCall)[0].Count | Should -Be 0
        }
    }

    # PowerShell may bind the object by value when its ApiKeyId is $null; only the absence of a list request is pinned.
    It 'Sends no list request for an object whose ApiKeyId is $null' {
        InModuleScope SendGridTools {
            $ErrorActionPreference = 'Continue'
            $null = @([pscustomobject]@{ ApiKeyId = $null } | Get-SGApiKey -Confirm:$false 2>&1)

            $Calls = @(@(Get-SgtNetworkCall)[0])
            @($Calls | Where-Object { ([uri]$_.Uri).AbsolutePath -eq '/v3/api_keys' }).Count | Should -Be 0
        }
    }

    It 'Sends only the valid value when an empty value comes first in the pipeline' {
        InModuleScope SendGridTools {
            $ErrorActionPreference = 'Continue'
            $Streams = @([pscustomobject]@{ ApiKeyId = '' }, [pscustomobject]@{ ApiKeyId = 'key-id-1' } | Get-SGApiKey -Confirm:$false 2>&1)
            $Errs = @($Streams | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })

            @($Errs).Count | Should -Be 1
            $Calls = @(Get-SgtNetworkCall)[0]
            $Calls.Count | Should -Be 1
            "$($Calls[0].Uri)" | Should -Be 'https://api.sendgrid.com/v3/api_keys/key-id-1'
        }
    }

    It 'Sends the same request as before for a valid value' {
        InModuleScope SendGridTools {
            $null = Get-SGApiKey -ApiKeyId 'key-id-1' -Confirm:$false

            $Calls = @(Get-SgtNetworkCall)[0]
            $Calls.Count | Should -Be 1
            "$($Calls[0].Uri)" | Should -Be 'https://api.sendgrid.com/v3/api_keys/key-id-1'
        }
    }

    It 'Sends the same request as before without parameters' {
        InModuleScope SendGridTools {
            $null = Get-SGApiKey -Confirm:$false

            $Calls = @(Get-SgtNetworkCall)[0]
            $Calls.Count | Should -Be 1
            "$($Calls[0].Uri)" | Should -Be 'https://api.sendgrid.com/v3/api_keys?limit=50&offset=0'
        }
    }
}

Describe 'Get-SGApiKey help (D117)' {
    It 'Says that an empty -ApiKeyId is refused' {
        $Text = ((Get-Help Get-SGApiKey -Parameter ApiKeyId).description.Text -join ' ') -replace '\s+', ' '
        $Text.Trim() | Should -BeLike '*An empty value is refused.'
    }

    It 'Says in the comment at -ApiKeyId that an empty value is refused' {
        (Get-Command Get-SGApiKey).Definition | Should -Match '# [^\r\n]*An empty value is refused\.\r?\n\s*\[Parameter\([^)]*\)\]\s*(\[[^\r\n]*\]\s*)*\$ApiKeyId\b'
    }
}

Describe 'Get-SGApiKey encodes the id in the path (D153)' {
    BeforeEach {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ api_key_id = 'sgt-key'; name = 'sgt-test-key'; scopes = @('mail.send') })
        }
    }

    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Puts <Name> in one path segment' -ForEach @(
        @{ Name = 'an id with a slash, a question mark and a hash'; Id = 'a/b?c#d'; Segment = 'a%2Fb%3Fc%23d' }
        @{ Name = 'an id with only unreserved characters'; Id = 'abc-1.2_3~'; Segment = 'abc-1.2_3~' }
    ) {
        InModuleScope SendGridTools -Parameters @{ Id = $Id; Segment = $Segment } {
            $null = Get-SGApiKey -ApiKeyId $Id -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -BeGreaterThan 0
            foreach ($Call in $Calls) {
                $Call.Uri.OriginalString | Should -BeLike "https://api.sendgrid.com/v3/api_keys/$Segment*"
                $Call.Uri.OriginalString | Should -Not -BeLike '*/a/b*'
                $Call.Uri.OriginalString | Should -Not -Match '[?#]'
            }
            $Calls[-1].Method | Should -Be 'Get'
            $Calls[-1].Uri.OriginalString | Should -BeExactly "https://api.sendgrid.com/v3/api_keys/$Segment"
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
