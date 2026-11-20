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

Describe 'Set-SGApiKey -Scopes' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Shows its syntax without throwing and names Scopes' {
        { Get-Command -Name Set-SGApiKey -Syntax } | Should -Not -Throw
        (Get-Command -Name Set-SGApiKey -Syntax) | Should -Match 'Scopes'
    }

    It 'Has an ArgumentCompleter and no ValidateSet on Scopes' {
        $Attributes = (Get-Command -Name Set-SGApiKey).Parameters['Scopes'].Attributes
        @($Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count | Should -Be 0
        @($Attributes | Where-Object { $_ -is [System.Management.Automation.ArgumentCompleterAttribute] }).Count | Should -Be 1
    }

    It 'Sends one Put to api_keys/<id> with the given scopes and the current name' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            Mock Get-SGApiKey { [pscustomobject]@{ Name = 'placeholder-name'; Scopes = @('alerts.read') } }
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ name = 'placeholder-name' })

            $null = Set-SGApiKey -UniqueId 'placeholder-id' -Scopes 'mail.send' -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Put'
            "$($Calls[0].Uri)" | Should -BeLike '*/api_keys/placeholder-id'
            $Sent = $Calls[0].Body | ConvertFrom-Json
            @($Sent.scopes) | Should -Be @('mail.send')
            $Sent.name | Should -Be 'placeholder-name'
        }
    }

    It 'Sends a scope that is not a known scope as given, without local validation' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            Mock Get-SGApiKey { [pscustomobject]@{ Name = 'placeholder-name'; Scopes = @('alerts.read') } }
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ name = 'placeholder-name' })

            [SendGridScopes]::ValidScopes() | Should -Not -Contain 'placeholder.future.scope'
            $null = Set-SGApiKey -UniqueId 'placeholder-id' -Scopes 'placeholder.future.scope' -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Sent = $Calls[0].Body | ConvertFrom-Json
            @($Sent.scopes) | Should -Be @('placeholder.future.scope')
        }
    }

    It 'Keeps the current scopes without -Scopes and uses -NewName for the name' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            Mock Get-SGApiKey { [pscustomobject]@{ Name = 'placeholder-name'; Scopes = @('alerts.read') } }
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ name = 'placeholder-new-name' })

            $null = Set-SGApiKey -UniqueId 'placeholder-id' -NewName 'placeholder-new-name' -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Sent = $Calls[0].Body | ConvertFrom-Json
            @($Sent.scopes) | Should -Be @('alerts.read')
            $Sent.name | Should -Be 'placeholder-new-name'
        }
    }

    It 'Makes no call with -WhatIf' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            Mock Get-SGApiKey { [pscustomobject]@{ Name = 'placeholder-name'; Scopes = @('alerts.read') } }
            Mock Invoke-SendGrid { }
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ name = 'placeholder-name' })

            $null = Set-SGApiKey -UniqueId 'placeholder-id' -Scopes 'mail.send' -WhatIf

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 0
            Should -Invoke Invoke-SendGrid -Times 0 -Exactly
        }
    }

    It 'Completes scopes from ValidScopes' {
        $Completer = (Get-Command -Name Set-SGApiKey).Parameters['Scopes'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ArgumentCompleterAttribute] }
        $Valid = InModuleScope SendGridTools { , @([SendGridScopes]::ValidScopes()) }
        $Partial = @(& $Completer.ScriptBlock 'Set-SGApiKey' 'Scopes' 'mail.' $null @{})
        $Partial.Count | Should -BeGreaterThan 0
        $Partial | Should -Be @($Valid | Where-Object { $_ -like 'mail.*' })
        $All = @(& $Completer.ScriptBlock 'Set-SGApiKey' 'Scopes' '' $null @{})
        $All | Should -Be @($Valid)
    }
}

