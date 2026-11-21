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

# The commands whose InputObject parameter set Sprint 1 step 3 changed. A Write-Error with
# -ErrorAction Stop inside the command ends the whole pipeline, so the items after the bad one are not sent.
Describe 'Mixed good and bad piped input' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Sends the item before the bad one and stops for <Command>' -ForEach @(
        @{ Command = 'Remove-SGSuppressionGroup'; Method = 'Delete'; Tail = '/asm/groups/1001' }
        @{ Command = 'Remove-SGAlert'; Method = 'Delete'; Tail = '/alerts/1001' }
        @{ Command = 'Set-SGSuppressionGroup'; Method = 'Patch'; Tail = '/asm/groups/1001' }
    ) {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Command = $Command; Method = $Method; Tail = $Tail } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            if ($Command -eq 'Set-SGSuppressionGroup') {
                { $null = 1001, 'abc', 1002 | Set-SGSuppressionGroup -Name 'name-placeholder' -Confirm:$false } |
                    Should -Throw -ExpectedMessage '*Failed to convert InputObject to Id.*'
            }
            else {
                { $null = 1001, 'abc', 1002 | & $Command -Confirm:$false } |
                    Should -Throw -ExpectedMessage '*Failed to convert InputObject to Id.*'
            }

            $Calls = @(Get-SgtNetworkCall | ForEach-Object { $_ })
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be $Method
            $Calls[0].Uri.AbsoluteUri | Should -BeLike "*$Tail"
        }
    }

    It 'Sends the address before the bad one and stops for Remove-SGGlobalSuppression' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            { $null = 'one@example.com', 'not an address', 'two@example.com' | Remove-SGGlobalSuppression -Confirm:$false } |
                Should -Throw -ExpectedMessage '*Failed to convert InputObject to an email address.*'

            $Calls = @(Get-SgtNetworkCall | ForEach-Object { $_ })
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Delete'
            $Calls[0].Uri.AbsoluteUri | Should -BeLike '*/suppression/unsubscribes/one%40example.com'
        }
    }
}

Describe 'A [MailAddress] from the pipeline' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Sends one Delete for Remove-SGGlobalSuppression' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = [MailAddress]'one@example.com' | Remove-SGGlobalSuppression -Confirm:$false

            $Calls = @(Get-SgtNetworkCall | ForEach-Object { $_ })
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Delete'
            $Calls[0].Uri.AbsoluteUri | Should -BeLike '*/suppression/unsubscribes/one%40example.com'
        }
    }

    # The InputObject switch of these four commands takes a [MailAddress] and uses its Address, as
    # Remove-SGGlobalSuppression does, so the call equals the call for the same address as a string.
    It 'Sends one call with only the address for a piped [MailAddress] to <Command>' -ForEach @(
        @{ Command = 'Remove-SGBlock' }
        @{ Command = 'Remove-SGBounce' }
        @{ Command = 'Remove-SGInvalidEmail' }
        @{ Command = 'Remove-SGSpamReport' }
    ) {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Command = $Command } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = 'one@example.com' | & $Command -Confirm:$false
            $StringCalls = @(Get-SgtNetworkCall | ForEach-Object { $_ })
            $StringCalls.Count | Should -Be 1

            Reset-SgtNetworkStub
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = [MailAddress]'one@example.com' | & $Command -Confirm:$false
            $Calls = @(Get-SgtNetworkCall | ForEach-Object { $_ })
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be $StringCalls[0].Method
            $Calls[0].Uri.AbsoluteUri | Should -Be $StringCalls[0].Uri.AbsoluteUri
            "$($Calls[0].Body)" | Should -Be "$($StringCalls[0].Body)"
        }
    }

    It 'Sends no display name for a piped [MailAddress] with one to <Command>' -ForEach @(
        @{ Command = 'Remove-SGBlock' }
        @{ Command = 'Remove-SGBounce' }
        @{ Command = 'Remove-SGInvalidEmail' }
        @{ Command = 'Remove-SGSpamReport' }
    ) {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Command = $Command } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = [MailAddress]::new('one@example.com', 'Sgt Name') | & $Command -Confirm:$false

            $Calls = @(Get-SgtNetworkCall | ForEach-Object { $_ })
            $Calls.Count | Should -Be 1
            $Calls[0].Uri.AbsoluteUri | Should -Not -BeLike '*Sgt*'
            "$($Calls[0].Body)" | Should -Not -BeLike '*Sgt*'
            "$($Calls[0].Uri.AbsoluteUri) $($Calls[0].Body)" | Should -BeLike '*one*example.com*'
        }
    }

    It 'Sends what two strings send for a string and a [MailAddress] piped together to <Command>' -ForEach @(
        @{ Command = 'Remove-SGBlock' }
        @{ Command = 'Remove-SGBounce' }
        @{ Command = 'Remove-SGInvalidEmail' }
        @{ Command = 'Remove-SGSpamReport' }
    ) {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Command = $Command } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = 'one@example.com', 'two@example.com' | & $Command -Confirm:$false
            $StringCalls = @(Get-SgtNetworkCall | ForEach-Object { $_ })

            Reset-SgtNetworkStub
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = 'one@example.com', [MailAddress]'two@example.com' | & $Command -Confirm:$false
            $Calls = @(Get-SgtNetworkCall | ForEach-Object { $_ })

            $Calls.Count | Should -Be $StringCalls.Count
            for ($Index = 0; $Index -lt $Calls.Count; $Index++) {
                $Calls[$Index].Method | Should -Be $StringCalls[$Index].Method
                $Calls[$Index].Uri.AbsoluteUri | Should -Be $StringCalls[$Index].Uri.AbsoluteUri
                "$($Calls[$Index].Body)" | Should -Be "$($StringCalls[$Index].Body)"
            }
        }
    }

    It 'Sends one Post for Add-SGGlobalSuppression' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            $null = [MailAddress]'one@example.com' | Add-SGGlobalSuppression -Confirm:$false

            $Calls = @(Get-SgtNetworkCall | ForEach-Object { $_ })
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Post'
            $Calls[0].Uri.AbsoluteUri | Should -BeLike '*/suppression/unsubscribes'
            "$($Calls[0].Body)" | Should -BeLike '*one@example.com*'
        }
    }
}

Describe '-OnBehalfOf with piped input' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Sends the header on every request for <Command>' -ForEach @(
        @{ Command = 'Remove-SGSuppressionGroup'; Items = @(1001, 1002) }
        @{ Command = 'Set-SGSuppressionGroup'; Items = @(1001, 1002) }
        @{ Command = 'Remove-SGAlert'; Items = @(1001, 1002) }
        @{ Command = 'Remove-SGGlobalSuppression'; Items = @('one@example.com', 'two@example.com') }
    ) {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Command = $Command; Items = $Items } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })

            if ($Command -eq 'Set-SGSuppressionGroup') {
                $null = $Items | Set-SGSuppressionGroup -Name 'name-placeholder' -OnBehalfOf 'subuser-placeholder' -Confirm:$false
            }
            else {
                $null = $Items | & $Command -OnBehalfOf 'subuser-placeholder' -Confirm:$false
            }

            $Calls = @(Get-SgtNetworkCall | ForEach-Object { $_ })
            $Calls.Count | Should -Be 2
            foreach ($Call in $Calls) {
                $Call.Headers['on-behalf-of'] | Should -BeExactly 'subuser-placeholder'
            }
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
