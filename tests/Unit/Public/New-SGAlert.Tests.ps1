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

Describe 'New-SGAlert frequency (D53)' {
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
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $OldCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
            try {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo('tr-TR')
                $null = New-SGAlert -EmailStatisticsSummary -EmailTo 'one@example.com' -Frequency $Frequency -Confirm:$false
            }
            finally {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $OldCulture
            }

            # Get-SgtNetworkCall wraps the list in one more array; unroll it before reading a call.
            $Calls = @(Get-SgtNetworkCall | ForEach-Object { $_ })
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Post'
            ($Calls[0].Body | ConvertFrom-Json).frequency | Should -BeExactly $Expected
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
