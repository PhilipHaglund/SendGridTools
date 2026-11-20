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
        function Script:New-SgtWebResponseObject {
            # The object Invoke-WebRequest -UseBasicParsing returns in Windows PowerShell 5.1, as far as the function reads it.
            param([int]$Code = 200, [string]$ContentType, [string]$Body = '', [byte[]]$Bytes, [string]$Location)
            if (-not $PSBoundParameters.ContainsKey('Bytes')) {
                $Bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($Body)
            }
            $Headers = @{}
            if ($ContentType) { $Headers['Content-Type'] = $ContentType }
            [pscustomobject]@{
                StatusCode        = $Code
                StatusDescription = "Status $Code"
                Headers           = $Headers
                RawContentStream  = [System.IO.MemoryStream]::new($Bytes)
                BaseResponse      = (New-SgtFakeWebResponse -Code $Code -Location $Location)
            }
        }
        function Script:Set-SgtWebResponse {
            # Makes the tripwire answer Invoke-WebRequest with -Response (the value is returned as it is) or throw -Throw.
            param($Response, $Throw)
            $global:SgtNetworkCall.Clear()
            if ($PSBoundParameters.ContainsKey('Throw')) {
                $global:SgtStubValue = $Throw
                $global:SgtWebRequestStub = { throw $global:SgtStubValue }
            }
            else {
                $global:SgtStubValue = $Response
                $global:SgtWebRequestStub = { $global:SgtStubValue }
            }
        }
    }
}

AfterAll {
    InModuleScope SendGridTools {
        Remove-Item -Path 'Function:\New-SgtWebResponseObject', 'Function:\Set-SgtWebResponse', 'Function:\New-SgtFakeWebResponse' -ErrorAction SilentlyContinue
    }
    Uninstall-SgtSessionHelper
    Disable-SgtNetworkTripwire
}

