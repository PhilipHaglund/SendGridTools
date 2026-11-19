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

Describe '-WhatIf on a writing command makes no call (D20)' {
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

    It 'Set-SGApiKey -WhatIf sends nothing, also for the read it does first' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = Set-SGApiKey -UniqueId 'placeholder-id' -Scopes 'mail.send' -WhatIf

            (Get-SgtNetworkCall).Count | Should -Be 0
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
