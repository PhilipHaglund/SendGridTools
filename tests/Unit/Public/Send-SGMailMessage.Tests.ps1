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
                    ($Sent.$Name | ConvertTo-Json -Depth 6 -Compress) | Should -BeExactly ($Runs.Off.Sent.$Name | ConvertTo-Json -Depth 6 -Compress) -Because "key $Name must be unchanged"
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

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
