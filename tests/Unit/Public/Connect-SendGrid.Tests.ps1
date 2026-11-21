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
        Mock -ModuleName SendGridTools Test-SendGridHostCanPrompt { $true }
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

Describe 'Connect-SendGrid -ApiKey and a host that cannot prompt' {
    BeforeAll {
        $script:ApiKey = ConvertTo-SecureString -String 'test-apikey-not-real' -AsPlainText -Force
    }
    BeforeEach {
        Mock -ModuleName SendGridTools Get-Credential { [pscredential]::new('apikey', (ConvertTo-SecureString -String 'test-key-asked-not-real' -AsPlainText -Force)) }
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

    It 'Declares -ApiKey as a securestring without a position in both parameter sets' {
        $Parameter = (Get-Command Connect-SendGrid).Parameters['ApiKey']
        $Parameter.ParameterType | Should -Be ([securestring])
        $Attributes = @($Parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] })
        $Attributes.Count | Should -Be 1
        $Attributes[0].Position | Should -Be ([int]::MinValue)
        $Attributes[0].ParameterSetName | Should -Be '__AllParameterSets'
        $Attributes[0].Mandatory | Should -BeFalse
        $Parameter.ParameterSets.Keys | Should -Contain '__AllParameterSets'
    }

    It 'Connects with -ApiKey without Get-Credential and keeps the key in the session' {
        Mock -ModuleName SendGridTools Test-SendGridHostCanPrompt { $false }
        InModuleScope SendGridTools -Parameters @{ ApiKey = $script:ApiKey } {
            Connect-SendGrid -ApiKey $ApiKey
            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            "$($Calls[0].Uri)" | Should -Be 'https://api.sendgrid.com/v3/scopes'
            $Calls[0].Headers.Authorization | Should -Be 'Bearer test-apikey-not-real'
            Set-SgtNetworkStub -Response ([pscustomobject]@{})
            $null = Invoke-SGCommand -Namespace subusers
            $Later = Get-SgtNetworkCall
            $Later.Count | Should -Be 1
            $Later[0].Headers.Authorization | Should -Be 'Bearer test-apikey-not-real'
        }
        Should -Invoke -ModuleName SendGridTools Get-Credential -Times 0 -Exactly
    }

    It 'Connects with -ApiKey to <Url> for <Label>' -ForEach @(
        @{ Label = '-Region EU'; Splat = @{ Region = 'EU' }; Url = 'https://api.eu.sendgrid.com/v3/scopes' }
        @{ Label = '-BaseUri'; Splat = @{ BaseUri = 'https://proxy.example.com' }; Url = 'https://proxy.example.com/v3/scopes' }
    ) {
        Mock -ModuleName SendGridTools Test-SendGridHostCanPrompt { $false }
        InModuleScope SendGridTools -Parameters @{ ApiKey = $script:ApiKey; Splat = $Splat; Url = $Url } {
            Connect-SendGrid -ApiKey $ApiKey @Splat
            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            "$($Calls[0].Uri)" | Should -Be $Url
            $Calls[0].Headers.Authorization | Should -Be 'Bearer test-apikey-not-real'
        }
        Should -Invoke -ModuleName SendGridTools Get-Credential -Times 0 -Exactly
    }

    It 'Refuses -ApiKey with -Credential without a call and leaves the session' {
        Mock -ModuleName SendGridTools Test-SendGridHostCanPrompt { $true }
        InModuleScope SendGridTools -Parameters @{ ApiKey = $script:ApiKey; Cred = $script:Cred } {
            $Existing = New-SgtTestSession -Credential $Cred -AgeHours 0
            $script:Session = $Existing
            { Connect-SendGrid -ApiKey $ApiKey -Credential $Cred } | Should -Throw 'Unable to connect to SendGrid. Error detail: Use either -Credential or -ApiKey, not both.'
            [object]::ReferenceEquals($script:Session, $Existing) | Should -BeTrue
            (Get-SgtNetworkCall).Count | Should -Be 0
        }
        Should -Invoke -ModuleName SendGridTools Get-Credential -Times 0 -Exactly
    }

    It 'Refuses to prompt in a host that cannot prompt: <Label>' -ForEach @(
        @{ Label = 'no session'; Splat = @{}; Existing = $false }
        @{ Label = '-Force over a session'; Splat = @{ Force = $true }; Existing = $true }
        @{ Label = '-Region EU over a global session'; Splat = @{ Region = 'EU' }; Existing = $true }
        @{ Label = '-Region EU with -WhatIf'; Splat = @{ Region = 'EU'; WhatIf = $true }; Existing = $true }
    ) {
        Mock -ModuleName SendGridTools Test-SendGridHostCanPrompt { $false }
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Splat = $Splat; HasExisting = $Existing } {
            $Existing = $null
            if ($HasExisting) {
                $Existing = New-SgtTestSession -Credential $Cred -AgeHours 0
                $script:Session = $Existing
            }
            { Connect-SendGrid @Splat } | Should -Throw '*-Credential*-ApiKey*'
            (Get-SgtNetworkCall).Count | Should -Be 0
            if ($HasExisting) {
                [object]::ReferenceEquals($script:Session, $Existing) | Should -BeTrue
            }
            else {
                $script:Session | Should -BeNullOrEmpty
            }
        }
        Should -Invoke -ModuleName SendGridTools Get-Credential -Times 0 -Exactly
    }

    It 'Asks with Get-Credential in an interactive host' {
        Mock -ModuleName SendGridTools Test-SendGridHostCanPrompt { $true }
        InModuleScope SendGridTools {
            Connect-SendGrid
            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Headers.Authorization | Should -Be 'Bearer test-key-asked-not-real'
        }
        Should -Invoke -ModuleName SendGridTools Get-Credential -Times 1 -Exactly
    }

    It 'Refreshes an existing session without a key in a host that cannot prompt' {
        Mock -ModuleName SendGridTools Test-SendGridHostCanPrompt { $false }
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $Existing = New-SgtTestSession -Credential $Cred -AgeHours 0
            $script:Session = $Existing
            { Connect-SendGrid } | Should -Not -Throw
            (Get-SgtNetworkCall).Count | Should -Be 1
            [object]::ReferenceEquals($script:Session, $Existing) | Should -BeTrue
        }
        Should -Invoke -ModuleName SendGridTools Get-Credential -Times 0 -Exactly
    }

    It 'Makes no call with -ApiKey and -WhatIf' {
        Mock -ModuleName SendGridTools Test-SendGridHostCanPrompt { $false }
        InModuleScope SendGridTools -Parameters @{ ApiKey = $script:ApiKey } {
            Connect-SendGrid -ApiKey $ApiKey -WhatIf
            (Get-SgtNetworkCall).Count | Should -Be 0
            $script:Session | Should -BeNullOrEmpty
        }
        Should -Invoke -ModuleName SendGridTools Get-Credential -Times 0 -Exactly
    }

    It 'Keeps -ApiKey out of verbose, debug and error output' {
        Mock -ModuleName SendGridTools Test-SendGridHostCanPrompt { $false }
        InModuleScope SendGridTools -Parameters @{ ApiKey = $script:ApiKey; Cred = $script:Cred } {
            $Success = Get-SgtLeakText -Action { $DebugPreference = 'Continue'; Connect-SendGrid -ApiKey $ApiKey -Verbose }
            $Success.Text | Should -Not -BeLike '*test-apikey-not-real*'
            $Refused = Get-SgtLeakText -Action { $DebugPreference = 'Continue'; Connect-SendGrid -ApiKey $ApiKey -Credential $Cred -Verbose }
            $Refused.Threw | Should -BeTrue
            $Refused.Text | Should -Not -BeLike '*test-apikey-not-real*'
        }
    }
}

