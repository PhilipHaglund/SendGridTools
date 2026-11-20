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
}

AfterAll {
    Uninstall-SgtSessionHelper
    Disable-SgtNetworkTripwire
}

Describe 'Send-SGMailMessage -SandboxMode (D78)' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    Context 'Request body' {
        BeforeAll {
            # Runs one send in module scope and returns the request count and the parsed body.
            # Kept as text and re-created inside the module, so it runs in module scope.
            $script:SendText = {
                param($Cred, $Shape, $Sandbox)
                $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
                Reset-SgtNetworkStub
                Set-SgtNetworkStub -Response ([pscustomobject]@{ placeholder = 'accepted' })
                $Params = @{
                    From    = 'sender@example.com'
                    To      = 'one@example.com'
                    Subject = 'placeholder subject'
                    Body    = 'placeholder body'
                }
                if ($Shape -like 'SeparateTo*') {
                    $Params['To'] = @('one@example.com', 'two@example.com')
                    $Params['SeparateTo'] = [switch]::new($true)
                }
                if ($Shape -like '*full') {
                    if ($Shape -like 'Default*') {
                        $Params['CC'] = 'copy@example.com'
                        $Params['BCC'] = 'blind@example.com'
                    }
                    $Params['BodyAsHtml'] = [switch]::new($true)
                    $Params['Attachment'] = [System.Net.Mail.Attachment]::new([System.IO.MemoryStream]::new([byte[]](104, 105)), 'note.txt', 'text/plain')
                    $Params['Priority'] = 'High'
                    $Params['ReplyTo'] = 'reply@example.com'
                    $Params['SendAt'] = (Get-Date).AddHours(1)
                    $Params['TemplateId'] = 'd-placeholder'
                    $Params['Categories'] = 'sgt-cat'
                }
                if ($Sandbox -eq 'on') { $Params['SandboxMode'] = [switch]::new($true) }
                if ($Sandbox -eq 'explicit-false') { $Params['SandboxMode'] = [switch]::new($false) }
                $null = Send-SGMailMessage @Params -Confirm:$false
                $Calls = @(Get-SgtNetworkCall | ForEach-Object { $_ })
                [pscustomobject]@{
                    Count = $Calls.Count
                    Sent  = if ($Calls.Count) { $Calls[0].Body | ConvertFrom-Json } else { $null }
                }
            }.ToString()
        }

        BeforeDiscovery {
            $script:Shapes = @(
                @{ Shape = 'Default minimal'; Keys = 'content, from, personalizations'; Personalizations = 1 }
                @{ Shape = 'Default full'; Keys = 'attachments, categories, content, from, personalizations, priority, reply_to, send_at, template_id'; Personalizations = 1 }
                @{ Shape = 'SeparateTo minimal'; Keys = 'content, from, personalizations'; Personalizations = 2 }
                @{ Shape = 'SeparateTo full'; Keys = 'attachments, categories, content, from, personalizations, priority, reply_to, send_at, template_id'; Personalizations = 2 }
            )
        }

        It 'Sends no mail_settings without -SandboxMode, <Shape>' -ForEach $script:Shapes {
            $Run = InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Shape = $Shape; Send = $script:SendText } {
                & ([scriptblock]::Create($Send)) $Cred $Shape 'off'
            }
            $Run.Count | Should -Be 1
            (@($Run.Sent.PSObject.Properties.Name | Sort-Object) -join ', ') | Should -BeExactly $Keys
            $Run.Sent.PSObject.Properties['mail_settings'] | Should -BeNullOrEmpty
            @($Run.Sent.personalizations).Count | Should -Be $Personalizations
        }

        It 'Sends no mail_settings with -SandboxMode:$false, <Shape>' -ForEach $script:Shapes {
            $Run = InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Shape = $Shape; Send = $script:SendText } {
                & ([scriptblock]::Create($Send)) $Cred $Shape 'explicit-false'
            }
            $Run.Count | Should -Be 1
            (@($Run.Sent.PSObject.Properties.Name | Sort-Object) -join ', ') | Should -BeExactly $Keys
            $Run.Sent.PSObject.Properties['mail_settings'] | Should -BeNullOrEmpty
        }

        It 'Sends mail_settings.sandbox_mode.enable true with -SandboxMode and changes nothing else, <Shape>' -ForEach $script:Shapes {
            $Runs = InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Shape = $Shape; Send = $script:SendText } {
                $Block = [scriptblock]::Create($Send)
                [pscustomobject]@{
                    Off = & $Block $Cred $Shape 'off'
                    On  = & $Block $Cred $Shape 'on'
                }
            }
            $Runs.On.Count | Should -Be 1
            $Sent = $Runs.On.Sent
            (@($Sent.PSObject.Properties.Name | Sort-Object) -join ', ') | Should -BeExactly ((@($Keys -split ', ') + 'mail_settings' | Sort-Object) -join ', ')
            @($Sent.mail_settings.PSObject.Properties.Name) | Should -BeExactly @('sandbox_mode')
            @($Sent.mail_settings.sandbox_mode.PSObject.Properties.Name) | Should -BeExactly @('enable')
            $Sent.mail_settings.sandbox_mode.enable | Should -BeOfType [bool]
            $Sent.mail_settings.sandbox_mode.enable | Should -BeTrue

            $Runs.Off.Count | Should -Be 1
            foreach ($Name in $Runs.Off.Sent.PSObject.Properties.Name) {
                if ($Name -eq 'send_at') {
                    $Sent.PSObject.Properties[$Name] | Should -Not -BeNullOrEmpty
                }
                else {
                    (ConvertTo-Json -InputObject $Sent.$Name -Depth 6 -Compress) | Should -BeExactly (ConvertTo-Json -InputObject $Runs.Off.Sent.$Name -Depth 6 -Compress) -Because "key $Name must be unchanged"
                }
            }
        }
    }

    Context 'ShouldProcess target under -WhatIf' {
        BeforeDiscovery {
            $script:Targets = @(
                @{ Name = 'Default minimal'; Recipients = "-To 'one@example.com'"; Expected = 'sender@example.com to "1" recipients with subject: "placeholder subject"' }
                @{ Name = 'Default with CC and BCC'; Recipients = "-To 'one@example.com' -CC 'copy@example.com' -BCC 'blind@example.com'"; Expected = 'sender@example.com to "3" recipients with subject: "placeholder subject"' }
                @{ Name = 'SeparateTo with two recipients'; Recipients = "-To 'one@example.com', 'two@example.com' -SeparateTo"; Expected = 'sender@example.com to "2" recipients with subject: "placeholder subject"' }
            )
        }

        It 'Names the target <Expected> <Suffix> for <Name>' -ForEach @(
            foreach ($T in $script:Targets) {
                @{ Name = $T.Name; Recipients = $T.Recipients; Expected = $T.Expected; Switch = ''; Suffix = ''; Tail = '' }
                @{ Name = $T.Name; Recipients = $T.Recipients; Expected = $T.Expected; Switch = '-SandboxMode'; Suffix = 'with -SandboxMode'; Tail = ' in sandbox mode' }
                @{ Name = $T.Name; Recipients = $T.Recipients; Expected = $T.Expected; Switch = '-SandboxMode:$false'; Suffix = 'with -SandboxMode:$false'; Tail = '' }
            }
        ) {
            $Script = "try { Send-SGMailMessage -From 'sender@example.com' $Recipients -Subject 'placeholder subject' -Body 'placeholder body' $Switch -WhatIf } catch { 'threw {0}' -f `$_.Exception.GetType().FullName }"
            $Run = Invoke-SgtInCountingHost -Script $Script
            $WhatIf = @($Run.HostLine | Where-Object { $_ -like 'What if:*' })
            $WhatIf.Count | Should -Be 1
            $WhatIf[0] -match 'on target "(.*)"\.?\s*$' | Should -BeTrue
            $Matches[1] | Should -BeExactly ($Expected + $Tail)
            $Run.PromptCount | Should -Be 0
            $Run.NetworkCallCount | Should -Be 0
            $Run.UnmockedCall | Should -BeNullOrEmpty
            $Run.Threw | Should -BeFalse
            @($Run.Output | Where-Object { $_ -like 'threw *' }) | Should -BeNullOrEmpty
        }
    }

    Context 'Parameter metadata' {
        It 'Declares SandboxMode as an optional, unpositioned switch in Default and SeparateTo only' {
            $Parameter = (Get-Command -Name Send-SGMailMessage).Parameters['SandboxMode']
            $Parameter | Should -Not -BeNullOrEmpty
            $Parameter.ParameterType | Should -Be ([System.Management.Automation.SwitchParameter])
            $Sets = @($Parameter.ParameterSets.Keys | Sort-Object)
            $Sets | Should -BeExactly @('Default', 'SeparateTo')
            foreach ($Set in $Sets) {
                $Parameter.ParameterSets[$Set].IsMandatory | Should -BeFalse
                $Parameter.ParameterSets[$Set].Position | Should -Be ([int]::MinValue)
            }
        }

        It 'Keeps the positions of the existing parameters' {
            $Expected = [ordered]@{ From = 0; To = 1; CC = 2; BCC = 3; Subject = 4; Body = 5; BodyAsHtml = 6; Attachment = 7 }
            $Parameters = (Get-Command -Name Send-SGMailMessage).Parameters
            foreach ($Name in $Expected.Keys) {
                $Parameters[$Name].ParameterSets['Default'].Position | Should -Be $Expected[$Name] -Because "$Name keeps its position"
            }
        }
    }
}

