BeforeDiscovery {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/SessionHelpers.ps1')
    $script:Cases = @(Get-SgtOverloadCase)
}

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

Describe 'Invoke-SendGrid without a session' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Throws the connect-first error when no session exists' {
        InModuleScope SendGridTools {
            Set-SgtNetworkStub -Response $null
            $script:Session = $null
            { Invoke-SendGrid -Method Get -Namespace 'scopes' } | Should -Throw -ExpectedMessage 'You must call the Connect-SendGrid cmdlet before calling any other cmdlets.'
            Get-SgtNetworkCall | Should -BeNullOrEmpty
        }
    }
}

Describe 'Invoke-SendGrid with an expired session' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Throws the expired-session error for an expired session' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            Set-SgtNetworkStub -Response $null
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 2
            { Invoke-SendGrid -Method Get -Namespace 'scopes' } | Should -Throw -ExpectedMessage 'The SendGrid session has expired. Run Connect-SendGrid -Force to reconnect.'
            Get-SgtNetworkCall | Should -BeNullOrEmpty
        }
    }
}

Describe 'Invoke-SendGrid with a connected session' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Makes one request for <Name> with matching body and on-behalf-of' -ForEach $script:Cases {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Case = @{ Method = $Method; Endpoint = $Endpoint; HasBody = $HasBody; HasObo = $HasObo; Body = $Body; Obo = $Obo } } {
            $Response = [pscustomobject]@{ name = 'mock-response' }
            Set-SgtNetworkStub -Response $Response
            $script:Session = [SendGridSession]::new()
            $script:Session.Connect($Cred)
            # The connect GET is not part of the request under test.
            Set-SgtNetworkStub -Response $Response

            $Params = @{ Method = $Case.Method; Namespace = $Case.Endpoint }
            if ($Case.HasBody) { $Params['ContentBody'] = $Case.Body }
            if ($Case.HasObo) { $Params['OnBehalfOf'] = $Case.Obo }
            $Result = Invoke-SendGrid @Params

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Call = $Calls[0]
            $Call.Method | Should -Be $Case.Method
            $Call.Uri.AbsoluteUri | Should -Be ('https://api.sendgrid.com/v3/{0}' -f $Case.Endpoint)
            $Call.BodyPassed | Should -Be $Case.HasBody
            $Call.Headers.ContainsKey('on-behalf-of') | Should -Be $Case.HasObo
            if ($Case.HasObo) {
                $Call.Headers['on-behalf-of'] | Should -Be $Case.Obo
            }
            @($Result).Count | Should -Be 1
            @($Result)[0].Name | Should -Be 'mock-response'
        }
    }

    It 'Flattens a results wrapper into the contained objects' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $Response = [pscustomobject]@{
                results = @(
                    [pscustomobject]@{ id = 1; name = 'first' }
                    [pscustomobject]@{ id = 2; name = 'second' }
                )
            }
            Set-SgtNetworkStub -Response $Response
            $script:Session = [SendGridSession]::new()
            $script:Session.Connect($Cred)

            $Result = @(Invoke-SendGrid -Method Get -Namespace 'things')

            $Result.Count | Should -Be 2
            $Result[0].Id | Should -Be 1
            $Result[0].Name | Should -Be 'first'
            $Result[1].Id | Should -Be 2
            $Result[1].Name | Should -Be 'second'
        }
    }

    It 'Converts an int64 lastat property to a DateTime named Lastat' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $Response = [pscustomobject]@{
                results = @([pscustomobject]@{ email = 'user@example.com'; lastat = [int64]1700000000 })
            }
            Set-SgtNetworkStub -Response $Response
            $script:Session = [SendGridSession]::new()
            $script:Session.Connect($Cred)

            $Result = @(Invoke-SendGrid -Method Get -Namespace 'things')

            $Result.Count | Should -Be 1
            $Result[0].Lastat | Should -BeOfType [datetime]
            $Result[0].Lastat | Should -Be ([datetime]::new(1970, 1, 1, 0, 0, 0, 0).AddSeconds(1700000000))
            $Result[0].Lastat.ToString('yyyy-MM-ddTHH:mm:ss', [cultureinfo]::InvariantCulture) | Should -Be '2023-11-14T22:13:20'
        }
    }
}

