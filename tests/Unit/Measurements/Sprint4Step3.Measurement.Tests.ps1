BeforeDiscovery {
    $script:Cultures = @('en-US', 'sv-SE', 'en-GB', 'tr-TR', 'th-TH')
    $script:FilterCases = @(
        foreach ($Culture in $script:Cultures) {
            @{ Culture = $Culture; Name = 'two times with a zone and milliseconds'; Filter = 'LastEventTime -between "2024-06-30T00:00:00Z","2024-07-02T23:59:59.999Z"' }
            @{ Culture = $Culture; Name = 'two dates whose day and month can change places'; Filter = 'Date -between "2024-03-04","2024-05-06"' }
        }
    )
    $script:DateCases = @(
        foreach ($Culture in $script:Cultures) {
            @{ Culture = $Culture; Name = 'year-month-day'; Json = '{"date":"2023-11-14","name":"sgt-test-name"}' }
            @{ Culture = $Culture; Name = 'month/day/year'; Json = '{"date":"11/14/2023","name":"sgt-test-name"}' }
        }
    )
    $script:NameCases = @(
        foreach ($Culture in $script:Cultures) {
            @{ Culture = $Culture; Mode = 'the thread culture' }
            @{ Culture = $Culture; Mode = 'the thread culture and Get-Culture' }
        }
    )
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/NetworkTripwire.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/SessionHelpers.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/PromptCountingHost.ps1')
    # Import once per run: in Windows PowerShell 5.1 a class stays bound to the first loaded module instance.
    if (-not (Get-Module -Name SendGridTools)) {
        Get-Module -Name SendGridTools -ListAvailable | Select-Object -First 1 | Import-Module -ErrorAction Stop
    }
    Enable-SgtNetworkTripwire
    Assert-SgtNetworkTripwireActive
    Install-SgtSessionHelper
    $script:Cred = [pscredential]::new('apikey', (ConvertTo-SecureString -String 'test-key-not-real' -AsPlainText -Force))
    $script:FixtureRoot = Join-Path -Path $PSScriptRoot -ChildPath '../Fixtures'

    function ConvertTo-SgtAsciiText {
        # A character outside printable ASCII is written as \uXXXX, so a log line reads the same in every console encoding.
        param([string]$Text)
        -join @(foreach ($Char in $Text.ToCharArray()) { if ([int]$Char -gt 126 -or [int]$Char -lt 32) { '\u{0:x4}' -f [int]$Char } else { [string]$Char } })
    }
    function Format-SgtMeasuredValue {
        # Type name and value, in the invariant culture. A list gives its element type, its count and every element.
        param($Value)
        if ($null -eq $Value) { return 'null' }
        if ($Value -is [array]) {
            $Parts = @(foreach ($Element in $Value) { Format-SgtMeasuredValue -Value $Element })
            return '{0}[{1}]({2})' -f $Value.GetType().GetElementType().Name, $Value.Count, ($Parts -join ', ')
        }
        if ($Value -is [datetime]) {
            return 'DateTime({0}, Kind {1})' -f $Value.ToString('yyyy-MM-ddTHH:mm:ss.fff', [System.Globalization.CultureInfo]::InvariantCulture), $Value.Kind
        }
        '{0}({1})' -f $Value.GetType().Name, (ConvertTo-SgtAsciiText -Text ([string]::Format([System.Globalization.CultureInfo]::InvariantCulture, '{0}', $Value)))
    }
    function Format-SgtMeasuredObject {
        # Every property of an object as name=type(value), in the object's own order.
        param($Object, [scriptblock]$Where = { $true })
        if ($null -eq $Object) { return 'no object' }
        $Parts = @(foreach ($Member in $Object.PSObject.Properties) {
                if (& $Where $Member.Name) { '{0}={1}' -f (ConvertTo-SgtAsciiText -Text $Member.Name), (Format-SgtMeasuredValue -Value $Member.Value) }
            })
        if ($Parts.Count -eq 0) { return 'no property' }
        $Parts -join '; '
    }
    function Format-SgtMeasuredError {
        param($ErrorRecord)
        $Inner = if ($ErrorRecord.Exception.InnerException) { $ErrorRecord.Exception.InnerException.GetType().Name } else { 'none' }
        'threw {0} (inner {1}), error id {2}: "{3}"' -f $ErrorRecord.Exception.GetType().Name, $Inner, $ErrorRecord.FullyQualifiedErrorId, (ConvertTo-SgtAsciiText -Text ([string]$ErrorRecord.Exception.Message))
    }
}

