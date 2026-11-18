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

Describe 'Set-SGBouncePurgeSetting' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Supports ShouldProcess with the default Medium impact and exposes -WhatIf and -Confirm' {
        $Command = Get-Command -Name Set-SGBouncePurgeSetting
        $Binding = $Command.ScriptBlock.Attributes | Where-Object { $_ -is [System.Management.Automation.CmdletBindingAttribute] }
        $Binding.SupportsShouldProcess | Should -BeTrue
        $Binding.ConfirmImpact | Should -Be 'Medium'
        $Command.Parameters.ContainsKey('WhatIf') | Should -BeTrue
        $Command.Parameters.ContainsKey('Confirm') | Should -BeTrue
    }

    It 'Makes no call with -WhatIf' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ enabled = $true })

            # ShouldProcess in the command itself, not only the one in Invoke-SendGrid, must stop the call.
            Mock Invoke-SendGrid { }

            $null = Set-SGBouncePurgeSetting -Enabled -SoftBounces 5 -HardBounces 10 -WhatIf

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 0
            Should -Invoke Invoke-SendGrid -Times 0 -Exactly
        }
    }

    It 'Makes the call without a prompt when ConfirmPreference is High and no switch is given' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $ConfirmPreference = 'High'
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ enabled = $true })

            $null = Set-SGBouncePurgeSetting -Enabled -SoftBounces 5 -HardBounces 10

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
        }
    }

    It 'Sends one Patch to mail_settings/bounce_purge with enabled, soft_bounces and hard_bounces' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ enabled = $true })

            $null = Set-SGBouncePurgeSetting -Enabled -SoftBounces 5 -HardBounces 10

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Patch'
            "$($Calls[0].Uri)" | Should -BeLike '*/mail_settings/bounce_purge'
            $Sent = $Calls[0].Body | ConvertFrom-Json
            @($Sent.PSObject.Properties.Name | Sort-Object) | Should -Be @('enabled', 'hard_bounces', 'soft_bounces')
            $Sent.enabled | Should -BeTrue
            $Sent.soft_bounces | Should -Be 5
            $Sent.hard_bounces | Should -Be 10
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
