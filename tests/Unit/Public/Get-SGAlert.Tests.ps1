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

Describe 'Get-SGAlert refuses an empty -AlertId (D116)' {
    BeforeEach {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response @([pscustomobject]@{ id = 1001; type = 'usage_limit' })
        }
    }

    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Refuses <Case> at binding and makes no call' -TestCases @(
        @{ Case = '$null'; Splat = @{ AlertId = $null } }
        @{ Case = '@()'; Splat = @{ AlertId = @() } }
        @{ Case = "''"; Splat = @{ AlertId = '' } }
        @{ Case = "@('')"; Splat = @{ AlertId = @('') } }
    ) {
        InModuleScope SendGridTools -Parameters @{ Splat = $Splat } {
            { Get-SGAlert @Splat } | Should -Throw -ErrorId 'ParameterArgumentValidationError*'
            @(Get-SgtNetworkCall)[0].Count | Should -Be 0
        }
    }

    It 'Refuses an empty value from the pipeline <Case> and makes no call' -TestCases @(
        @{ Case = 'as a string'; ByProperty = $false }
        @{ Case = 'by property AlertId'; ByProperty = $true }
    ) {
        InModuleScope SendGridTools -Parameters @{ ByProperty = $ByProperty } {
            # A pipeline binding error follows the caller's preference, not -ErrorAction; CI's pwsh shell sets Stop.
            $ErrorActionPreference = 'Continue'
            if ($ByProperty) {
                $Streams = @([pscustomobject]@{ AlertId = '' } | Get-SGAlert 2>&1)
            }
            else {
                $Streams = @('' | Get-SGAlert 2>&1)
            }
            $Errs = @($Streams | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })

            @($Errs).Count | Should -Be 1
            "$($Errs[0].FullyQualifiedErrorId)" | Should -BeLike 'ParameterArgument*'
            @(Get-SgtNetworkCall)[0].Count | Should -Be 0
        }
    }

    # PowerShell may bind the object by value when its AlertId is $null; only the absence of a list request is pinned.
    It 'Sends no list request for an object whose AlertId is $null' {
        InModuleScope SendGridTools {
            $ErrorActionPreference = 'Continue'
            $null = @([pscustomobject]@{ AlertId = $null } | Get-SGAlert 2>&1)

            $Calls = @(@(Get-SgtNetworkCall)[0])
            @($Calls | Where-Object { ([uri]$_.Uri).AbsolutePath -eq '/v3/alerts' }).Count | Should -Be 0
        }
    }

    It 'Sends only the valid value when an empty value comes first in the pipeline' {
        InModuleScope SendGridTools {
            $ErrorActionPreference = 'Continue'
            $Streams = @([pscustomobject]@{ AlertId = '' }, [pscustomobject]@{ AlertId = '1001' } | Get-SGAlert 2>&1)
            $Errs = @($Streams | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })

            @($Errs).Count | Should -Be 1
            $Calls = @(Get-SgtNetworkCall)[0]
            $Calls.Count | Should -Be 1
            "$($Calls[0].Uri)" | Should -Be 'https://api.sendgrid.com/v3/alerts/1001'
        }
    }

    It 'Sends the same request as before for a valid value' {
        InModuleScope SendGridTools {
            $null = Get-SGAlert -AlertId '1001'

            $Calls = @(Get-SgtNetworkCall)[0]
            $Calls.Count | Should -Be 1
            "$($Calls[0].Uri)" | Should -Be 'https://api.sendgrid.com/v3/alerts/1001'
        }
    }

    It 'Sends the same request as before without parameters' {
        InModuleScope SendGridTools {
            $null = Get-SGAlert

            $Calls = @(Get-SgtNetworkCall)[0]
            $Calls.Count | Should -Be 1
            "$($Calls[0].Uri)" | Should -Be 'https://api.sendgrid.com/v3/alerts'
        }
    }
}

Describe 'Get-SGAlert help (D117)' {
    It 'Says that an empty -AlertId is refused' {
        $Text = ((Get-Help Get-SGAlert -Parameter AlertId).description.Text -join ' ') -replace '\s+', ' '
        $Text.Trim() | Should -BeLike '*An empty value is refused.'
        (Get-Command Get-SGAlert).Definition | Should -Match '# [^\r\n]*An empty value is refused\.\r?\n\s*\[Parameter\('
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
