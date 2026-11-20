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

Describe 'Get-SGEmailActivity verbose output and query (D18)' {
    BeforeEach {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ messages = @([pscustomobject]@{ msg_id = 'sgt-test-message-id'; status = 'delivered' }) })
        }
    }
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Sends the same query and writes no value for -Property' {
        InModuleScope SendGridTools {
            $SavedVerbose = $global:VerbosePreference
            try {
                $global:VerbosePreference = 'SilentlyContinue'
                $VerbosePreference = 'SilentlyContinue'
                $Streams = @(& { Get-SGEmailActivity -Property ToEmail -EQ -Value 'one@example.com' -Verbose } 4>&1)
            }
            finally {
                $global:VerbosePreference = $SavedVerbose
            }
            $Messages = @($Streams | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $_.Message })

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Uri.OriginalString | Should -BeExactly 'https://api.sendgrid.com/v3/messages?limit=10&query=(to_email %3D %22one%40example.com%22)'
            @($Messages | Where-Object { $_ -ceq 'Filter Query: Property: ToEmail, Operator: =' }).Count | Should -Be 1
            @($Messages | Where-Object { $_ -ceq 'Starting process with method: Get and namespace: messages' }).Count | Should -Be 1
            @($Messages | Where-Object { $_ -ceq 'Successfully invoked "Get-SGEmailActivity" on "messages".' }).Count | Should -Be 1
            foreach ($Line in $Messages) {
                $Line | Should -Not -BeLike '*one@example.com*'
                $Line | Should -Not -BeLike '*one%40example*'
                $Line | Should -Not -BeLike '*query=*'
            }
        }
    }

    It 'Sends the same query and writes no value for -Filter' {
        InModuleScope SendGridTools {
            $SavedVerbose = $global:VerbosePreference
            try {
                $global:VerbosePreference = 'SilentlyContinue'
                $VerbosePreference = 'SilentlyContinue'
                $Streams = @(& { Get-SGEmailActivity -Filter 'ToEmail -eq "one@example.com"' -Verbose } 4>&1)
            }
            finally {
                $global:VerbosePreference = $SavedVerbose
            }
            $Messages = @($Streams | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $_.Message })

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Uri.OriginalString | Should -BeExactly 'https://api.sendgrid.com/v3/messages?limit=10&query=(to_email%3D%22one%40example.com%22)'
            ($Messages -join "`n") | Should -Match 'Property: to_email, Operator: -eq'
            @($Messages | Where-Object { $_ -ceq 'Starting process with method: Get and namespace: messages' }).Count | Should -Be 1
            @($Messages | Where-Object { $_ -ceq 'Successfully invoked "Get-SGEmailActivity" on "messages".' }).Count | Should -Be 1
            foreach ($Line in $Messages) {
                $Line | Should -Not -BeLike '*one@example.com*'
                $Line | Should -Not -BeLike '*one%40example*'
                $Line | Should -Not -BeLike '*query=*'
            }
        }
    }

    It 'Returns the messages' {
        InModuleScope SendGridTools {
            $SavedVerbose = $global:VerbosePreference
            try {
                $global:VerbosePreference = 'SilentlyContinue'
                $VerbosePreference = 'SilentlyContinue'
                $Result = @(Get-SGEmailActivity -Property ToEmail -EQ -Value 'one@example.com')
            }
            finally {
                $global:VerbosePreference = $SavedVerbose
            }
            $Result.Count | Should -Be 1
            $Result[0].MsgId | Should -Be 'sgt-test-message-id'
        }
    }
}

