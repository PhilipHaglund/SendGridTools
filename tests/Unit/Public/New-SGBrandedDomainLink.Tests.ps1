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

Describe 'New-SGBrandedDomainLink request' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Sends the subdomain it is given' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = New-SGBrandedDomainLink -Domain 'example.com' -SendGridSubDomain 'link' -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Post'
            "$($Calls[0].Uri)" | Should -BeLike '*/whitelabel/links'
            $Sent = $Calls[0].Body | ConvertFrom-Json
            @($Sent.PSObject.Properties.Name | Sort-Object) | Should -Be @('domain', 'subdomain')
            $Sent.subdomain | Should -Be 'link'
            $Sent.domain | Should -Be 'example.com'
        }
    }

    It 'Names the full domain as the ShouldProcess target when a subdomain is given' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $Leak = Get-SgtLeakText -Action { New-SGBrandedDomainLink -Domain 'example.com' -SendGridSubDomain 'link' -Confirm:$false -Verbose }

            $Leak.Verbose | Should -BeLike '*"link.example.com"*'
        }
    }

    It 'Sends no subdomain when none is given' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = New-SGBrandedDomainLink -Domain 'example.com' -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Post'
            $Sent = $Calls[0].Body | ConvertFrom-Json
            @($Sent.PSObject.Properties.Name | Sort-Object) | Should -Be @('domain')
        }
    }

    It 'Names the domain alone as the ShouldProcess target when no subdomain is given' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $Leak = Get-SgtLeakText -Action { New-SGBrandedDomainLink -Domain 'example.com' -Confirm:$false -Verbose }

            $Leak.Verbose | Should -BeLike '*"example.com"*'
            $Leak.Verbose | Should -Not -BeLike '*".example.com"*'
        }
    }

    It 'Sets the on-behalf-of header and adds nothing to the body' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = New-SGBrandedDomainLink -Domain 'example.com' -OnBehalfOf 'subuser-placeholder' -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Headers['on-behalf-of'] | Should -Be 'subuser-placeholder'
            $Sent = $Calls[0].Body | ConvertFrom-Json
            @($Sent.PSObject.Properties.Name | Sort-Object) | Should -Be @('domain')
        }
    }

    It 'Asks once and sends default when Default is given and the answer is yes' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })
            Mock Confirm-SendGridContinue -ModuleName SendGridTools -MockWith { $true }

            $null = New-SGBrandedDomainLink -Domain 'example.com' -Default -Confirm:$false

            Should -Invoke Confirm-SendGridContinue -ModuleName SendGridTools -Times 1 -Exactly -ParameterFilter {
                $Query -eq 'example.com' -and $Caption -ceq 'Setting this domain as the default domain will remove the current default domain. Do you want to continue?'
            }
            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Sent = $Calls[0].Body | ConvertFrom-Json
            $Sent.default | Should -BeTrue
            @($Sent.PSObject.Properties.Name | Sort-Object) | Should -Be @('default', 'domain')
        }
    }

    It 'Asks once and sends no default when Default is given and the answer is no' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })
            Mock Confirm-SendGridContinue -ModuleName SendGridTools -MockWith { $false }

            $null = New-SGBrandedDomainLink -Domain 'example.com' -Default -Confirm:$false

            Should -Invoke Confirm-SendGridContinue -ModuleName SendGridTools -Times 1 -Exactly
            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Sent = $Calls[0].Body | ConvertFrom-Json
            $Sent.PSObject.Properties.Name | Should -Not -Contain 'default'
        }
    }

    It 'Does not ask and sends no default when Default is given as false' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })
            Mock Confirm-SendGridContinue -ModuleName SendGridTools -MockWith { $true }

            $null = New-SGBrandedDomainLink -Domain 'example.com' -Default:$false -Confirm:$false

            Should -Invoke Confirm-SendGridContinue -ModuleName SendGridTools -Times 0 -Exactly
            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Sent = $Calls[0].Body | ConvertFrom-Json
            $Sent.PSObject.Properties.Name | Should -Not -Contain 'default'
        }
    }

    It 'Does not ask and sends no default when Default is not given' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })
            Mock Confirm-SendGridContinue -ModuleName SendGridTools -MockWith { $true }

            $null = New-SGBrandedDomainLink -Domain 'example.com' -Confirm:$false

            Should -Invoke Confirm-SendGridContinue -ModuleName SendGridTools -Times 0 -Exactly
            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Sent = $Calls[0].Body | ConvertFrom-Json
            $Sent.PSObject.Properties.Name | Should -Not -Contain 'default'
        }
    }

    It 'Makes no call under WhatIf' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = New-SGBrandedDomainLink -Domain 'example.com' -SendGridSubDomain 'link' -WhatIf

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 0
        }
    }
}

