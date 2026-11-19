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
    # The IPAddress completer calls Get-SGIPAddress; answer it in module scope so a test can never reach the real command.
    Mock -CommandName Get-SGIPAddress -ModuleName SendGridTools -MockWith { [pscustomobject]@{ Ip = '192.0.2.10' }, [pscustomobject]@{ Ip = '192.0.2.11' } }
}

AfterAll {
    Uninstall-SgtSessionHelper
    Disable-SgtNetworkTripwire
}

Describe 'New-SGAuthenticatedDomain request' {
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

            $null = New-SGAuthenticatedDomain -Domain 'example.com' -SendGridSubdomain 'email' -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Post'
            "$($Calls[0].Uri)" | Should -BeLike '*/whitelabel/domains'
            $Sent = $Calls[0].Body | ConvertFrom-Json
            @($Sent.PSObject.Properties.Name | Sort-Object) | Should -Be @('automatic_security', 'domain', 'subdomain')
            $Sent.subdomain | Should -Be 'email'
            $Sent.domain | Should -Be 'example.com'
            $Sent.automatic_security | Should -Be $true
        }
    }

    It 'Names the full domain as the ShouldProcess target when a subdomain is given' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $Leak = Get-SgtLeakText -Action { New-SGAuthenticatedDomain -Domain 'example.com' -SendGridSubdomain 'email' -Confirm:$false -Verbose }

            $Leak.Verbose | Should -BeLike '*"email.example.com"*'
        }
    }

    It 'Sends no subdomain when none is given' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = New-SGAuthenticatedDomain -Domain 'example.com' -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Post'
            $Sent = $Calls[0].Body | ConvertFrom-Json
            @($Sent.PSObject.Properties.Name | Sort-Object) | Should -Be @('automatic_security', 'domain')
        }
    }

    It 'Names the domain alone as the ShouldProcess target when no subdomain is given' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $Leak = Get-SgtLeakText -Action { New-SGAuthenticatedDomain -Domain 'example.com' -Confirm:$false -Verbose }

            $Leak.Verbose | Should -BeLike '*"example.com"*'
            $Leak.Verbose | Should -Not -BeLike '*".example.com"*'
        }
    }

    It 'Sends the username it is given' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = New-SGAuthenticatedDomain -Domain 'example.com' -Username 'subuser-placeholder' -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Sent = $Calls[0].Body | ConvertFrom-Json
            @($Sent.PSObject.Properties.Name | Sort-Object) | Should -Be @('automatic_security', 'domain', 'username')
            $Sent.username | Should -Be 'subuser-placeholder'
        }
    }

    It 'Sends automatic security as false when it is disabled' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = New-SGAuthenticatedDomain -Domain 'example.com' -DisableAutomaticSecurity -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Sent = $Calls[0].Body | ConvertFrom-Json
            @($Sent.PSObject.Properties.Name | Sort-Object) | Should -Be @('automatic_security', 'domain')
            $Sent.automatic_security | Should -BeFalse
        }
    }

    It 'Adds the custom SPF flag when automatic security is disabled and custom SPF is given' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = New-SGAuthenticatedDomain -Domain 'example.com' -DisableAutomaticSecurity -CustomSPF -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Sent = $Calls[0].Body | ConvertFrom-Json
            @($Sent.PSObject.Properties.Name | Sort-Object) | Should -Be @('automatic_security', 'custom_spf', 'domain')
            $Sent.automatic_security | Should -BeFalse
            $Sent.custom_spf | Should -BeTrue
        }
    }

    It 'Sends the custom DKIM selector it is given' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = New-SGAuthenticatedDomain -Domain 'example.com' -CustomDkimSelector 'abc' -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Sent = $Calls[0].Body | ConvertFrom-Json
            @($Sent.PSObject.Properties.Name | Sort-Object) | Should -Be @('automatic_security', 'custom_dkim_selector', 'domain')
            $Sent.custom_dkim_selector | Should -Be 'abc'
        }
    }

    It 'Sets the on-behalf-of header and adds nothing to the body' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = New-SGAuthenticatedDomain -Domain 'example.com' -OnBehalfOf 'subuser-placeholder' -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Headers['on-behalf-of'] | Should -Be 'subuser-placeholder'
            $Sent = $Calls[0].Body | ConvertFrom-Json
            @($Sent.PSObject.Properties.Name | Sort-Object) | Should -Be @('automatic_security', 'domain')
        }
    }

    It 'Sends the one IP address it is given as an array' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = New-SGAuthenticatedDomain -Domain 'example.com' -IPAddress '192.0.2.10' -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Sent = $Calls[0].Body | ConvertFrom-Json
            @($Sent.PSObject.Properties.Name | Sort-Object) | Should -Be @('automatic_security', 'domain', 'ips')
            @($Sent.ips) | Should -Be @('192.0.2.10')
            $Calls[0].Body | Should -Match '"ips":\s*\[\s*"192\.0\.2\.10"\s*\]'
        }
    }

    It 'Sends every IP address it is given' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = New-SGAuthenticatedDomain -Domain 'example.com' -IPAddress '192.0.2.10', '192.0.2.11' -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Sent = $Calls[0].Body | ConvertFrom-Json
            @($Sent.ips) | Should -Be @('192.0.2.10', '192.0.2.11')
        }
    }

    It 'Sends no ips when no IP address is given' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = New-SGAuthenticatedDomain -Domain 'example.com' -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Sent = $Calls[0].Body | ConvertFrom-Json
            $Sent.PSObject.Properties.Name | Should -Not -Contain 'ips'
        }
    }

    It 'Sends no custom SPF flag when custom SPF is given as false' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = New-SGAuthenticatedDomain -Domain 'example.com' -DisableAutomaticSecurity -CustomSPF:$false -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Sent = $Calls[0].Body | ConvertFrom-Json
            @($Sent.PSObject.Properties.Name | Sort-Object) | Should -Be @('automatic_security', 'domain')
            $Sent.automatic_security | Should -BeFalse
        }
    }

    It 'Rejects custom SPF without disabling automatic security and makes no call' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            # -CustomSPF exists only with -DisableAutomaticSecurity, so binding fails; assert the binding failure, not a specific error id.
            { New-SGAuthenticatedDomain -Domain 'example.com' -CustomSPF -Confirm:$false } | Should -Throw -ExceptionType ([System.Management.Automation.ParameterBindingException])

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 0
        }
    }

    It 'Sends automatic security as true when the switch is not given' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = New-SGAuthenticatedDomain -Domain 'example.com' -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Sent = $Calls[0].Body | ConvertFrom-Json
            $Sent.automatic_security | Should -BeTrue
        }
    }

    It 'Sends automatic security as true when the switch is given as false' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = New-SGAuthenticatedDomain -Domain 'example.com' -DisableAutomaticSecurity:$false -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Sent = $Calls[0].Body | ConvertFrom-Json
            $Sent.automatic_security | Should -BeTrue
        }
    }

    It 'Asks once and sends default when Default is given and the answer is yes' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })
            Mock Confirm-SendGridContinue -ModuleName SendGridTools -MockWith { $true }

            $null = New-SGAuthenticatedDomain -Domain 'example.com' -Default -Confirm:$false

            Should -Invoke Confirm-SendGridContinue -ModuleName SendGridTools -Times 1 -Exactly -ParameterFilter {
                $Query -eq 'example.com' -and $Caption -ceq 'Setting this domain as the default domain will remove the current default domain. Do you want to continue?'
            }
            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Sent = $Calls[0].Body | ConvertFrom-Json
            $Sent.default | Should -BeTrue
        }
    }

    It 'Asks once and sends no default when Default is given and the answer is no' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })
            Mock Confirm-SendGridContinue -ModuleName SendGridTools -MockWith { $false }

            $null = New-SGAuthenticatedDomain -Domain 'example.com' -Default -Confirm:$false

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

            $null = New-SGAuthenticatedDomain -Domain 'example.com' -Default:$false -Confirm:$false

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

            $null = New-SGAuthenticatedDomain -Domain 'example.com' -Confirm:$false

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

            $null = New-SGAuthenticatedDomain -Domain 'example.com' -SendGridSubdomain 'email' -WhatIf

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 0
        }
    }
}

