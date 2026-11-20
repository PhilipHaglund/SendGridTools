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

Describe 'Get-SGMailSetting paging parameters are checked by presence and validated at binding (D154)' {
    BeforeEach {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ result = @() })
        }
    }

    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Refuses <Name> at binding and makes no call' -ForEach @(
        @{ Name = '-Limit 0'; Splat = @{ Limit = 0 } }
        @{ Name = '-Limit -1'; Splat = @{ Limit = -1 } }
        @{ Name = '-Offset -1'; Splat = @{ Offset = -1 } }
    ) {
        InModuleScope SendGridTools -Parameters @{ Splat = $Splat } {
            { Get-SGMailSetting @Splat } | Should -Throw -ErrorId 'ParameterArgumentValidationError*'
            (Get-SgtNetworkCall).Count | Should -Be 0
        }
    }

    It 'Sends <Expected> for <Name>' -ForEach @(
        @{ Name = 'no parameters'; Splat = @{}; Expected = '' }
        @{ Name = '-Limit 1'; Splat = @{ Limit = 1 }; Expected = '?limit=1' }
        @{ Name = '-Offset 0'; Splat = @{ Offset = 0 }; Expected = '?offset=0' }
        @{ Name = '-Limit 5 -Offset 0'; Splat = @{ Limit = 5; Offset = 0 }; Expected = '?limit=5&offset=0' }
        @{ Name = '-Limit 5 -Offset 10'; Splat = @{ Limit = 5; Offset = 10 }; Expected = '?limit=5&offset=10' }
    ) {
        InModuleScope SendGridTools -Parameters @{ Splat = $Splat; Expected = $Expected } {
            $null = Get-SGMailSetting @Splat

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Get'
            ([uri]$Calls[0].Uri).Query | Should -BeExactly $Expected
        }
    }
}

Describe 'Get-SGMailSetting paging help (D154)' {
    It 'Says that a limit below 1 is refused' {
        $Text = ((Get-Help Get-SGMailSetting -Parameter Limit).description.Text -join ' ') -replace '\s+', ' '
        $Text.Trim() | Should -BeLike '*A value below 1 is refused.'
    }

    It 'Says that an offset below 0 is refused' {
        $Text = ((Get-Help Get-SGMailSetting -Parameter Offset).description.Text -join ' ') -replace '\s+', ' '
        $Text.Trim() | Should -BeLike '*A value below 0 is refused.'
    }

    It 'Says in the comment at -Limit that a value below 1 is refused' {
        (Get-Command Get-SGMailSetting).Definition | Should -Match '# [^\r\n]*A value below 1 is refused\.\r?\n\s*\[Parameter\([^)]*\)\]\s*(\[[^\r\n]*\]\s*)*\$Limit\b'
    }

    It 'Says in the comment at -Offset that a value below 0 is refused' {
        (Get-Command Get-SGMailSetting).Definition | Should -Match '# [^\r\n]*A value below 0 is refused\.\r?\n\s*\[Parameter\([^)]*\)\]\s*(\[[^\r\n]*\]\s*)*\$Offset\b'
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