Describe 'Invoke-SendGridDesktopRequest' {
    BeforeAll {
        $script:Uri = 'https://api.sendgrid.com/v3/scopes'
    }

    AfterEach {
        $global:SgtWebRequestStub = $null
        $global:SgtNetworkStub = $null
        $global:SgtNetworkCall.Clear()
    }

    It 'Sends <Method> with -UseBasicParsing -MaximumRedirection 0 and the same headers and body' -ForEach @(
        @{ Method = 'Get'; HasBody = $false }
        @{ Method = 'Post'; HasBody = $true }
        @{ Method = 'Put'; HasBody = $true }
        @{ Method = 'Patch'; HasBody = $true }
        @{ Method = 'Delete'; HasBody = $true }
    ) {
        InModuleScope SendGridTools -Parameters @{ Method = $Method; HasBody = $HasBody } {
            Set-SgtWebResponse -Response (New-SgtWebResponseObject -ContentType 'application/json' -Body '{"ok":1}')
            $Headers = @{ Authorization = 'Bearer test-key-not-real' }
            $Json = '{"name":"x"}'
            if ($HasBody) {
                $null = Invoke-SendGridDesktopRequest -Method $Method -Uri 'https://api.sendgrid.com/v3/scopes' -Headers $Headers -Body $Json
            }
            else {
                $null = Invoke-SendGridDesktopRequest -Method $Method -Uri 'https://api.sendgrid.com/v3/scopes' -Headers $Headers
            }
            $Calls = @($global:SgtNetworkCall)
            $Calls.Count | Should -Be 1
            $Calls[0].Command | Should -Be 'Invoke-WebRequest'
            $Calls[0].UseBasicParsing | Should -BeTrue
            $Calls[0].MaximumRedirectionPassed | Should -BeTrue
            $Calls[0].MaximumRedirection | Should -Be 0
            $Calls[0].Method | Should -Be $Method
            "$($Calls[0].Uri)" | Should -Be 'https://api.sendgrid.com/v3/scopes'
            [object]::ReferenceEquals($Calls[0].Headers, $Headers) | Should -BeTrue
            $Calls[0].BodyPassed | Should -Be $HasBody
            if ($HasBody) { $Calls[0].Body | Should -BeExactly $Json }
        }
    }

    It 'Throws a WebException with the response for <Code>' -ForEach @(
        @{ Code = 300 }, @{ Code = 303 }, @{ Code = 304 }, @{ Code = 305 }, @{ Code = 307 }, @{ Code = 308 }
    ) {
        InModuleScope SendGridTools -Parameters @{ Code = $Code } {
            Set-SgtWebResponse -Response (New-SgtWebResponseObject -Code $Code -Location 'https://other.example.net/v3/x')
            $Caught = $null
            try { $null = Invoke-SendGridDesktopRequest -Method Get -Uri 'https://api.sendgrid.com/v3/scopes' -Headers @{ Authorization = 'Bearer test-key-not-real' } }
            catch { $Caught = $_ }
            $Caught | Should -Not -BeNullOrEmpty
            $Caught.Exception | Should -BeOfType ([System.Net.WebException])
            $Caught.Exception.Status | Should -Be ([System.Net.WebExceptionStatus]::ProtocolError)
            [int]$Caught.Exception.Response.StatusCode | Should -Be $Code
            $Caught.Exception.Response.Headers['Location'] | Should -BeExactly 'https://other.example.net/v3/x'
        }
    }

    It 'Gives the refusal text through Get-SendGridRedirectRefusal for <Code> with <Kind> Location' -ForEach @(
        foreach ($Code in 300, 303, 304, 305, 307, 308) {
            @{ Code = $Code; Kind = 'an absolute'; Location = 'https://other.example.net/v3/x'; Named = 'other.example.net' }
            @{ Code = $Code; Kind = 'a relative'; Location = '/v3/elsewhere'; Named = 'api.sendgrid.com' }
            @{ Code = $Code; Kind = 'no'; Location = ''; Named = 'an unknown host' }
        }
    ) {
        InModuleScope SendGridTools -Parameters @{ Code = $Code; Location = $Location; Named = $Named } {
            Set-SgtWebResponse -Response (New-SgtWebResponseObject -Code $Code -Location $Location)
            $Caught = $null
            try { $null = Invoke-SendGridDesktopRequest -Method Get -Uri 'https://api.sendgrid.com/v3/scopes' -Headers @{ Authorization = 'Bearer test-key-not-real' } }
            catch { $Caught = $_ }
            $Caught | Should -Not -BeNullOrEmpty
            Get-SendGridRedirectRefusal -ErrorRecord $Caught -RequestUri 'https://api.sendgrid.com/v3/scopes' |
                Should -BeExactly "SendGrid answered with a redirect to $Named; the request was refused so that the API key is not sent there."
        }
    }

    It 'Passes an Invoke-WebRequest error through unchanged (HTTP 404)' {
        InModuleScope SendGridTools {
            $Exception = [System.Net.WebException]::new('web failure', $null, [System.Net.WebExceptionStatus]::ProtocolError, (New-SgtFakeWebResponse -Code 404))
            $Record = [System.Management.Automation.ErrorRecord]::new($Exception, 'WebCmdletWebResponseException,Microsoft.PowerShell.Commands.InvokeWebRequestCommand', [System.Management.Automation.ErrorCategory]::InvalidOperation, 'sgt-target')
            $Record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new('{"errors":[{"field":"name","message":"x"}]}')
            Set-SgtWebResponse -Throw $Record
            $Caught = $null
            try { $null = Invoke-SendGridDesktopRequest -Method Get -Uri 'https://api.sendgrid.com/v3/scopes' -Headers @{ Authorization = 'Bearer test-key-not-real' } }
            catch { $Caught = $_ }
            [object]::ReferenceEquals($Caught.Exception, $Exception) | Should -BeTrue
            $Caught.ErrorDetails.Message | Should -BeExactly '{"errors":[{"field":"name","message":"x"}]}'
            $Caught.TargetObject | Should -BeExactly 'sgt-target'
            ($Caught.FullyQualifiedErrorId -split ',')[0] | Should -BeExactly 'WebCmdletWebResponseException'
            (ConvertTo-SendGridException -ErrorRecord $Caught -Context Query).Message | Should -BeExactly 'SendGrid Error (HTTP 404): "name: x"'
        }
    }

    It 'Passes an Invoke-WebRequest error through unchanged (MaximumRedirectExceeded for 302)' {
        InModuleScope SendGridTools {
            $Request = [SgtFakeWebRequest]::new()
            $Request.HaveResponse = $true
            $Request.Response = New-SgtFakeWebResponse -Code 302 -Location 'https://other.example.net/v3/x'
            $Exception = [System.InvalidOperationException]::new('The maximum redirection count has been exceeded.')
            $Record = [System.Management.Automation.ErrorRecord]::new($Exception, 'MaximumRedirectExceeded,Microsoft.PowerShell.Commands.InvokeWebRequestCommand', [System.Management.Automation.ErrorCategory]::InvalidOperation, $Request)
            $Record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new('The maximum redirection count has been exceeded.')
            Set-SgtWebResponse -Throw $Record
            $Caught = $null
            try { $null = Invoke-SendGridDesktopRequest -Method Get -Uri 'https://api.sendgrid.com/v3/scopes' -Headers @{ Authorization = 'Bearer test-key-not-real' } }
            catch { $Caught = $_ }
            [object]::ReferenceEquals($Caught.Exception, $Exception) | Should -BeTrue
            $Caught.ErrorDetails.Message | Should -BeExactly 'The maximum redirection count has been exceeded.'
            [object]::ReferenceEquals($Caught.TargetObject, $Request) | Should -BeTrue
            ($Caught.FullyQualifiedErrorId -split ',')[0] | Should -BeExactly 'MaximumRedirectExceeded'
            Get-SendGridRedirectRefusal -ErrorRecord $Caught -RequestUri 'https://api.sendgrid.com/v3/scopes' |
                Should -BeExactly 'SendGrid answered with a redirect to other.example.net; the request was refused so that the API key is not sent there.'
        }
    }

    Context 'JSON' {
        It 'Returns a JSON object as one PSCustomObject' {
            InModuleScope SendGridTools {
                Set-SgtWebResponse -Response (New-SgtWebResponseObject -ContentType 'application/json' -Body '{"id":1}')
                $Raw = (Invoke-SendGridDesktopRequest -Method Get -Uri 'https://api.sendgrid.com/v3/scopes' -Headers @{ Authorization = 'Bearer test-key-not-real' })
                $Raw | Should -BeOfType ([pscustomobject])
                $Raw.id | Should -Be 1
            }
        }

        # Windows PowerShell 5.1 only: there ConvertFrom-Json gives a list as one array; PowerShell 7 enumerates it.
        It 'Returns a JSON list of <Count> as one Object[] (Windows PowerShell 5.1 only)' -Skip:($PSVersionTable.PSEdition -ne 'Desktop') -ForEach @(
            @{ Json = '[{"id":1}]'; Count = 1 }
            @{ Json = '[{"id":1},{"id":2},{"id":3}]'; Count = 3 }
            @{ Json = '[]'; Count = 0 }
        ) {
            InModuleScope SendGridTools -Parameters @{ Json = $Json; Count = $Count } {
                Set-SgtWebResponse -Response (New-SgtWebResponseObject -ContentType 'application/json' -Body $Json)
                $Raw = (Invoke-SendGridDesktopRequest -Method Get -Uri 'https://api.sendgrid.com/v3/scopes' -Headers @{ Authorization = 'Bearer test-key-not-real' })
                ($Raw -is [object[]]) | Should -BeTrue
                $Raw.Count | Should -Be $Count
            }
        }

        It 'Decodes the body with the character set of Content-Type' {
            InModuleScope SendGridTools {
                $Text = ([string][char]0xE5) + [char]0xE4 + [char]0xF6 + ' ' + [char]::ConvertFromUtf32(0x1F600)
                $Bytes = [System.Text.UTF8Encoding]::new($false).GetBytes('{"t":"' + $Text + '"}')
                Set-SgtWebResponse -Response (New-SgtWebResponseObject -ContentType 'application/json; charset=utf-8' -Bytes $Bytes)
                $Raw = (Invoke-SendGridDesktopRequest -Method Get -Uri 'https://api.sendgrid.com/v3/scopes' -Headers @{ Authorization = 'Bearer test-key-not-real' })
                $Raw.t | Should -BeExactly $Text
            }
        }

        It 'Decodes the body as ISO-8859-1 when Content-Type names no character set' {
            InModuleScope SendGridTools {
                $Text = ([string][char]0xE5) + [char]0xE4 + [char]0xF6 + ' ' + [char]::ConvertFromUtf32(0x1F600)
                $Bytes = [System.Text.UTF8Encoding]::new($false).GetBytes('{"t":"' + $Text + '"}')
                Set-SgtWebResponse -Response (New-SgtWebResponseObject -ContentType 'application/json' -Bytes $Bytes)
                $Raw = (Invoke-SendGridDesktopRequest -Method Get -Uri 'https://api.sendgrid.com/v3/scopes' -Headers @{ Authorization = 'Bearer test-key-not-real' })
                $Expected = [System.Text.Encoding]::GetEncoding('ISO-8859-1').GetString($Bytes) | ConvertFrom-Json
                $Raw.t | Should -BeExactly $Expected.t
            }
        }

        It 'Decodes the body with the default code page for an unknown character set' {
            InModuleScope SendGridTools {
                $Text = ([string][char]0xE5) + [char]0xE4 + [char]0xF6
                $Bytes = [System.Text.UTF8Encoding]::new($false).GetBytes('{"t":"' + $Text + '"}')
                Set-SgtWebResponse -Response (New-SgtWebResponseObject -ContentType 'application/json; charset=sgt-unknown' -Bytes $Bytes)
                $Raw = (Invoke-SendGridDesktopRequest -Method Get -Uri 'https://api.sendgrid.com/v3/scopes' -Headers @{ Authorization = 'Bearer test-key-not-real' })
                $Expected = [System.Text.Encoding]::GetEncoding(0).GetString($Bytes) | ConvertFrom-Json
                $Raw.t | Should -BeExactly $Expected.t
            }
        }
    }

    It 'Returns empty text for an empty body (<Code>, <ContentType>)' -ForEach @(
        @{ Code = 200; ContentType = 'application/json' }
        @{ Code = 202; ContentType = '' }
        @{ Code = 204; ContentType = '' }
    ) {
        InModuleScope SendGridTools -Parameters @{ Code = $Code; ContentType = $ContentType } {
            Set-SgtWebResponse -Response (New-SgtWebResponseObject -Code $Code -ContentType $ContentType -Body '')
            $Raw = (Invoke-SendGridDesktopRequest -Method Get -Uri 'https://api.sendgrid.com/v3/scopes' -Headers @{ Authorization = 'Bearer test-key-not-real' })
            ($Raw -is [string]) | Should -BeTrue
            $Raw | Should -BeExactly ''
        }
    }

    It 'Returns text and XML as Invoke-RestMethod does: <Name>' -ForEach @(
        @{ Name = 'plain text'; ContentType = 'text/plain'; Body = 'sgt plain text'; Kind = 'String'; Want = 'sgt plain text' }
        @{ Name = 'a JSON number after XML fails'; ContentType = 'text/plain'; Body = '1001'; Kind = 'Number'; Want = 1001 }
        @{ Name = 'well-formed HTML'; ContentType = 'text/html'; Body = '<html><body><p>sgt</p></body></html>'; Kind = 'Xml'; Want = '<html><body><p>sgt</p></body></html>' }
        @{ Name = 'HTML that is not XML'; ContentType = 'text/html'; Body = '<!DOCTYPE html><html><body><p>sgt html<br></body></html>'; Kind = 'String'; Want = '<!DOCTYPE html><html><body><p>sgt html<br></body></html>' }
        @{ Name = 'XML under a JSON content type'; ContentType = 'application/json'; Body = '<sgt><a>1</a></sgt>'; Kind = 'Xml'; Want = '<sgt><a>1</a></sgt>' }
    ) {
        InModuleScope SendGridTools -Parameters @{ ContentType = $ContentType; Body = $Body; Kind = $Kind; Want = $Want } {
            Set-SgtWebResponse -Response (New-SgtWebResponseObject -ContentType $ContentType -Body $Body)
            $Raw = (Invoke-SendGridDesktopRequest -Method Get -Uri 'https://api.sendgrid.com/v3/scopes' -Headers @{ Authorization = 'Bearer test-key-not-real' })
            switch ($Kind) {
                'String' { ($Raw -is [string]) | Should -BeTrue; $Raw | Should -BeExactly $Want }
                'Number' { $Raw | Should -Be $Want }
                'Xml' { $Raw | Should -BeOfType ([System.Xml.XmlDocument]); $Raw.OuterXml | Should -BeExactly $Want }
            }
        }
    }

    It 'Returns the items of an RSS feed one by one' {
        InModuleScope SendGridTools {
            $Feed = '<rss version="2.0"><channel><title>sgt</title><item><title>sgt-1</title></item><item><title>sgt-2</title></item></channel></rss>'
            Set-SgtWebResponse -Response (New-SgtWebResponseObject -ContentType 'application/rss+xml' -Body $Feed)
            $Items = @(Invoke-SendGridDesktopRequest -Method Get -Uri 'https://api.sendgrid.com/v3/scopes' -Headers @{ Authorization = 'Bearer test-key-not-real' })
            $Items.Count | Should -Be 2
            $Items[0] | Should -BeOfType ([System.Xml.XmlElement])
            $Items[0].OuterXml | Should -BeExactly '<item><title>sgt-1</title></item>'
            $Items[1].OuterXml | Should -BeExactly '<item><title>sgt-2</title></item>'
        }
    }

    It 'Returns nothing when Invoke-WebRequest returns nothing' {
        InModuleScope SendGridTools {
            $global:SgtNetworkCall.Clear()
            $global:SgtWebRequestStub = { }
            $Items = @(Invoke-SendGridDesktopRequest -Method Get -Uri 'https://api.sendgrid.com/v3/scopes' -Headers @{ Authorization = 'Bearer test-key-not-real' })
            $Items.Count | Should -Be 0
        }
    }

    It 'Leaves the caller''s ProgressPreference unchanged' {
        InModuleScope SendGridTools {
            Set-SgtWebResponse -Response (New-SgtWebResponseObject -ContentType 'application/json' -Body '{"ok":1}')
            $ProgressPreference = 'Continue'
            $null = Invoke-SendGridDesktopRequest -Method Get -Uri 'https://api.sendgrid.com/v3/scopes' -Headers @{ Authorization = 'Bearer test-key-not-real' }
            $ProgressPreference | Should -Be 'Continue'
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