AfterAll {
    Uninstall-SgtSessionHelper
    Disable-SgtNetworkTripwire
}

# Sprint 4 step 3 measurements (D30-D34). Each It writes one MEASURE line with type names, made-up values, counts,
# True/False and version numbers only, and asserts nothing about the measured value, so the same file measures any
# version of the module. A culture is set inside try/finally and restored.
Describe 'Sprint 4 step 3 measurements' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
        Remove-Variable -Name SgtMeasureCultureName -Scope Global -ErrorAction SilentlyContinue
    }

    It 'D30/D31: type and value per property for <Name>' -ForEach @(
        @{ Name = 'D30 numbers that fit Int32'; Json = '{"created":1700000000,"updated_at":1700000001,"added_at":1700000002,"assigned_at":1700000003,"last_validation_attempt_at":1700000004,"valid":true}' }
        @{ Name = 'D30 zero and one-digit numbers'; Json = '{"created":0,"updated_at":5,"added_at":0,"assigned_at":7,"last_validation_attempt_at":9,"valid":false}' }
        @{ Name = 'D30 a number above Int32 in added_at only'; Json = '{"added_at":5000000000,"name":"sgt-test-name"}' }
        @{ Name = 'D30 a number above Int32 in created only'; Json = '{"created":5000000000,"name":"sgt-test-name"}' }
        @{ Name = 'D30 values that are no whole number'; Json = '{"created":1.5,"updated_at":null,"added_at":"sgt-test-text","assigned_at":false,"last_validation_attempt_at":2.5,"valid":true}' }
        @{ Name = 'D30 whole numbers under names outside the pattern'; Json = '{"id":1001,"count":3,"user_id":1002,"at":1700000000,"format":1700000001}' }
        @{ Name = 'D31 a list of numbers'; Json = '{"created":[1700000000,1700000001,1700000002],"updated_at":[1700000003,1700000004],"added_at":[1700000005,1700000006],"assigned_at":[1700000007,1700000008],"last_validation_attempt_at":[1700000009,1700000010],"valid":[true,false]}' }
        @{ Name = 'D31 a list of one number'; Json = '{"created":[1700000000],"updated_at":[1700000001],"added_at":[1700000002]}' }
        @{ Name = 'D31 a list of a number and a text'; Json = '{"created":[1700000000,"sgt-test-text"],"updated_at":["sgt-test-text",1700000001],"added_at":[1700000002,null]}' }
    ) {
        $Run = InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Json = $Json } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            # The answer is parsed by ConvertFrom-Json in the running shell, the parser Invoke-RestMethod uses for JSON in that edition.
            $Parsed = $Json | ConvertFrom-Json
            Set-SgtNetworkStub -Response $Parsed
            $Out = $null
            $Caught = $null
            try { $Out = @(Invoke-SendGrid -Method Get -Namespace 'things') } catch { $Caught = $_ }
            @{ Parsed = $Parsed; Out = $Out; Caught = $Caught }
        }
        $Outcome = if ($Run.Caught) { Format-SgtMeasuredError -ErrorRecord $Run.Caught } else { 'objects {0}; {1}' -f @($Run.Out).Count, (Format-SgtMeasuredObject -Object @($Run.Out)[0]) }
        $Result = 'parsed answer: {0} || output: {1}' -f (Format-SgtMeasuredObject -Object $Run.Parsed), $Outcome
        Write-Host ('MEASURE D30 [{0} {1}] {2}: {3}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Name, $Result)
        $Result | Should -Not -BeNullOrEmpty
    }

    It 'D30: the time-named properties in the output for fixture <File>' -ForEach @(
        @{ File = 'api-keys-page.json' }
        @{ File = 'ips-list.json' }
        @{ File = 'send-ips-page.json' }
        @{ File = 'subusers-include-region-page.json' }
        @{ File = 'subusers-page.json' }
        @{ File = 'user-settings-enforced-tls.json' }
        @{ File = 'whitelabel-domains-page.json' }
    ) {
        $Run = InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Path = (Join-Path -Path $script:FixtureRoot -ChildPath $File) } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            $Parsed = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
            Set-SgtNetworkStub -Response $Parsed
            $Out = $null
            $Caught = $null
            try { $Out = @(Invoke-SendGrid -Method Get -Namespace 'things') } catch { $Caught = $_ }
            @{ Out = $Out; Caught = $Caught }
        }
        # An output name has no underscore, so a name that ended on _at ends on At.
        $TimeNamed = { param($MemberName) $MemberName -match 'valid|created|updated|lastat' -or $MemberName -cmatch 'At$' }
        $Result = if ($Run.Caught) { Format-SgtMeasuredError -ErrorRecord $Run.Caught } else { 'objects {0}; first object: {1}' -f @($Run.Out).Count, (Format-SgtMeasuredObject -Object @($Run.Out)[0] -Where $TimeNamed) }
        Write-Host ('MEASURE D30 [{0} {1}] fixture {2}: {3}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $File, $Result)
        $Result | Should -Not -BeNullOrEmpty
    }

    # Get-SGIPAddress reads ips through Invoke-SendGrid and send_ips/ips through Invoke-SendGridCursorList, so the
    # same kind of field is measured through the command for both readers.
    It 'D30: the time-named properties in the output of <Name>' -ForEach @(
        @{ Name = 'Get-SGIPAddress (ips)'; IncludeRegion = $false; Json = '[{"ip":"192.0.2.10","assigned_at":1700000003,"pools":[],"warmup":false}]' }
        @{ Name = 'Get-SGIPAddress -IncludeRegion (send_ips/ips)'; IncludeRegion = $true; Json = '{"result":[{"ip":"192.0.2.10","added_at":1700000002,"updated_at":1700000001,"region":"us"}],"_metadata":{"next_params":{"after_key":null}}}' }
    ) {
        $Run = InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Json = $Json; IncludeRegion = $IncludeRegion } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ($Json | ConvertFrom-Json)
            $Out = $null
            $Caught = $null
            try { $Out = @(Get-SGIPAddress -IncludeRegion:$IncludeRegion) } catch { $Caught = $_ }
            @{ Out = $Out; Caught = $Caught }
        }
        $TimeNamed = { param($MemberName) $MemberName -match 'valid|created|updated|lastat' -or $MemberName -cmatch 'At$' }
        $Result = if ($Run.Caught) { Format-SgtMeasuredError -ErrorRecord $Run.Caught } else { 'objects {0}; first object: {1}' -f @($Run.Out).Count, (Format-SgtMeasuredObject -Object @($Run.Out)[0] -Where $TimeNamed) }
        Write-Host ('MEASURE D30 [{0} {1}] {2}: {3}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Name, $Result)
        $Result | Should -Not -BeNullOrEmpty
    }

    It 'D32: what binding -Value gives for -Property <Property>' -ForEach @(
        @{ Property = 'TemplateId' }
        @{ Property = 'TemplateName' }
        @{ Property = 'ToEmail' }
        @{ Property = 'Status' }
    ) {
        $Result = InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Property = $Property } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ messages = @([pscustomobject]@{ msg_id = 'sgt-test-message-id'; status = 'delivered' }) })
            $Value = if ($Property -eq 'Status') { 'delivered' } else { 'sgt-test-value' }
            $Call = try {
                $Out = @(Get-SGEmailActivity -Property $Property -EQ -Value $Value -ErrorAction Stop)
                'no error; objects {0}' -f $Out.Count
            }
            catch {
                'threw {0}, error id {1}, names Get-SGTemplate: {2}' -f $_.Exception.GetType().Name, $_.FullyQualifiedErrorId, ("$($_.Exception.Message)" -match 'Get-SGTemplate')
            }
            $Calls = Get-SgtNetworkCall
            $Uris = @($Calls | ForEach-Object { $_.Uri.OriginalString }) -join ' , '
            # The Value parameter as Get-Command sees it for this -Property, without running the command.
            $Meta = try {
                $Parameter = (Get-Command -Name Get-SGEmailActivity -ArgumentList $Property -ErrorAction Stop).Parameters['Value']
                if ($null -eq $Parameter) {
                    'no Value parameter'
                }
                else {
                    $Sets = @(foreach ($SetName in $Parameter.ParameterSets.Keys) { '{0} at position {1}' -f $SetName, $Parameter.ParameterSets[$SetName].Position })
                    'type {0}; sets {1}; ValidateSet attributes {2}' -f $Parameter.ParameterType.Name, ($Sets -join ','), @($Parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count
                }
            }
            catch {
                'Get-Command threw {0}' -f $_.Exception.GetType().Name
            }
            'call: {0}; requests {1}; request uris: {2} || Value parameter: {3}' -f $Call, $Calls.Count, $Uris, $Meta
        }
        Write-Host ('MEASURE D32 [{0} {1}] -Property {2}: {3}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Property, $Result)
        $Result | Should -Not -BeNullOrEmpty
    }

    It 'D33: the verbose lines for <Name>' -ForEach @(
        @{ Name = 'Get-SGEmailActivity with a filter value'; Kind = 'Activity'; Json = $null }
        @{ Name = 'Invoke-SendGrid with a query string and an object with one property as answer'; Kind = 'Direct'; Json = '{"name":"sgt-test-name"}' }
        @{ Name = 'Invoke-SendGrid with a query string and an empty object as answer'; Kind = 'Direct'; Json = '{}' }
        @{ Name = 'Invoke-SendGrid with a query string and a list of two empty objects as answer'; Kind = 'Direct'; Json = '[{},{}]' }
        @{ Name = 'Invoke-SendGrid with a query string and no answer'; Kind = 'Direct'; Json = $null }
    ) {
        $Messages = InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Kind = $Kind; Json = $Json } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            if ($Kind -eq 'Activity') {
                Set-SgtNetworkStub -Response ([pscustomobject]@{ messages = @([pscustomobject]@{ msg_id = 'sgt-test-message-id'; status = 'delivered' }) })
            }
            elseif ($null -eq $Json) {
                Set-SgtNetworkStub -Response $null
            }
            else {
                Set-SgtNetworkStub -Response ($Json | ConvertFrom-Json)
            }
            # A module function reads the global preference, so set both and restore the global one.
            $SavedVerbose = $global:VerbosePreference
            try {
                $global:VerbosePreference = 'SilentlyContinue'
                $VerbosePreference = 'SilentlyContinue'
                $Streams = if ($Kind -eq 'Activity') {
                    @(& { Get-SGEmailActivity -Property ToEmail -EQ -Value 'one@example.com' -Verbose } 4>&1)
                }
                else {
                    @(& { Invoke-SendGrid -Method Get -Namespace 'things?limit=1&name=sgt-test-value' -CallingCmdlet 'sgt-test-caller' -Verbose } 4>&1)
                }
            }
            finally {
                $global:VerbosePreference = $SavedVerbose
            }
            , @($Streams | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $_.Message })
        }
        $Messages = @($Messages)
        $Result = 'verbose lines {0}; "Successfully invoked" lines {1}; lines with the query part {2}: {3}' -f $Messages.Count, @($Messages | Where-Object { $_ -like 'Successfully invoked*' }).Count, @($Messages | Where-Object { $_ -match '\?|limit=|query=' }).Count, (@($Messages | ForEach-Object { '[{0}]' -f (ConvertTo-SgtAsciiText -Text $_) }) -join ' ')
        Write-Host ('MEASURE D33 [{0} {1}] {2}: {3}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Name, $Result)
        $Result | Should -Not -BeNullOrEmpty
    }

    # -WhatIf writes its line through the host, so it is measured in a new process whose host records every line.
    # The module has no session there and the request is never sent.
    It 'D33: the host lines for <Name>' -ForEach @(
        @{ Name = 'Invoke-SendGrid -WhatIf with a query string'; Script = 'Invoke-SendGrid -Method Get -Namespace ''things?limit=1&name=sgt-test-value'' -WhatIf' }
        @{ Name = 'Get-SGEmailActivity with WhatIfPreference at the caller'; Script = '$WhatIfPreference = $true; Get-SGEmailActivity -Property ToEmail -EQ -Value ''one@example.com''' }
    ) {
        $Run = Invoke-SgtInCountingHost -Script $Script
        $Result = 'prompts {0}; host lines {1}: {2}; threw {3}; calls {4}; unmocked calls {5}' -f $Run.PromptCount, $Run.HostLine.Count, (@($Run.HostLine | ForEach-Object { '[{0}]' -f (ConvertTo-SgtAsciiText -Text $_) }) -join ' '), $Run.Threw, $Run.NetworkCallCount, $Run.UnmockedCall.Count
        Write-Host ('MEASURE D33 [{0} {1}] {2}: {3}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Name, $Result)
        $Run.UnmockedCall | Should -BeNullOrEmpty
        $Result | Should -Not -BeNullOrEmpty
    }

    It 'D34: the filter query under <Culture> for <Name>' -ForEach $script:FilterCases {
        $Result = InModuleScope SendGridTools -Parameters @{ Culture = $Culture; Filter = $Filter } {
            $SavedCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
            $Outcome = $null
            $Caught = $null
            try {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo($Culture)
                try { $Outcome = 'query {0}' -f (ConvertTo-FilterQuery -Filter $Filter) } catch { $Caught = $_ }
            }
            finally {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $SavedCulture
            }
            if ($Caught) { $Caught } else { $Outcome }
        }
        if ($Result -is [System.Management.Automation.ErrorRecord]) { $Result = Format-SgtMeasuredError -ErrorRecord $Result }
        Write-Host ('MEASURE D34 [{0} {1}] filter, {2}, {3}: {4}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Culture, $Name, (ConvertTo-SgtAsciiText -Text $Result))
        $Result | Should -Not -BeNullOrEmpty
    }

    It 'D34: the date field under <Culture> for <Name>' -ForEach $script:DateCases {
        $Run = InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Culture = $Culture; Json = $Json } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ($Json | ConvertFrom-Json)
            $SavedCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
            $Out = $null
            $Caught = $null
            try {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo($Culture)
                try { $Out = @(Invoke-SendGrid -Method Get -Namespace 'things') } catch { $Caught = $_ }
            }
            finally {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $SavedCulture
            }
            @{ Out = $Out; Caught = $Caught }
        }
        $Result = if ($Run.Caught) { Format-SgtMeasuredError -ErrorRecord $Run.Caught } else { Format-SgtMeasuredObject -Object @($Run.Out)[0] }
        Write-Host ('MEASURE D34 [{0} {1}] date field, {2}, {3}: {4}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Culture, $Name, $Result)
        $Result | Should -Not -BeNullOrEmpty
    }

    # Get-Culture reads the host's culture, which need not follow the thread culture, so the names are measured with
    # the thread culture alone and with Get-Culture answering the same culture inside the module.
    It 'D34: the property names for id, ip and is_enabled under <Culture> with <Mode>' -ForEach $script:NameCases {
        if ($Mode -eq 'the thread culture and Get-Culture') {
            $global:SgtMeasureCultureName = $Culture
            Mock -CommandName Get-Culture -ModuleName SendGridTools -MockWith { [System.Globalization.CultureInfo]::GetCultureInfo($global:SgtMeasureCultureName) }
        }
        $Run = InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Culture = $Culture } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ('{"id":1001,"ip":"192.0.2.10","is_enabled":true}' | ConvertFrom-Json)
            $SavedCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
            $Out = $null
            $Caught = $null
            $Says = $null
            try {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo($Culture)
                $Says = (Get-Culture).Name
                try { $Out = @(Invoke-SendGrid -Method Get -Namespace 'things') } catch { $Caught = $_ }
            }
            finally {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $SavedCulture
            }
            @{ Out = $Out; Caught = $Caught; Says = $Says }
        }
        $Outcome = if ($Run.Caught) { Format-SgtMeasuredError -ErrorRecord $Run.Caught } else { Format-SgtMeasuredObject -Object @($Run.Out)[0] }
        $Result = 'Get-Culture in the module says {0}; {1}' -f $Run.Says, $Outcome
        Write-Host ('MEASURE D34 [{0} {1}] names, {2}, {3}: {4}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Culture, $Mode, $Result)
        $Result | Should -Not -BeNullOrEmpty
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
