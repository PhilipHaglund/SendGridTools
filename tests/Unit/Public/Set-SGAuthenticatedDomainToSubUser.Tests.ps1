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
}

AfterAll {
    Uninstall-SgtSessionHelper
    Disable-SgtNetworkTripwire
}
Describe 'Set-SGAuthenticatedDomainToSubUser asks once (D50)' {
    BeforeAll {
        $script:Answer = '{"id":1001,"subdomain":"sgt-test-sub","domain":"example.com","valid":false}'
    }

    It 'Asks one question with -Confirm' {
        $Run = Invoke-SgtInCountingHost -Script '$null = Set-SGAuthenticatedDomainToSubUser -UniqueId ''1001'' -UserName ''sgt-test-subuser'' -Confirm' -AnswerJson $script:Answer

        $Run.PromptCount | Should -Be 1
        $Run.NetworkCallCount | Should -Be 2
        $Run.Threw | Should -BeFalse
        $Run.UnmockedCall | Should -BeNullOrEmpty
    }

    It 'Names the object in one What if line with -WhatIf' {
        $Run = Invoke-SgtInCountingHost -Script '$null = Set-SGAuthenticatedDomainToSubUser -UniqueId ''1001'' -UserName ''sgt-test-subuser'' -WhatIf' -AnswerJson $script:Answer

        $WhatIf = @($Run.HostLine | Where-Object { $_ -like 'What if:*' })
        $WhatIf.Count | Should -Be 1
        $WhatIf[0] | Should -BeLike '*sgt-test-sub.example.com*'
        @($Run.HostLine | Where-Object { $_ -like '*Get-SG*' }) | Should -BeNullOrEmpty
        $Run.NetworkCallCount | Should -Be 1
        $Run.PromptCount | Should -Be 0
        $Run.Threw | Should -BeFalse
        $Run.UnmockedCall | Should -BeNullOrEmpty
    }
}
Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
