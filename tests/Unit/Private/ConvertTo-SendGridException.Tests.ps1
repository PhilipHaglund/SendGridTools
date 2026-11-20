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
    InModuleScope SendGridTools {
        function Script:New-SgtHttpRecord {
            # Builds the ErrorRecord that Invoke-RestMethod throws for an HTTP error, in the shape of the running shell:
            # an HttpResponseException in PowerShell 7 and a WebException with a response in Windows PowerShell 5.1.
            # Code 0 gives an error without an HTTP response.
            param([int]$Code, [string]$Details, [string]$Message)
            if ($Code -eq 0) {
                $Text = if ($Message) { $Message } else { 'No such host is known.' }
                $Exception = [System.Net.Http.HttpRequestException]::new($Text)
            }
            elseif ($PSVersionTable.PSEdition -eq 'Core') {
                $Status = [System.Enum]::ToObject([System.Net.HttpStatusCode], $Code)
                $Response = [System.Net.Http.HttpResponseMessage]::new($Status)
                $Text = if ($Message) { $Message } else { 'Response status code does not indicate success: {0} ({1}).' -f $Code, $Status }
                $Exception = [Microsoft.PowerShell.Commands.HttpResponseException]::new($Text, $Response)
            }
            else {
                $Status = [System.Enum]::ToObject([System.Net.HttpStatusCode], $Code)
                $Text = if ($Message) { $Message } else { 'The remote server returned an error: ({0}) {1}.' -f $Code, $Status }
                $Exception = [System.Net.WebException]::new($Text, $null, [System.Net.WebExceptionStatus]::ProtocolError, (New-SgtFakeWebResponse -Code $Code))
            }
            $Record = [System.Management.Automation.ErrorRecord]::new($Exception, 'WebCmdletWebResponseException,Microsoft.PowerShell.Commands.InvokeRestMethodCommand', [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
            if ($Details) { $Record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new($Details) }
            $Record
        }
    }
}

AfterAll {
    InModuleScope SendGridTools {
        Remove-Item -Path 'Function:\New-SgtFakeWebResponse', 'Function:\New-SgtHttpRecord' -ErrorAction SilentlyContinue
    }
    Uninstall-SgtSessionHelper
    Disable-SgtNetworkTripwire
}

Describe 'ConvertTo-SendGridException' {
    Context 'with an HTTP response and SendGrid errors' {
        It 'names the status and the field of a 400' {
            InModuleScope SendGridTools {
                $Record = New-SgtHttpRecord -Code 400 -Details '{"errors":[{"field":"name","message":"name is required"}]}'
                $Result = ConvertTo-SendGridException -ErrorRecord $Record -Context Query
                $Result.Message | Should -BeExactly 'SendGrid Error (HTTP 400): "name: name is required"'
            }
        }

        It 'leaves out a null field of a 404' {
            InModuleScope SendGridTools {
                $Record = New-SgtHttpRecord -Code 404 -Details '{"errors":[{"field":null,"message":"resource not found"}]}'
                $Result = ConvertTo-SendGridException -ErrorRecord $Record -Context Query
                $Result.Message | Should -BeExactly 'SendGrid Error (HTTP 404): "resource not found"'
            }
        }

        It 'leaves out an empty field' {
            InModuleScope SendGridTools {
                $Record = New-SgtHttpRecord -Code 400 -Details '{"errors":[{"field":"","message":"bad request"}]}'
                $Result = ConvertTo-SendGridException -ErrorRecord $Record -Context Query
                $Result.Message | Should -BeExactly 'SendGrid Error (HTTP 400): "bad request"'
            }
        }

        It 'keeps the order of two errors and joins them with a comma' {
            InModuleScope SendGridTools {
                $Record = New-SgtHttpRecord -Code 400 -Details '{"errors":[{"field":"a","message":"first"},{"message":"second"}]}'
                $Result = ConvertTo-SendGridException -ErrorRecord $Record -Context Query
                $Result.Message | Should -BeExactly 'SendGrid Error (HTTP 400): "a: first, second"'
            }
        }

        It 'gives the same text for Connect (R1b)' {
            InModuleScope SendGridTools {
                $Record = New-SgtHttpRecord -Code 401 -Details '{"errors":[{"message":"access forbidden"}]}'
                $Result = ConvertTo-SendGridException -ErrorRecord $Record -Context Connect
                $Result.Message | Should -BeExactly 'SendGrid Error (HTTP 401): "access forbidden"'
            }
        }

        It 'returns a RuntimeException that keeps the original exception' {
            InModuleScope SendGridTools {
                $Record = New-SgtHttpRecord -Code 404 -Details '{"errors":[{"field":"id","message":"not found"}]}'
                $Result = ConvertTo-SendGridException -ErrorRecord $Record -Context Query
                $Result.GetType().FullName | Should -BeExactly 'System.Management.Automation.RuntimeException'
                [object]::ReferenceEquals($Result.InnerException, $Record.Exception) | Should -BeTrue
            }
        }

        It 'puts the status as an int and the errors in Data' {
            InModuleScope SendGridTools {
                $Record = New-SgtHttpRecord -Code 404 -Details '{"errors":[{"field":"id","message":"not found"},{"message":"other"}]}'
                $Result = ConvertTo-SendGridException -ErrorRecord $Record -Context Query
                $Result.Data['StatusCode'] | Should -BeOfType [int]
                $Result.Data['StatusCode'] | Should -Be 404
                $Errors = @($Result.Data['SendGridErrors'])
                $Errors.Count | Should -Be 2
                $Errors[0].Field | Should -BeExactly 'id'
                $Errors[0].Message | Should -BeExactly 'not found'
                $Errors[1].Field | Should -BeNullOrEmpty
                $Errors[1].Message | Should -BeExactly 'other'
            }
        }
    }

    Context 'with an HTTP response and no usable SendGrid errors' {
        It 'gives the HTTP text and no parse error for an HTML body' {
            InModuleScope SendGridTools {
                $Record = New-SgtHttpRecord -Code 500 -Details '<html><body>made-up upstream failure</body></html>'
                $Result = ConvertTo-SendGridException -ErrorRecord $Record -Context Query
                $Result.Message | Should -BeExactly ('SendGrid Error (HTTP 500). {0}' -f $Record.Exception.Message)
                $Result.Message | Should -Not -Match 'JSON|Invalid object passed|primitive'
                $Result.Data['StatusCode'] | Should -Be 500
                $Result.Data.Contains('SendGridErrors') | Should -BeFalse
            }
        }

        It 'gives the HTTP text for a body of <Body>' -ForEach @(
            @{ Body = '{}' }
            @{ Body = '{"errors":[]}' }
        ) {
            InModuleScope SendGridTools -Parameters @{ Body = $Body } {
                $Record = New-SgtHttpRecord -Code 500 -Details $Body
                $Result = ConvertTo-SendGridException -ErrorRecord $Record -Context Query
                $Result.Message | Should -BeExactly ('SendGrid Error (HTTP 500). {0}' -f $Record.Exception.Message)
                $Result.Data.Contains('SendGridErrors') | Should -BeFalse
            }
        }

        It 'gives the HTTP text when there are no error details' {
            InModuleScope SendGridTools {
                $Record = New-SgtHttpRecord -Code 503
                $Result = ConvertTo-SendGridException -ErrorRecord $Record -Context Connect
                $Result.Message | Should -BeExactly ('SendGrid Error (HTTP 503). {0}' -f $Record.Exception.Message)
            }
        }
    }

    Context 'without an HTTP response' {
        It 'gives the query text' {
            InModuleScope SendGridTools {
                $Record = New-SgtHttpRecord -Code 0
                $Result = ConvertTo-SendGridException -ErrorRecord $Record -Context Query
                $Result.Message | Should -BeExactly ('Unable to query SendGrid: {0}' -f $Record.Exception.Message)
                $Result.Data.Contains('StatusCode') | Should -BeFalse
                [object]::ReferenceEquals($Result.InnerException, $Record.Exception) | Should -BeTrue
            }
        }

        It 'gives the connect text' {
            InModuleScope SendGridTools {
                $Record = New-SgtHttpRecord -Code 0
                $Result = ConvertTo-SendGridException -ErrorRecord $Record -Context Connect
                $Result.Message | Should -BeExactly ('Unable to connect to SendGrid. {0}' -f $Record.Exception.Message)
            }
        }

        It 'keeps today''s text for Query when the details hold errors (R1)' {
            InModuleScope SendGridTools {
                $Record = New-SgtErrorRecord -Message 'http failure' -Details '{"errors":[{"field":"name","message":"bad request"}]}'
                $Result = ConvertTo-SendGridException -ErrorRecord $Record -Context Query
                $Result.Message | Should -BeExactly 'SendGrid Error: "bad request"'
                $Result.Data.Contains('StatusCode') | Should -BeFalse
                @($Result.Data['SendGridErrors'])[0].Field | Should -BeExactly 'name'
            }
        }

        It 'keeps today''s text for Connect when the details hold errors (R1)' {
            InModuleScope SendGridTools {
                $Record = New-SgtErrorRecord -Message 'http failure' -Details '{"errors":[{"message":"bad request"}]}'
                $Result = ConvertTo-SendGridException -ErrorRecord $Record -Context Connect
                $Result.Message | Should -BeExactly 'Unable to connect to SendGrid. http failure'
            }
        }

        It 'never shows a parse error for details that are not JSON' {
            InModuleScope SendGridTools {
                $Record = New-SgtErrorRecord -Message 'http failure' -Details 'not json at all'
                $Result = ConvertTo-SendGridException -ErrorRecord $Record -Context Query
                $Result.Message | Should -BeExactly 'Unable to query SendGrid: http failure'
            }
        }
    }

    Context 'the request address and the key' {
        It 'removes the query part of the address from the text' {
            InModuleScope SendGridTools {
                $Address = 'https://api.example.com/v3/x?email=a%40example.com'
                $Record = New-SgtHttpRecord -Code 0 -Message ('The request to {0} failed.' -f $Address)
                $Result = ConvertTo-SendGridException -ErrorRecord $Record -Context Query -RequestUri ([uri]$Address)
                $Result.Message | Should -BeExactly 'Unable to query SendGrid: The request to https://api.example.com/v3/x failed.'
                $Result.Message | Should -Not -Match 'email='
            }
        }

        It 'removes the query part from the HTTP text too' {
            InModuleScope SendGridTools {
                $Address = 'https://api.example.com/v3/x?email=a%40example.com'
                $Record = New-SgtHttpRecord -Code 500 -Message ('Failure at {0}' -f $Address)
                $Result = ConvertTo-SendGridException -ErrorRecord $Record -Context Query -RequestUri ([uri]$Address)
                $Result.Message | Should -BeExactly 'SendGrid Error (HTTP 500). Failure at https://api.example.com/v3/x'
            }
        }

        It 'never holds the key or the Authorization header in the text, ToString or Data' {
            InModuleScope SendGridTools {
                # Plant the key where the function must not copy it from: the request and response headers, and a body field outside errors.
                $Record = New-SgtHttpRecord -Code 400 -Details '{"errors":[{"field":"name","message":"name is required"}],"auth":"Authorization: Bearer test-key-not-real"}'
                $Response = $Record.Exception.Response
                if ($Response -is [System.Net.Http.HttpResponseMessage]) {
                    $Response.RequestMessage = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Get, 'https://api.example.com/v3/x')
                    $null = $Response.RequestMessage.Headers.TryAddWithoutValidation('Authorization', 'Bearer test-key-not-real')
                }
                else {
                    $Response.Headers['Authorization'] = 'Bearer test-key-not-real'
                }
                $Record.ErrorDetails.Message | Should -Match 'test-key-not-real'
                $PlantedHeader = if ($Response -is [System.Net.Http.HttpResponseMessage]) { $Response.RequestMessage.Headers.Authorization.ToString() } else { $Response.Headers['Authorization'] }
                $PlantedHeader | Should -Match 'test-key-not-real'
                $Result = ConvertTo-SendGridException -ErrorRecord $Record -Context Query -RequestUri ([uri]'https://api.example.com/v3/x?a=b')
                $Result.Message | Should -BeExactly 'SendGrid Error (HTTP 400): "name: name is required"'
                $All = @($Result.Message, $Result.ToString()) + @($Result.Data.Values | ForEach-Object { $_ | ConvertTo-Json -Depth 4 -Compress })
                $All.Count | Should -BeGreaterThan 2
                ($All -join ' ') | Should -Not -Match 'test-key-not-real'
                ($All -join ' ') | Should -Not -Match 'Authorization'
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
