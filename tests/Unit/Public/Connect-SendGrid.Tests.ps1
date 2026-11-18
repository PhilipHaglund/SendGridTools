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

Describe 'Connect-SendGrid parameters' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Defaults to the Region parameter set' {
        (Get-Command Connect-SendGrid).DefaultParameterSet | Should -Be 'Region'
    }

    It 'Limits -Region to Global and EU' {
        $Set = (Get-Command Connect-SendGrid).Parameters['Region'].Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        @($Set.ValidValues) | Should -Be @('Global', 'EU')
    }

    It 'Keeps -Credential at Position 0 and -Force at Position 1' {
        $P = (Get-Command Connect-SendGrid).Parameters
        ($P['Credential'].Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } | Select-Object -First 1).Position | Should -Be 0
        ($P['Force'].Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } | Select-Object -First 1).Position | Should -Be 1
    }

    It 'Refuses -Region together with -BaseUri without a call' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            Set-SgtNetworkStub -Response ([pscustomobject]@{})
            { Connect-SendGrid -Credential $Cred -Region EU -BaseUri https://example.com } | Should -Throw -ErrorId 'AmbiguousParameterSet*'
            Get-SgtNetworkCall | Should -BeNullOrEmpty
        }
    }

    It 'Refuses a non-https -BaseUri without a call and leaves no session' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = $null
            Set-SgtNetworkStub -Response ([pscustomobject]@{})
            { Connect-SendGrid -Credential $Cred -BaseUri http://example.com } | Should -Throw 'Unable to connect to SendGrid. Error detail: The base URI*'
            Get-SgtNetworkCall | Should -BeNullOrEmpty
            $script:Session | Should -BeNullOrEmpty
        }
    }

    It 'Leaves an existing session untouched when -BaseUri is refused' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            Set-SgtNetworkStub -Response ([pscustomobject]@{})
            $Existing = New-SgtTestSession -Credential $Cred -AgeHours 0
            $script:Session = $Existing
            { Connect-SendGrid -Credential $Cred -BaseUri http://example.com } | Should -Throw 'Unable to connect to SendGrid*'
            [object]::ReferenceEquals($script:Session, $Existing) | Should -BeTrue
            Get-SgtNetworkCall | Should -BeNullOrEmpty
        }
    }

    It 'Does not put the user information of a refused -BaseUri in the error' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = $null
            Set-SgtNetworkStub -Response ([pscustomobject]@{})
            $Message = $null
            try { Connect-SendGrid -Credential $Cred -BaseUri 'http://user:pass@example.com' } catch { $Message = $_.Exception.Message }
            $Message | Should -BeLike 'Unable to connect to SendGrid*The base URI*'
            $Message | Should -Not -BeLike '*pass*'
            Get-SgtNetworkCall | Should -BeNullOrEmpty
        }
    }
}

