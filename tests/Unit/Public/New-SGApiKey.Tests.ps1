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

Describe 'New-SGApiKey with scopes' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Sends one Post to api_keys with the name and the scopes in order' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ name = 'placeholder-key' })

            $null = New-SGApiKey -Name 'placeholder-key' -Scope 'mail.send', 'alerts.read' -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Post'
            "$($Calls[0].Uri)" | Should -BeLike '*/api_keys'
            $Sent = $Calls[0].Body | ConvertFrom-Json
            @($Sent.PSObject.Properties.Name | Sort-Object) | Should -Be @('name', 'scopes')
            $Sent.name | Should -Be 'placeholder-key'
            @($Sent.scopes) | Should -Be @('mail.send', 'alerts.read')
        }
    }

    It 'Sets the on-behalf-of header with -OnBehalfOf' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ name = 'placeholder-key' })

            $null = New-SGApiKey -Name 'placeholder-key' -Scope 'mail.send' -OnBehalfOf 'subuser-placeholder' -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Headers['on-behalf-of'] | Should -Be 'subuser-placeholder'
        }
    }

    It 'Makes no call with -WhatIf' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ name = 'placeholder-key' })

            $null = New-SGApiKey -Name 'placeholder-key' -Scope 'mail.send' -WhatIf

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 0
        }
    }

    It 'Never asks the full-access question in the Scopes set' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ name = 'placeholder-key' })
            Mock Confirm-SendGridContinue -ModuleName SendGridTools -MockWith { throw 'Confirm-SendGridContinue must not be called' }

            $null = New-SGApiKey -Name 'placeholder-key' -Scope 'mail.send' -Confirm:$false
            $null = New-SGApiKey -Name 'placeholder-key' -Scope 'mail.send' -Force -Confirm:$false

            Should -Invoke Confirm-SendGridContinue -ModuleName SendGridTools -Times 0 -Exactly
            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 2
        }
    }

    It 'Completes scopes from ValidScopes' {
        $Completer = (Get-Command -Name New-SGApiKey).Parameters['Scope'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ArgumentCompleterAttribute] }
        $Valid = InModuleScope SendGridTools { , @([SendGridScopes]::ValidScopes()) }
        $Partial = @(& $Completer.ScriptBlock 'New-SGApiKey' 'Scope' 'mail.' $null @{})
        $Partial.Count | Should -BeGreaterThan 0
        $Partial | Should -Be @($Valid | Where-Object { $_ -like 'mail.*' })
        $All = @(& $Completer.ScriptBlock 'New-SGApiKey' 'Scope' '' $null @{})
        $All | Should -Be @($Valid)
    }
}