Describe 'Connect-SendGrid refresh with a given key (D9)' {
    BeforeAll {
        $script:OldCred = [pscredential]::new('apikey', (ConvertTo-SecureString -String 'test-key-old-not-real' -AsPlainText -Force))
        $script:NewCred = [pscredential]::new('apikey', (ConvertTo-SecureString -String 'test-key-new-not-real' -AsPlainText -Force))
        $script:NewKey = ConvertTo-SecureString -String 'test-key-new-not-real' -AsPlainText -Force
    }
    BeforeEach {
        Mock -ModuleName SendGridTools Get-Credential { throw 'Get-Credential must not be called' }
        Mock -ModuleName SendGridTools Test-SendGridHostCanPrompt { $true }
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

    It 'Verifies and keeps a new key given with -Credential on the same host' {
        InModuleScope SendGridTools -Parameters @{ Old = $script:OldCred; New = $script:NewCred } {
            $Existing = New-SgtTestSession -Credential $Old -AgeHours 0.5
            $script:Session = $Existing
            Connect-SendGrid -Credential $New
            [object]::ReferenceEquals($script:Session, $Existing) | Should -BeTrue
            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            "$($Calls[0].Method)" | Should -Be 'Get'
            "$($Calls[0].Uri)" | Should -Be 'https://api.sendgrid.com/v3/scopes'
            $Calls[0].Headers.Authorization | Should -Be 'Bearer test-key-new-not-real'
            $script:Session._Credential.GetNetworkCredential().Password | Should -Be 'test-key-new-not-real'
            $script:Session._CreateDateTime | Should -BeGreaterThan (Get-Date).AddMinutes(-1)
            $script:Session._Connected | Should -BeTrue
        }
        Should -Invoke -ModuleName SendGridTools Get-Credential -Times 0 -Exactly
    }

    It 'Verifies and keeps a new key given with -ApiKey on the same host' {
        InModuleScope SendGridTools -Parameters @{ Old = $script:OldCred; NewKey = $script:NewKey } {
            $Existing = New-SgtTestSession -Credential $Old -AgeHours 0.5
            $script:Session = $Existing
            Connect-SendGrid -ApiKey $NewKey
            [object]::ReferenceEquals($script:Session, $Existing) | Should -BeTrue
            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            "$($Calls[0].Method)" | Should -Be 'Get'
            "$($Calls[0].Uri)" | Should -Be 'https://api.sendgrid.com/v3/scopes'
            $Calls[0].Headers.Authorization | Should -Be 'Bearer test-key-new-not-real'
            $script:Session._Credential.UserName | Should -Be 'apikey'
            $script:Session._Credential.GetNetworkCredential().Password | Should -Be 'test-key-new-not-real'
            $script:Session._CreateDateTime | Should -BeGreaterThan (Get-Date).AddMinutes(-1)
            $script:Session._Connected | Should -BeTrue
        }
        Should -Invoke -ModuleName SendGridTools Get-Credential -Times 0 -Exactly
    }

    It 'Keeps the EU host of the session when a key is given (<Label>)' -ForEach @(
        @{ Label = 'no region'; Splat = @{} }
        @{ Label = '-Region EU'; Splat = @{ Region = 'EU' } }
    ) {
        InModuleScope SendGridTools -Parameters @{ Old = $script:OldCred; New = $script:NewCred; Splat = $Splat } {
            $Existing = New-SgtTestSession -Credential $Old -AgeHours 0.5
            $Existing._BaseURL = [uri]'https://api.eu.sendgrid.com/v3'
            $script:Session = $Existing
            Connect-SendGrid -Credential $New @Splat
            [object]::ReferenceEquals($script:Session, $Existing) | Should -BeTrue
            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            "$($Calls[0].Uri)" | Should -Be 'https://api.eu.sendgrid.com/v3/scopes'
            $Calls[0].Headers.Authorization | Should -Be 'Bearer test-key-new-not-real'
            $script:Session._BaseURL.AbsoluteUri | Should -Be 'https://api.eu.sendgrid.com/v3'
        }
    }

    It 'Writes the refreshed-with-key verbose line' {
        InModuleScope SendGridTools -Parameters @{ Old = $script:OldCred; New = $script:NewCred } {
            $script:Session = New-SgtTestSession -Credential $Old -AgeHours 0.5
            $Streams = Connect-SendGrid -Credential $New -Verbose 4>&1
            $Messages = @($Streams | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $_.Message })
            $Messages | Should -Contain 'Existing connection to SendGrid refreshed with the given API key.'
            $Messages | Should -Not -Contain 'Existing connection to SendGrid refreshed.'
        }
    }

    It 'Refreshes without a key exactly as before' {
        InModuleScope SendGridTools -Parameters @{ Old = $script:OldCred } {
            $Existing = New-SgtTestSession -Credential $Old -AgeHours 0.5
            $script:Session = $Existing
            $Streams = Connect-SendGrid -Verbose 4>&1
            $Messages = @($Streams | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $_.Message })
            [object]::ReferenceEquals($script:Session, $Existing) | Should -BeTrue
            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Headers.Authorization | Should -Be 'Bearer test-key-old-not-real'
            $Messages | Should -Contain 'Existing connection to SendGrid refreshed.'
            $Messages | Should -Not -Contain 'Existing connection to SendGrid refreshed with the given API key.'
        }
        Should -Invoke -ModuleName SendGridTools Get-Credential -Times 0 -Exactly
        InModuleScope SendGridTools -Parameters @{ Old = $script:OldCred } {
            Set-SgtNetworkStub -Response ([pscustomobject]@{ scopes = @('scopes.read') })
            $script:Session = New-SgtTestSession -Credential $Old -AgeHours 2
            { Connect-SendGrid } | Should -Throw '*The SendGrid session has expired*'
            (Get-SgtNetworkCall).Count | Should -Be 0
            $script:Session | Should -BeNullOrEmpty
        }
    }

    It 'Removes the session when the given key fails verification' {
        InModuleScope SendGridTools -Parameters @{ Old = $script:OldCred; New = $script:NewCred } {
            $script:Session = New-SgtTestSession -Credential $Old -AgeHours 0.5
            Set-SgtNetworkStub -Throw 'sgt-test-unauthorized'
            { Connect-SendGrid -Credential $New } | Should -Throw 'Unable to connect to SendGrid. Error detail: Unable to connect to SendGrid. sgt-test-unauthorized*'
            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Headers.Authorization | Should -Be 'Bearer test-key-new-not-real'
            $script:Session | Should -BeNullOrEmpty
        }
    }

    It 'Uses the given key on an expired session on the same host' {
        InModuleScope SendGridTools -Parameters @{ Old = $script:OldCred; New = $script:NewCred } {
            $script:Session = New-SgtTestSession -Credential $Old -AgeHours 2
            Connect-SendGrid -Credential $New
            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Headers.Authorization | Should -Be 'Bearer test-key-new-not-real'
            $script:Session._CreateDateTime | Should -BeGreaterThan (Get-Date).AddMinutes(-1)
            $script:Session._Connected | Should -BeTrue
        }
    }

    It 'Keeps the new key out of verbose, debug and error output' {
        InModuleScope SendGridTools -Parameters @{ Old = $script:OldCred; New = $script:NewCred } {
            $script:Session = New-SgtTestSession -Credential $Old -AgeHours 0.5
            $Result = Get-SgtLeakText -Action { $DebugPreference = 'Continue'; Connect-SendGrid -Credential $New -Verbose }
            $Result.Text | Should -Not -BeLike '*test-key-new-not-real*'
            $Result.Text | Should -Not -BeLike '*test-key-old-not-real*'
        }
    }
}

