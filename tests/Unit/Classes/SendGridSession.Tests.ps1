BeforeDiscovery {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/SessionHelpers.ps1')
    $script:Cases = @(Get-SgtOverloadCase)
    $script:NeverConnectedCases = @(Get-SgtOverloadCase)
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

# The class methods call Invoke-RestMethod. The tripwire's global function answers those calls: Set-SgtNetworkStub
# plays the role of a mock (see Support/NetworkTripwire.ps1 for why Pester Mock is not used for class calls).

Describe 'SendGridSession constructor and BuildEndpointURL' {
    It 'Starts with no endpoint and not connected' {
        InModuleScope SendGridTools {
            $Session = [SendGridSession]::new()
            $Session.EndpointURL | Should -BeNullOrEmpty
            $Session._Connected | Should -BeFalse
        }
    }

    It 'Builds the v3 URL for a resource' {
        InModuleScope SendGridTools {
            $Session = [SendGridSession]::new()
            $Session.BuildEndpointURL('scopes')
            $Session.EndpointURL.AbsoluteUri | Should -Be 'https://api.sendgrid.com/v3/scopes'
        }
    }

    It 'Clears the endpoint for <Label>' -ForEach @(
        @{ Label = 'an empty string'; Value = '' }
        @{ Label = 'null'; Value = $null }
    ) {
        InModuleScope SendGridTools -Parameters @{ Value = $Value } {
            $Session = [SendGridSession]::new()
            $Session.BuildEndpointURL('scopes')
            $Session.BuildEndpointURL($Value)
            $Session.EndpointURL | Should -BeNullOrEmpty
        }
    }
}

Describe 'SendGridSession with a base URL' {
    AfterEach {
        InModuleScope SendGridTools { Reset-SgtNetworkStub }
    }

    It 'Builds the endpoint from the base URL it is given' {
        InModuleScope SendGridTools {
            $Session = [SendGridSession]::new([uri]'https://api.eu.sendgrid.com/v3')
            $Session.BuildEndpointURL('scopes')
            $Session.EndpointURL.AbsoluteUri | Should -Be 'https://api.eu.sendgrid.com/v3/scopes'
        }
    }

    It 'Keeps the global base URL for the constructor without arguments' {
        InModuleScope SendGridTools {
            [SendGridSession]::new()._BaseURL.AbsoluteUri | Should -Be 'https://api.sendgrid.com/v3'
        }
    }

    It 'Connects to the scopes of the given base URL' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            Set-SgtNetworkStub -Response ([pscustomobject]@{ scopes = @('scopes.read') })
            $Session = [SendGridSession]::new([uri]'https://api.eu.sendgrid.com/v3')
            $Session.Connect($Cred)
            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            "$($Calls[0].Uri)" | Should -Be 'https://api.eu.sendgrid.com/v3/scopes'
        }
    }

    It 'Sends InvokeQuery to the given base URL' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            Set-SgtNetworkStub -Response ([pscustomobject]@{})
            $Session = [SendGridSession]::new([uri]'https://api.eu.sendgrid.com/v3')
            $Session._Credential = $Cred
            $Session._Connected = $true
            $Session._CreateDateTime = Get-Date
            $null = $Session.InvokeQuery('Get', 'subusers')
            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            "$($Calls[0].Uri)" | Should -Be 'https://api.eu.sendgrid.com/v3/subusers'
        }
    }
}

Describe 'SendGridSession Connect with credential' {
    AfterEach {
        InModuleScope SendGridTools { Reset-SgtNetworkStub }
    }

    It 'Sends one GET to scopes with the bearer and content type headers' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            Set-SgtNetworkStub -Response $null
            $Session = [SendGridSession]::new()
            $Session.Connect($Cred)
            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Get'
            $Calls[0].Uri.AbsoluteUri | Should -Be 'https://api.sendgrid.com/v3/scopes'
            $Calls[0].Headers['Authorization'] | Should -Be 'Bearer test-key-not-real'
            $Calls[0].Headers['Content-Type'] | Should -Be 'application/json'
        }
    }

    It 'Marks the session connected and stamps the creation time' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            Set-SgtNetworkStub -Response $null
            $Session = [SendGridSession]::new()
            $Session.Connect($Cred)
            $Session._Connected | Should -BeTrue
            ((Get-Date) - $Session._CreateDateTime).TotalSeconds | Should -BeLessThan 60
            ((Get-Date) - $Session._CreateDateTime).TotalSeconds | Should -BeGreaterThan -5
        }
    }

    It 'Throws the connect error and stays disconnected when the request fails' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            Set-SgtNetworkStub -Throw 'boom'
            $Session = [SendGridSession]::new()
            { $Session.Connect($Cred) } | Should -Throw -ExpectedMessage 'Unable to connect to SendGrid. boom'
            $Session._Connected | Should -BeFalse
        }
    }
}