Describe 'New-SGBrandedDomainLink verbose messages' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Writes no verbose record for <Label> without -Verbose and writes it with -Verbose' -ForEach @(
        @{ Label = 'the note with a subdomain'; CallArgs = @{ Domain = 'example.com'; SendGridSubDomain = 'link' }; Message = 'SendGrid will not generate a custom subdomain. Domain to be used: example.com' }
        @{ Label = 'the note without a subdomain'; CallArgs = @{ Domain = 'example.com' }; Message = 'SendGrid will automatically generate a custom branded subdomain for you. Example:url1234.example.com' }
    ) {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; CallArgs = $CallArgs; Message = $Message } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            # A module function reads the global preference, so set both and restore the global one.
            $SavedVerbose = $global:VerbosePreference
            try {
                $global:VerbosePreference = 'SilentlyContinue'
                $VerbosePreference = 'SilentlyContinue'
                $Without = @(& { New-SGBrandedDomainLink @CallArgs -Confirm:$false } 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] })
                $With = @(& { New-SGBrandedDomainLink @CallArgs -Confirm:$false -Verbose } 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] })
            }
            finally {
                $global:VerbosePreference = $SavedVerbose
            }

            @($Without | Where-Object { $_.Message -eq $Message }).Count | Should -Be 0
            @($With | Where-Object { $_.Message -eq $Message }).Count | Should -Be 1
        }
    }
}
Describe 'New-SGBrandedDomainLink -Force' {
    BeforeAll {
        . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/PromptCountingHost.ps1')
    }

    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Skips the question and sends default with -Default -Force' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })
            Mock Confirm-SendGridContinue -ModuleName SendGridTools -MockWith { throw 'Confirm-SendGridContinue must not be called' }

            $null = New-SGBrandedDomainLink -Domain 'example.com' -Default -Force -Confirm:$false

            Should -Invoke Confirm-SendGridContinue -ModuleName SendGridTools -Times 0 -Exactly
            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            ($Calls[0].Body | ConvertFrom-Json).default | Should -BeTrue
        }
    }

    It 'Sends the same body with -Force as with the answer yes' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })
            Mock Confirm-SendGridContinue -ModuleName SendGridTools -MockWith { $true }

            $null = New-SGBrandedDomainLink -Domain 'example.com' -Default -Confirm:$false
            $null = New-SGBrandedDomainLink -Domain 'example.com' -Default -Force -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 2
            $Calls[1].Body | Should -Be $Calls[0].Body
        }
    }

    It 'Makes no call and asks nothing under -Default -Force -WhatIf' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })
            Mock Confirm-SendGridContinue -ModuleName SendGridTools -MockWith { $true }

            $null = New-SGBrandedDomainLink -Domain 'example.com' -Default -Force -WhatIf

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 0
            Should -Invoke Confirm-SendGridContinue -ModuleName SendGridTools -Times 0 -Exactly
        }
    }

    It 'Asks once as before when -Force is given as false' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })
            Mock Confirm-SendGridContinue -ModuleName SendGridTools -MockWith { $true }

            $null = New-SGBrandedDomainLink -Domain 'example.com' -Default -Force:$false -Confirm:$false

            Should -Invoke Confirm-SendGridContinue -ModuleName SendGridTools -Times 1 -Exactly
            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            ($Calls[0].Body | ConvertFrom-Json).default | Should -BeTrue
        }
    }

    It 'Asks nothing and sends no default with -Force alone' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })
            Mock Confirm-SendGridContinue -ModuleName SendGridTools -MockWith { throw 'Confirm-SendGridContinue must not be called' }

            $null = New-SGBrandedDomainLink -Domain 'example.com' -Force -Confirm:$false

            Should -Invoke Confirm-SendGridContinue -ModuleName SendGridTools -Times 0 -Exactly
            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            ($Calls[0].Body | ConvertFrom-Json).PSObject.Properties.Name | Should -Not -Contain 'default'
        }
    }

    It 'Declares Force as a switch without a position' {
        $Parameter = (Get-Command -Name New-SGBrandedDomainLink).Parameters['Force']

        $Parameter.ParameterType | Should -Be ([switch])
        $ParameterAttributes = @($Parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] })
        $ParameterAttributes.Count | Should -BeGreaterThan 0
        foreach ($Attribute in $ParameterAttributes) {
            $Attribute.Position | Should -Be ([int]::MinValue)
        }
    }

    It 'Counts the questions in a console host: <Switches> asks <Prompts>' -ForEach @(
        @{ Switches = '-Default -Force -Confirm'; Prompts = 1; Requests = 1 }
        @{ Switches = '-Default -Force'; Prompts = 0; Requests = 1 }
        @{ Switches = '-Default -Confirm'; Prompts = 2; Requests = 1 }
    ) {
        $Run = Invoke-SgtInCountingHost -Script "`$null = New-SGBrandedDomainLink -Domain 'example.com' $Switches" -AnswerJson '{"id":1001}'

        $Run.PromptCount | Should -Be $Prompts
        $Run.NetworkCallCount | Should -Be $Requests
        $Run.UnmockedCall | Should -BeNullOrEmpty
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