Describe 'Invoke-SendGrid keeps empty lists (D8)' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Keeps an empty list as a property with an empty value' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            Set-SgtNetworkStub -Response ('[{"ip":"192.0.2.10","pools":[],"warmup":false}]' | ConvertFrom-Json)
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0

            $Result = @(Invoke-SendGrid -Method Get -Namespace 'things')

            $Result.Count | Should -Be 1
            (@($Result[0].PSObject.Properties.Name | Sort-Object) -join ',') | Should -Be 'Ip,Pools,Warmup'
            $Result[0].PSObject.Properties['Pools'] | Should -Not -BeNullOrEmpty
            @($Result[0].Pools).Count | Should -Be 0
            $Result[0].Ip | Should -Be '192.0.2.10'
            $Result[0].Warmup | Should -Be $false
        }
    }

    It 'Gives the same output as before for a list with elements, null, a number and dates' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            Set-SgtNetworkStub -Response ('[{"subusers":["sgt-test-subuser-1","sgt-test-subuser-2"],"start_date":null,"count":3,"created":1700000000,"date":"2023-11-14"}]' | ConvertFrom-Json)
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0

            $Result = @(Invoke-SendGrid -Method Get -Namespace 'things')

            $Result.Count | Should -Be 1
            (@($Result[0].PSObject.Properties.Name | Sort-Object) -join ',') | Should -Be 'Count,Created,Date,StartDate,Subusers'
            @($Result[0].Subusers) | Should -Be @('sgt-test-subuser-1', 'sgt-test-subuser-2')
            $Result[0].PSObject.Properties['StartDate'] | Should -Not -BeNullOrEmpty
            $Result[0].PSObject.Properties['StartDate'].Value | Should -BeNullOrEmpty
            $Result[0].PSObject.Properties['Count'].Value | Should -Be 3
            if ($PSVersionTable.PSEdition -eq 'Core') {
                $Result[0].Created | Should -BeOfType [datetime]
                $Result[0].Created | Should -Be ([datetime]::new(1970, 1, 1, 0, 0, 0, 0).AddSeconds(1700000000))
            }
            else {
                # Windows PowerShell 5.1 reads this number as Int32, which the int64 conversion does not match; it stays a number as before.
                $Result[0].Created | Should -Be 1700000000
            }
            $Result[0].Date | Should -BeOfType [datetime]
            $Result[0].Date | Should -Be ([datetime]::Parse('2023-11-14'))
        }
    }

    It 'Returns an object for a response whose only properties are empty lists' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            Set-SgtNetworkStub -Response ('{"pools":[],"subusers":[]}' | ConvertFrom-Json)
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0

            $Result = @(Invoke-SendGrid -Method Get -Namespace 'things')

            $Result.Count | Should -Be 1
            (@($Result[0].PSObject.Properties.Name | Sort-Object) -join ',') | Should -Be 'Pools,Subusers'
            @($Result[0].Pools).Count | Should -Be 0
            @($Result[0].Subusers).Count | Should -Be 0
        }
    }

    It 'Does not throw for an empty errors list' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            Set-SgtNetworkStub -Response ('{"errors":[],"name":"sgt-test-ok"}' | ConvertFrom-Json)
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0

            { Invoke-SendGrid -Method Get -Namespace 'things' } | Should -Not -Throw
            $Result = @(Invoke-SendGrid -Method Get -Namespace 'things')

            $Result.Count | Should -Be 1
            (@($Result[0].PSObject.Properties.Name | Sort-Object) -join ',') | Should -Be 'Errors,Name'
            @($Result[0].Errors).Count | Should -Be 0
        }
    }

    It 'Throws the error message for an errors list with one error, as before' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            Set-SgtNetworkStub -Response ('{"errors":[{"field":null,"message":"sgt-test-error-message"}]}' | ConvertFrom-Json)
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0

            { Invoke-SendGrid -Method Get -Namespace 'things' } | Should -Throw -ExpectedMessage 'sgt-test-error-message'
        }
    }

    It 'Keeps an empty list in every object of a list' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            Set-SgtNetworkStub -Response ('[{"id":1,"pools":[]},{"id":2,"pools":["sgt-test-pool"]}]' | ConvertFrom-Json)
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0

            $Result = @(Invoke-SendGrid -Method Get -Namespace 'things')

            $Result.Count | Should -Be 2
            foreach ($Item in $Result) {
                (@($Item.PSObject.Properties.Name | Sort-Object) -join ',') | Should -Be 'Id,Pools'
            }
            @($Result[0].Pools).Count | Should -Be 0
            @($Result[1].Pools) | Should -Be @('sgt-test-pool')
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
