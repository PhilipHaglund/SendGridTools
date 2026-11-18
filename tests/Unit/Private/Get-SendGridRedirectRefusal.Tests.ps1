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
    InModuleScope SendGridTools {
        function Script:New-SgtHttpMessage {
            param([int]$Code, [string]$Location)
            $Message = [System.Net.Http.HttpResponseMessage]::new([System.Enum]::ToObject([System.Net.HttpStatusCode], $Code))
            if ($Location) { $Message.Headers.Location = [uri]::new($Location, [UriKind]::RelativeOrAbsolute) }
            $Message
        }
        function Script:New-SgtFakeWebResponse {
            param([int]$Code, [string]$Location)
            $Response = [SgtFakeWebResponse]::new()
            $Response.StatusCode = [System.Enum]::ToObject([System.Net.HttpStatusCode], $Code)
            if ($Location) { $Response.Headers['Location'] = $Location }
            $Response
        }
        function Script:New-SgtRedirectRecord {
            # Builds the ErrorRecord that Invoke-RestMethod throws, in one of the measured forms.
            param([ValidateSet('Message', 'WebException', 'MaximumRedirect')][string]$Form, [int]$Code, [string]$Location, [switch]$HaveResponse)
            switch ($Form) {
                'Message' {
                    $Exception = [SgtFakeHttpResponseException]::new('Response status code does not indicate success.')
                    $Exception.Response = New-SgtHttpMessage -Code $Code -Location $Location
                    $Id = 'WebCmdletWebResponseException,Microsoft.PowerShell.Commands.InvokeRestMethodCommand'
                    [System.Management.Automation.ErrorRecord]::new($Exception, $Id, [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
                }
                'WebException' {
                    $Exception = [System.Net.WebException]::new('x', $null, [System.Net.WebExceptionStatus]::ProtocolError, (New-SgtFakeWebResponse -Code $Code -Location $Location))
                    [System.Management.Automation.ErrorRecord]::new($Exception, 'WebCmdletWebResponseException,Microsoft.PowerShell.Commands.InvokeRestMethodCommand', [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
                }
                'MaximumRedirect' {
                    $Request = $null
                    if ($Code) {
                        $Request = [SgtFakeWebRequest]::new()
                        $Request.HaveResponse = [bool]$HaveResponse
                        $Request.Response = New-SgtFakeWebResponse -Code $Code -Location $Location
                    }
                    $Exception = [System.InvalidOperationException]::new('The maximum redirection count has been exceeded.')
                    $Record = [System.Management.Automation.ErrorRecord]::new($Exception, 'MaximumRedirectExceeded,Microsoft.PowerShell.Commands.InvokeRestMethodCommand', [System.Management.Automation.ErrorCategory]::InvalidOperation, $Request)
                    $Record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new('The maximum redirection count has been exceeded. To increase the number of redirections allowed, supply a higher value to the -MaximumRedirection parameter.')
                    $Record
                }
            }
        }
    }
}

AfterAll {
    InModuleScope SendGridTools {
        Remove-Item -Path 'Function:\New-SgtHttpMessage', 'Function:\New-SgtFakeWebResponse', 'Function:\New-SgtRedirectRecord' -ErrorAction SilentlyContinue
    }
    Uninstall-SgtSessionHelper
    Disable-SgtNetworkTripwire
}

Describe 'Get-SendGridRedirectRefusal' {
    BeforeAll {
        $script:Expected = 'SendGrid answered with a redirect to other.example.net; the request was refused so that the API key is not sent there.'
        $script:Location = 'https://user:pw@other.example.net:8443/v3/scopes?token=abc#frag'
        $script:RequestUri = [uri]'https://api.sendgrid.com/v3/scopes'
    }

    It 'Returns the refusal for the pwsh form (HttpResponseException, 302)' -Skip:($PSVersionTable.PSEdition -ne 'Core') {
        InModuleScope SendGridTools -Parameters @{ Expected = $script:Expected; Location = $script:Location; RequestUri = $script:RequestUri } {
            $Message = New-SgtHttpMessage -Code 302 -Location $Location
            $Exception = [Microsoft.PowerShell.Commands.HttpResponseException]::new('Response status code does not indicate success: 302 (Found).', $Message)
            $Record = [System.Management.Automation.ErrorRecord]::new($Exception, 'WebCmdletWebResponseException,Microsoft.PowerShell.Commands.InvokeRestMethodCommand', [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
            Get-SendGridRedirectRefusal -ErrorRecord $Record -RequestUri $RequestUri | Should -BeExactly $Expected
        }
    }

    It 'Returns the refusal for an exception carrying an HttpResponseMessage <Code>' -ForEach @(
        @{ Code = 301 }, @{ Code = 302 }, @{ Code = 303 }, @{ Code = 307 }, @{ Code = 308 }
    ) {
        InModuleScope SendGridTools -Parameters @{ Code = $Code; Expected = $script:Expected; Location = $script:Location; RequestUri = $script:RequestUri } {
            $Record = New-SgtRedirectRecord -Form Message -Code $Code -Location $Location
            Get-SendGridRedirectRefusal -ErrorRecord $Record -RequestUri $RequestUri | Should -BeExactly $Expected
        }
    }

    It 'Returns the refusal for the WebException form' {
        InModuleScope SendGridTools -Parameters @{ Expected = $script:Expected; Location = $script:Location; RequestUri = $script:RequestUri } {
            $Record = New-SgtRedirectRecord -Form WebException -Code 302 -Location $Location
            Get-SendGridRedirectRefusal -ErrorRecord $Record -RequestUri $RequestUri | Should -BeExactly $Expected
        }
    }

    It 'Returns the refusal for the measured 5.1 form (MaximumRedirectExceeded)' {
        InModuleScope SendGridTools -Parameters @{ Expected = $script:Expected; Location = $script:Location; RequestUri = $script:RequestUri } {
            $Record = New-SgtRedirectRecord -Form MaximumRedirect -Code 302 -Location $Location -HaveResponse
            Get-SendGridRedirectRefusal -ErrorRecord $Record -RequestUri $RequestUri | Should -BeExactly $Expected
        }
    }

    It 'Names an unknown host for MaximumRedirectExceeded without a readable response' {
        InModuleScope SendGridTools -Parameters @{ RequestUri = $script:RequestUri } {
            $Record = New-SgtRedirectRecord -Form MaximumRedirect -Code 0
            Get-SendGridRedirectRefusal -ErrorRecord $Record -RequestUri $RequestUri | Should -BeExactly 'SendGrid answered with a redirect to an unknown host; the request was refused so that the API key is not sent there.'
        }
    }

    It 'Does not call GetResponse when HaveResponse is false' {
        InModuleScope SendGridTools -Parameters @{ Location = $script:Location; RequestUri = $script:RequestUri } {
            $Record = New-SgtRedirectRecord -Form MaximumRedirect -Code 302 -Location $Location
            $Record.TargetObject.HaveResponse | Should -BeFalse
            Get-SendGridRedirectRefusal -ErrorRecord $Record -RequestUri $RequestUri | Should -BeExactly 'SendGrid answered with a redirect to an unknown host; the request was refused so that the API key is not sent there.'
        }
    }

    It 'Resolves a relative Location against the request URI' {
        InModuleScope SendGridTools {
            $Record = New-SgtRedirectRecord -Form Message -Code 302 -Location '/v3/elsewhere'
            Get-SendGridRedirectRefusal -ErrorRecord $Record -RequestUri ([uri]'https://api.eu.sendgrid.com/v3/scopes') | Should -BeExactly 'SendGrid answered with a redirect to api.eu.sendgrid.com; the request was refused so that the API key is not sent there.'
        }
    }

    It 'Names an unknown host for a <Code> without Location' -ForEach @(@{ Code = 304 }, @{ Code = 302 }) {
        InModuleScope SendGridTools -Parameters @{ Code = $Code; RequestUri = $script:RequestUri } {
            foreach ($Form in 'Message', 'WebException') {
                $Record = New-SgtRedirectRecord -Form $Form -Code $Code
                Get-SendGridRedirectRefusal -ErrorRecord $Record -RequestUri $RequestUri | Should -BeExactly 'SendGrid answered with a redirect to an unknown host; the request was refused so that the API key is not sent there.'
            }
        }
    }

    It 'Never names the path, query, user information or key' {
        InModuleScope SendGridTools -Parameters @{ Location = $script:Location; RequestUri = $script:RequestUri } {
            foreach ($Form in 'Message', 'WebException') {
                $Record = New-SgtRedirectRecord -Form $Form -Code 302 -Location $Location
                Get-SendGridRedirectRefusal -ErrorRecord $Record -RequestUri $RequestUri | Should -Not -Match 'v3|scopes|token|abc|frag|user|pw|8443|test-key-not-real'
            }
        }
    }

    It 'Returns nothing for <Code>' -ForEach @(
        @{ Code = 200 }, @{ Code = 400 }, @{ Code = 401 }, @{ Code = 404 }, @{ Code = 500 }
    ) {
        InModuleScope SendGridTools -Parameters @{ Code = $Code; RequestUri = $script:RequestUri } {
            foreach ($Form in 'Message', 'WebException') {
                $Record = New-SgtRedirectRecord -Form $Form -Code $Code
                Get-SendGridRedirectRefusal -ErrorRecord $Record -RequestUri $RequestUri | Should -BeNullOrEmpty
            }
        }
    }

    It 'Returns nothing for a plain ErrorRecord <Label>' -ForEach @(
        @{ Label = 'without ErrorDetails'; Details = $null }
        @{ Label = 'with ErrorDetails'; Details = '{"errors":[{"message":"bad request"}]}' }
    ) {
        InModuleScope SendGridTools -Parameters @{ Details = $Details; RequestUri = $script:RequestUri } {
            $Record = New-SgtErrorRecord -Message 'http failure' -Details $Details
            Get-SendGridRedirectRefusal -ErrorRecord $Record -RequestUri $RequestUri | Should -BeNullOrEmpty
        }
    }

    It 'Returns nothing and does not throw when Response has no StatusCode' {
        InModuleScope SendGridTools -Parameters @{ RequestUri = $script:RequestUri } {
            $Exception = [System.Exception]::new('odd')
            $Exception | Add-Member -NotePropertyName Response -NotePropertyValue ([pscustomobject]@{})
            $Record = [System.Management.Automation.ErrorRecord]::new($Exception, 'Odd', [System.Management.Automation.ErrorCategory]::NotSpecified, $null)
            { Get-SendGridRedirectRefusal -ErrorRecord $Record -RequestUri $RequestUri } | Should -Not -Throw
            Get-SendGridRedirectRefusal -ErrorRecord $Record -RequestUri $RequestUri | Should -BeNullOrEmpty
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
