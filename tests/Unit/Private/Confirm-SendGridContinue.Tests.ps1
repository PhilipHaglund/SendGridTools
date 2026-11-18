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
}

AfterAll {
    Uninstall-SgtSessionHelper
    Disable-SgtNetworkTripwire
}

Describe 'Confirm-SendGridContinue' {
    It 'Returns <Answer> when ShouldContinue answers <Answer>' -ForEach @(
        @{ Answer = $true }
        @{ Answer = $false }
    ) {
        InModuleScope SendGridTools -Parameters @{ Answer = $Answer } {
            $Fake = [pscustomobject]@{ Calls = [System.Collections.Generic.List[object]]::new(); Answer = $Answer }
            $Fake | Add-Member -MemberType ScriptMethod -Name ShouldContinue -Value {
                param($Query, $Caption)
                $this.Calls.Add(@($Query, $Caption))
                $this.Answer
            }

            $Result = Confirm-SendGridContinue -Cmdlet $Fake -Query 'example.com' -Caption 'A caption text'

            $Result | Should -BeOfType [bool]
            $Result | Should -Be $Answer
            $Fake.Calls.Count | Should -Be 1
        }
    }

    It 'Passes the query first and the caption second' {
        InModuleScope SendGridTools {
            $Fake = [pscustomobject]@{ Calls = [System.Collections.Generic.List[object]]::new() }
            $Fake | Add-Member -MemberType ScriptMethod -Name ShouldContinue -Value {
                param($Query, $Caption)
                $this.Calls.Add(@($Query, $Caption))
                $true
            }

            $null = Confirm-SendGridContinue -Cmdlet $Fake -Query 'the query' -Caption 'the caption'

            $Fake.Calls.Count | Should -Be 1
            $Fake.Calls[0][0] | Should -Be 'the query'
            $Fake.Calls[0][1] | Should -Be 'the caption'
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