Describe 'Send-SGMailMessage -BatchId and -Unsubscribe (D102)' {
    BeforeAll {
        # Runs one send in module scope. $Extra is the text of a scriptblock that returns a hashtable of extra
        # parameters, so [SGASM] is built inside the module. Returns the count, the parsed body and the raw body.
        $script:SendText = {
            param($Cred, $Shape, $Extra)
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Reset-SgtNetworkStub
            Set-SgtNetworkStub -Response ([pscustomobject]@{ placeholder = 'accepted' })
            $Params = @{
                From    = 'sender@example.com'
                To      = 'one@example.com'
                Subject = 'placeholder subject'
                Body    = 'placeholder body'
            }
            if ($Shape -like 'SeparateTo*') {
                $Params['To'] = @('one@example.com', 'two@example.com')
                $Params['SeparateTo'] = [switch]::new($true)
            }
            if ($Shape -like '*full') {
                if ($Shape -like 'Default*') {
                    $Params['CC'] = 'copy@example.com'
                    $Params['BCC'] = 'blind@example.com'
                }
                $Params['BodyAsHtml'] = [switch]::new($true)
                $Params['Attachment'] = [System.Net.Mail.Attachment]::new([System.IO.MemoryStream]::new([byte[]](104, 105)), 'note.txt', 'text/plain')
                $Params['Priority'] = 'High'
                $Params['ReplyTo'] = 'reply@example.com'
                $Params['SendAt'] = (Get-Date).AddHours(1)
                $Params['TemplateId'] = 'd-placeholder'
                $Params['Categories'] = 'sgt-cat'
            }
            foreach ($Entry in (& ([scriptblock]::Create($Extra))).GetEnumerator()) { $Params[$Entry.Key] = $Entry.Value }
            $Threw = $null
            try { $null = Send-SGMailMessage @Params -Confirm:$false -ErrorAction Stop }
            catch { $Threw = $_.Exception.Message }
            $Calls = @(Get-SgtNetworkCall | ForEach-Object { $_ })
            [pscustomobject]@{
                Count = $Calls.Count
                Raw   = if ($Calls.Count) { $Calls[0].Body } else { $null }
                Sent  = if ($Calls.Count) { $Calls[0].Body | ConvertFrom-Json } else { $null }
                Threw = $Threw
            }
        }.ToString()
        $script:Cases = @{
            Both = '@{ BatchId = ''sgt-made-up-batch''; Unsubscribe = & { $A = [SGASM]::new(7); $A.GroupsToDisplay = 7, 8; $A } }'
        }
    }

    BeforeDiscovery {
        $script:Shapes = @(
            @{ Shape = 'Default minimal'; Keys = 'content, from, personalizations' }
            @{ Shape = 'Default full'; Keys = 'attachments, categories, content, from, personalizations, priority, reply_to, send_at, template_id' }
            @{ Shape = 'SeparateTo minimal'; Keys = 'content, from, personalizations' }
            @{ Shape = 'SeparateTo full'; Keys = 'attachments, categories, content, from, personalizations, priority, reply_to, send_at, template_id' }
        )
    }

    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Sends -BatchId as batch_id and nothing else new, <Shape>' -ForEach $script:Shapes {
        $Run = InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Shape = $Shape; Send = $script:SendText } {
            & ([scriptblock]::Create($Send)) $Cred $Shape '@{ BatchId = ''sgt-made-up-batch'' }'
        }
        $Run.Count | Should -Be 1
        (@($Run.Sent.PSObject.Properties.Name | Sort-Object) -join ', ') | Should -BeExactly ((@($Keys -split ', ') + 'batch_id' | Sort-Object) -join ', ')
        $Run.Sent.batch_id | Should -BeExactly 'sgt-made-up-batch'
    }

    It 'Sends -Unsubscribe as asm with group_id and groups_to_display, <Shape>' -ForEach $script:Shapes {
        $Run = InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Shape = $Shape; Send = $script:SendText } {
            & ([scriptblock]::Create($Send)) $Cred $Shape '@{ Unsubscribe = & { $A = [SGASM]::new(7); $A.GroupsToDisplay = 7, 8; $A } }'
        }
        $Run.Count | Should -Be 1
        (@($Run.Sent.PSObject.Properties.Name | Sort-Object) -join ', ') | Should -BeExactly ((@($Keys -split ', ') + 'asm' | Sort-Object) -join ', ')
        (@($Run.Sent.asm.PSObject.Properties.Name | Sort-Object) -join ', ') | Should -BeExactly 'group_id, groups_to_display'
        $Run.Sent.asm.group_id | Should -Not -BeOfType [string]
        $Run.Sent.asm.group_id | Should -Be 7
        $Run.Raw | Should -Match '"group_id":\s*7[,\s}]'
        @($Run.Sent.asm.groups_to_display) | Should -Be @(7, 8)
    }

    It 'Sends one display group as a JSON array' {
        $Run = InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Send = $script:SendText } {
            & ([scriptblock]::Create($Send)) $Cred 'Default minimal' '@{ Unsubscribe = & { $A = [SGASM]::new(7); $A.GroupsToDisplay = 7; $A } }'
        }
        $Run.Count | Should -Be 1
        $Run.Raw | Should -Match '"groups_to_display":\s*\['
    }

    It 'Leaves out an empty groups_to_display' {
        $Run = InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Send = $script:SendText } {
            & ([scriptblock]::Create($Send)) $Cred 'Default minimal' '@{ Unsubscribe = [SGASM]::new(1) }'
        }
        $Run.Count | Should -Be 1
        @($Run.Sent.asm.PSObject.Properties.Name) | Should -BeExactly @('group_id')
        $Run.Sent.asm.group_id | Should -Be 1
    }

    It 'Refuses GroupId <Id> with a plain message and no request' -ForEach @(
        @{ Id = 0; Make = '[SGASM]::new()' }
        @{ Id = -5; Make = '[SGASM]::new(-5)' }
    ) {
        $Run = InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Make = $Make; Send = $script:SendText } {
            & ([scriptblock]::Create($Send)) $Cred 'Default minimal' ('@{{ Unsubscribe = {0} }}' -f $Make)
        }
        $Run.Threw | Should -BeExactly 'Unsubscribe needs a GroupId greater than 0.'
        $Run.Count | Should -Be 0
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }

    It 'Adds categories, batch_id, asm and mail_settings in that order in the source' {
        $Command = Get-Command -Name Send-SGMailMessage
        $Ast = $Command.ScriptBlock.Ast
        $Calls = $Ast.FindAll({
                param($Node)
                $Node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
                $Node.Member.Value -eq 'Add' -and
                $Node.Expression.Extent.Text -eq '$ContentBody' -and
                $Node.Arguments[0] -is [System.Management.Automation.Language.StringConstantExpressionAst]
            }, $true)
        $Names = @($Calls | ForEach-Object { $_.Arguments[0].Value })
        $Wanted = @($Names | Where-Object { $_ -in 'categories', 'batch_id', 'asm', 'mail_settings' })
        $Wanted | Should -BeExactly @('categories', 'batch_id', 'asm', 'mail_settings')
    }

    It 'Changes no other key when -BatchId and -Unsubscribe are added, <Shape>' -ForEach $script:Shapes {
        $Runs = InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Shape = $Shape; Send = $script:SendText; Both = $script:Cases.Both } {
            $Block = [scriptblock]::Create($Send)
            [pscustomobject]@{
                Off = & $Block $Cred $Shape '@{}'
                On  = & $Block $Cred $Shape $Both
            }
        }
        (@($Runs.Off.Sent.PSObject.Properties.Name | Sort-Object) -join ', ') | Should -BeExactly $Keys
        foreach ($Name in $Runs.Off.Sent.PSObject.Properties.Name) {
            if ($Name -eq 'send_at') {
                $Runs.On.Sent.PSObject.Properties[$Name] | Should -Not -BeNullOrEmpty
            }
            else {
                (ConvertTo-Json -InputObject $Runs.On.Sent.$Name -Depth 6 -Compress) | Should -BeExactly (ConvertTo-Json -InputObject $Runs.Off.Sent.$Name -Depth 6 -Compress) -Because "key $Name must be unchanged"
            }
        }
    }

    It 'Sends batch_id, asm and mail_settings together with -SandboxMode' {
        $Run = InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Send = $script:SendText } {
            & ([scriptblock]::Create($Send)) $Cred 'Default minimal' '@{ SandboxMode = [switch]::new($true); BatchId = ''sgt-made-up-batch''; Unsubscribe = [SGASM]::new(3) }'
        }
        $Run.Count | Should -Be 1
        (@($Run.Sent.PSObject.Properties.Name | Sort-Object) -join ', ') | Should -BeExactly 'asm, batch_id, content, from, mail_settings, personalizations'
        $Run.Sent.mail_settings.sandbox_mode.enable | Should -BeTrue
    }

    It 'Makes no request and asks nothing under -WhatIf with -BatchId and -Unsubscribe' {
        $Script = "try { Send-SGMailMessage -From 'sender@example.com' -To 'one@example.com' -Subject 'placeholder subject' -Body 'placeholder body' -BatchId 'sgt-made-up-batch' -Unsubscribe ([SGASM]::new(3)) -WhatIf } catch { 'threw {0}' -f `$_.Exception.GetType().FullName }"
        $Run = Invoke-SgtInCountingHost -Script $Script -AnswerJson '{}'
        @($Run.HostLine | Where-Object { $_ -like 'What if:*' }).Count | Should -Be 1
        $Run.NetworkCallCount | Should -Be 0
        $Run.PromptCount | Should -Be 0
        $Run.UnmockedCall | Should -BeNullOrEmpty
        $Run.Threw | Should -BeFalse
        @($Run.Output | Where-Object { $_ -like 'threw *' }) | Should -BeNullOrEmpty
    }

    It 'Refuses a GroupId of 0 under -WhatIf with the plain message, no What if line and no request' {
        $Script = "try { Send-SGMailMessage -From 'sender@example.com' -To 'one@example.com' -Subject 'placeholder subject' -Body 'placeholder body' -Unsubscribe ([SGASM]::new()) -WhatIf } catch { 'threw {0}' -f `$_.Exception.Message }"
        $Run = Invoke-SgtInCountingHost -Script $Script -AnswerJson '{}'
        @($Run.HostLine | Where-Object { $_ -like 'What if:*' }).Count | Should -Be 0
        $Run.NetworkCallCount | Should -Be 0
        $Run.PromptCount | Should -Be 0
        $Run.UnmockedCall | Should -BeNullOrEmpty
        @($Run.Output | Where-Object { $_ -like 'threw *' }) | Should -BeExactly @('threw Unsubscribe needs a GroupId greater than 0.')
    }
}