Describe 'SendGridSession Connect with stored credential' {
    AfterEach {
        InModuleScope SendGridTools { Reset-SgtNetworkStub }
    }

    It 'Sends the same GET when the session is fresh' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            Set-SgtNetworkStub -Response $null
            $Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            $Session.Connect()
            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].Method | Should -Be 'Get'
            $Calls[0].Uri.AbsoluteUri | Should -Be 'https://api.sendgrid.com/v3/scopes'
            $Calls[0].Headers['Authorization'] | Should -Be 'Bearer test-key-not-real'
            $Calls[0].Headers['Content-Type'] | Should -Be 'application/json'
            $Session._Connected | Should -BeTrue
        }
    }

    It 'Throws, makes no request and clears the credential when the lifetime is exceeded' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            Set-SgtNetworkStub -Response $null
            $Session = New-SgtTestSession -Credential $Cred -AgeHours 2
            { $Session.Connect() } | Should -Throw -ExpectedMessage 'The SendGrid session has expired. Run Connect-SendGrid -Force to reconnect.'
            Get-SgtNetworkCall | Should -BeNullOrEmpty
            $Session._Credential | Should -BeNullOrEmpty
            $Session._Connected | Should -BeFalse
        }
    }

    It 'Throws the no-credentials error for a fresh session without a stored credential' {
        InModuleScope SendGridTools {
            Set-SgtNetworkStub -Response $null
            $Session = New-SgtTestSession -Credential $null -AgeHours 0
            { $Session.Connect() } | Should -Throw -ExpectedMessage 'Unable to connect to SendGrid. No credentials saved in context.'
            Get-SgtNetworkCall | Should -BeNullOrEmpty
        }
    }
}

Describe 'SendGridSession Disconnect' {
    It 'Clears credential, connected flag and endpoint' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            $Session.BuildEndpointURL('scopes')
            $Session.Disconnect()
            $Session._Credential | Should -BeNullOrEmpty
            $Session._Connected | Should -BeFalse
            $Session.EndpointURL | Should -BeNullOrEmpty
        }
    }
}

