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
Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