Describe 'Set-SGApiKey ids from the pipeline' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Sends the request to the right path for <Name> from the pipeline' -ForEach @(
        @{ Name = 'a long'; Ids = @([long]1001); TypeName = 'System.Int64' }
        @{ Name = 'an integer'; Ids = @([int]1001); TypeName = 'System.Int32' }
        @{ Name = 'a string'; Ids = @('1001'); TypeName = 'System.String' }
        @{ Name = 'an object with an Id property'; Ids = @([pscustomobject]@{ Id = 1001 }); TypeName = 'System.Management.Automation.PSCustomObject' }
    ) {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Ids = $Ids; TypeName = $TypeName } {
            Mock Get-SGApiKey { [pscustomobject]@{ Name = 'placeholder-name'; Scopes = @('alerts.read') } }
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            # Guard: the value that is piped really has the intended type (an int must not stand in for a long).
            @($Ids).Count | Should -Be 1
            @($Ids)[0].GetType().FullName | Should -Be $TypeName

            $null = $Ids | Set-SGApiKey -Scopes 'mail.send' -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Put'
            "$($Calls[0].Uri)" | Should -BeLike '*/api_keys/1001'
        }
    }

    It 'Fails with a conversion error and sends nothing for a double from the pipeline' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            Mock Get-SGApiKey { [pscustomobject]@{ Name = 'placeholder-name'; Scopes = @('alerts.read') } }
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })
            $Ids = @([double]1001.5)
            @($Ids)[0].GetType().FullName | Should -Be 'System.Double'

            { $Ids | Set-SGApiKey -Scopes 'mail.send' -Confirm:$false } | Should -Throw '*Failed to convert InputObject to Id.*'

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 0
        }
    }
}

Describe 'Set-SGApiKey verbose output (D21)' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Names the current key in the verbose line' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            Mock Get-SGApiKey { [pscustomobject]@{ Name = 'placeholder-name'; Scopes = @('alerts.read') } }
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ name = 'placeholder-name' })

            $Records = Set-SGApiKey -UniqueId 'placeholder-id' -Scopes 'mail.send' -Confirm:$false -Verbose 4>&1
            $Messages = @($Records | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $_.Message })

            $Messages | Should -Contain 'Updating key placeholder-name'
        }
    }

    It 'Reads the key before it asks, as before' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            Mock Get-SGApiKey { [pscustomobject]@{ Name = 'placeholder-name'; Scopes = @('alerts.read') } }
            Mock Invoke-SendGrid { }
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0

            $null = Set-SGApiKey -UniqueId 'placeholder-id' -Scopes 'mail.send' -WhatIf

            Should -Invoke Get-SGApiKey -Times 1 -Exactly
            Should -Invoke Invoke-SendGrid -Times 0 -Exactly
        }
    }
}

Describe 'Set-SGApiKey asks once (D50)' {
    BeforeAll {
        $script:Answer = '{"api_key_id":"placeholder-id","name":"placeholder-name","scopes":["alerts.read"]}'
    }

    It 'Asks one question with -Confirm' {
        $Run = Invoke-SgtInCountingHost -Script '$null = Set-SGApiKey -UniqueId ''placeholder-id'' -Scopes ''mail.send'' -Confirm' -AnswerJson $script:Answer

        $Run.PromptCount | Should -Be 1
        $Run.NetworkCallCount | Should -Be 2
        $Run.Threw | Should -BeFalse
        $Run.UnmockedCall | Should -BeNullOrEmpty
    }

    It 'Names the object in one What if line with -WhatIf' {
        $Run = Invoke-SgtInCountingHost -Script '$null = Set-SGApiKey -UniqueId ''placeholder-id'' -Scopes ''mail.send'' -WhatIf' -AnswerJson $script:Answer

        $WhatIf = @($Run.HostLine | Where-Object { $_ -like 'What if:*' })
        $WhatIf.Count | Should -Be 1
        $WhatIf[0] | Should -BeLike '*placeholder-id*'
        @($Run.HostLine | Where-Object { $_ -like '*Get-SG*' }) | Should -BeNullOrEmpty
        $Run.NetworkCallCount | Should -Be 1
        $Run.PromptCount | Should -Be 0
        $Run.Threw | Should -BeFalse
        $Run.UnmockedCall | Should -BeNullOrEmpty
    }
}

Describe 'Set-SGApiKey encodes the id in the path (D153)' {
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
            $null = Set-SGApiKey -UniqueId $Id -NewName 'sgt-new-name' -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -BeGreaterThan 0
            foreach ($Call in $Calls) {
                $Call.Uri.OriginalString | Should -BeLike "https://api.sendgrid.com/v3/api_keys/$Segment*"
                $Call.Uri.OriginalString | Should -Not -BeLike '*/a/b*'
                $Call.Uri.OriginalString | Should -Not -Match '[?#]'
            }
            $Calls[-1].Method | Should -Be 'Put'
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
