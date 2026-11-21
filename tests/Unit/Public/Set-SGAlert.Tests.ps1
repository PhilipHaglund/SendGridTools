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

Describe 'Set-SGAlert frequency (D53)' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Sends frequency <Expected> for <Frequency> under tr-TR' -ForEach @(
        @{ Frequency = 'Daily'; Expected = 'daily' }
        @{ Frequency = 'Weekly'; Expected = 'weekly' }
        @{ Frequency = 'Monthly'; Expected = 'monthly' }
    ) {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Frequency = $Frequency; Expected = $Expected } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001; type = 'stats_notification' })

            $OldCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
            try {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('tr-TR')
                $null = Set-SGAlert -AlertId 1001 -EmailTo 'one@example.com' -Frequency $Frequency -Confirm:$false
            }
            finally {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $OldCulture
            }

            # Get-SgtNetworkCall wraps the list in one more array; unroll it before filtering.
            $Calls = @(Get-SgtNetworkCall | ForEach-Object { $_ })
            $Patch = @($Calls | Where-Object { $_.Method -eq 'Patch' })
            $Calls.Count | Should -Be 2
            $Patch.Count | Should -Be 1
            ($Patch[0].Body | ConvertFrom-Json).frequency | Should -BeExactly $Expected
        }
    }
}

Describe 'Set-SGAlert usage_limit (D193)' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Sends percentage 98 for a usage_limit alert' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001; type = 'usage_limit'; percentage = 99 })

            $null = Set-SGAlert -AlertId 1001 -Percentage 98 -Confirm:$false

            $Calls = @(Get-SgtNetworkCall | ForEach-Object { $_ })
            $Patch = @($Calls | Where-Object { $_.Method -eq 'Patch' })
            $Calls.Count | Should -Be 2
            $Patch.Count | Should -Be 1
            "$($Patch[0].Uri)" | Should -BeLike '*/v3/alerts/1001'
            $Body = $Patch[0].Body | ConvertFrom-Json
            $Body.percentage | Should -Be 98
            $Body.PSObject.Properties.Name | Should -Not -Contain 'frequency'
        }
    }

    It 'Refuses a usage_limit alert with only -Frequency' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001; type = 'usage_limit'; percentage = 99 })

            { Set-SGAlert -AlertId 1001 -Frequency Daily -Confirm:$false } | Should -Throw -ExpectedMessage 'Nothing to update for alert 1001. Specify -Percentage or -EmailTo.'

            $Calls = @(Get-SgtNetworkCall | ForEach-Object { $_ })
            @($Calls | Where-Object { $_.Method -eq 'Patch' }).Count | Should -Be 0
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