Describe 'Get-SGEmailActivity binds -Value for a template property without a call (D32)' {
    BeforeEach {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ messages = @([pscustomobject]@{ msg_id = 'sgt-test-message-id'; status = 'delivered' }) })
        }
    }
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Sends the template id as the filter value and makes no other request' {
        InModuleScope SendGridTools {
            $Result = @(Get-SGEmailActivity -Property TemplateId -EQ -Value 'sgt-test-template-id')
            $Calls = (Get-SgtNetworkCall)
            $Calls.Count | Should -Be 1
            $Calls[0].Uri.OriginalString | Should -BeExactly 'https://api.sendgrid.com/v3/messages?limit=10&query=(template_id %3D %22sgt-test-template-id%22)'
            $Result.Count | Should -Be 1
        }
    }

    It 'Sends both template ids for two values' {
        InModuleScope SendGridTools {
            $null = @(Get-SGEmailActivity -Property TemplateId -EQ -Value 'sgt-test-template-1', 'sgt-test-template-2')
            $Calls = (Get-SgtNetworkCall)
            $Calls.Count | Should -Be 1
            $Calls[0].Uri.OriginalString | Should -BeExactly 'https://api.sendgrid.com/v3/messages?limit=10&query=(template_id IN (%22sgt-test-template-1%22,%22sgt-test-template-2%22))'
        }
    }

    It 'Refuses -Property TemplateName with <Operator> and sends nothing' -ForEach @(
        @{ Operator = 'EQ' }
        @{ Operator = 'NE' }
        @{ Operator = 'Contains' }
        @{ Operator = 'NotContains' }
        @{ Operator = 'no operator switch' }
    ) {
        Mock -CommandName Get-SGApiKey -ModuleName SendGridTools -MockWith { throw 'Get-SGApiKey must not be called' }
        Mock -CommandName Get-SGSuppressionGroup -ModuleName SendGridTools -MockWith { throw 'Get-SGSuppressionGroup must not be called' }
        Mock -CommandName Get-SGTeammate -ModuleName SendGridTools -MockWith { throw 'Get-SGTeammate must not be called' }
        InModuleScope SendGridTools -Parameters @{ Operator = $Operator } {
            $Switches = @{}
            if ($Operator -ne 'no operator switch') {
                $Switches[$Operator] = $true
            }
            $Message = $null
            try {
                $null = @(Get-SGEmailActivity -Property TemplateName -Value 'sgt-test-template-name' @Switches)
            }
            catch {
                $Message = $_.Exception.Message
            }
            $Message | Should -BeExactly 'SendGrid cannot filter email activity by template name; use -Property TemplateId.'
            (Get-SgtNetworkCall).Count | Should -Be 0
        }
        Should -Invoke -CommandName Get-SGApiKey -ModuleName SendGridTools -Times 0 -Exactly
        Should -Invoke -CommandName Get-SGSuppressionGroup -ModuleName SendGridTools -Times 0 -Exactly
        Should -Invoke -CommandName Get-SGTeammate -ModuleName SendGridTools -Times 0 -Exactly
    }

    It 'Gives -Value for <Property> the type, set and position it has for ToEmail' -ForEach @(
        @{ Property = 'TemplateId' }
        @{ Property = 'TemplateName' }
    ) {
        InModuleScope SendGridTools -Parameters @{ Property = $Property } {
            $Parameter = (Get-Command -Name Get-SGEmailActivity -ArgumentList $Property).Parameters['Value']
            $Parameter | Should -Not -BeNullOrEmpty
            $Parameter.ParameterType | Should -Be ([string[]])
            @($Parameter.ParameterSets.Keys) | Should -Be @('PropertySet')
            $Parameter.ParameterSets['PropertySet'].Position | Should -Be 2
            $Parameter.ParameterSets['PropertySet'].IsMandatory | Should -BeFalse
            @($Parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count | Should -Be 0
            (Get-SgtNetworkCall).Count | Should -Be 0
        }
    }
}

