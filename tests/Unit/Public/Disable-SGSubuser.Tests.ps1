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

Describe 'Disable-SGSubuser encodes the username in the path (D63)' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Sends one Patch to <Expected> for <Name>' -ForEach @(
        @{ Name = 'a b+c'; Expected = '/v3/subusers/a%20b%2Bc'; Segments = 4 }
        @{ Name = 'a/b'; Expected = '/v3/subusers/a%2Fb'; Segments = 4 }
        @{ Name = 'sgt-test-subuser'; Expected = '/v3/subusers/sgt-test-subuser'; Segments = 4 }
    ) {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Name = $Name; Expected = $Expected; Segments = $Segments } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = Disable-SGSubuser -Username $Name -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Patch'
            $Calls[0].Uri.AbsolutePath | Should -BeExactly $Expected
            $Calls[0].Uri.Segments.Count | Should -Be $Segments
        }
    }
}

Describe 'Disable-SGSubuser help' {
    It 'Describes -Username as the username of the Subuser to disable' {
        $Text = (Get-Help Disable-SGSubuser -Parameter Username).Description.Text -join ' '
        $Text | Should -BeLike '*username of the Subuser to disable*'
        $Text | Should -Not -Match '\bID\b'
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
