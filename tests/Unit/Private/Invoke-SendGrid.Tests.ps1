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

Describe 'Invoke-SendGrid keeps the error record (D15)' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Passes on the session''s error record when the transport throws' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            Set-SgtNetworkStub -Throw ([System.InvalidOperationException]::new('sgt-test-transport-text', [System.TimeoutException]::new('sgt-test-inner-text')))
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            $Caught = $null
            try { Invoke-SendGrid -Method Get -Namespace 'things' } catch { $Caught = $_ }

            $Caught.Exception.Message | Should -BeExactly 'Unable to query SendGrid: sgt-test-transport-text'
            $Caught.Exception | Should -BeOfType [System.Management.Automation.RuntimeException]
            "$($Caught.ScriptStackTrace)" | Should -Match 'InvokeQuery'
        }
    }

    It 'Keeps the text of a SendGrid error body' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            Set-SgtNetworkStub -Throw (New-SgtErrorRecord -Message 'sgt-test-transport-text' -Details '{"errors":[{"field":null,"message":"sgt-test-api-text"}]}')
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            $Caught = $null
            try { Invoke-SendGrid -Method Get -Namespace 'things' } catch { $Caught = $_ }

            $Caught.Exception.Message | Should -BeExactly 'SendGrid Error: "sgt-test-api-text"'
            "$($Caught.ScriptStackTrace)" | Should -Match 'InvokeQuery'
        }
    }

    It 'Keeps the type and the inner exception of an exception from the session' {
        InModuleScope SendGridTools {
            $script:Session = & ([scriptblock]::Create('class SgtThrowingSession : SendGridSession { [PSCustomObject[]] InvokeQuery ([string]$WebRequestMethod, [string]$Endpoint) { throw [System.InvalidOperationException]::new(''sgt-test-session-text'', [System.TimeoutException]::new(''sgt-test-inner-text'')) } }; [SgtThrowingSession]::new()'))
            $Caught = $null
            try { Invoke-SendGrid -Method Get -Namespace 'things' } catch { $Caught = $_ }

            $Caught.Exception | Should -BeOfType [System.InvalidOperationException]
            $Caught.Exception.Message | Should -BeExactly 'sgt-test-session-text'
            $Caught.Exception.InnerException | Should -BeOfType [System.TimeoutException]
            $Caught.Exception.InnerException.Message | Should -BeExactly 'sgt-test-inner-text'
            (Get-SgtNetworkCall).Count | Should -Be 0
        }
    }

    It 'Gives a command the same message text as before' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            Set-SgtNetworkStub -Throw ([System.InvalidOperationException]::new('sgt-test-transport-text', [System.TimeoutException]::new('sgt-test-inner-text')))
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            $Caught = $null
            try { Remove-SGGlobalSuppression -EmailAddress 'one@example.com' -Confirm:$false } catch { $Caught = $_ }

            $Caught.Exception.Message | Should -BeExactly 'Failed to remove email address "one@example.com" from global suppressions list. Unable to query SendGrid: sgt-test-transport-text'
        }
    }
}

