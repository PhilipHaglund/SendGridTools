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

Describe 'Set-SGForwardBounceSetting' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Supports ShouldProcess with the default Medium impact and exposes -WhatIf and -Confirm' {
        $Command = Get-Command -Name Set-SGForwardBounceSetting
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

            $null = Set-SGForwardBounceSetting -Email 'bounce@example.com' -Enabled -WhatIf

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

            $null = Set-SGForwardBounceSetting -Email 'bounce@example.com' -Enabled

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
        }
    }

    It 'Sends one Patch to mail_settings/forward_bounce with enabled and email' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ enabled = $true })

            $null = Set-SGForwardBounceSetting -Email 'bounce@example.com' -Enabled

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Patch'
            "$($Calls[0].Uri)" | Should -BeLike '*/mail_settings/forward_bounce'
            $Sent = $Calls[0].Body | ConvertFrom-Json
            @($Sent.PSObject.Properties.Name | Sort-Object) | Should -Be @('email', 'enabled')
            $Sent.email | Should -Be 'bounce@example.com'
            $Sent.enabled | Should -BeTrue
        }
    }

    It 'Sends an empty email when -Email is $null' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ enabled = $false })

            $null = Set-SGForwardBounceSetting -Email $null

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Sent = $Calls[0].Body | ConvertFrom-Json
            @($Sent.PSObject.Properties.Name | Sort-Object) | Should -Be @('email')
            $Sent.email | Should -Be ''
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
