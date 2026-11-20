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

    It 'Binds -Value for TemplateName and sends the value' {
        InModuleScope SendGridTools {
            $Result = @(Get-SGEmailActivity -Property TemplateName -EQ -Value 'sgt-test-template-name')
            $Calls = (Get-SgtNetworkCall)
            $Calls.Count | Should -Be 1
            # The field name of the TemplateName filter is an existing gap and is not asserted.
            $Calls[0].Uri.OriginalString | Should -BeLike 'https://api.sendgrid.com/v3/messages?limit=10&query=(*%22sgt-test-template-name%22)'
        }
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

    Context 'Completer' {
        It 'Completes <Property> from <Lookup>: nothing before it runs, one call when it runs, all or the matching value' -ForEach @(
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
            @{ Property = 'ApiKeyName'; Lookup = 'Get-SGApiKey' }
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
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