Describe 'New-SGAuthenticatedDomain binding' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Reads the syntax without calling Get-SGIPAddress' {
        Mock -CommandName Get-SGIPAddress -ModuleName SendGridTools -MockWith { throw 'Get-SGIPAddress must not be called' }

        $null = Get-Command -Name New-SGAuthenticatedDomain -Syntax

        Should -Invoke Get-SGIPAddress -ModuleName SendGridTools -Times 0 -Exactly
    }

    It 'Binds and runs under WhatIf without calling Get-SGIPAddress and sends nothing' {
        Mock -CommandName Get-SGIPAddress -ModuleName SendGridTools -MockWith { throw 'Get-SGIPAddress must not be called' }
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = New-SGAuthenticatedDomain -Domain 'example.com' -WhatIf

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 0
        }

        Should -Invoke Get-SGIPAddress -ModuleName SendGridTools -Times 0 -Exactly
    }

    It 'Sends both IP addresses in order without calling Get-SGIPAddress' {
        Mock -CommandName Get-SGIPAddress -ModuleName SendGridTools -MockWith { throw 'Get-SGIPAddress must not be called' }
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = New-SGAuthenticatedDomain -Domain 'example.com' -IPAddress '192.0.2.10', '192.0.2.11' -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            @(($Calls[0].Body | ConvertFrom-Json).ips) | Should -Be @('192.0.2.10', '192.0.2.11')
        }

        Should -Invoke Get-SGIPAddress -ModuleName SendGridTools -Times 0 -Exactly
    }

    It 'Sends an address the account does not offer as it is given' {
        Mock -CommandName Get-SGIPAddress -ModuleName SendGridTools -MockWith { throw 'Get-SGIPAddress must not be called' }
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = New-SGAuthenticatedDomain -Domain 'example.com' -IPAddress '198.51.100.7' -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            @(($Calls[0].Body | ConvertFrom-Json).ips) | Should -Be @('198.51.100.7')
        }
    }

    It 'Sends no ips without IPAddress' {
        Mock -CommandName Get-SGIPAddress -ModuleName SendGridTools -MockWith { throw 'Get-SGIPAddress must not be called' }
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = New-SGAuthenticatedDomain -Domain 'example.com' -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            ($Calls[0].Body | ConvertFrom-Json).PSObject.Properties.Name | Should -Not -Contain 'ips'
        }
    }

    It 'Declares IPAddress as an ordinary string array parameter with a completer and no position' {
        Mock -CommandName Get-SGIPAddress -ModuleName SendGridTools -MockWith { throw 'Get-SGIPAddress must not be called' }
        $Parameter = (Get-Command -Name New-SGAuthenticatedDomain).Parameters['IPAddress']

        $Parameter.ParameterType | Should -Be ([string[]])
        @($Parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count | Should -Be 0
        @($Parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ArgumentCompleterAttribute] }).Count | Should -Be 1
        $ParameterAttributes = @($Parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] })
        $ParameterAttributes.Count | Should -BeGreaterThan 0
        foreach ($Attribute in $ParameterAttributes) {
            $Attribute.Position | Should -Be ([int]::MinValue)
        }
    }

    It 'Binds a third positional argument to Username and sends no ips' {
        Mock -CommandName Get-SGIPAddress -ModuleName SendGridTools -MockWith { throw 'Get-SGIPAddress must not be called' }
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = New-SGAuthenticatedDomain 'example.com' 'email' 'subuser-placeholder' -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Sent = $Calls[0].Body | ConvertFrom-Json
            $Sent.username | Should -Be 'subuser-placeholder'
            $Sent.PSObject.Properties.Name | Should -Not -Contain 'ips'
        }
    }

    It 'Completes the IP addresses of the account' {
        # The completer script block is not bound to the module session state, so mock the command in both scopes.
        Mock -CommandName Get-SGIPAddress -ModuleName SendGridTools -MockWith { [pscustomobject]@{ Ip = '192.0.2.10' }, [pscustomobject]@{ Ip = '192.0.2.11' } }
        Mock -CommandName Get-SGIPAddress -MockWith { [pscustomobject]@{ Ip = '192.0.2.10' }, [pscustomobject]@{ Ip = '192.0.2.11' } }
        $Completer = (Get-Command -Name New-SGAuthenticatedDomain).Parameters['IPAddress'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ArgumentCompleterAttribute] }

        @(& $Completer.ScriptBlock 'New-SGAuthenticatedDomain' 'IPAddress' '' $null @{}) | Should -Be @('192.0.2.10', '192.0.2.11')
        @(& $Completer.ScriptBlock 'New-SGAuthenticatedDomain' 'IPAddress' '192.0.2.1' $null @{}) | Should -Be @('192.0.2.10', '192.0.2.11')
        @(& $Completer.ScriptBlock 'New-SGAuthenticatedDomain' 'IPAddress' '192.0.2.11' $null @{}) | Should -Be @('192.0.2.11')
    }

    It 'Completes nothing and does not throw when Get-SGIPAddress fails' {
        Mock -CommandName Get-SGIPAddress -ModuleName SendGridTools -MockWith { throw 'Get-SGIPAddress failed' }
        Mock -CommandName Get-SGIPAddress -MockWith { throw 'Get-SGIPAddress failed' }
        $Completer = (Get-Command -Name New-SGAuthenticatedDomain).Parameters['IPAddress'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ArgumentCompleterAttribute] }

        { $script:Completed = @(& $Completer.ScriptBlock 'New-SGAuthenticatedDomain' 'IPAddress' '' $null @{}) } | Should -Not -Throw
        $script:Completed.Count | Should -Be 0
    }

    It 'Offers CustomSPF only with DisableAutomaticSecurity and sends it without calling Get-SGIPAddress' {
        Mock -CommandName Get-SGIPAddress -ModuleName SendGridTools -MockWith { throw 'Get-SGIPAddress must not be called' }
        (Get-Command -Name New-SGAuthenticatedDomain).Parameters.Keys | Should -Not -Contain 'CustomSPF'
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = New-SGAuthenticatedDomain -Domain 'example.com' -DisableAutomaticSecurity -CustomSPF -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            ($Calls[0].Body | ConvertFrom-Json).custom_spf | Should -BeTrue
        }

        Should -Invoke Get-SGIPAddress -ModuleName SendGridTools -Times 0 -Exactly
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
