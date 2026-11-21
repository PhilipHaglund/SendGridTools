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

Describe 'Set commands refuse an update without fields (D167)' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Refuses <Name> and sends no Patch' -ForEach @(
        @{
            Name = 'Set-SGSuppressionGroup with no field'
            Script = { Set-SGSuppressionGroup -UniqueId 1001 -Confirm:$false }
            Message = 'Nothing to update for suppression group 1001. Specify -Name, -Description or -IsDefault.'
        }
        @{
            Name = 'Set-SGSuppressionGroup with no field under WhatIf'
            Script = { Set-SGSuppressionGroup -UniqueId 1001 -WhatIf }
            Message = 'Nothing to update for suppression group 1001. Specify -Name, -Description or -IsDefault.'
        }
        @{
            Name = 'Set-SGSuppressionGroup with no field from the pipeline'
            Script = { 1001 | Set-SGSuppressionGroup -Confirm:$false }
            Message = 'Nothing to update for suppression group 1001. Specify -Name, -Description or -IsDefault.'
        }
        @{
            Name = 'Set-SGAuthenticatedDomain with no field'
            Script = { Set-SGAuthenticatedDomain -UniqueId 1001 -Confirm:$false }
            Message = 'Nothing to update for authenticated domain 1001. Specify -SetDefault or -SetCustomSPF.'
        }
        @{
            Name = 'Set-SGAuthenticatedDomain with both switches off'
            Script = { Set-SGAuthenticatedDomain -UniqueId 1001 -SetDefault:$false -SetCustomSPF:$false -Confirm:$false }
            Message = 'Nothing to update for authenticated domain 1001. Specify -SetDefault or -SetCustomSPF.'
        }
        @{
            Name = 'Set-SGAuthenticatedDomain with no field under WhatIf'
            Script = { Set-SGAuthenticatedDomain -UniqueId 1001 -WhatIf }
            Message = 'Nothing to update for authenticated domain 1001. Specify -SetDefault or -SetCustomSPF.'
        }
        @{
            Name = 'Set-SGBrandedDomainLink with no field'
            Script = { Set-SGBrandedDomainLink -UniqueId 1001 -Confirm:$false }
            Message = 'Nothing to update for branded domain link 1001. Specify -SetDefault.'
        }
        @{
            Name = 'Set-SGBrandedDomainLink with the switch off'
            Script = { Set-SGBrandedDomainLink -UniqueId 1001 -SetDefault:$false -Confirm:$false }
            Message = 'Nothing to update for branded domain link 1001. Specify -SetDefault.'
        }
        @{
            Name = 'Set-SGBrandedDomainLink with no field under WhatIf'
            Script = { Set-SGBrandedDomainLink -UniqueId 1001 -WhatIf }
            Message = 'Nothing to update for branded domain link 1001. Specify -SetDefault.'
        }
    ) {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Script = $Script; Message = $Message } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $Script | Should -Throw -ExpectedMessage $Message

            @(Get-SgtNetworkCall | ForEach-Object { $_ } | Where-Object { $_.Method -eq 'Patch' }).Count | Should -Be 0
        }
    }

    It 'Refuses Set-SGAlert on a <Type> without a field it uses, after one Get only' -ForEach @(
        @{
            Type = 'usage_alert'
            Frequency = 'Weekly'
            Percentage = $null
            Message = 'Nothing to update for alert 1001. Specify -Percentage or -EmailTo.'
        }
        @{
            Type = 'stats_notification'
            Frequency = $null
            Percentage = 50
            Message = 'Nothing to update for alert 1001. Specify -Frequency or -EmailTo.'
        }
    ) {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Type = $Type; Frequency = $Frequency; Percentage = $Percentage; Message = $Message } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001; type = $Type; email_to = 'one@example.com' })

            if ($null -ne $Frequency) {
                { Set-SGAlert -AlertId 1001 -Frequency $Frequency -Confirm:$false } | Should -Throw -ExpectedMessage $Message
            }
            else {
                { Set-SGAlert -AlertId 1001 -Percentage $Percentage -Confirm:$false } | Should -Throw -ExpectedMessage $Message
            }

            $Calls = @(Get-SgtNetworkCall | ForEach-Object { $_ })
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Get'
            @($Calls | Where-Object { $_.Method -eq 'Patch' }).Count | Should -Be 0
        }
    }

    It 'Still sends one Patch for <Name>' -ForEach @(
        @{
            Name = 'Set-SGSuppressionGroup -IsDefault:$false'
            Script = { Set-SGSuppressionGroup -UniqueId 1001 -IsDefault:$false -Confirm:$false }
            Key = 'is_default'
        }
        @{
            Name = 'Set-SGAlert on a usage_alert with -EmailTo'
            Script = { Set-SGAlert -AlertId 1001 -Frequency Weekly -EmailTo 'one@example.com' -Confirm:$false }
            Key = 'email_to'
        }
        @{
            Name = 'Set-SGAuthenticatedDomain -SetCustomSPF'
            Script = { Set-SGAuthenticatedDomain -UniqueId 1001 -SetCustomSPF -Confirm:$false }
            Key = 'custom_spf'
        }
        @{
            Name = 'Set-SGBrandedDomainLink -SetDefault'
            Script = { Set-SGBrandedDomainLink -UniqueId 1001 -SetDefault -Confirm:$false }
            Key = 'default'
        }
    ) {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Script = $Script; Key = $Key } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001; type = 'usage_alert'; email_to = 'one@example.com' })

            $null = & $Script

            $Patch = @(Get-SgtNetworkCall | ForEach-Object { $_ } | Where-Object { $_.Method -eq 'Patch' })
            $Patch.Count | Should -Be 1
            @(($Patch[0].Body | ConvertFrom-Json).PSObject.Properties.Name) | Should -Be @($Key)
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
