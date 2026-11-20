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

# Every run goes through the counting host: a regression to an unbound Invoke-SendGrid call must throw there, never wait on a console.
Describe 'Get-SGTeammate sends the username in the path (D63)' {
    It 'Sends one request to <Expected> for <Name>' -ForEach @(
        @{ Name = 'a b+c'; Expected = '/v3/teammates/a%20b%2Bc' }
        @{ Name = 'placeholder-name'; Expected = '/v3/teammates/placeholder-name' }
    ) {
        $Script = @"
try { `$null = Get-SGTeammate -Username '$Name' } catch { 'threw {0}' -f `$_.Exception.GetType().FullName }
foreach (`$Call in `$global:SgtNetworkCall) { 'path {0}' -f ([uri]`$Call.Uri).AbsolutePath }
"@
        $Run = Invoke-SgtInCountingHost -Script $Script -AnswerJson '{"username":"placeholder-name"}'

        @($Run.Output | Where-Object { $_ -like 'threw *' }).Count | Should -Be 0
        $Run.NetworkCallCount | Should -Be 1
        @($Run.Output | Where-Object { $_ -like 'path *' }) | Should -Be @("path $Expected")
        $Run.UnmockedCall | Should -BeNullOrEmpty
    }

    It 'Sends one request to /v3/teammates without -Username' {
        $Script = @'
try { $null = Get-SGTeammate } catch { 'threw {0}' -f $_.Exception.GetType().FullName }
foreach ($Call in $global:SgtNetworkCall) { 'path {0}' -f ([uri]$Call.Uri).AbsolutePath }
'@
        $Run = Invoke-SgtInCountingHost -Script $Script -AnswerJson '{"result":[]}'

        @($Run.Output | Where-Object { $_ -like 'threw *' }).Count | Should -Be 0
        $Run.NetworkCallCount | Should -Be 1
        @($Run.Output | Where-Object { $_ -like 'path *' }) | Should -Be @('path /v3/teammates')
        $Run.UnmockedCall | Should -BeNullOrEmpty
    }
}

Describe 'Get-SGTeammate refuses an empty -Username (D116)' {
    BeforeEach {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response @([pscustomobject]@{ username = 'sgt-test-user' })
        }
    }

    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Refuses <Case> at binding and makes no call' -TestCases @(
        @{ Case = '$null'; Splat = @{ Username = $null } }
        @{ Case = '@()'; Splat = @{ Username = @() } }
        @{ Case = "''"; Splat = @{ Username = '' } }
        @{ Case = "@('')"; Splat = @{ Username = @('') } }
    ) {
        InModuleScope SendGridTools -Parameters @{ Splat = $Splat } {
            { Get-SGTeammate @Splat } | Should -Throw -ErrorId 'ParameterArgumentValidationError*'
            @(Get-SgtNetworkCall)[0].Count | Should -Be 0
        }
    }

    It 'Refuses an empty value from the pipeline <Case> and makes no call' -TestCases @(
        @{ Case = 'as a string'; ByProperty = $false }
        @{ Case = 'by property Username'; ByProperty = $true }
    ) {
        InModuleScope SendGridTools -Parameters @{ ByProperty = $ByProperty } {
            # A pipeline binding error follows the caller's preference, not -ErrorAction; CI's pwsh shell sets Stop.
            $ErrorActionPreference = 'Continue'
            if ($ByProperty) {
                $Streams = @([pscustomobject]@{ Username = '' } | Get-SGTeammate 2>&1)
            }
            else {
                $Streams = @('' | Get-SGTeammate 2>&1)
            }
            $Errs = @($Streams | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })

            @($Errs).Count | Should -Be 1
            "$($Errs[0].FullyQualifiedErrorId)" | Should -BeLike 'ParameterArgument*'
            @(Get-SgtNetworkCall)[0].Count | Should -Be 0
        }
    }

    # PowerShell may bind the object by value when its Username is $null; only the absence of a list request is pinned.
    It 'Sends no list request for an object whose Username is $null' {
        InModuleScope SendGridTools {
            $ErrorActionPreference = 'Continue'
            $null = @([pscustomobject]@{ Username = $null } | Get-SGTeammate 2>&1)

            $Calls = @(@(Get-SgtNetworkCall)[0])
            @($Calls | Where-Object { ([uri]$_.Uri).AbsolutePath -eq '/v3/teammates' }).Count | Should -Be 0
        }
    }

    It 'Sends only the valid value when an empty value comes first in the pipeline' {
        InModuleScope SendGridTools {
            $ErrorActionPreference = 'Continue'
            $Streams = @([pscustomobject]@{ Username = '' }, [pscustomobject]@{ Username = 'sgt-test-user' } | Get-SGTeammate 2>&1)
            $Errs = @($Streams | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })

            @($Errs).Count | Should -Be 1
            $Calls = @(Get-SgtNetworkCall)[0]
            $Calls.Count | Should -Be 1
            "$($Calls[0].Uri)" | Should -Be 'https://api.sendgrid.com/v3/teammates/sgt-test-user'
        }
    }

    It 'Sends the same request as before for a valid value' {
        InModuleScope SendGridTools {
            $null = Get-SGTeammate -Username 'sgt-test-user'

            $Calls = @(Get-SgtNetworkCall)[0]
            $Calls.Count | Should -Be 1
            "$($Calls[0].Uri)" | Should -Be 'https://api.sendgrid.com/v3/teammates/sgt-test-user'
        }
    }

    It 'Sends the same request as before without parameters' {
        InModuleScope SendGridTools {
            $null = Get-SGTeammate

            $Calls = @(Get-SgtNetworkCall)[0]
            $Calls.Count | Should -Be 1
            "$($Calls[0].Uri)" | Should -Be 'https://api.sendgrid.com/v3/teammates'
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