Describe 'Invoke-SendGrid gives one text for errors (D16)' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Gives the text of one error as before' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            Set-SgtNetworkStub -Response ('{"errors":[{"field":null,"message":"sgt-test-error-one"}]}' | ConvertFrom-Json)
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            $Caught = $null
            try { Invoke-SendGrid -Method Get -Namespace 'things' } catch { $Caught = $_ }

            $Caught.Exception.Message | Should -BeExactly 'sgt-test-error-one'
        }
    }

    It 'Joins two errors in order with a semicolon and a space' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            Set-SgtNetworkStub -Response ('{"errors":[{"field":null,"message":"sgt-test-error-one"},{"field":null,"message":"sgt-test-error-two"}]}' | ConvertFrom-Json)
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            $Caught = $null
            try { Invoke-SendGrid -Method Get -Namespace 'things' } catch { $Caught = $_ }

            $Caught.Exception.Message | Should -BeExactly 'sgt-test-error-one; sgt-test-error-two'
            $Caught.Exception | Should -BeOfType [System.Management.Automation.RuntimeException]
        }
    }

    It 'Joins three errors in order' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            Set-SgtNetworkStub -Response ('{"errors":[{"field":null,"message":"sgt-test-error-one"},{"field":null,"message":"sgt-test-error-two"},{"field":null,"message":"sgt-test-error-three"}]}' | ConvertFrom-Json)
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            $Caught = $null
            try { Invoke-SendGrid -Method Get -Namespace 'things' } catch { $Caught = $_ }

            $Caught.Exception.Message | Should -BeExactly 'sgt-test-error-one; sgt-test-error-two; sgt-test-error-three'
        }
    }

    It 'Throws as before for one error without a message' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            Set-SgtNetworkStub -Response ('{"errors":[{"field":"sgt-test-field"}]}' | ConvertFrom-Json)
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            $Caught = $null
            try { Invoke-SendGrid -Method Get -Namespace 'things' } catch { $Caught = $_ }

            $Caught.Exception.Message | Should -BeExactly 'ScriptHalted'
        }
    }

    It 'Leaves out an entry without a message when several errors are joined' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            Set-SgtNetworkStub -Response ('{"errors":[{"field":"sgt-test-field"},{"field":null,"message":"sgt-test-error-two"},{"field":null,"message":"sgt-test-error-three"}]}' | ConvertFrom-Json)
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            $Caught = $null
            try { Invoke-SendGrid -Method Get -Namespace 'things' } catch { $Caught = $_ }

            $Caught.Exception.Message | Should -BeExactly 'sgt-test-error-two; sgt-test-error-three'
        }
    }

    It 'Gives the one message of several errors without a leading space' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            Set-SgtNetworkStub -Response ('{"errors":[{"field":"sgt-test-field"},{"field":null,"message":"sgt-test-error-two"}]}' | ConvertFrom-Json)
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            $Caught = $null
            try { Invoke-SendGrid -Method Get -Namespace 'things' } catch { $Caught = $_ }

            $Caught.Exception.Message | Should -BeExactly 'sgt-test-error-two'
        }
    }

    It 'Gives a command the joined text' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            Set-SgtNetworkStub -Response ('{"errors":[{"field":null,"message":"sgt-test-error-one"},{"field":null,"message":"sgt-test-error-two"}]}' | ConvertFrom-Json)
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            $Caught = $null
            try { Remove-SGGlobalSuppression -EmailAddress 'one@example.com' -Confirm:$false } catch { $Caught = $_ }

            $Caught.Exception.Message | Should -BeExactly 'Failed to remove email address "one@example.com" from global suppressions list. sgt-test-error-one; sgt-test-error-two'
        }
    }
}

Describe 'Invoke-SendGrid writes its note only with -Verbose (D19)' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Writes "Successfully invoked" for an empty object only with -Verbose' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{})
            $Message = 'Successfully invoked "sgt-test-caller" on "things".'

            # A module function reads the global preference, so set both and restore the global one.
            $SavedVerbose = $global:VerbosePreference
            try {
                $global:VerbosePreference = 'SilentlyContinue'
                $VerbosePreference = 'SilentlyContinue'
                $Without = @(& { Invoke-SendGrid -Method Get -Namespace 'things' -CallingCmdlet 'sgt-test-caller' } 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] })
                $With = @(& { Invoke-SendGrid -Method Get -Namespace 'things' -CallingCmdlet 'sgt-test-caller' -Verbose } 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] })
            }
            finally {
                $global:VerbosePreference = $SavedVerbose
            }

            $Without.Count | Should -Be 0
            @($With | Where-Object { $_.Message -ceq $Message }).Count | Should -BeGreaterThan 0
        }
    }
}

