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

Describe 'SGASM' {
    # [SGASM] is not visible outside the module, so every case builds the object inside the module
    # and hands back plain values.
    It 'SGASM() gives GroupId 0 and an empty int[] GroupsToDisplay' {
        $R = InModuleScope SendGridTools {
            $X = [SGASM]::new()
            [pscustomobject]@{
                GroupId  = $X.GroupId
                Groups   = @($X.GroupsToDisplay)
                IsNull   = $null -eq $X.GroupsToDisplay
                TypeName = if ($null -ne $X.GroupsToDisplay) { $X.GroupsToDisplay.GetType().FullName } else { '' }
            }
        }
        $R.GroupId | Should -Be 0
        $R.IsNull | Should -BeFalse
        $R.Groups.Count | Should -Be 0
        $R.TypeName | Should -BeExactly 'System.Int32[]'
    }

    It 'SGASM(5) gives GroupId 5 and an empty GroupsToDisplay' {
        $R = InModuleScope SendGridTools {
            $X = [SGASM]::new(5)
            [pscustomobject]@{
                GroupId = $X.GroupId
                Groups  = @($X.GroupsToDisplay)
                IsNull  = $null -eq $X.GroupsToDisplay
            }
        }
        $R.GroupId | Should -Be 5
        $R.IsNull | Should -BeFalse
        $R.Groups.Count | Should -Be 0
    }

    It 'SGASM(5, @(1, 2)) keeps GroupsToDisplay as 1, 2' {
        $R = InModuleScope SendGridTools {
            $X = [SGASM]::new(5, @(1, 2))
            [pscustomobject]@{
                GroupId  = $X.GroupId
                Groups   = @($X.GroupsToDisplay)
                IsNull   = $null -eq $X.GroupsToDisplay
                TypeName = if ($null -ne $X.GroupsToDisplay) { $X.GroupsToDisplay.GetType().FullName } else { '' }
            }
        }
        $R.GroupId | Should -Be 5
        $R.IsNull | Should -BeFalse
        $R.Groups.Count | Should -Be 2
        $R.Groups[0] | Should -Be 1
        $R.Groups[1] | Should -Be 2
        $R.TypeName | Should -BeExactly 'System.Int32[]'
    }

    It 'SGASM(5, $null) gives GroupId 5 and an empty GroupsToDisplay' {
        $R = InModuleScope SendGridTools {
            $X = [SGASM]::new(5, $null)
            [pscustomobject]@{
                GroupId = $X.GroupId
                Groups  = @($X.GroupsToDisplay)
                IsNull  = $null -eq $X.GroupsToDisplay
            }
        }
        $R.GroupId | Should -Be 5
        $R.IsNull | Should -BeFalse
        $R.Groups.Count | Should -Be 0
    }

    It 'ToString returns the GroupId as text' {
        $R = InModuleScope SendGridTools {
            [pscustomobject]@{
                WithGroups = ([SGASM]::new(5, @(1, 2))).ToString()
                Default    = ([SGASM]::new()).ToString()
            }
        }
        $R.WithGroups | Should -BeExactly '5'
        $R.Default | Should -BeExactly '0'
    }

    It 'Converts a hashtable to SGASM' {
        $R = InModuleScope SendGridTools {
            $Full = [SGASM]@{ GroupId = 7; GroupsToDisplay = 7, 8 }
            $Part = [SGASM]@{ GroupId = 7 }
            [pscustomobject]@{
                FullId     = $Full.GroupId
                FullGroups = @($Full.GroupsToDisplay)
                PartId     = $Part.GroupId
                PartGroups = @($Part.GroupsToDisplay)
                PartIsNull = $null -eq $Part.GroupsToDisplay
            }
        }
        $R.FullId | Should -Be 7
        $R.FullGroups.Count | Should -Be 2
        $R.FullGroups[0] | Should -Be 7
        $R.FullGroups[1] | Should -Be 8
        $R.PartId | Should -Be 7
        $R.PartIsNull | Should -BeFalse
        $R.PartGroups.Count | Should -Be 0
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
