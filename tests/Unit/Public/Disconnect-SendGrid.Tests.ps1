# The error path of Disconnect-SendGrid is covered in CommandErrorPath.Tests.ps1.
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

Describe 'Disconnect-SendGrid' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Removes the session variable and makes no call' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{})

            Disconnect-SendGrid -Confirm:$false

            Test-Path -Path 'Variable:\script:Session' | Should -BeFalse
            Get-SgtNetworkCall | Should -BeNullOrEmpty
        }
    }

    It 'Keeps the session and its connected state under WhatIf' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{})

            Disconnect-SendGrid -WhatIf

            Test-Path -Path 'Variable:\script:Session' | Should -BeTrue
            $script:Session.GetType().Name | Should -BeExactly 'SendGridSession'
            $script:Session._Connected | Should -BeTrue
            Get-SgtNetworkCall | Should -BeNullOrEmpty
        }
    }

    It 'Warns once and raises no error without a session' {
        InModuleScope SendGridTools {
            Remove-Variable -Name Session -Scope Script -ErrorAction SilentlyContinue
            Set-SgtNetworkStub -Response ([pscustomobject]@{})

            Disconnect-SendGrid -Confirm:$false -WarningVariable Warned -ErrorVariable Failed -WarningAction SilentlyContinue -ErrorAction SilentlyContinue

            @($Warned).Count | Should -Be 1
            "$($Warned[0])" | Should -BeExactly 'No active SendGrid session was found.'
            @($Failed).Count | Should -Be 0
            Get-SgtNetworkCall | Should -BeNullOrEmpty
        }
    }

    It 'Resolves the alias Disconnect-SG to the command' {
        (Get-Command -Name 'Disconnect-SG').ResolvedCommand.Name | Should -BeExactly 'Disconnect-SendGrid'
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