Describe 'Connect-SendGrid writes its notes only with -Verbose (D19)' {
    BeforeAll {
        $script:OldCred = [pscredential]::new('apikey', (ConvertTo-SecureString -String 'test-key-old-not-real' -AsPlainText -Force))
        $script:NewCred = [pscredential]::new('apikey', (ConvertTo-SecureString -String 'test-key-new-not-real' -AsPlainText -Force))
    }
    BeforeEach {
        Mock -ModuleName SendGridTools Get-Credential { throw 'Get-Credential must not be called' }
        Mock -ModuleName SendGridTools Test-SendGridHostCanPrompt { $true }
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

    It 'Writes the note for <Label> only with -Verbose' -ForEach @(
        @{ Label = 'a new session'; Existing = $false; WithKey = $true; Message = 'Connection to SendGrid established.' }
        @{ Label = 'a refresh with a key'; Existing = $true; WithKey = $true; Message = 'Existing connection to SendGrid refreshed with the given API key.' }
        @{ Label = 'a refresh without a key'; Existing = $true; WithKey = $false; Message = 'Existing connection to SendGrid refreshed.' }
    ) {
        InModuleScope SendGridTools -Parameters @{ Old = $script:OldCred; New = $script:NewCred; Existing = $Existing; WithKey = $WithKey; Message = $Message } {
            $CallArgs = @{}
            if ($WithKey) { $CallArgs['Credential'] = $New }
            $Messages = @{}
            # A module function reads the global preference, so set both and restore the global one.
            $SavedVerbose = $global:VerbosePreference
            try {
                $global:VerbosePreference = 'SilentlyContinue'
                $VerbosePreference = 'SilentlyContinue'
                foreach ($Mode in 'Without', 'With') {
                    $script:Session = $null
                    if ($Existing) { $script:Session = New-SgtTestSession -Credential $Old -AgeHours 0.5 }
                    if ($Mode -eq 'With') {
                        $Streams = @(& { Connect-SendGrid @CallArgs -Verbose } 4>&1)
                    }
                    else {
                        $Streams = @(& { Connect-SendGrid @CallArgs } 4>&1)
                    }
                    $Messages[$Mode] = @($Streams | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $_.Message })
                }
            }
            finally {
                $global:VerbosePreference = $SavedVerbose
            }

            @($Messages['Without'] | Where-Object { $_ -ceq $Message }).Count | Should -Be 0
            @($Messages['With'] | Where-Object { $_ -ceq $Message }).Count | Should -Be 1
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
