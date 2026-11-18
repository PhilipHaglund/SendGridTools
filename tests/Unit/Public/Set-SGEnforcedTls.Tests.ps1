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

Describe 'Set-SGEnforcedTls request' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Sends only <Keys> for <Label>' -ForEach @(
        @{ Label = '-RequireTls'; Keys = 'require_tls'; Splat = @{ RequireTls = $true } }
        @{ Label = '-RequireValidCert'; Keys = 'require_valid_cert'; Splat = @{ RequireValidCert = $true } }
        @{ Label = '-Version'; Keys = 'version'; Splat = @{ Version = '1.2' } }
        @{ Label = '-RequireTls -RequireValidCert'; Keys = 'require_tls require_valid_cert'; Splat = @{ RequireTls = $true; RequireValidCert = $true } }
        @{ Label = '-RequireTls -Version'; Keys = 'require_tls version'; Splat = @{ RequireTls = $true; Version = '1.2' } }
        @{ Label = '-RequireValidCert -Version'; Keys = 'require_valid_cert version'; Splat = @{ RequireValidCert = $true; Version = '1.2' } }
        @{ Label = 'all three'; Keys = 'require_tls require_valid_cert version'; Splat = @{ RequireTls = $true; RequireValidCert = $true; Version = '1.2' } }
    ) {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Keys = $Keys; Splat = $Splat } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ require_tls = $true })

            $null = Set-SGEnforcedTls @Splat -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Patch'
            "$($Calls[0].Uri)" | Should -BeLike '*/v3/user/settings/enforced_tls'
            $Names = @(($Calls[0].Body | ConvertFrom-Json).PSObject.Properties.Name | Sort-Object)
            $Names | Should -Be @($Keys -split ' ')
        }
    }

    It 'Sends false for -RequireTls:$false' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ require_tls = $false })

            $null = Set-SGEnforcedTls -RequireTls:$false -Confirm:$false

            $Body = (Get-SgtNetworkCall)[0].Body | ConvertFrom-Json
            $Body.require_tls | Should -BeFalse
            $Body.require_tls | Should -BeOfType [bool]
        }
    }

    It 'Sends false for -RequireValidCert:$false' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ require_valid_cert = $false })

            $null = Set-SGEnforcedTls -RequireValidCert:$false -Confirm:$false

            $Body = (Get-SgtNetworkCall)[0].Body | ConvertFrom-Json
            $Body.require_valid_cert | Should -BeFalse
            $Body.require_valid_cert | Should -BeOfType [bool]
        }
    }

    It 'Sends -Version <Version> as a number' -ForEach @(
        @{ Version = '1.1' }
        @{ Version = '1.2' }
        @{ Version = '1.3' }
    ) {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Version = $Version } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ version = 1.2 })

            $null = Set-SGEnforcedTls -Version $Version -Confirm:$false

            $Raw = (Get-SgtNetworkCall)[0].Body
            $Raw | Should -Match ('"version":\s*{0}[,}}\s]' -f [regex]::Escape($Version))
            $Raw | Should -Not -Match ('"{0}"' -f [regex]::Escape($Version))
        }
    }

    It 'Sends -Version as a number under sv-SE' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ version = 1.2 })
            $Thread = [System.Threading.Thread]::CurrentThread
            $Original = $Thread.CurrentCulture
            try {
                $Thread.CurrentCulture = [cultureinfo]::GetCultureInfo('sv-SE')
                $null = Set-SGEnforcedTls -Version '1.2' -Confirm:$false
            }
            finally {
                $Thread.CurrentCulture = $Original
            }

            $Raw = (Get-SgtNetworkCall)[0].Body
            $Raw | Should -Match '"version":\s*1\.2[,}\s]'
            $Raw | Should -Not -Match '"1\.2"'
        }
    }

    It 'Refuses -Version 1.0 and makes no call' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{})

            { Set-SGEnforcedTls -Version '1.0' -Confirm:$false } | Should -Throw

            (Get-SgtNetworkCall).Count | Should -Be 0
        }
    }

    It 'Refuses a call without a setting and makes no call' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{})

            { Set-SGEnforcedTls -Confirm:$false } | Should -Throw '*-RequireTls*-RequireValidCert*-Version*'

            (Get-SgtNetworkCall).Count | Should -Be 0
        }
    }

    It 'Refuses a call with only -OnBehalfOf and makes no call' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{})

            { Set-SGEnforcedTls -OnBehalfOf 'subuser-placeholder' -Confirm:$false } | Should -Throw '*-RequireTls*-RequireValidCert*-Version*'

            (Get-SgtNetworkCall).Count | Should -Be 0
        }
    }

    It 'Makes no call with -WhatIf' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{})

            $null = Set-SGEnforcedTls -RequireTls -WhatIf

            (Get-SgtNetworkCall).Count | Should -Be 0
        }
    }

    It 'Has ConfirmImpact High' {
        $Attribute = (Get-Command -Name Set-SGEnforcedTls).ScriptBlock.Attributes | Where-Object { $_ -is [System.Management.Automation.CmdletBindingAttribute] }
        $Attribute.ConfirmImpact | Should -Be 'High'
        $Attribute.SupportsShouldProcess | Should -BeTrue
    }

    It 'Sends -OnBehalfOf as the on-behalf-of header' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ require_tls = $true })

            $null = Set-SGEnforcedTls -RequireTls -OnBehalfOf 'subuser-placeholder' -Confirm:$false

            (Get-SgtNetworkCall)[0].Headers['on-behalf-of'] | Should -Be 'subuser-placeholder'
        }
    }

    It 'Returns only the response and no dictionary' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ require_tls = $true; require_valid_cert = $false; version = 1.2 })

            $Out = @(Set-SGEnforcedTls -RequireTls -Confirm:$false)

            @($Out | Where-Object { $_ -is [System.Collections.IDictionary] }).Count | Should -Be 0
            $Out.Count | Should -Be 1
        }
    }

    It 'Wraps an API error' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Throw (New-SgtErrorRecord -Message 'boom')

            { Set-SGEnforcedTls -RequireTls -Confirm:$false } | Should -Throw 'Failed to update SendGrid Enforced TLS settings.*'
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