Describe 'SendGridSession InvokeQuery <Name>' -ForEach $script:Cases {
    BeforeAll {
        $script:Case = @{ Name = $Name; Method = $Method; Endpoint = $Endpoint; HasBody = $HasBody; HasObo = $HasObo; Body = $Body; Obo = $Obo }
    }

    AfterEach {
        InModuleScope SendGridTools { Reset-SgtNetworkStub }
    }

    It 'Sends the request with the expected method, URI, headers and body' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Case = $script:Case } {
            Set-SgtNetworkStub -Response ([pscustomobject]@{ ok = 'mock-response' })
            $Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            $Result = Invoke-SgtOverload -Session $Session -Case $Case
            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Call = $Calls[0]
            $Call.Method | Should -Be $Case.Method
            $Call.Uri.AbsoluteUri | Should -Be ('https://api.sendgrid.com/v3/{0}' -f $Case.Endpoint)
            $Call.Headers['Authorization'] | Should -Be 'Bearer test-key-not-real'
            $Call.Headers['Content-Type'] | Should -Be $(if ($Case.HasBody) { 'application/json; charset=utf-8' } else { 'application/json' })
            if ($Case.HasObo) {
                $Call.Headers.ContainsKey('on-behalf-of') | Should -BeTrue
                $Call.Headers['on-behalf-of'] | Should -Be $Case.Obo
            }
            else {
                $Call.Headers.ContainsKey('on-behalf-of') | Should -BeFalse
            }
            if ($Case.HasBody) {
                $Call.BodyPassed | Should -BeTrue
                $Call.Body | Should -Be ($Case.Body | ConvertTo-Json -Depth 5)
            }
            else {
                $Call.BodyPassed | Should -BeFalse
            }
            @($Result)[0].ok | Should -Be 'mock-response'
            $Session.EndpointURL | Should -BeNullOrEmpty
        }
    }

    It 'Sends a body as UTF-8 bytes without a byte order mark, and a call without a body keeps its content type' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Case = $script:Case } {
            Set-SgtNetworkStub -Response ([pscustomobject]@{ ok = 'mock-response' })
            $Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            # a-ring, e-acute, euro sign and a grinning face (a surrogate pair), built from code points to keep the file ASCII.
            $Sample = [string][char]0xE5 + [char]0xE9 + [char]0x20AC + [char]::ConvertFromUtf32(0x1F600)
            $Used = if ($Case.HasBody) { @{ name = $Sample } } else { $null }
            $Used2 = @{ Name = $Case.Name; Method = $Case.Method; Endpoint = $Case.Endpoint; HasBody = $Case.HasBody; HasObo = $Case.HasObo; Body = $Used; Obo = $Case.Obo }
            $null = Invoke-SgtOverload -Session $Session -Case $Used2
            $Call = (Get-SgtNetworkCall)[0]
            if ($Case.HasBody) {
                $Json = $Used | ConvertTo-Json -Depth 5
                $Expected = [System.Text.UTF8Encoding]::new($false).GetBytes($Json)
                ($Call.BodyBytes -is [byte[]]) | Should -BeTrue
                ($Call.BodyBytes -join ',') | Should -BeExactly ($Expected -join ',')
                $Call.Body | Should -BeExactly $Json
                $Call.Headers['Content-Type'] | Should -BeExactly 'application/json; charset=utf-8'
            }
            else {
                $Call.BodyPassed | Should -BeFalse
                $Call.BodyBytes | Should -BeNullOrEmpty
                $Call.Headers['Content-Type'] | Should -BeExactly 'application/json'
            }
        }
    }

    It 'Throws the SendGrid error text when the response carries error details' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Case = $script:Case } {
            Set-SgtNetworkStub -Throw (New-SgtErrorRecord -Message 'http failure' -Details '{"errors":[{"message":"bad request"}]}')
            $Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            { Invoke-SgtOverload -Session $Session -Case $Case } | Should -Throw -ExpectedMessage 'SendGrid Error: "bad request"'
            $Session.EndpointURL | Should -BeNullOrEmpty
        }
    }

    It 'Throws the generic error text when there are no error details' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Case = $script:Case } {
            Set-SgtNetworkStub -Throw (New-SgtErrorRecord -Message 'http failure')
            $Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            { Invoke-SgtOverload -Session $Session -Case $Case } | Should -Throw -ExpectedMessage 'Unable to query SendGrid: http failure'
            $Session.EndpointURL | Should -BeNullOrEmpty
        }
    }

    It 'Throws the expired-session error, disconnects and makes no request when the session is expired' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Case = $script:Case } {
            Set-SgtNetworkStub -Response $null
            $Session = New-SgtTestSession -Credential $Cred -AgeHours 2
            { Invoke-SgtOverload -Session $Session -Case $Case } | Should -Throw -ExpectedMessage 'The SendGrid session has expired. Run Connect-SendGrid -Force to reconnect.'
            Get-SgtNetworkCall | Should -BeNullOrEmpty
            $Session._Connected | Should -BeFalse
            $Session._Credential | Should -BeNullOrEmpty
        }
    }
}

Describe 'SendGridSession InvokeQuery on a never-connected session <Name>' -ForEach $script:NeverConnectedCases {
    AfterEach {
        InModuleScope SendGridTools { Reset-SgtNetworkStub }
    }

    It 'Throws the connect-first error' {
        InModuleScope SendGridTools -Parameters @{ Case = @{ Name = $Name; Method = $Method; Endpoint = $Endpoint; HasBody = $HasBody; HasObo = $HasObo; Body = $Body; Obo = $Obo } } {
            Set-SgtNetworkStub -Response $null
            $Session = [SendGridSession]::new()
            { Invoke-SgtOverload -Session $Session -Case $Case } | Should -Throw -ExpectedMessage 'You must call the Connect-SendGrid cmdlet before calling any other cmdlets.'
            Get-SgtNetworkCall | Should -BeNullOrEmpty
        }
    }
}

Describe 'SendGridSession InvokeQuery after Disconnect <Name>' -ForEach $script:NeverConnectedCases {
    AfterEach {
        InModuleScope SendGridTools { Reset-SgtNetworkStub }
    }

    It 'Throws the connect-first error after Disconnect (<Name>)' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Case = @{ Name = $Name; Method = $Method; Endpoint = $Endpoint; HasBody = $HasBody; HasObo = $HasObo; Body = $Body; Obo = $Obo } } {
            Set-SgtNetworkStub -Response $null
            $Session = [SendGridSession]::new()
            $Session.Connect($Cred)
            $Session._Connected | Should -BeTrue
            (Get-SgtNetworkCall).Count | Should -Be 1
            $Session.Disconnect()
            { Invoke-SgtOverload -Session $Session -Case $Case } | Should -Throw -ExpectedMessage 'You must call the Connect-SendGrid cmdlet before calling any other cmdlets.'
            (Get-SgtNetworkCall).Count | Should -Be 1
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
