BeforeDiscovery {
    $script:Cases = @(
        @{ Label = 'a plain password'; Plain = 'subuser-password-not-real' }
        @{ Label = 'a password JSON must escape'; Plain = 'subuser-password-not-real "\ x' }
    )
}

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

Describe 'New-SGSubuser request' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Sends username, email, password and ips for <Label>' -ForEach $script:Cases {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Plain = $Plain } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ username = 'subuser-placeholder'; user_id = 1; email = 'subuser@example.invalid' })

            $null = New-SGSubuser -Username 'subuser-placeholder' -Email 'subuser@example.invalid' -Password (ConvertTo-SecureString -String $Plain -AsPlainText -Force) -Ips '192.0.2.10' -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Post'
            "$($Calls[0].Uri)" | Should -BeLike '*/subusers'
            $Sent = $Calls[0].Body | ConvertFrom-Json
            @($Sent.PSObject.Properties.Name | Sort-Object) | Should -Be @('email', 'ips', 'password', 'username')
            $Sent.password | Should -BeExactly $Plain
            $Sent.username | Should -Be 'subuser-placeholder'
            $Sent.email | Should -Be 'subuser@example.invalid'
            @($Sent.ips) | Should -Be @('192.0.2.10')
        }
    }

    It 'Sends one Post per piped object with its own values' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ username = 'subuser-placeholder'; user_id = 1; email = 'subuser@example.invalid' })
            $Items = @(
                [pscustomobject]@{ Username = 'subuser-one'; Email = 'one@example.com'; Password = (ConvertTo-SecureString -String 'pw-one-not-real' -AsPlainText -Force); Ips = '192.0.2.10' }
                [pscustomobject]@{ Username = 'subuser-two'; Email = 'two@example.com'; Password = (ConvertTo-SecureString -String 'pw-two-not-real' -AsPlainText -Force); Ips = '192.0.2.11' }
            )

            $null = $Items | New-SGSubuser -Confirm:$false

            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 2
            $One = $Calls[0].Body | ConvertFrom-Json
            $One.username | Should -Be 'subuser-one'
            $One.email | Should -Be 'one@example.com'
            $One.password | Should -BeExactly 'pw-one-not-real'
            @($One.ips) | Should -Be @('192.0.2.10')
            $Two = $Calls[1].Body | ConvertFrom-Json
            $Two.username | Should -Be 'subuser-two'
            $Two.email | Should -Be 'two@example.com'
            $Two.password | Should -BeExactly 'pw-two-not-real'
            @($Two.ips) | Should -Be @('192.0.2.11')
        }
    }
}

Describe 'New-SGSubuser password exposure' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Does not show the password (<Scenario>)' -ForEach @(
        @{ Scenario = 'success' }
        @{ Scenario = 'failure with error details' }
        @{ Scenario = 'failure without error details' }
    ) {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Scenario = $Scenario } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            switch ($Scenario) {
                'success' { Set-SgtNetworkStub -Response ([pscustomobject]@{ username = 'subuser-placeholder'; user_id = 1; email = 'subuser@example.invalid' }) }
                'failure with error details' { Set-SgtNetworkStub -Throw (New-SgtErrorRecord -Message 'http failure' -Details '{"errors":[{"message":"bad request"}]}') }
                default { Set-SgtNetworkStub -Throw (New-SgtErrorRecord -Message 'http failure') }
            }
            $Password = ConvertTo-SecureString -String 'subuser-password-not-real' -AsPlainText -Force

            $Leak = Get-SgtLeakText -Action { New-SGSubuser -Username 'subuser-placeholder' -Email 'subuser@example.invalid' -Password $Password -Ips '192.0.2.10' -Confirm:$false }

            $Leak.Threw | Should -Be ($Scenario -ne 'success')
            $Leak.Text | Should -Not -BeLike '*subuser-password-not-real*'

            @($Leak.Output | Where-Object { $_ -is [System.Collections.IDictionary] }).Count | Should -Be 0

            if ($Scenario -eq 'success') {
                @($Leak.Output).Count | Should -Be 1
                $Leak.Output[0].Username | Should -Be 'subuser-placeholder'
            }
        }
    }

    It 'Shows the body keys in verbose (positive control)' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ username = 'subuser-placeholder'; user_id = 1; email = 'subuser@example.invalid' })
            $Password = ConvertTo-SecureString -String 'subuser-password-not-real' -AsPlainText -Force

            $Leak = Get-SgtLeakText -Action { New-SGSubuser -Username 'subuser-placeholder' -Email 'subuser@example.invalid' -Password $Password -Ips '192.0.2.10' -Confirm:$false }

            $Leak.Verbose | Should -BeLike '*ContentBody: Key: password, Type: System.String*'
        }
    }

    It 'Sends nothing and shows no password with -WhatIf' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ username = 'subuser-placeholder' })
            $Password = ConvertTo-SecureString -String 'subuser-password-not-real' -AsPlainText -Force

            $Leak = Get-SgtLeakText -Action { New-SGSubuser -Username 'subuser-placeholder' -Email 'subuser@example.invalid' -Password $Password -Ips '192.0.2.10' -WhatIf }

            Get-SgtNetworkCall | Should -BeNullOrEmpty
            $Leak.Text | Should -Not -BeLike '*subuser-password-not-real*'
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
