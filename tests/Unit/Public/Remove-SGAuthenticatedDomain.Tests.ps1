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

Describe 'Remove-SGAuthenticatedDomain ids from the pipeline' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Sends the request to the right path for <Name> from the pipeline' -ForEach @(
        @{ Name = 'a long'; Ids = @([long]1001); TypeName = 'System.Int64' }
        @{ Name = 'an integer'; Ids = @([int]1001); TypeName = 'System.Int32' }
        @{ Name = 'a string'; Ids = @('1001'); TypeName = 'System.String' }
        @{ Name = 'an object with an Id property'; Ids = @([pscustomobject]@{ Id = 1001 }); TypeName = 'System.Management.Automation.PSCustomObject' }
    ) {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Ids = $Ids; TypeName = $TypeName } {
            Mock Get-SGAuthenticatedDomain { [pscustomobject]@{ Valid = $false; Subdomain = 'em0001'; Domain = 'domain-1.example.com' } }
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            # Guard: the value that is piped really has the intended type (an int must not stand in for a long).
            @($Ids).Count | Should -Be 1
            @($Ids)[0].GetType().FullName | Should -Be $TypeName

            $null = $Ids | Remove-SGAuthenticatedDomain -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Delete'
            "$($Calls[0].Uri)" | Should -BeLike '*/whitelabel/domains/1001'
        }
    }

    It 'Fails with a conversion error and sends nothing for a double from the pipeline' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            Mock Get-SGAuthenticatedDomain { [pscustomobject]@{ Valid = $false; Subdomain = 'em0001'; Domain = 'domain-1.example.com' } }
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })
            $Ids = @([double]1001.5)
            @($Ids)[0].GetType().FullName | Should -Be 'System.Double'

            { $Ids | Remove-SGAuthenticatedDomain -Confirm:$false } | Should -Throw '*Failed to convert InputObject to Id.*'

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 0
        }
    }
}
Describe 'Remove-SGAuthenticatedDomain verbose messages' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Writes no verbose record for <Label> without -Verbose and writes it with -Verbose' -ForEach @(
        @{ Label = 'the DNS reminder'; CallArgs = @{ UniqueId = '1001' }; Message = 'Don''t forget to remove DNS records.' }
    ) {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; CallArgs = $CallArgs; Message = $Message } {
            Mock Get-SGAuthenticatedDomain { [pscustomobject]@{ Valid = $false; Subdomain = 'em0001'; Domain = 'domain-1.example.com' } }
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            # A module function reads the global preference, so set both and restore the global one.
            $SavedVerbose = $global:VerbosePreference
            try {
                $global:VerbosePreference = 'SilentlyContinue'
                $VerbosePreference = 'SilentlyContinue'
                $Without = @(& { Remove-SGAuthenticatedDomain @CallArgs -Confirm:$false } 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] })
                $With = @(& { Remove-SGAuthenticatedDomain @CallArgs -Confirm:$false -Verbose } 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] })
            }
            finally {
                $global:VerbosePreference = $SavedVerbose
            }

            @($Without | Where-Object { $_.Message -eq $Message }).Count | Should -Be 0
            @($With | Where-Object { $_.Message -eq $Message }).Count | Should -Be 1
        }
    }
}

Describe 'Remove-SGAuthenticatedDomain asks once (D50)' {
    BeforeAll {
        $script:Answer = '{"id":1001,"subdomain":"sgt-test-sub","domain":"example.com","valid":false}'
    }

    It 'Asks one question with -Confirm' {
        $Run = Invoke-SgtInCountingHost -Script '$null = Remove-SGAuthenticatedDomain -UniqueId ''1001'' -Confirm' -AnswerJson $script:Answer

        $Run.PromptCount | Should -Be 1
        $Run.NetworkCallCount | Should -Be 2
        $Run.Threw | Should -BeFalse
        $Run.UnmockedCall | Should -BeNullOrEmpty
    }

    It 'Names the object in one What if line with -WhatIf' {
        $Run = Invoke-SgtInCountingHost -Script '$null = Remove-SGAuthenticatedDomain -UniqueId ''1001'' -WhatIf' -AnswerJson $script:Answer

        $WhatIf = @($Run.HostLine | Where-Object { $_ -like 'What if:*' })
        $WhatIf.Count | Should -Be 1
        $WhatIf[0] | Should -BeLike '*sgt-test-sub.example.com(1001)*'
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