Describe 'New-SGApiKey -FullAccessKey and -Force' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Asks the full-access question once and sends one Post when the answer is yes' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ name = 'placeholder-key' })
            Mock Confirm-SendGridContinue -ModuleName SendGridTools -MockWith { $true }

            $null = New-SGApiKey -Name 'placeholder-key' -FullAccessKey -Confirm:$false

            Should -Invoke Confirm-SendGridContinue -ModuleName SendGridTools -Times 1 -Exactly -ParameterFilter {
                $Query -ceq 'You are about to create an API key (placeholder-key) with Full Access. Do you want to continue?' -and $Caption -ceq 'New-SGApiKey'
            }
            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Post'
            "$($Calls[0].Uri)" | Should -BeLike '*/api_keys'
            $Sent = $Calls[0].Body | ConvertFrom-Json
            @($Sent.PSObject.Properties.Name) | Should -Be @('name')
        }
    }

    It 'Asks once and sends nothing when the answer is no' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ name = 'placeholder-key' })
            Mock Confirm-SendGridContinue -ModuleName SendGridTools -MockWith { $false }

            $null = New-SGApiKey -Name 'placeholder-key' -FullAccessKey -Confirm:$false

            Should -Invoke Confirm-SendGridContinue -ModuleName SendGridTools -Times 1 -Exactly
            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 0
        }
    }

    It 'Asks nothing and sends nothing with -WhatIf' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ name = 'placeholder-key' })
            Mock Confirm-SendGridContinue -ModuleName SendGridTools -MockWith { throw 'Confirm-SendGridContinue must not be called' }

            $null = New-SGApiKey -Name 'placeholder-key' -FullAccessKey -WhatIf

            Should -Invoke Confirm-SendGridContinue -ModuleName SendGridTools -Times 0 -Exactly
            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 0
        }
    }

    It 'Skips the question and sends one Post with -Force' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ name = 'placeholder-key' })
            Mock Confirm-SendGridContinue -ModuleName SendGridTools -MockWith { throw 'Confirm-SendGridContinue must not be called' }

            $null = New-SGApiKey -Name 'placeholder-key' -FullAccessKey -Force -Confirm:$false

            Should -Invoke Confirm-SendGridContinue -ModuleName SendGridTools -Times 0 -Exactly
            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Post'
        }
    }

    It 'Has an example in its help that uses -Force' {
        $Text = [System.IO.File]::ReadAllText((Join-Path -Path $PSScriptRoot -ChildPath '../../../source/Public/New-SGApiKey.ps1'))
        $Help = [regex]::Match($Text, '<#[\s\S]*?#>').Value
        $Help | Should -Match '\.EXAMPLE\s+PS C:\\> [^\r\n]*-Force'
    }

    It 'Sends the same body with -Force as after the answer yes' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ name = 'placeholder-key' })
            Mock Confirm-SendGridContinue -ModuleName SendGridTools -MockWith { $true }
            $null = New-SGApiKey -Name 'placeholder-key' -FullAccessKey -Confirm:$false
            Should -Invoke Confirm-SendGridContinue -ModuleName SendGridTools -Times 1 -Exactly

            $null = New-SGApiKey -Name 'placeholder-key' -FullAccessKey -Force -Confirm:$false

            # The count stays at the one question of the first call: -Force asked nothing.
            Should -Invoke Confirm-SendGridContinue -ModuleName SendGridTools -Times 1 -Exactly
            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 2
            $Calls[1].Body | Should -Be $Calls[0].Body
        }
    }

    It 'Asks nothing and sends nothing with -Force -WhatIf' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ name = 'placeholder-key' })
            Mock Confirm-SendGridContinue -ModuleName SendGridTools -MockWith { throw 'Confirm-SendGridContinue must not be called' }

            $null = New-SGApiKey -Name 'placeholder-key' -FullAccessKey -Force -WhatIf

            Should -Invoke Confirm-SendGridContinue -ModuleName SendGridTools -Times 0 -Exactly
            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 0
        }
    }

    It 'Declares Force as a switch without a position in every parameter set' {
        $Parameter = (Get-Command -Name New-SGApiKey).Parameters['Force']

        $Parameter.ParameterType | Should -Be ([switch])
        $Parameter.ParameterSets.Keys | Should -Contain '__AllParameterSets'
        $ParameterAttributes = @($Parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] })
        $ParameterAttributes.Count | Should -BeGreaterThan 0
        foreach ($Attribute in $ParameterAttributes) {
            $Attribute.Position | Should -Be ([int]::MinValue)
        }
    }
}

Describe 'New-SGApiKey counts the questions in a console host' {
    BeforeAll {
        $script:Answer = '{"name":"placeholder-key"}'
    }

    It 'Asks nothing, calls nothing and names the key in one What if line with -FullAccessKey -WhatIf' {
        $Run = Invoke-SgtInCountingHost -Script '$null = New-SGApiKey -Name ''placeholder-key'' -FullAccessKey -WhatIf' -AnswerJson $script:Answer

        $WhatIf = @($Run.HostLine | Where-Object { $_ -like 'What if:*' })
        $WhatIf.Count | Should -Be 1
        $WhatIf[0] | Should -BeLike '*placeholder-key*'
        $Run.PromptCount | Should -Be 0
        $Run.NetworkCallCount | Should -Be 0
        $Run.Threw | Should -BeFalse
        $Run.UnmockedCall | Should -BeNullOrEmpty
    }

    It 'Counts the questions in a console host: <Switches> asks <Prompts>' -ForEach @(
        @{ Switches = '-FullAccessKey -Confirm'; Prompts = 2; Requests = 1 }
        @{ Switches = '-FullAccessKey'; Prompts = 1; Requests = 1 }
        @{ Switches = '-FullAccessKey -Force -Confirm'; Prompts = 1; Requests = 1 }
        @{ Switches = '-FullAccessKey -Force'; Prompts = 0; Requests = 1 }
    ) {
        $Run = Invoke-SgtInCountingHost -Script "`$null = New-SGApiKey -Name 'placeholder-key' $Switches" -AnswerJson $script:Answer

        $Run.PromptCount | Should -Be $Prompts
        $Run.NetworkCallCount | Should -Be $Requests
        $Run.UnmockedCall | Should -BeNullOrEmpty
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
