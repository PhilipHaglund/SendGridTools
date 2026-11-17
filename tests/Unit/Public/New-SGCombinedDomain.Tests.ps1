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
    # The authenticated domain command has a DynamicParam block that calls Get-SGIPAddress; answer it in module scope.
    Mock -CommandName Get-SGIPAddress -ModuleName SendGridTools -MockWith { [pscustomobject]@{ Ip = '192.0.2.10' } }
}

AfterAll {
    Uninstall-SgtSessionHelper
    Disable-SgtNetworkTripwire
}

Describe 'New-SGCombinedDomain request' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Sends the subdomain it is given to both the authenticated domain and the branded link' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = New-SGCombinedDomain -Domain 'example.com' -SendGridSubDomain 'email' -Confirm:$false

            $All = Get-SgtNetworkCall
            $Calls = @($All | Where-Object { $_.Method -ne 'Get' })
            $Calls.Count | Should -Be 2
            $Calls[0].Method | Should -Be 'Post'
            "$($Calls[0].Uri)" | Should -BeLike '*/whitelabel/domains'
            $SentDomain = $Calls[0].Body | ConvertFrom-Json
            $SentDomain.subdomain | Should -Be 'email'
            $Calls[1].Method | Should -Be 'Post'
            "$($Calls[1].Uri)" | Should -BeLike '*/whitelabel/links'
            $SentLink = $Calls[1].Body | ConvertFrom-Json
            $SentLink.subdomain | Should -Be 'email'
        }
    }

    It 'Sends no subdomain when none is given' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = New-SGCombinedDomain -Domain 'example.com' -Confirm:$false

            $All = Get-SgtNetworkCall
            $Calls = @($All | Where-Object { $_.Method -ne 'Get' })
            $Calls.Count | Should -Be 2
            $Calls[0].Method | Should -Be 'Post'
            $Calls[1].Method | Should -Be 'Post'
            $SentDomain = $Calls[0].Body | ConvertFrom-Json
            $SentLink = $Calls[1].Body | ConvertFrom-Json
            @($SentDomain.PSObject.Properties.Name | Sort-Object) | Should -Be @('automatic_security', 'domain')
            @($SentLink.PSObject.Properties.Name | Sort-Object) | Should -Be @('domain')
        }
    }

    It 'Sends the manual security flags and the subdomain to the authenticated domain and only the domain and subdomain to the link' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = New-SGCombinedDomain -Domain 'example.com' -SendGridSubDomain 'email' -DisableAutomaticSecurity -CustomSPF -Confirm:$false

            $All = Get-SgtNetworkCall
            $Calls = @($All | Where-Object { $_.Method -ne 'Get' })
            $Calls.Count | Should -Be 2
            $SentDomain = $Calls[0].Body | ConvertFrom-Json
            @($SentDomain.PSObject.Properties.Name | Sort-Object) | Should -Be @('automatic_security', 'custom_spf', 'domain', 'subdomain')
            $SentDomain.automatic_security | Should -BeFalse
            $SentDomain.custom_spf | Should -BeTrue
            $SentDomain.subdomain | Should -Be 'email'
            $SentLink = $Calls[1].Body | ConvertFrom-Json
            @($SentLink.PSObject.Properties.Name | Sort-Object) | Should -Be @('domain', 'subdomain')
        }
    }

    It 'Sends no custom SPF flag when only automatic security is disabled' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = New-SGCombinedDomain -Domain 'example.com' -DisableAutomaticSecurity -Confirm:$false

            $All = Get-SgtNetworkCall
            $Calls = @($All | Where-Object { $_.Method -ne 'Get' })
            $Calls.Count | Should -Be 2
            $SentDomain = $Calls[0].Body | ConvertFrom-Json
            @($SentDomain.PSObject.Properties.Name | Sort-Object) | Should -Be @('automatic_security', 'domain')
            $SentDomain.automatic_security | Should -BeFalse
        }
    }

    It 'Throws and makes no call when custom SPF is given without disabling automatic security' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            { New-SGCombinedDomain -Domain 'example.com' -CustomSPF -Confirm:$false } | Should -Throw -ExpectedMessage '*CustomSPF parameter can only be used with the DisableAutomaticSecurity parameter*'

            $All = Get-SgtNetworkCall
            $Calls = @($All | Where-Object { $_.Method -ne 'Get' })
            $Calls.Count | Should -Be 0
        }
    }

    It 'Makes no call under WhatIf' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = New-SGCombinedDomain -Domain 'example.com' -SendGridSubDomain 'email' -WhatIf

            $All = Get-SgtNetworkCall
            $Calls = @($All | Where-Object { $_.Method -ne 'Get' })
            $Calls.Count | Should -Be 0
        }
    }
}

Describe 'New-SGCombinedDomain forwarding' {
    BeforeEach {
        Mock -CommandName New-SGAuthenticatedDomain -ModuleName SendGridTools -MockWith { }
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })
        }
    }

    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Forwards neither security switch when neither is given' {
        InModuleScope SendGridTools {
            $null = New-SGCombinedDomain -Domain 'example.com' -Confirm:$false
        }

        Should -Invoke New-SGAuthenticatedDomain -ModuleName SendGridTools -Times 1 -Exactly -ParameterFilter {
            -not $PesterBoundParameters.ContainsKey('CustomSPF') -and -not $PesterBoundParameters.ContainsKey('DisableAutomaticSecurity')
        }
    }

    It 'Forwards only DisableAutomaticSecurity when custom SPF is not given' {
        InModuleScope SendGridTools {
            $null = New-SGCombinedDomain -Domain 'example.com' -DisableAutomaticSecurity -Confirm:$false
        }

        Should -Invoke New-SGAuthenticatedDomain -ModuleName SendGridTools -Times 1 -Exactly -ParameterFilter {
            $PesterBoundParameters['DisableAutomaticSecurity'] -eq $true -and -not $PesterBoundParameters.ContainsKey('CustomSPF')
        }
    }

    It 'Forwards both switches when both are given' {
        InModuleScope SendGridTools {
            $null = New-SGCombinedDomain -Domain 'example.com' -DisableAutomaticSecurity -CustomSPF -Confirm:$false
        }

        Should -Invoke New-SGAuthenticatedDomain -ModuleName SendGridTools -Times 1 -Exactly -ParameterFilter {
            $PesterBoundParameters['DisableAutomaticSecurity'] -eq $true -and $PesterBoundParameters['CustomSPF'] -eq $true
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