Describe 'Connect-SendGrid base URL' {
    BeforeEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Set-SgtNetworkStub -Response ([pscustomobject]@{ scopes = @('scopes.read') })
        }
    }
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'Uses the global host when no new parameter is given' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            Connect-SendGrid -Credential $Cred
            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Get'
            "$($Calls[0].Uri)" | Should -Be 'https://api.sendgrid.com/v3/scopes'
            $script:Session._BaseURL.AbsoluteUri | Should -Be 'https://api.sendgrid.com/v3'
        }
    }

    It 'Connects to <Url> for <Label>' -ForEach @(
        @{ Label = '-Region Global'; Splat = @{ Region = 'Global' }; Url = 'https://api.sendgrid.com/v3/scopes' }
        @{ Label = '-Region EU'; Splat = @{ Region = 'EU' }; Url = 'https://api.eu.sendgrid.com/v3/scopes' }
        @{ Label = '-BaseUri'; Splat = @{ BaseUri = 'https://proxy.example.com' }; Url = 'https://proxy.example.com/v3/scopes' }
    ) {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Splat = $Splat; Url = $Url } {
            Connect-SendGrid -Credential $Cred @Splat
            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            "$($Calls[0].Uri)" | Should -Be $Url
        }
    }

    It 'Sends later commands to the host of the session' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            Connect-SendGrid -Credential $Cred -Region EU
            Set-SgtNetworkStub -Response ([pscustomobject]@{})
            $null = Invoke-SGCommand -Namespace subusers
            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            "$($Calls[0].Uri)" | Should -Be 'https://api.eu.sendgrid.com/v3/subusers'
        }
    }

    It 'Creates a new session for another region without -Force' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $Existing = New-SgtTestSession -Credential $Cred -AgeHours 0
            $script:Session = $Existing
            Connect-SendGrid -Credential $Cred -Region EU
            [object]::ReferenceEquals($script:Session, $Existing) | Should -BeFalse
            $script:Session._BaseURL.AbsoluteUri | Should -Be 'https://api.eu.sendgrid.com/v3'
            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            "$($Calls[0].Uri)" | Should -Be 'https://api.eu.sendgrid.com/v3/scopes'
        }
    }

    It 'Refreshes the existing session <Label>' -ForEach @(
        @{ Label = 'without new parameters'; Splat = @{} }
        @{ Label = 'for -Region Global'; Splat = @{ Region = 'Global' } }
    ) {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Splat = $Splat } {
            $Existing = New-SgtTestSession -Credential $Cred -AgeHours 0
            $script:Session = $Existing
            Connect-SendGrid @Splat
            [object]::ReferenceEquals($script:Session, $Existing) | Should -BeTrue
            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            "$($Calls[0].Uri)" | Should -Be 'https://api.sendgrid.com/v3/scopes'
        }
    }

    It 'Refreshes an existing EU session with a bare Connect-SendGrid' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $Existing = New-SgtTestSession -Credential $Cred -AgeHours 0
            $Existing._BaseURL = [uri]'https://api.eu.sendgrid.com/v3'
            $script:Session = $Existing
            Connect-SendGrid
            [object]::ReferenceEquals($script:Session, $Existing) | Should -BeTrue
            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Get'
            "$($Calls[0].Uri)" | Should -Be 'https://api.eu.sendgrid.com/v3/scopes'
        }
    }

    It 'Asks for the key again and does not reuse the old one when -Region names another host' {
        Mock -ModuleName SendGridTools Get-Credential { [pscredential]::new('apikey', (ConvertTo-SecureString -String 'test-key-b-not-real' -AsPlainText -Force)) }
        InModuleScope SendGridTools {
            $KeyA = [pscredential]::new('apikey', (ConvertTo-SecureString -String 'test-key-a-not-real' -AsPlainText -Force))
            $script:Session = New-SgtTestSession -Credential $KeyA -AgeHours 0
            Connect-SendGrid -Region EU
            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            "$($Calls[0].Uri)" | Should -Be 'https://api.eu.sendgrid.com/v3/scopes'
            $Calls[0].Headers.Authorization | Should -Be 'Bearer test-key-b-not-real'
            foreach ($Call in $Calls) { "$($Call.Headers.Authorization)" | Should -Not -BeLike '*test-key-a-not-real*' }
        }
    }

    It 'Connects to the global host with a positional credential' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            Connect-SendGrid $Cred
            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            "$($Calls[0].Uri)" | Should -Be 'https://api.sendgrid.com/v3/scopes'
        }
    }

    It 'Connects to the global host through the alias Connect-SG' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            Connect-SG -Credential $Cred
            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            "$($Calls[0].Uri)" | Should -Be 'https://api.sendgrid.com/v3/scopes'
        }
    }

    It 'Makes no call and keeps the session with -WhatIf' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $Existing = New-SgtTestSession -Credential $Cred -AgeHours 0
            $script:Session = $Existing
            Connect-SendGrid -Credential $Cred -Region EU -WhatIf
            Get-SgtNetworkCall | Should -BeNullOrEmpty
            [object]::ReferenceEquals($script:Session, $Existing) | Should -BeTrue
        }
    }

    It 'Keeps the API key out of the output of -Region EU with -Verbose' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $Leak = Get-SgtLeakText -Action { Connect-SendGrid -Credential $Cred -Region EU -Verbose }
            $Leak.Text | Should -Not -BeLike '*test-key-not-real*'
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