Describe 'Send-SGMailMessage -Categories (D103)' {
    BeforeAll {
        # Runs one send in module scope with the category names built from $Names (the text of an expression).
        # Returns the request count, the parsed body, the exception type and whether it was a binding exception.
        $script:SendCategories = {
            param($Cred, $Names)
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Reset-SgtNetworkStub
            Set-SgtNetworkStub -Response ([pscustomobject]@{ placeholder = 'accepted' })
            $Params = @{
                From       = 'sender@example.com'
                To         = 'one@example.com'
                Subject    = 'placeholder subject'
                Body       = 'placeholder body'
                # @() keeps an empty result an empty array; without it an empty list would bind as $null.
                Categories = [string[]]@(& ([scriptblock]::Create($Names)))
            }
            $Threw = $null
            try { $null = Send-SGMailMessage @Params -Confirm:$false -ErrorAction Stop }
            catch { $Threw = $_.Exception }
            $Calls = @(Get-SgtNetworkCall | ForEach-Object { $_ })
            [pscustomobject]@{
                Count     = $Calls.Count
                Sent      = if ($Calls.Count) { $Calls[0].Body | ConvertFrom-Json } else { $null }
                ThrewType = if ($Threw) { $Threw.GetType().Name } else { $null }
                IsBinding = ($Threw -is [System.Management.Automation.ParameterBindingException])
            }
        }.ToString()
    }

    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Sends <Label> exactly' -ForEach @(
        @{ Label = '1 name'; Names = '''one-name'''; Expected = @('one-name') }
        @{ Label = '10 names'; Names = '1..10 | ForEach-Object { "sgt-cat-$_" }'; Expected = @(1..10 | ForEach-Object { "sgt-cat-$_" }) }
        @{ Label = 'a name of 1 character'; Names = '''a'''; Expected = @('a') }
        @{ Label = 'a name of 255 characters'; Names = '''b'' * 255'; Expected = @('b' * 255) }
        @{ Label = 'a name of 11 characters'; Names = '''abcdefghijk'''; Expected = @('abcdefghijk') }
    ) {
        $Run = InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Names = $Names; Send = $script:SendCategories } {
            & ([scriptblock]::Create($Send)) $Cred $Names
        }
        $Run.Count | Should -Be 1
        @($Run.Sent.categories).Count | Should -Be $Expected.Count
        @($Run.Sent.categories) | Should -BeExactly $Expected
    }

    It 'Refuses <Label> at binding and sends no request' -ForEach @(
        @{ Label = '11 names'; Names = '1..11 | ForEach-Object { "sgt-cat-$_" }' }
        @{ Label = 'a name of 256 characters'; Names = '''c'' * 256' }
        @{ Label = 'an empty name'; Names = '''''' }
        @{ Label = 'an empty list'; Names = '@()' }
    ) {
        $Run = InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Names = $Names; Send = $script:SendCategories } {
            & ([scriptblock]::Create($Send)) $Cred $Names
        }
        $Run.IsBinding | Should -BeTrue
        $Run.ThrewType | Should -BeExactly 'ParameterBindingValidationException'
        $Run.Count | Should -Be 0
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }

    It 'Says 10 and 255 in the help of -Categories' {
        $Text = (Get-Help -Name Send-SGMailMessage -Parameter Categories | Out-String)
        $Text | Should -Match '\b10\b'
        $Text | Should -Match '\b255\b'
    }
}

