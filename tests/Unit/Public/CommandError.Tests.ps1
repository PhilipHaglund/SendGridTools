BeforeDiscovery {
    $script:Commands = @(
        @{ Command = 'Get-SGApiKey'; Prefix = 'Failed to retrieve SendGrid API Key. ' }
        @{ Command = 'Send-SGMailMessage'; Prefix = 'Failed to send email via SendGrid API. ' }
    )
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
        function Script:New-SgtCommandRecord {
            # Builds the ErrorRecord that Invoke-RestMethod throws, in the shape of the running shell:
            # an HttpResponseException in PowerShell 7 and a WebException with a response in Windows PowerShell 5.1.
            # Code 0 gives an error without an HTTP response.
            param([int]$Code, [string]$Details)
            if ($Code -eq 0) {
                $Exception = [System.Net.Http.HttpRequestException]::new('No such host is known.')
            }
            elseif ($PSVersionTable.PSEdition -eq 'Core') {
                $Status = [System.Enum]::ToObject([System.Net.HttpStatusCode], $Code)
                $Message = [System.Net.Http.HttpResponseMessage]::new($Status)
                $Exception = [Microsoft.PowerShell.Commands.HttpResponseException]::new(('Response status code does not indicate success: {0} ({1}).' -f $Code, $Status), $Message)
            }
            else {
                $Status = [System.Enum]::ToObject([System.Net.HttpStatusCode], $Code)
                $Exception = [System.Net.WebException]::new(('The remote server returned an error: ({0}) {1}.' -f $Code, $Status), $null, [System.Net.WebExceptionStatus]::ProtocolError, (New-SgtFakeWebResponse -Code $Code))
            }
            $Record = [System.Management.Automation.ErrorRecord]::new($Exception, 'WebCmdletWebResponseException,Microsoft.PowerShell.Commands.InvokeRestMethodCommand', [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
            if ($Details) { $Record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new($Details) }
            $Record
        }
    }
}

AfterAll {
    InModuleScope SendGridTools {
        Remove-Item -Path 'Function:\New-SgtFakeWebResponse', 'Function:\New-SgtCommandRecord' -ErrorAction SilentlyContinue
    }
    Uninstall-SgtSessionHelper
    Disable-SgtNetworkTripwire
}

Describe 'Command errors keep the exception, the HTTP status and the SendGrid errors' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    Context 'A command that queries SendGrid, called from outside the module' {
        BeforeEach {
            InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
                $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
                $script:Raised = New-SgtCommandRecord -Code 404 -Details '{"errors":[{"field":null,"message":"resource not found"}]}'
                Set-SgtNetworkStub -Throw $script:Raised
            }
        }

        It '<Command> names the status and the SendGrid error and keeps the cause' -ForEach $script:Commands {
            $Caught = $null
            try {
                if ($Command -eq 'Get-SGApiKey') {
                    $null = Get-SGApiKey -ApiKeyId 'key-id-1'
                }
                else {
                    $null = Send-SGMailMessage -From 'sender@example.com' -To 'one@example.com' -Subject 'placeholder subject' -Body 'placeholder body' -Confirm:$false
                }
            }
            catch { $Caught = $_ }
            $Caught | Should -Not -BeNullOrEmpty
            $Caught.Exception.Message | Should -BeExactly ($Prefix + 'SendGrid Error (HTTP 404): "resource not found"')
            $Caught.Exception | Should -BeOfType [Microsoft.PowerShell.Commands.WriteErrorException]
            $Caught.FullyQualifiedErrorId | Should -BeExactly "Microsoft.PowerShell.Commands.WriteErrorException,$Command"
            $Caught.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::NotSpecified)
            $Caught.Exception.Data['StatusCode'] | Should -Be 404
            $Caught.Exception.Data['StatusCode'] | Should -BeOfType [int]
            @($Caught.Exception.Data['SendGridErrors']).Count | Should -Be 1
            @($Caught.Exception.Data['SendGridErrors'])[0].Message | Should -BeExactly 'resource not found'
            $Session = $Caught.Exception.InnerException
            $Session | Should -BeOfType [System.Management.Automation.RuntimeException]
            $Session.Message | Should -BeExactly 'SendGrid Error (HTTP 404): "resource not found"'
            $Original = InModuleScope SendGridTools { $script:Raised.Exception }
            [object]::ReferenceEquals($Session.InnerException, $Original) | Should -BeTrue
            Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
        }

        It 'Get-SGApiKey gives no StatusCode when SendGrid did not answer' {
            InModuleScope SendGridTools { Set-SgtNetworkStub -Throw (New-SgtCommandRecord -Code 0) }
            $Caught = $null
            try { $null = Get-SGApiKey -ApiKeyId 'key-id-1' } catch { $Caught = $_ }
            $Caught.Exception.Message | Should -BeExactly 'Failed to retrieve SendGrid API Key. Unable to query SendGrid: No such host is known.'
            $Caught.Exception.Data.Contains('StatusCode') | Should -BeFalse
            $Caught.Exception.Data.Contains('SendGridErrors') | Should -BeFalse
            $Caught.Exception.InnerException | Should -BeOfType [System.Management.Automation.RuntimeException]
            Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
        }
    }

    Context 'Connect-SendGrid' {
        It 'Keeps the status of a refused key in Data' {
            InModuleScope SendGridTools {
                Set-SgtNetworkStub -Throw (New-SgtCommandRecord -Code 401 -Details '{"errors":[{"field":null,"message":"invalid key"}]}')
            }
            $Caught = $null
            try { Connect-SendGrid -Credential $script:Cred } catch { $Caught = $_ }
            $Caught | Should -Not -BeNullOrEmpty
            $Caught.Exception.Data['StatusCode'] | Should -Be 401
            $Caught.Exception.Message | Should -BeLike 'Unable to connect to SendGrid. Error detail: *'
            $Caught.Exception.Message | Should -BeLike '*SendGrid Error (HTTP 401): "invalid key"*'
            $Caught.FullyQualifiedErrorId | Should -BeExactly 'Microsoft.PowerShell.Commands.WriteErrorException,Connect-SendGrid'
            $Caught.Exception | Should -BeOfType [Microsoft.PowerShell.Commands.WriteErrorException]
            Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
        }
    }

    Context 'Disconnect-SendGrid' {
        It 'Writes the text of the exception and keeps it as the cause' {
            InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
                $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            }
            Mock -CommandName Remove-Variable -ModuleName SendGridTools -ParameterFilter { $Name -eq 'Session' } -MockWith { throw 'made-up removal failure' }
            $Stream = @(Disconnect-SendGrid -Confirm:$false 2>&1)
            $Record = @($Stream | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Record.Count | Should -Be 1
            $Record[0].Exception.Message | Should -BeExactly 'Unable to disconnect from SendGrid. made-up removal failure'
            $Record[0].Exception | Should -BeOfType [Microsoft.PowerShell.Commands.WriteErrorException]
            $Record[0].Exception.InnerException.Message | Should -BeExactly 'made-up removal failure'
            $Record[0].FullyQualifiedErrorId | Should -BeExactly 'Microsoft.PowerShell.Commands.WriteErrorException,Disconnect-SendGrid'
            Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
