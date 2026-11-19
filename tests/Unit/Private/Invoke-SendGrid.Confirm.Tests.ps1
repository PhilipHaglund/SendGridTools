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

Describe 'Invoke-SendGrid never asks (D20)' {
    It 'Does not ask when the caller has ConfirmPreference <Level>' -ForEach @(
        @{ Level = 'Low' }
        @{ Level = 'Medium' }
    ) {
        $Script = ('$ConfirmPreference = ''{0}''; Invoke-SendGrid -Method Get -Namespace ''things''' -f $Level)

        $Result = Invoke-SgtInCountingHost -Script $Script

        $Result.PromptCount | Should -Be 0
        $Result.ThrownMessage | Should -BeExactly 'You must call the Connect-SendGrid cmdlet before calling any other cmdlets.'
        $Result.UnmockedCall | Should -BeNullOrEmpty
    }

    It '<Command> -Confirm asks once, with its own question' -ForEach @(
        @{ Command = 'Remove-SGGlobalSuppression'; Target = 'Remove email address one@example.com from global suppressions list.' }
        @{ Command = 'Add-SGGlobalSuppression'; Target = 'Add email address one@example.com to the global suppressions list.' }
    ) {
        $Result = Invoke-SgtInCountingHost -Script ("$Command -EmailAddress 'one@example.com' -Confirm")

        $Result.PromptCount | Should -Be 1
        $Result.Prompt[0] | Should -BeLike "*$Target*"
        $Result.Threw | Should -BeTrue
        $Result.ThrownMessage | Should -BeLike '*You must call the Connect-SendGrid cmdlet*'
        $Result.UnmockedCall | Should -BeNullOrEmpty
    }

    It 'Still stops under WhatIf (<Name>)' -ForEach @(
        @{ Name = 'preference'; Script = '$WhatIfPreference = $true; Invoke-SendGrid -Method Get -Namespace ''things''' }
        @{ Name = 'switch'; Script = 'Invoke-SendGrid -Method Delete -Namespace ''things'' -WhatIf' }
    ) {
        $Result = Invoke-SgtInCountingHost -Script $Script

        $Result.PromptCount | Should -Be 0
        $Result.Threw | Should -BeFalse
        $Result.HostLine.Count | Should -Be 1
        $Result.HostLine[0] | Should -BeLike '*: things*'
        $Result.NetworkCallCount | Should -Be 0
    }
}

Describe '-WhatIf on a writing command makes no writing call (D20)' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It '<Command> -WhatIf sends nothing' -ForEach @(
        @{ Command = 'Add-SGGlobalSuppression' }
        @{ Command = 'Remove-SGGlobalSuppression' }
        @{ Command = 'Remove-SGBounce' }
    ) {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Command = $Command } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = & $Command -EmailAddress 'one@example.com' -WhatIf

            (Get-SgtNetworkCall).Count | Should -Be 0
        }
    }

    It 'Set-SGApiKey -WhatIf sends only the read it does first (D50)' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = Set-SGApiKey -UniqueId 'placeholder-id' -Scopes 'mail.send' -WhatIf

            $Calls = @(Get-SgtNetworkCall)
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Get'
            @($Calls | Where-Object { $_.Method -eq 'Put' }).Count | Should -Be 0
        }
    }
}

Describe 'A request with an answer asks nothing more (D20)' {
    It 'Invoke-SendGrid does not ask while it reads an answer (ConfirmPreference <Level>)' -ForEach @(
        @{ Level = 'Low' }
        @{ Level = 'Medium' }
    ) {
        $Script = ('$ConfirmPreference = ''{0}''; $null = Invoke-SendGrid -Method Get -Namespace ''things''' -f $Level)

        $Result = Invoke-SgtInCountingHost -Script $Script -AnswerJson '{"first_name":"sgt-test-one","second_name":"sgt-test-two"}'

        $Result.PromptCount | Should -Be 0
        $Result.Threw | Should -BeFalse
        $Result.NetworkCallCount | Should -Be 1
        $Result.UnmockedCall | Should -BeNullOrEmpty
    }

    It '<Command> -Confirm asks once when the request gets an answer' -ForEach @(
        @{ Command = 'Add-SGGlobalSuppression'; Json = '{"recipient_emails":["one@example.com"]}'; Target = 'Add email address one@example.com to the global suppressions list.' }
        @{ Command = 'Remove-SGGlobalSuppression'; Json = '{"name":"sgt-test-name"}'; Target = 'Remove email address one@example.com from global suppressions list.' }
    ) {
        $Result = Invoke-SgtInCountingHost -Script ('$null = {0} -EmailAddress ''one@example.com'' -Confirm' -f $Command) -AnswerJson $Json

        $Result.PromptCount | Should -Be 1
        $Result.Prompt[0] | Should -BeLike "*$Target*"
        $Result.Threw | Should -BeFalse
        $Result.NetworkCallCount | Should -Be 1
        $Result.UnmockedCall | Should -BeNullOrEmpty
    }

    It 'Returns the answer with title-cased property names when it does not ask' {
        $Script = '$ConfirmPreference = ''Low''; (Invoke-SendGrid -Method Get -Namespace ''things'').PSObject.Properties.Name -join '','''

        $Result = Invoke-SgtInCountingHost -Script $Script -AnswerJson '{"first_name":"sgt-test-one","second_name":"sgt-test-two"}'

        $Result.Output | Should -Contain 'FirstName,SecondName'
        $Result.PromptCount | Should -Be 0
    }

    It 'Still sends nothing under -WhatIf with a session and an answer' {
        $Result = Invoke-SgtInCountingHost -Script '$null = Add-SGGlobalSuppression -EmailAddress ''one@example.com'' -WhatIf' -AnswerJson '{"recipient_emails":["one@example.com"]}'

        $Result.PromptCount | Should -Be 0
        $Result.NetworkCallCount | Should -Be 0
        $Result.HostLine.Count | Should -Be 1
        $Result.Threw | Should -BeFalse
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
