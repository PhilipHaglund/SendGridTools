BeforeDiscovery {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/SessionHelpers.ps1')
    $script:Targets = @(
        @{ Label = 'Connect(credential)'; Target = 'Connect(credential)'; Case = $null }
        @{ Label = 'Connect()'; Target = 'Connect()'; Case = $null }
    ) + @(Get-SgtOverloadCase | ForEach-Object { @{ Label = "InvokeQuery $($_.Name)"; Target = 'InvokeQuery'; Case = $_ } })
    $script:QueryTargets = @($script:Targets | Where-Object { $_.Target -eq 'InvokeQuery' })
    $script:RefusalCases = foreach ($Target in $script:Targets) {
        foreach ($Code in 300, 301, 302, 303, 304, 305, 307, 308) {
            foreach ($Kind in 'an absolute', 'a relative', 'no') {
                @{ Label = $Target.Label; Target = $Target.Target; Case = $Target.Case; Code = $Code; Kind = $Kind }
            }
        }
    }
    $script:ResultCases = foreach ($Target in $script:QueryTargets) {
        @{ Label = $Target.Label; Case = $Target.Case; Name = 'an object'; Body = '{"id":1}' }
        @{ Label = $Target.Label; Case = $Target.Case; Name = 'a one-element list'; Body = '[{"id":1}]' }
        @{ Label = $Target.Label; Case = $Target.Case; Name = 'a three-element list'; Body = '[{"id":1},{"id":2},{"id":3}]' }
        @{ Label = $Target.Label; Case = $Target.Case; Name = 'an empty body'; Body = '' }
    }
    $script:ErrorCases = foreach ($Target in $script:Targets) {
        @{ Label = $Target.Label; Target = $Target.Target; Case = $Target.Case; Code = 400; Details = '{"errors":[{"field":"name","message":"sgt bad request"},{"message":"sgt second error"}]}'; Want = 'SendGrid Error (HTTP 400): "name: sgt bad request, sgt second error"' }
        @{ Label = $Target.Label; Target = $Target.Target; Case = $Target.Case; Code = 404; Details = '{"errors":[{"message":"resource not found"}]}'; Want = 'SendGrid Error (HTTP 404): "resource not found"' }
        @{ Label = $Target.Label; Target = $Target.Target; Case = $Target.Case; Code = 500; Details = '<html><body>sgt server error</body></html>'; Want = $null }
    }
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
        function Script:New-SgtWebResponseObject {
            # The object Invoke-WebRequest -UseBasicParsing returns in Windows PowerShell 5.1, as far as the function reads it.
            param([int]$Code = 200, [string]$ContentType, [string]$Body = '', [string]$Location)
            $Headers = @{}
            if ($ContentType) { $Headers['Content-Type'] = $ContentType }
            [pscustomobject]@{
                StatusCode        = $Code
                StatusDescription = "Status $Code"
                Headers           = $Headers
                RawContentStream  = [System.IO.MemoryStream]::new([System.Text.UTF8Encoding]::new($false).GetBytes($Body))
                BaseResponse      = (New-SgtFakeWebResponse -Code $Code -Location $Location)
            }
        }
        function Script:New-SgtHttpMessage {
            param([int]$Code, [string]$Location)
            $Message = [System.Net.Http.HttpResponseMessage]::new([System.Enum]::ToObject([System.Net.HttpStatusCode], $Code))
            if ($Location) {
                # A path starting with a single slash is a relative reference; on Linux and macOS RelativeOrAbsolute would make it a file URI.
                $Kind = if ($Location -match '^/(?!/)') { [UriKind]::Relative } else { [UriKind]::RelativeOrAbsolute }
                $Message.Headers.Location = [uri]::new($Location, $Kind)
            }
            $Message
        }
        function Script:New-SgtShellErrorRecord {
            # The error record that Invoke-WebRequest (5.1) or Invoke-RestMethod (PowerShell 7) throws for an HTTP error.
            param([int]$Code, [string]$Details)
            if ($PSVersionTable.PSEdition -eq 'Desktop') {
                $Exception = [System.Net.WebException]::new('web failure', $null, [System.Net.WebExceptionStatus]::ProtocolError, (New-SgtFakeWebResponse -Code $Code))
                $Id = 'WebCmdletWebResponseException,Microsoft.PowerShell.Commands.InvokeWebRequestCommand'
            }
            else {
                $Exception = [SgtFakeHttpResponseException]::new('Response status code does not indicate success.')
                $Exception.Response = New-SgtHttpMessage -Code $Code
                $Id = 'WebCmdletWebResponseException,Microsoft.PowerShell.Commands.InvokeRestMethodCommand'
            }
            $Record = [System.Management.Automation.ErrorRecord]::new($Exception, $Id, [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
            if ($Details) { $Record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new($Details) }
            $Record
        }
        function Script:Set-SgtRefusalStub {
            # 5.1: a 301 or 302 is thrown as MaximumRedirectExceeded, every other 3xx is returned as a response.
            # PowerShell 7: Invoke-RestMethod throws an exception that carries the HttpResponseMessage.
            param([int]$Code, [string]$Location)
            if ($PSVersionTable.PSEdition -eq 'Desktop') {
                if ($Code -in 301, 302) {
                    $Request = [SgtFakeWebRequest]::new()
                    $Request.HaveResponse = $true
                    $Request.Response = New-SgtFakeWebResponse -Code $Code -Location $Location
                    $Record = [System.Management.Automation.ErrorRecord]::new([System.InvalidOperationException]::new('The maximum redirection count has been exceeded.'), 'MaximumRedirectExceeded,Microsoft.PowerShell.Commands.InvokeWebRequestCommand', [System.Management.Automation.ErrorCategory]::InvalidOperation, $Request)
                    $Record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new('The maximum redirection count has been exceeded.')
                    $global:SgtStubValue = $Record
                    $global:SgtWebRequestStub = { throw $global:SgtStubValue }
                }
                else {
                    $global:SgtStubValue = New-SgtWebResponseObject -Code $Code -Location $Location
                    $global:SgtWebRequestStub = { $global:SgtStubValue }
                }
            }
            else {
                $Exception = [SgtFakeHttpResponseException]::new('Response status code does not indicate success.')
                $Exception.Response = New-SgtHttpMessage -Code $Code -Location $Location
                $global:SgtStubValue = [System.Management.Automation.ErrorRecord]::new($Exception, 'WebCmdletWebResponseException,Microsoft.PowerShell.Commands.InvokeRestMethodCommand', [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
                $global:SgtNetworkStub = { throw $global:SgtStubValue }
            }
            $global:SgtNetworkCall.Clear()
        }
        function Script:Invoke-SgtSessionTarget {
            # Runs one target and returns the session and the thrown message.
            param([string]$Target, $Case, [pscredential]$Credential)
            # Start connected, so that the assertion on _Connected after a refusal can fail.
            $Session = New-SgtTestSession -Credential $Credential -AgeHours 0
            $Message = $null
            $Result = $null
            try {
                switch ($Target) {
                    'Connect(credential)' { $Session.Connect($Credential) }
                    'Connect()' { $Session.Connect() }
                    default {
                        # Called directly: a function boundary would unroll the [PSCustomObject[]] the method returns.
                        if ($Case.HasBody -and $Case.HasObo) { $Result = $Session.InvokeQuery($Case.Method, $Case.Endpoint, $Case.Body, $Case.Obo) }
                        elseif ($Case.HasBody) { $Result = $Session.InvokeQuery($Case.Method, $Case.Endpoint, $Case.Body) }
                        elseif ($Case.HasObo) { $Result = $Session.InvokeQuery($Case.Method, $Case.Endpoint, $Case.Obo) }
                        else { $Result = $Session.InvokeQuery($Case.Method, $Case.Endpoint) }
                    }
                }
            }
            catch { $Message = $_.Exception.Message }
            [pscustomobject]@{ Session = $Session; Message = $Message; Result = $Result }
        }
    }
}

AfterAll {
    InModuleScope SendGridTools {
        Remove-Item -Path 'Function:\New-SgtWebResponseObject', 'Function:\New-SgtHttpMessage', 'Function:\New-SgtShellErrorRecord', 'Function:\Set-SgtRefusalStub', 'Function:\Invoke-SgtSessionTarget', 'Function:\New-SgtFakeWebResponse' -ErrorAction SilentlyContinue
    }
    Uninstall-SgtSessionHelper
    Disable-SgtNetworkTripwire
}

Describe 'SendGridSession sends through the transport of the shell' {
    AfterEach {
        InModuleScope SendGridTools {
            Reset-SgtNetworkStub
            $global:SgtWebRequestStub = $null
        }
    }

    It 'Calls the right command in this shell from <Label>' -ForEach $script:Targets {
        InModuleScope SendGridTools -Parameters @{ Target = $Target; Case = $Case; Cred = $script:Cred } {
            $global:SgtWebRequestStub = { New-SgtWebResponseObject -ContentType 'application/json; charset=utf-8' -Body '{"ok":"mock-response"}' }
            Set-SgtNetworkStub -Response ([pscustomobject]@{ ok = 'mock-response' })
            $Result = Invoke-SgtSessionTarget -Target $Target -Case $Case -Credential $Cred
            $Result.Message | Should -BeNullOrEmpty
            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            if ($PSVersionTable.PSEdition -eq 'Desktop') {
                $Calls[0].Command | Should -Be 'Invoke-WebRequest'
                $Calls[0].UseBasicParsing | Should -BeTrue
            }
            else {
                $Calls[0].Command | Should -Be 'Invoke-RestMethod'
            }
            $Calls[0].MaximumRedirectionPassed | Should -BeTrue
            $Calls[0].MaximumRedirection | Should -Be 0
            $Calls[0].BodyPassed | Should -Be ($null -ne $Case -and $Case.HasBody)
        }
    }

    It 'Refuses <Code> in <Label> (<Kind> Location)' -ForEach $script:RefusalCases {
        InModuleScope SendGridTools -Parameters @{ Target = $Target; Case = $Case; Code = $Code; Kind = $Kind; Cred = $script:Cred } {
            $Location = switch ($Kind) {
                'an absolute' { 'https://other.example.net/v3/scopes?token=abc' }
                'a relative' { '/v3/elsewhere' }
                default { '' }
            }
            $Named = switch ($Kind) {
                'an absolute' { 'other.example.net' }
                'a relative' { 'api.sendgrid.com' }
                default { 'an unknown host' }
            }
            Set-SgtRefusalStub -Code $Code -Location $Location
            $Result = Invoke-SgtSessionTarget -Target $Target -Case $Case -Credential $Cred
            $Result.Message | Should -BeExactly "SendGrid answered with a redirect to $Named; the request was refused so that the API key is not sent there."
            $Result.Message | Should -Not -Match 'v3|scopes|test-key-not-real'
            if ($Target -like 'Connect*') {
                $Result.Session._Connected | Should -BeFalse
            }
            else {
                $Result.Session.EndpointURL | Should -BeNullOrEmpty
            }
        }
    }

    It 'Returns what Invoke-RestMethod returns for 2xx in <Label>: <Name>' -ForEach $script:ResultCases {
        InModuleScope SendGridTools -Parameters @{ Case = $Case; Body = $Body; Cred = $script:Cred } {
            $Raw = if ($Body -eq '') { '' } else { $Body | ConvertFrom-Json }
            $global:SgtWebRequestStub = { New-SgtWebResponseObject -ContentType 'application/json; charset=utf-8' -Body $global:SgtBodyText }
            $global:SgtBodyText = $Body
            Set-SgtNetworkStub -Response $Raw
            $Result = Invoke-SgtSessionTarget -Target 'InvokeQuery' -Case $Case -Credential $Cred
            $Result.Message | Should -BeNullOrEmpty
            $Expected = [PSCustomObject[]]$Raw
            ($Result.Result -is [PSCustomObject[]]) | Should -BeTrue
            $Result.Result.Count | Should -Be $Expected.Count
            (ConvertTo-Json -InputObject $Result.Result -Compress -Depth 10) | Should -BeExactly (ConvertTo-Json -InputObject $Expected -Compress -Depth 10)
            Remove-Variable -Name SgtBodyText -Scope Global -ErrorAction SilentlyContinue
        }
    }

    It 'Gives the step 1 text for <Code> in <Label>' -ForEach $script:ErrorCases {
        InModuleScope SendGridTools -Parameters @{ Target = $Target; Case = $Case; Code = $Code; Details = $Details; Want = $Want; Cred = $script:Cred } {
            $Record = New-SgtShellErrorRecord -Code $Code -Details $Details
            Set-SgtNetworkStub -Throw $Record
            $global:SgtWebRequestStub = { throw $global:SgtStubValue }
            $Result = Invoke-SgtSessionTarget -Target $Target -Case $Case -Credential $Cred
            $Expected = if ($Want) { $Want } else { 'SendGrid Error (HTTP {0}). {1}' -f $Code, $Record.Exception.Message }
            $Result.Message | Should -BeExactly $Expected
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
