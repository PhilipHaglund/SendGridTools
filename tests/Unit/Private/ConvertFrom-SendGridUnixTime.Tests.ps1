BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/NetworkTripwire.ps1')
    # Import once per run: in Windows PowerShell 5.1 a class stays bound to the first loaded module instance.
    if (-not (Get-Module -Name SendGridTools)) {
        Get-Module -Name SendGridTools -ListAvailable | Select-Object -First 1 | Import-Module -ErrorAction Stop
    }
    Enable-SgtNetworkTripwire
    Assert-SgtNetworkTripwireActive
}

AfterAll {
    Disable-SgtNetworkTripwire
}

Describe 'ConvertFrom-SendGridUnixTime turns whole numbers within Int32 under a time name into dates (D52)' {
    It 'Gives a date for 1700000000 sent as <TypeName>' -ForEach @(
        @{ TypeName = 'Int32' }
        @{ TypeName = 'Int64' }
    ) {
        InModuleScope SendGridTools -Parameters @{ TypeName = $TypeName } {
            $Number = if ($TypeName -eq 'Int32') { [int]1700000000 } else { [int64]1700000000 }

            $Result = ConvertFrom-SendGridUnixTime -Name 'added_at' -Value $Number

            $Result.Converted | Should -BeTrue
            $Result.Value | Should -BeOfType [datetime]
            $Result.Value | Should -Be ([datetime]::new(1970, 1, 1, 0, 0, 0, 0).AddSeconds(1700000000))
        }
    }

    It 'Gives a date for the Int32 limit <Limit>' -ForEach @(
        @{ Limit = 'MaxValue' }
        @{ Limit = 'MinValue' }
    ) {
        InModuleScope SendGridTools -Parameters @{ Limit = $Limit } {
            $Number = [int]::$Limit

            $Result = ConvertFrom-SendGridUnixTime -Name 'added_at' -Value $Number

            $Result.Converted | Should -BeTrue
            $Result.Value | Should -BeOfType [datetime]
            $Result.Value | Should -Be ([datetime]::new(1970, 1, 1, 0, 0, 0, 0).AddSeconds($Number))
        }
    }

    It 'Leaves the Int64 value <Number> as it is' -ForEach @(
        @{ Number = [int64]2147483648 }
        @{ Number = [int64]-2147483649 }
        @{ Number = [int64]3000000000 }
    ) {
        InModuleScope SendGridTools -Parameters @{ Number = $Number } {
            $Result = ConvertFrom-SendGridUnixTime -Name 'added_at' -Value $Number

            $Result.Converted | Should -BeFalse
            $Result.Value | Should -BeOfType [int64]
            $Result.Value | Should -Be $Number
        }
    }

    It 'Gives a list of dates in the same order for a list within Int32' {
        InModuleScope SendGridTools {
            $Epoch = [datetime]::new(1970, 1, 1, 0, 0, 0, 0)

            $Result = ConvertFrom-SendGridUnixTime -Name 'added_at' -Value @([int64]1700000000, [int64]1700000001)

            $Result.Converted | Should -BeTrue
            ($Result.Value -is [object[]]) | Should -BeTrue
            $Result.Value.Count | Should -Be 2
            $Result.Value[0] | Should -BeOfType [datetime]
            $Result.Value[0] | Should -Be $Epoch.AddSeconds(1700000000)
            $Result.Value[1] | Should -BeOfType [datetime]
            $Result.Value[1] | Should -Be $Epoch.AddSeconds(1700000001)
        }
    }

    It 'Leaves a list as it is when one number is outside Int32' {
        InModuleScope SendGridTools {
            $Result = ConvertFrom-SendGridUnixTime -Name 'added_at' -Value @([int64]1700000000, [int64]3000000000)

            $Result.Converted | Should -BeFalse
            ($Result.Value -is [array]) | Should -BeTrue
            $Result.Value.Count | Should -Be 2
            $Result.Value[0] | Should -BeOfType [int64]
            $Result.Value[0] | Should -Be 1700000000
            $Result.Value[1] | Should -BeOfType [int64]
            $Result.Value[1] | Should -Be 3000000000
        }
    }

    It 'Leaves a number under the name id as it is' {
        InModuleScope SendGridTools {
            $Result = ConvertFrom-SendGridUnixTime -Name 'id' -Value 1700000000

            $Result.Converted | Should -BeFalse
            $Result.Value | Should -Not -BeOfType [datetime]
            $Result.Value | Should -Be 1700000000
        }
    }

    It 'Leaves <Label> under added_at as it is' -ForEach @(
        @{ Label = 'a null'; Value = $null }
        @{ Label = 'an empty list'; Value = @() }
        @{ Label = 'a text'; Value = 'sgt-test-text' }
        @{ Label = 'a Boolean'; Value = $true }
        @{ Label = 'a decimal number'; Value = 1.5 }
    ) {
        InModuleScope SendGridTools -Parameters @{ Value = $Value } {
            $Result = ConvertFrom-SendGridUnixTime -Name 'added_at' -Value $Value

            $Result.Converted | Should -BeFalse
            if ($null -eq $Value) {
                $Result.Value | Should -BeNullOrEmpty
            }
            elseif ($Value -is [array]) {
                ($Result.Value -is [array]) | Should -BeTrue
                $Result.Value.Count | Should -Be 0
            }
            else {
                $Result.Value | Should -BeOfType $Value.GetType()
                $Result.Value | Should -Be $Value
            }
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