Describe 'Send-SGMailMessage help for -Unsubscribe (D104)' {
    BeforeAll {
        $script:Squash = { param([string]$Text) ($Text -replace '\s+', ' ').Trim() }
        $script:ParamHelp = & $script:Squash ((Get-Help -Name Send-SGMailMessage -Parameter Unsubscribe | Out-String))
        $script:Definition = & $script:Squash ((Get-Command -Name Send-SGMailMessage).Definition)
        $script:FullHelp = & $script:Squash ((Get-Help -Name Send-SGMailMessage -Full | Out-String))
    }

    It 'says in the parameter help that GroupId must be greater than 0' {
        $script:ParamHelp | Should -Match 'greater than 0'
    }

    It 'shows in the parameter help how to set GroupsToDisplay as a property' {
        $script:ParamHelp.Contains('$Unsubscribe.GroupsToDisplay = 123, 124') | Should -BeTrue
    }

    It 'has the property example in the parameter comment block and not the two-argument example' {
        $script:Definition.Contains('$Unsubscribe = [SGASM]::new(123); $Unsubscribe.GroupsToDisplay = 123, 124') | Should -BeTrue
        $script:Definition.Contains('[SGASM]::new(123, @(1, 2, 3))') | Should -BeFalse
    }

    It 'says in the definition that GroupId must be greater than 0 when the message is sent' {
        $script:Definition.Contains('It must be greater than 0 when the message is sent.') | Should -BeTrue
    }

    It 'says the second constructor argument is not kept' {
        $script:Definition.Contains('The second argument is not kept today; set GroupsToDisplay as a property.') | Should -BeTrue
    }

    It 'names no backlog id in the help or the definition' {
        $script:FullHelp | Should -Not -Match 'SGT-\d'
        $script:FullHelp | Should -Not -Match 'BL-\d'
        $script:Definition | Should -Not -Match 'SGT-\d'
        $script:Definition | Should -Not -Match 'BL-\d'
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