Describe 'Invoke-SendGrid turns Unix seconds under a time name into dates (D30, D31)' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Gives a date for <Field> sent as <TypeName>' -ForEach @(
        foreach ($TypeName in 'Int32', 'Int64') {
            @{ Field = 'created'; OutputName = 'Created'; TypeName = $TypeName }
            @{ Field = 'updated_at'; OutputName = 'UpdatedAt'; TypeName = $TypeName }
            @{ Field = 'added_at'; OutputName = 'AddedAt'; TypeName = $TypeName }
            @{ Field = 'assigned_at'; OutputName = 'AssignedAt'; TypeName = $TypeName }
            @{ Field = 'last_validation_attempt_at'; OutputName = 'LastValidationAttemptAt'; TypeName = $TypeName }
        }
    ) {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Field = $Field; OutputName = $OutputName; TypeName = $TypeName } {
            $Epoch = [datetime]::new(1970, 1, 1, 0, 0, 0, 0)
            $Value = if ($TypeName -eq 'Int32') { [int]1700000000 } else { [int64]1700000000 }
            $Answer = [pscustomobject]@{ name = 'sgt-test-name' }
            $Answer | Add-Member -NotePropertyName $Field -NotePropertyValue $Value
            Set-SgtNetworkStub -Response $Answer
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0

            $Result = @(Invoke-SendGrid -Method Get -Namespace 'things')

            $Result[0].$OutputName | Should -BeOfType [datetime]
            $Result[0].$OutputName | Should -Be $Epoch.AddSeconds(1700000000)
            $Result[0].$OutputName.Kind | Should -Be ([System.DateTimeKind]::Unspecified)
        }
    }

    It 'Gives dates for an answer as the running shell parses it' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $Epoch = [datetime]::new(1970, 1, 1, 0, 0, 0, 0)
            Set-SgtNetworkStub -Response ('{"created":1700000000,"updated_at":1700000001,"added_at":1700000002,"assigned_at":1700000003,"last_validation_attempt_at":1700000004,"valid":true}' | ConvertFrom-Json)
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0

            $Result = @(Invoke-SendGrid -Method Get -Namespace 'things')

            $Names = 'Created', 'UpdatedAt', 'AddedAt', 'AssignedAt', 'LastValidationAttemptAt'
            for ($i = 0; $i -lt $Names.Count; $i++) {
                $Result[0].($Names[$i]) | Should -BeOfType [datetime]
                $Result[0].($Names[$i]) | Should -Be $Epoch.AddSeconds(1700000000 + $i)
            }
            $Result[0].Valid | Should -BeOfType [bool]
            $Result[0].Valid | Should -BeTrue
        }
    }

    It 'Gives the epoch start for zero' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $Epoch = [datetime]::new(1970, 1, 1, 0, 0, 0, 0)
            Set-SgtNetworkStub -Response ('{"added_at":0,"assigned_at":0}' | ConvertFrom-Json)
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0

            $Result = @(Invoke-SendGrid -Method Get -Namespace 'things')

            $Result[0].AddedAt | Should -BeOfType [datetime]
            $Result[0].AddedAt | Should -Be $Epoch
            $Result[0].AssignedAt | Should -BeOfType [datetime]
            $Result[0].AssignedAt | Should -Be $Epoch
        }
    }

    It 'Leaves a Boolean, a decimal number, a text and an empty value as they are' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            Set-SgtNetworkStub -Response ('{"created":1.5,"updated_at":null,"added_at":"sgt-test-text","assigned_at":false,"valid":true}' | ConvertFrom-Json)
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0

            $Result = @(Invoke-SendGrid -Method Get -Namespace 'things')

            $Result[0].Created | Should -Not -BeOfType [datetime]
            $Result[0].Created | Should -Be 1.5
            $Result[0].PSObject.Properties['UpdatedAt'] | Should -Not -BeNullOrEmpty
            $Result[0].PSObject.Properties['UpdatedAt'].Value | Should -BeNullOrEmpty
            $Result[0].AddedAt | Should -BeExactly 'sgt-test-text'
            $Result[0].AssignedAt | Should -BeOfType [bool]
            $Result[0].AssignedAt | Should -BeFalse
            $Result[0].Valid | Should -BeOfType [bool]
            $Result[0].Valid | Should -BeTrue
        }
    }

    It 'Leaves a whole number under another name as it is' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            Set-SgtNetworkStub -Response ('{"id":1001,"count":3,"user_id":1002,"at":1700000000,"format":1700000001}' | ConvertFrom-Json)
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0

            $Result = @(Invoke-SendGrid -Method Get -Namespace 'things')

            $Expected = [ordered]@{ Id = 1001; Count = 3; UserId = 1002; At = 1700000000; Format = 1700000001 }
            foreach ($Name in $Expected.Keys) {
                $Result[0].$Name | Should -Not -BeOfType [datetime]
                $Result[0].$Name | Should -Be $Expected[$Name]
            }
        }
    }

    It 'Gives a list of dates in the same order for a list of <TypeName> numbers' -ForEach @(
        @{ TypeName = 'Int32' }
        @{ TypeName = 'Int64' }
    ) {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; TypeName = $TypeName } {
            $Epoch = [datetime]::new(1970, 1, 1, 0, 0, 0, 0)
            $Type = [type]"System.$TypeName"
            $Answer = [pscustomobject]@{
                created  = @(1700000000, 1700000001, 1700000002 | ForEach-Object { [System.Convert]::ChangeType($_, $Type) })
                added_at = @(1700000005, 1700000006 | ForEach-Object { [System.Convert]::ChangeType($_, $Type) })
            }
            Set-SgtNetworkStub -Response $Answer
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0

            $Result = @(Invoke-SendGrid -Method Get -Namespace 'things')

            $Value = $Result[0].PSObject.Properties['Created'].Value
            ($Value -is [array]) | Should -BeTrue
            $Value.Count | Should -Be 3
            for ($i = 0; $i -lt 3; $i++) {
                $Value[$i] | Should -BeOfType [datetime]
                $Value[$i] | Should -Be $Epoch.AddSeconds(1700000000 + $i)
            }
            $Added = $Result[0].PSObject.Properties['AddedAt'].Value
            ($Added -is [array]) | Should -BeTrue
            $Added.Count | Should -Be 2
            $Added[0] | Should -BeOfType [datetime]
            $Added[0] | Should -Be $Epoch.AddSeconds(1700000005)
            $Added[1] | Should -BeOfType [datetime]
            $Added[1] | Should -Be $Epoch.AddSeconds(1700000006)
        }
    }

    It 'Gives a list of dates for a list as the running shell parses it' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $Epoch = [datetime]::new(1970, 1, 1, 0, 0, 0, 0)
            Set-SgtNetworkStub -Response ('{"updated_at":[1700000003,1700000004],"last_validation_attempt_at":[1700000009,1700000010],"valid":[true,false]}' | ConvertFrom-Json)
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0

            $Result = @(Invoke-SendGrid -Method Get -Namespace 'things')

            $Updated = $Result[0].PSObject.Properties['UpdatedAt'].Value
            ($Updated -is [array]) | Should -BeTrue
            $Updated.Count | Should -Be 2
            $Updated[0] | Should -BeOfType [datetime]
            $Updated[0] | Should -Be $Epoch.AddSeconds(1700000003)
            $Updated[1] | Should -BeOfType [datetime]
            $Updated[1] | Should -Be $Epoch.AddSeconds(1700000004)
            $Last = $Result[0].PSObject.Properties['LastValidationAttemptAt'].Value
            ($Last -is [array]) | Should -BeTrue
            $Last.Count | Should -Be 2
            $Last[0] | Should -BeOfType [datetime]
            $Last[0] | Should -Be $Epoch.AddSeconds(1700000009)
            $Last[1] | Should -BeOfType [datetime]
            $Last[1] | Should -Be $Epoch.AddSeconds(1700000010)
            $Valid = $Result[0].PSObject.Properties['Valid'].Value
            ($Valid -is [array]) | Should -BeTrue
            $Valid.Count | Should -Be 2
            $Valid[0] | Should -BeOfType [bool]
            $Valid[0] | Should -BeTrue
            $Valid[1] | Should -BeOfType [bool]
            $Valid[1] | Should -BeFalse
        }
    }

    It 'Keeps a list of one number as a list of one date' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $Epoch = [datetime]::new(1970, 1, 1, 0, 0, 0, 0)
            Set-SgtNetworkStub -Response ('{"updated_at":[1700000001]}' | ConvertFrom-Json)
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0

            $Result = @(Invoke-SendGrid -Method Get -Namespace 'things')

            $Value = $Result[0].PSObject.Properties['UpdatedAt'].Value
            ($Value -is [array]) | Should -BeTrue
            $Value.Count | Should -Be 1
            $Value[0] | Should -BeOfType [datetime]
            $Value[0] | Should -Be $Epoch.AddSeconds(1700000001)
        }
    }

    It 'Leaves a list that mixes a number with a text or an empty value as it is' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            Set-SgtNetworkStub -Response ('{"created":[1700000000,"sgt-test-text"],"added_at":[1700000002,null]}' | ConvertFrom-Json)
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0

            $Result = @(Invoke-SendGrid -Method Get -Namespace 'things')

            $Created = $Result[0].PSObject.Properties['Created'].Value
            $Created.Count | Should -Be 2
            $Created[0] | Should -Not -BeOfType [datetime]
            $Created[0] | Should -Be 1700000000
            $Created[1] | Should -BeExactly 'sgt-test-text'
            $Added = $Result[0].PSObject.Properties['AddedAt'].Value
            $Added.Count | Should -Be 2
            $Added[0] | Should -Not -BeOfType [datetime]
            $Added[0] | Should -Be 1700000002
            $Added[1] | Should -BeNullOrEmpty
        }
    }

    It 'Gives each object of a list its own date' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $Epoch = [datetime]::new(1970, 1, 1, 0, 0, 0, 0)
            Set-SgtNetworkStub -Response ('[{"created":1700000000},{"created":1700000001}]' | ConvertFrom-Json)
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0

            $Result = @(Invoke-SendGrid -Method Get -Namespace 'things')

            $Result.Count | Should -Be 2
            $Result[0].Created | Should -BeOfType [datetime]
            $Result[0].Created | Should -Be $Epoch.AddSeconds(1700000000)
            $Result[1].Created | Should -BeOfType [datetime]
            $Result[1].Created | Should -Be $Epoch.AddSeconds(1700000001)
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
