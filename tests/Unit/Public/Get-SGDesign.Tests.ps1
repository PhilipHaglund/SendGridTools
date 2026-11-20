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

Describe 'Get-SGDesign sends a valid query (D65)' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Sends <Expected> for <Name>' -ForEach @(
        @{ Name = '-PageSize 50'; Splat = @{ PageSize = 50 }; Expected = '?page_size=50' }
        @{ Name = '-PageToken a+b'; Splat = @{ PageToken = 'a+b' }; Expected = '?page_token=a%2Bb' }
        @{ Name = '-Summary'; Splat = @{ Summary = $true }; Expected = '?summary=true' }
        @{ Name = '-Summary:$false'; Splat = @{ Summary = $false }; Expected = '?summary=false' }
        @{ Name = 'no parameters'; Splat = @{}; Expected = '' }
        @{ Name = '-PageSize 5 -Summary:$false'; Splat = @{ PageSize = 5; Summary = $false }; Expected = '?page_size=5&summary=false' }
        @{ Name = '-PageSize 50 -PageToken token'; Splat = @{ PageSize = 50; PageToken = 'token' }; Expected = '?page_size=50&page_token=token' }
    ) {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Splat = $Splat; Expected = $Expected } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ result = @() })

            $null = Get-SGDesign @Splat

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Get'
            ([uri]$Calls[0].Uri).Query | Should -BeExactly $Expected
        }
    }
}

Describe 'Get-SGDesign page size is checked by presence and validated at binding (D154)' {
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
        @{ Name = '-PageSize 0'; Splat = @{ PageSize = 0 } }
        @{ Name = '-PageSize -1'; Splat = @{ PageSize = -1 } }
    ) {
        InModuleScope SendGridTools -Parameters @{ Splat = $Splat } {
            { Get-SGDesign @Splat } | Should -Throw -ErrorId 'ParameterArgumentValidationError*'
            (Get-SgtNetworkCall).Count | Should -Be 0
        }
    }

    It 'Sends <Expected> for <Name>' -ForEach @(
        @{ Name = 'no parameters'; Splat = @{}; Expected = '' }
        @{ Name = '-PageSize 1'; Splat = @{ PageSize = 1 }; Expected = '?page_size=1' }
        @{ Name = '-PageSize 100'; Splat = @{ PageSize = 100 }; Expected = '?page_size=100' }
    ) {
        InModuleScope SendGridTools -Parameters @{ Splat = $Splat; Expected = $Expected } {
            $null = Get-SGDesign @Splat

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            ([uri]$Calls[0].Uri).Query | Should -BeExactly $Expected
        }
    }
}

Describe 'Get-SGDesign paging help (D154)' {
    It 'Says that a page size below 1 is refused' {
        $Text = ((Get-Help Get-SGDesign -Parameter PageSize).description.Text -join ' ') -replace '\s+', ' '
        $Text.Trim() | Should -BeLike '*A value below 1 is refused.'
        $Text | Should -Not -BeLike '*other than 0*'
    }

    It 'Says in the comment at -PageSize that a value below 1 is refused' {
        (Get-Command Get-SGDesign).Definition | Should -Match '# [^\r\n]*A value below 1 is refused\.\r?\n\s*\[Parameter\([^)]*\)\]\s*(\[[^\r\n]*\]\s*)*\$PageSize\b'
    }
}
Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