Describe 'Get-SGEmailActivity binds -Value for a key, group or teammate property without a call (D85)' {
    BeforeEach {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ messages = @([pscustomobject]@{ msg_id = 'sgt-test-message-id'; status = 'delivered' }) })
        }
        Mock -CommandName Get-SGApiKey -ModuleName SendGridTools -MockWith {
            [pscustomobject]@{ ApiKeyId = 'sgt-key-id-1'; Name = 'sgt-key-name-1' }
            [pscustomobject]@{ ApiKeyId = 'sgt-key-id-2'; Name = 'sgt-key-name-2' }
        }
        Mock -CommandName Get-SGSuppressionGroup -ModuleName SendGridTools -MockWith {
            [pscustomobject]@{ Id = 101; Name = 'sgt-group-name-1' }
            [pscustomobject]@{ Id = 102; Name = 'sgt-group-name-2' }
        }
        Mock -CommandName Get-SGTeammate -ModuleName SendGridTools -MockWith {
            [pscustomobject]@{ Username = 'sgt-teammate-1' }
            [pscustomobject]@{ Username = 'sgt-teammate-2' }
        }
    }
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Binds -Value for <Property> without a call to any lookup' -ForEach @(
        @{ Property = 'ApiKeyId' }
        @{ Property = 'ApiKeyName' }
        @{ Property = 'AsmGroupId' }
        @{ Property = 'AsmGroupName' }
        @{ Property = 'Teammate' }
    ) {
        Mock -CommandName Get-SGApiKey -ModuleName SendGridTools -MockWith { throw 'Get-SGApiKey must not be called' }
        Mock -CommandName Get-SGSuppressionGroup -ModuleName SendGridTools -MockWith { throw 'Get-SGSuppressionGroup must not be called' }
        Mock -CommandName Get-SGTeammate -ModuleName SendGridTools -MockWith { throw 'Get-SGTeammate must not be called' }
        InModuleScope SendGridTools -Parameters @{ Property = $Property } {
            $Parameter = (Get-Command -Name Get-SGEmailActivity -ArgumentList $Property).Parameters['Value']
            $Parameter | Should -Not -BeNullOrEmpty
            $Parameter.ParameterType | Should -Be ([string[]])
            @($Parameter.ParameterSets.Keys) | Should -Be @('PropertySet')
            $Parameter.ParameterSets['PropertySet'].Position | Should -Be 2
            $Parameter.ParameterSets['PropertySet'].IsMandatory | Should -BeFalse
            @($Parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count | Should -Be 0
            @($Parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ArgumentCompleterAttribute] }).Count | Should -Be 1
            (Get-SgtNetworkCall).Count | Should -Be 0
        }
        Should -Invoke -CommandName Get-SGApiKey -ModuleName SendGridTools -Times 0 -Exactly
        Should -Invoke -CommandName Get-SGSuppressionGroup -ModuleName SendGridTools -Times 0 -Exactly
        Should -Invoke -CommandName Get-SGTeammate -ModuleName SendGridTools -Times 0 -Exactly
    }

    It 'Sends <Property> with one value as <QueryOne> and looks up <ExpectedLookups> time(s)' -ForEach @(
        @{ Property = 'ApiKeyId'; Values = @('sgt-key-id-1'); QueryOne = '(api_key_id %3D %22sgt-key-id-1%22)'; ExpectedLookups = 0; Lookup = 'Get-SGApiKey' }
        @{ Property = 'ApiKeyName'; Values = @('sgt-key-name-1'); QueryOne = '(api_key_id %3D %22sgt-key-id-1%22)'; ExpectedLookups = 1; Lookup = 'Get-SGApiKey' }
        @{ Property = 'AsmGroupId'; Values = @('101'); QueryOne = '(asm_group_id %3D %22101%22)'; ExpectedLookups = 0; Lookup = 'Get-SGSuppressionGroup' }
        @{ Property = 'AsmGroupName'; Values = @('sgt-group-name-1'); QueryOne = '(asm_group_id %3D %22101%22)'; ExpectedLookups = 1; Lookup = 'Get-SGSuppressionGroup' }
        @{ Property = 'Teammate'; Values = @('sgt-teammate-1'); QueryOne = '(teammate %3D %22sgt-teammate-1%22)'; ExpectedLookups = 0; Lookup = 'Get-SGTeammate' }
    ) {
        InModuleScope SendGridTools -Parameters @{ Property = $Property; Values = $Values; QueryOne = $QueryOne } {
            $null = @(Get-SGEmailActivity -Property $Property -EQ -Value $Values)
            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Uri.OriginalString | Should -BeExactly ('https://api.sendgrid.com/v3/messages?limit=10&query=' + $QueryOne)
        }
        Should -Invoke -CommandName $Lookup -ModuleName SendGridTools -Times $ExpectedLookups -Exactly
        foreach ($Other in @('Get-SGApiKey', 'Get-SGSuppressionGroup', 'Get-SGTeammate') | Where-Object { $_ -ne $Lookup }) {
            Should -Invoke -CommandName $Other -ModuleName SendGridTools -Times 0 -Exactly
        }
    }

    It 'Sends <Property> with two values as <QueryTwo> and looks up <ExpectedLookups> time(s)' -ForEach @(
        @{ Property = 'ApiKeyId'; Values = @('sgt-key-id-1', 'sgt-key-id-2'); QueryTwo = '(api_key_id IN (%22sgt-key-id-1%22,%22sgt-key-id-2%22))'; ExpectedLookups = 0; Lookup = 'Get-SGApiKey' }
        @{ Property = 'ApiKeyName'; Values = @('sgt-key-name-1', 'sgt-key-name-2'); QueryTwo = '(api_key_id IN (%22sgt-key-id-1%22,%22sgt-key-id-2%22))'; ExpectedLookups = 1; Lookup = 'Get-SGApiKey' }
        @{ Property = 'AsmGroupId'; Values = @('101', '102'); QueryTwo = '(asm_group_id IN (%22101%22,%22102%22))'; ExpectedLookups = 0; Lookup = 'Get-SGSuppressionGroup' }
        @{ Property = 'AsmGroupName'; Values = @('sgt-group-name-1', 'sgt-group-name-2'); QueryTwo = '(asm_group_id IN (%22101%22,%22102%22))'; ExpectedLookups = 1; Lookup = 'Get-SGSuppressionGroup' }
        @{ Property = 'Teammate'; Values = @('sgt-teammate-1', 'sgt-teammate-2'); QueryTwo = '(teammate IN (%22sgt-teammate-1%22,%22sgt-teammate-2%22))'; ExpectedLookups = 0; Lookup = 'Get-SGTeammate' }
    ) {
        InModuleScope SendGridTools -Parameters @{ Property = $Property; Values = $Values; QueryTwo = $QueryTwo } {
            $null = @(Get-SGEmailActivity -Property $Property -EQ -Value $Values)
            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Uri.OriginalString | Should -BeExactly ('https://api.sendgrid.com/v3/messages?limit=10&query=' + $QueryTwo)
        }
        Should -Invoke -CommandName $Lookup -ModuleName SendGridTools -Times $ExpectedLookups -Exactly
        foreach ($Other in @('Get-SGApiKey', 'Get-SGSuppressionGroup', 'Get-SGTeammate') | Where-Object { $_ -ne $Lookup }) {
            Should -Invoke -CommandName $Other -ModuleName SendGridTools -Times 0 -Exactly
        }
    }

    It 'Stops with a message and sends nothing for <Property> with <Case>' -ForEach @(
        @{ Property = 'ApiKeyName'; Case = 'an unknown name'; Values = @('sgt-key-name-missing'); Expected = "No API key named 'sgt-key-name-missing'."; Lookup = 'Get-SGApiKey' }
        @{ Property = 'ApiKeyName'; Case = 'one known and one unknown name'; Values = @('sgt-key-name-1', 'sgt-key-name-missing'); Expected = "No API key named 'sgt-key-name-missing'."; Lookup = 'Get-SGApiKey' }
        @{ Property = 'AsmGroupName'; Case = 'an unknown name'; Values = @('sgt-group-name-missing'); Expected = "No unsubscribe group named 'sgt-group-name-missing'."; Lookup = 'Get-SGSuppressionGroup' }
        @{ Property = 'AsmGroupName'; Case = 'one known and one unknown name'; Values = @('sgt-group-name-1', 'sgt-group-name-missing'); Expected = "No unsubscribe group named 'sgt-group-name-missing'."; Lookup = 'Get-SGSuppressionGroup' }
    ) {
        InModuleScope SendGridTools -Parameters @{ Property = $Property; Values = $Values; Expected = $Expected } {
            $Message = $null
            try {
                $null = @(Get-SGEmailActivity -Property $Property -EQ -Value $Values)
            }
            catch {
                $Message = $_.Exception.Message
            }
            $Message | Should -BeExactly $Expected
            (Get-SgtNetworkCall).Count | Should -Be 0
        }
        Should -Invoke -CommandName $Lookup -ModuleName SendGridTools -Times 1 -Exactly
    }

    It 'Sends nothing for <Property> with <Case> under -ErrorAction SilentlyContinue' -ForEach @(
        @{ Property = 'TemplateName'; Case = 'the refused template name'; Values = @('sgt-template-name'); Expected = 'SendGrid cannot filter email activity by template name; use -Property TemplateId.' }
        @{ Property = 'ApiKeyName'; Case = 'an unknown name'; Values = @('sgt-key-name-missing'); Expected = "No API key named 'sgt-key-name-missing'." }
        @{ Property = 'ApiKeyName'; Case = 'one known and one unknown name'; Values = @('sgt-key-name-1', 'sgt-key-name-missing'); Expected = "No API key named 'sgt-key-name-missing'." }
        @{ Property = 'AsmGroupName'; Case = 'an unknown name'; Values = @('sgt-group-name-missing'); Expected = "No unsubscribe group named 'sgt-group-name-missing'." }
        @{ Property = 'AsmGroupName'; Case = 'one known and one unknown name'; Values = @('sgt-group-name-1', 'sgt-group-name-missing'); Expected = "No unsubscribe group named 'sgt-group-name-missing'." }
    ) {
        InModuleScope SendGridTools -Parameters @{ Property = $Property; Values = $Values; Expected = $Expected } {
            $Collected = $null
            $Thrown = $null
            try {
                $null = @(Get-SGEmailActivity -Property $Property -EQ -Value $Values -ErrorAction SilentlyContinue -ErrorVariable Collected)
            }
            catch {
                $Thrown = $_.Exception.Message
            }
            (Get-SgtNetworkCall).Count | Should -Be 0
            $Messages = @(@($Collected) | ForEach-Object { $_.Exception.Message }) + @($Thrown) | Where-Object { $_ }
            $Messages | Should -Contain $Expected
        }
    }

    It 'Sends nothing for the refused template name under -ErrorAction Ignore' {
        InModuleScope SendGridTools {
            try {
                $null = @(Get-SGEmailActivity -Property TemplateName -EQ -Value 'sgt-template-name' -ErrorAction Ignore)
            }
            catch {
                $null = $_
            }
            (Get-SgtNetworkCall).Count | Should -Be 0
        }
    }

    It 'Sends <Property> with -NE and two names as <QueryTwo> with one lookup' -ForEach @(
        @{ Property = 'ApiKeyName'; Values = @('sgt-key-name-1', 'sgt-key-name-2'); QueryTwo = '(api_key_id NOT%20IN (%22sgt-key-id-1%22,%22sgt-key-id-2%22))'; Lookup = 'Get-SGApiKey' }
        @{ Property = 'AsmGroupName'; Values = @('sgt-group-name-1', 'sgt-group-name-2'); QueryTwo = '(asm_group_id NOT%20IN (%22101%22,%22102%22))'; Lookup = 'Get-SGSuppressionGroup' }
    ) {
        InModuleScope SendGridTools -Parameters @{ Property = $Property; Values = $Values; QueryTwo = $QueryTwo } {
            $null = @(Get-SGEmailActivity -Property $Property -NE -Value $Values)
            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Uri.OriginalString | Should -BeExactly ('https://api.sendgrid.com/v3/messages?limit=10&query=' + $QueryTwo)
        }
        Should -Invoke -CommandName $Lookup -ModuleName SendGridTools -Times 1 -Exactly
    }

    Context 'Completer' {
        It 'Completes <Property> from <Lookup>: nothing before it runs, all or the matching value' -ForEach @(
            @{ Property = 'ApiKeyId'; Lookup = 'Get-SGApiKey'; All = @('sgt-key-id-1', 'sgt-key-id-2'); Prefix = 'sgt-key-id-2'; Matching = @('sgt-key-id-2') }
            @{ Property = 'ApiKeyName'; Lookup = 'Get-SGApiKey'; All = @('sgt-key-name-1', 'sgt-key-name-2'); Prefix = 'sgt-key-name-1'; Matching = @('sgt-key-name-1') }
            @{ Property = 'AsmGroupId'; Lookup = 'Get-SGSuppressionGroup'; All = @('101', '102'); Prefix = '102'; Matching = @('102') }
            @{ Property = 'AsmGroupName'; Lookup = 'Get-SGSuppressionGroup'; All = @('sgt-group-name-1', 'sgt-group-name-2'); Prefix = 'sgt-group-name-2'; Matching = @('sgt-group-name-2') }
            @{ Property = 'Teammate'; Lookup = 'Get-SGTeammate'; All = @('sgt-teammate-1', 'sgt-teammate-2'); Prefix = 'sgt-teammate-1'; Matching = @('sgt-teammate-1') }
        ) {
            # The completer script block may run outside the module session state, so mock the lookup in both scopes.
            Mock -CommandName Get-SGApiKey -MockWith {
                [pscustomobject]@{ ApiKeyId = 'sgt-key-id-1'; Name = 'sgt-key-name-1' }
                [pscustomobject]@{ ApiKeyId = 'sgt-key-id-2'; Name = 'sgt-key-name-2' }
            }
            Mock -CommandName Get-SGSuppressionGroup -MockWith {
                [pscustomobject]@{ Id = 101; Name = 'sgt-group-name-1' }
                [pscustomobject]@{ Id = 102; Name = 'sgt-group-name-2' }
            }
            Mock -CommandName Get-SGTeammate -MockWith {
                [pscustomobject]@{ Username = 'sgt-teammate-1' }
                [pscustomobject]@{ Username = 'sgt-teammate-2' }
            }
            $Completer = (Get-Command -Name Get-SGEmailActivity -ArgumentList $Property).Parameters['Value'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ArgumentCompleterAttribute] }
            Should -Invoke -CommandName $Lookup -ModuleName SendGridTools -Times 0 -Exactly

            $Everything = @(& $Completer.ScriptBlock 'Get-SGEmailActivity' 'Value' '' $null @{})
            $Everything | Should -Be $All
            $Everything[0] | Should -BeOfType ([string])
            @(& $Completer.ScriptBlock 'Get-SGEmailActivity' 'Value' $Prefix $null @{}) | Should -Be $Matching
            @(& $Completer.ScriptBlock 'Get-SGEmailActivity' 'Value' 'sgt-no-such-value' $null @{}).Count | Should -Be 0
        }

        It 'Calls <Lookup> once for one run of the completer for <Property>' -ForEach @(
            @{ Property = 'ApiKeyId'; Lookup = 'Get-SGApiKey' }
            @{ Property = 'ApiKeyName'; Lookup = 'Get-SGApiKey' }
            @{ Property = 'AsmGroupId'; Lookup = 'Get-SGSuppressionGroup' }
            @{ Property = 'AsmGroupName'; Lookup = 'Get-SGSuppressionGroup' }
            @{ Property = 'Teammate'; Lookup = 'Get-SGTeammate' }
        ) {
            $Completer = (Get-Command -Name Get-SGEmailActivity -ArgumentList $Property).Parameters['Value'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ArgumentCompleterAttribute] }
            Should -Invoke -CommandName $Lookup -ModuleName SendGridTools -Times 0 -Exactly
            $null = @(& $Completer.ScriptBlock 'Get-SGEmailActivity' 'Value' '' $null @{})
            Should -Invoke -CommandName $Lookup -ModuleName SendGridTools -Times 1 -Exactly
        }

        It 'Completes nothing and does not throw when <Lookup> fails for <Property>' -ForEach @(
            @{ Property = 'ApiKeyId'; Lookup = 'Get-SGApiKey' }
            @{ Property = 'ApiKeyName'; Lookup = 'Get-SGApiKey' }
            @{ Property = 'AsmGroupId'; Lookup = 'Get-SGSuppressionGroup' }
            @{ Property = 'AsmGroupName'; Lookup = 'Get-SGSuppressionGroup' }
            @{ Property = 'Teammate'; Lookup = 'Get-SGTeammate' }
        ) {
            Mock -CommandName $Lookup -ModuleName SendGridTools -MockWith { throw 'The lookup failed' }
            Mock -CommandName $Lookup -MockWith { throw 'The lookup failed' }
            $Completer = (Get-Command -Name Get-SGEmailActivity -ArgumentList $Property).Parameters['Value'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ArgumentCompleterAttribute] }

            { $script:Completed = @(& $Completer.ScriptBlock 'Get-SGEmailActivity' 'Value' '' $null @{}) } | Should -Not -Throw
            $script:Completed.Count | Should -Be 0
        }

        It 'Wraps a key name with a space or a single quote so that Tab inserts one argument' {
            Mock -CommandName Get-SGApiKey -ModuleName SendGridTools -MockWith {
                [pscustomobject]@{ ApiKeyId = 'sgt-key-id-1'; Name = 'sgt key name' }
                [pscustomobject]@{ ApiKeyId = 'sgt-key-id-2'; Name = "sgt'key" }
                [pscustomobject]@{ ApiKeyId = 'sgt-key-id-3'; Name = 'sgt-plain-name' }
            }
            Mock -CommandName Get-SGApiKey -MockWith {
                [pscustomobject]@{ ApiKeyId = 'sgt-key-id-1'; Name = 'sgt key name' }
                [pscustomobject]@{ ApiKeyId = 'sgt-key-id-2'; Name = "sgt'key" }
                [pscustomobject]@{ ApiKeyId = 'sgt-key-id-3'; Name = 'sgt-plain-name' }
            }
            $Completer = (Get-Command -Name Get-SGEmailActivity -ArgumentList ApiKeyName).Parameters['Value'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ArgumentCompleterAttribute] }

            @(& $Completer.ScriptBlock 'Get-SGEmailActivity' 'Value' '' $null @{}) | Should -Be @("'sgt key name'", "'sgt''key'", 'sgt-plain-name')
        }

        It 'Quotes every value that would not bind as one bare word for <Property>' -ForEach @(
            @{ Property = 'ApiKeyId'; Lookup = 'Get-SGApiKey' }
            @{ Property = 'ApiKeyName'; Lookup = 'Get-SGApiKey' }
            @{ Property = 'AsmGroupId'; Lookup = 'Get-SGSuppressionGroup' }
            @{ Property = 'AsmGroupName'; Lookup = 'Get-SGSuppressionGroup' }
            @{ Property = 'Teammate'; Lookup = 'Get-SGTeammate' }
        ) {
            $Typographic = 'sgt' + [char]0x2019 + 'key'
            $Raw = @('-sgt-key-id', 'sgt,key', 'sgt;key', $Typographic, 'sgt-key-id-1', 'sgt key', "sgt'key")
            $Script:Raw = $Raw
            $Expected = @("'-sgt-key-id'", "'sgt,key'", "'sgt;key'", ("'sgt" + [char]0x2019 + [char]0x2019 + "key'"), 'sgt-key-id-1', "'sgt key'", "'sgt''key'")
            $Block = {
                foreach ($Value in $Script:Raw) {
                    [pscustomobject]@{ ApiKeyId = $Value; Name = $Value; Id = $Value; Username = $Value }
                }
            }
            Mock -CommandName $Lookup -ModuleName SendGridTools -MockWith $Block
            Mock -CommandName $Lookup -MockWith $Block
            $Completer = (Get-Command -Name Get-SGEmailActivity -ArgumentList $Property).Parameters['Value'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ArgumentCompleterAttribute] }

            @(& $Completer.ScriptBlock 'Get-SGEmailActivity' 'Value' '' $null @{}) | Should -Be $Expected
        }

        It 'Completes <Property> through TabExpansion2 with exactly one lookup and no network call' -ForEach @(
            @{ Property = 'ApiKeyName'; Lookup = 'Get-SGApiKey'; Expected = @('sgt-key-name-1', 'sgt-key-name-2') }
            @{ Property = 'AsmGroupName'; Lookup = 'Get-SGSuppressionGroup'; Expected = @('sgt-group-name-1', 'sgt-group-name-2') }
            @{ Property = 'Teammate'; Lookup = 'Get-SGTeammate'; Expected = @('sgt-teammate-1', 'sgt-teammate-2') }
        ) {
            $global:SgtLookupCount = 0
            $global:SgtLookupNames = $Expected
            try {
                # The same block is mocked in the module scope and in the test scope; both count into one global.
                $Block = {
                    $global:SgtLookupCount++
                    foreach ($Name in $global:SgtLookupNames) {
                        [pscustomobject]@{ ApiKeyId = 'sgt-key-id'; Id = 101; Name = $Name; Username = $Name }
                    }
                }
                Mock -CommandName $Lookup -ModuleName SendGridTools -MockWith $Block
                Mock -CommandName $Lookup -MockWith $Block
                $Line = "Get-SGEmailActivity -Property $Property -EQ -Value "
                $Result = TabExpansion2 -inputScript $Line -cursorColumn $Line.Length
                @($Result.CompletionMatches.CompletionText) | Should -Be $Expected
                $global:SgtLookupCount | Should -Be 1
                InModuleScope SendGridTools {
                    (Get-SgtNetworkCall).Count | Should -Be 0
                }
            }
            finally {
                Remove-Variable -Name SgtLookupCount, SgtLookupNames -Scope Global -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'Get-SGEmailActivity sends the same encoded filter text in both shells' {
    BeforeEach {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ messages = @([pscustomobject]@{ msg_id = 'sgt-test-message-id'; status = 'delivered' }) })
        }
    }
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Sends the operator -NE as %21%3D' {
        InModuleScope SendGridTools {
            $null = Get-SGEmailActivity -Property Subject -NE -Value 'sgt-subject'
            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Uri.OriginalString | Should -BeExactly 'https://api.sendgrid.com/v3/messages?limit=10&query=(subject %21%3D %22sgt-subject%22)'
        }
    }

    It 'Sends an apostrophe, parentheses and an asterisk in a value as percent escapes' {
        InModuleScope SendGridTools {
            $null = Get-SGEmailActivity -Property Subject -EQ -Value "a'b(c)*"
            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Uri.OriginalString | Should -BeExactly 'https://api.sendgrid.com/v3/messages?limit=10&query=(subject %3D %22a%27b%28c%29%2A%22)'
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
