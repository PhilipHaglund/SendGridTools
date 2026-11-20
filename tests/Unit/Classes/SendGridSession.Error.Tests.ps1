BeforeDiscovery {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/SessionHelpers.ps1')
    $script:Targets = @(
        @{ Label = 'Connect(credential)'; Target = 'Connect(credential)'; Case = $null }
        @{ Label = 'Connect()'; Target = 'Connect()'; Case = $null }
    ) + @(Get-SgtOverloadCase | ForEach-Object { @{ Label = "InvokeQuery $($_.Name)"; Target = 'InvokeQuery'; Case = $_ } })
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/NetworkTripwire.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/SessionHelpers.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/RedirectFakes.ps1')
    # Import once per run: in Windows PowerShell 5.1 a class stays bound to the first loaded module instance.
    if (-not (Get-Module -Name SendGridTools)) {
        Get-Module -Name SendGridTools -ListAvailable | Select-Object -First 1 | Import-Module -ErrorAction Stop
    }
    Enable-SgtNetworkTripwire
    Assert-SgtNetworkTripwireActive
    Install-SgtSessionHelper
    Add-SgtRedirectFake
    Install-SgtRedirectBuilder
    $script:Cred = [pscredential]::new('apikey', (ConvertTo-SecureString -String 'test-key-not-real' -AsPlainText -Force))
    InModuleScope SendGridTools {
        function Script:New-SgtStatusRecord {
            # Builds the ErrorRecord that Invoke-RestMethod throws for an HTTP error, in the shape of the running shell.
            param([int]$Code, [string]$Details, [string]$Location)
            if ($PSVersionTable.PSEdition -eq 'Core') {
                $Status = [System.Enum]::ToObject([System.Net.HttpStatusCode], $Code)
                $Response = [System.Net.Http.HttpResponseMessage]::new($Status)
                if ($Location) { $Response.Headers.Location = [uri]$Location }
                $Exception = [Microsoft.PowerShell.Commands.HttpResponseException]::new(('Response status code does not indicate success: {0} ({1}).' -f $Code, $Status), $Response)
            }
            else {
                $Exception = [System.Net.WebException]::new('The remote server returned an error.', $null, [System.Net.WebExceptionStatus]::ProtocolError, (New-SgtFakeWebResponse -Code $Code -Location $Location))
            }
            $Record = [System.Management.Automation.ErrorRecord]::new($Exception, 'WebCmdletWebResponseException,Microsoft.PowerShell.Commands.InvokeRestMethodCommand', [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
            if ($Details) { $Record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new($Details) }
            $Record
        }
        function Script:Invoke-SgtErrorTarget {
            # Runs one target against a connected session and returns the session and the error it threw.
            param([string]$Target, $Case, [pscredential]$Credential)
            $Session = New-SgtTestSession -Credential $Credential -AgeHours 0
            $Caught = $null
            try {
                switch ($Target) {
                    'Connect(credential)' { $Session.Connect($Credential) }
                    'Connect()' { $Session.Connect() }
                    default { $null = Invoke-SgtOverload -Session $Session -Case $Case }
                }
            }
            catch { $Caught = $_ }
            [pscustomobject]@{ Session = $Session; Caught = $Caught }
        }
    }
}

AfterAll {
    InModuleScope SendGridTools {
        Remove-Item -Path 'Function:\New-SgtFakeWebResponse', 'Function:\New-SgtStatusRecord', 'Function:\Invoke-SgtErrorTarget' -ErrorAction SilentlyContinue
    }
    Uninstall-SgtSessionHelper
    Disable-SgtNetworkTripwire
}

Describe 'SendGridSession error from SendGrid' {
    AfterEach {
        InModuleScope SendGridTools { Reset-SgtNetworkStub }
    }

    It 'Throws the HTTP text and keeps the original exception in <Label>' -ForEach $script:Targets {
        InModuleScope SendGridTools -Parameters @{ Target = $Target; Case = $Case; Cred = $script:Cred } {
            $Record = New-SgtStatusRecord -Code 404 -Details '{"errors":[{"field":"id","message":"resource not found"}],"auth":"Authorization: Bearer test-key-not-real"}'
            Set-SgtNetworkStub -Throw $Record
            $Result = Invoke-SgtErrorTarget -Target $Target -Case $Case -Credential $Cred
            $Exception = $Result.Caught.Exception
            $Exception.Message | Should -BeExactly 'SendGrid Error (HTTP 404): "id: resource not found"'
            # The session credential holds test-key-not-real and the body plants it outside errors: neither may reach the error.
            $Cred.GetNetworkCredential().Password | Should -BeExactly 'test-key-not-real'
            $Seen = @($Exception.Message, $Exception.ToString()) + @($Exception.Data.Values | ForEach-Object { $_ | ConvertTo-Json -Depth 4 -Compress })
            ($Seen -join ' ') | Should -Not -Match 'test-key-not-real'
            ($Seen -join ' ') | Should -Not -Match 'Authorization'
            $Exception.GetType().FullName | Should -BeExactly 'System.Management.Automation.RuntimeException'
            [object]::ReferenceEquals($Exception.InnerException, $Record.Exception) | Should -BeTrue
            $Exception.Data['StatusCode'] | Should -BeOfType [int]
            $Exception.Data['StatusCode'] | Should -Be 404
            @($Exception.Data['SendGridErrors'])[0].Message | Should -BeExactly 'resource not found'
            if ($Target -like 'Connect*') {
                $Result.Session._Connected | Should -BeFalse
            }
            else {
                $Result.Session.EndpointURL | Should -BeNullOrEmpty
            }
        }
    }

    It 'Shows no parse error for a body that is not JSON in <Label>' -ForEach $script:Targets {
        InModuleScope SendGridTools -Parameters @{ Target = $Target; Case = $Case; Cred = $script:Cred } {
            $Record = New-SgtStatusRecord -Code 500 -Details '<html><body>made-up upstream failure</body></html>'
            Set-SgtNetworkStub -Throw $Record
            $Result = Invoke-SgtErrorTarget -Target $Target -Case $Case -Credential $Cred
            $Result.Caught.Exception.Message | Should -BeExactly ('SendGrid Error (HTTP 500). {0}' -f $Record.Exception.Message)
            $Result.Caught.Exception.Data['StatusCode'] | Should -Be 500
        }
    }

    It 'Still refuses a 302 with the redirect text in <Label>' -ForEach $script:Targets {
        InModuleScope SendGridTools -Parameters @{ Target = $Target; Case = $Case; Cred = $script:Cred } {
            Set-SgtNetworkStub -Throw (New-SgtStatusRecord -Code 302 -Location 'https://other.example.net/v3/scopes?token=abc')
            $Result = Invoke-SgtErrorTarget -Target $Target -Case $Case -Credential $Cred
            $Result.Caught.Exception.Message | Should -BeExactly 'SendGrid answered with a redirect to other.example.net; the request was refused so that the API key is not sent there.'
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
