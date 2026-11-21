BeforeDiscovery {
    # M1: what the session sends for non-ASCII text in a body. M2: what it makes of a 200 answer. M3: what it makes of a 400 answer.
    $script:M1Case = @(
        @{ CaseName = 'Post (method, endpoint, body)'; Method = 'Post'; HasObo = $false }
        @{ CaseName = 'Patch (method, endpoint, body, onBehalfOf)'; Method = 'Patch'; HasObo = $true }
    )
    $script:M2Case = @(
        @{ CaseName = 'application/json, UTF-8 bytes'; ContentType = 'application/json'; Charset = 'utf-8'; Escaped = $false }
        @{ CaseName = 'application/json; charset=utf-8, UTF-8 bytes'; ContentType = 'application/json; charset=utf-8'; Charset = 'utf-8'; Escaped = $false }
        @{ CaseName = 'application/json; charset=iso-8859-1, ISO-8859-1 bytes'; ContentType = 'application/json; charset=iso-8859-1'; Charset = 'iso-8859-1'; Escaped = $true }
        @{ CaseName = 'text/plain, UTF-8 bytes'; ContentType = 'text/plain'; Charset = 'utf-8'; Escaped = $false }
    )
    $script:M3Case = @(
        @{ CaseName = 'application/json'; ContentType = 'application/json' }
        @{ CaseName = 'application/json; charset=utf-8'; ContentType = 'application/json; charset=utf-8' }
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
    $script:Cred = [pscredential]::new('apikey', (ConvertTo-SecureString -String 'not-a-real-key' -AsPlainText -Force))
    $script:Shell = '{0} {1}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion
    # a-ring, a-diaeresis, o-diaeresis, e-acute, euro sign and a grinning face (a surrogate pair), built from code points
    # so that the file stays ASCII and Windows PowerShell 5.1 reads it the same way as PowerShell 7.
    $script:Sample = [string][char]0xE5 + [char]0xE4 + [char]0xF6 + [char]0xE9 + [char]0x20AC + [char]::ConvertFromUtf32(0x1F600)
    $script:Utf8 = [System.Text.UTF8Encoding]::new($false)
    $script:Latin1 = [System.Text.Encoding]::GetEncoding('iso-8859-1')

    function script:Format-SgtCodePoint {
        # Code points as a U+XXXX list, a surrogate pair as one code point, so console encoding cannot distort the record.
        param([AllowNull()][string]$Text)
        if ($null -eq $Text) { return '(null)' }
        $List = [System.Collections.Generic.List[string]]::new()
        $Index = 0
        while ($Index -lt $Text.Length) {
            if ([char]::IsHighSurrogate($Text[$Index]) -and ($Index + 1) -lt $Text.Length -and [char]::IsLowSurrogate($Text[$Index + 1])) {
                $List.Add(('U+{0:X4}' -f [char]::ConvertToUtf32($Text[$Index], $Text[$Index + 1])))
                $Index += 2
            }
            else {
                $List.Add(('U+{0:X4}' -f [int]$Text[$Index]))
                $Index++
            }
        }
        $List -join ' '
    }

    function script:Start-SgtLoopbackListener {
        # Starts an HttpListener on 127.0.0.1 on a free port and serves exactly one request in a separate runspace.
        # The caller must call Stop-SgtLoopbackListener in a finally block.
        param([int]$Status = 200, [string]$ContentType = '', [byte[]]$Body = [byte[]]@())
        $Listener = $null
        $Port = 0
        for ($Try = 1; $Try -le 5 -and $null -eq $Listener; $Try++) {
            $Probe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
            $Probe.Start()
            $Port = ([System.Net.IPEndPoint]$Probe.LocalEndpoint).Port
            $Probe.Stop()
            $Candidate = [System.Net.HttpListener]::new()
            $Candidate.Prefixes.Add(('http://127.0.0.1:{0}/' -f $Port))
            try {
                $Candidate.Start()
                $Listener = $Candidate
            }
            catch {
                $Candidate.Close()
            }
        }
        if ($null -eq $Listener) { throw 'Could not start a loopback listener on a free port.' }
        $Script = {
            param($Listener, [int]$Status, [string]$ContentType, [byte[]]$Body)
            $Task = $Listener.GetContextAsync()
            if (-not $Task.Wait(15000)) { return $null }
            $Context = $Task.Result
            $Request = $Context.Request
            $Memory = [System.IO.MemoryStream]::new()
            $Request.InputStream.CopyTo($Memory)
            $Record = @{
                Method        = $Request.HttpMethod
                Path          = $Request.Url.AbsolutePath
                ContentType   = $Request.ContentType
                Authorization = ($Request.Headers['Authorization'] -eq 'Bearer not-a-real-key')
                Body          = $Memory.ToArray()
            }
            $Response = $Context.Response
            $Response.StatusCode = $Status
            if ($ContentType) { $Response.ContentType = $ContentType }
            $Response.ContentLength64 = $Body.Length
            if ($Body.Length -gt 0) { $Response.OutputStream.Write($Body, 0, $Body.Length) }
            $Response.OutputStream.Close()
            $Response.Close()
            $Record
        }
        $Runspace = [powershell]::Create()
        $null = $Runspace.AddScript($Script).AddArgument($Listener).AddArgument($Status).AddArgument($ContentType).AddArgument($Body)
        $Handle = $Runspace.BeginInvoke()
        [pscustomobject]@{ Listener = $Listener; Runspace = $Runspace; Handle = $Handle; Port = $Port }
    }

    function script:Stop-SgtLoopbackListener {
        # Returns the one recorded request, or $null when none arrived. Always stops and disposes listener and runspace.
        param($Server)
        $Record = $null
        try {
            if ($Server.Handle.AsyncWaitHandle.WaitOne(15000)) {
                $Record = @($Server.Runspace.EndInvoke($Server.Handle))[0]
            }
        }
        finally {
            try { $Server.Listener.Stop() } catch { $null = $_ }
            try { $Server.Listener.Close() } catch { $null = $_ }
            try { $Server.Runspace.Stop() } catch { $null = $_ }
            $Server.Runspace.Dispose()
        }
        $Record
    }

    InModuleScope SendGridTools {
        function Script:Invoke-SgtLoopbackQuery {
            # Sends one request to the loopback listener through SendGridSession.InvokeQuery and reports the result or the error.
            # The two global tripwire functions are removed for this call only and restored in finally.
            param([int]$Port, [string]$Method, [string]$Endpoint, [hashtable]$Body, [string]$OnBehalfOf, [pscredential]$Credential)
            $Session = [SendGridSession]::new([uri]('http://127.0.0.1:{0}/v3' -f $Port))
            $Session._Credential = $Credential
            $Session._Connected = $true
            $Session._CreateDateTime = Get-Date
            if ($Session._BaseURL.Host -ne '127.0.0.1') { throw 'The loopback measurement may only call 127.0.0.1.' }
            $Saved = @{}
            foreach ($Name in 'Invoke-RestMethod', 'Invoke-WebRequest') {
                $Saved[$Name] = (Get-Command -Name $Name -CommandType Function).ScriptBlock
            }
            $Proxy = [System.Net.WebProxy]::new()
            $SavedWebProxy = [System.Net.WebRequest]::DefaultWebProxy
            $SavedHttpProxy = $null
            if ($PSVersionTable.PSEdition -ne 'Desktop') { $SavedHttpProxy = [System.Net.Http.HttpClient]::DefaultProxy }
            $Out = @{ Result = $null; Error = $null }
            try {
                foreach ($Name in $Saved.Keys) { Remove-Item -Path ('Function:\{0}' -f $Name) }
                if ($PSVersionTable.PSEdition -eq 'Desktop') { [System.Net.WebRequest]::DefaultWebProxy = $Proxy }
                else { [System.Net.Http.HttpClient]::DefaultProxy = $Proxy }
                try {
                    if ($null -ne $Body -and $OnBehalfOf) { $Out.Result = $Session.InvokeQuery($Method, $Endpoint, $Body, $OnBehalfOf) }
                    elseif ($null -ne $Body) { $Out.Result = $Session.InvokeQuery($Method, $Endpoint, $Body) }
                    elseif ($OnBehalfOf) { $Out.Result = $Session.InvokeQuery($Method, $Endpoint, $OnBehalfOf) }
                    else { $Out.Result = $Session.InvokeQuery($Method, $Endpoint) }
                }
                catch {
                    $Out.Error = $_
                }
            }
            finally {
                if ($PSVersionTable.PSEdition -eq 'Desktop') { [System.Net.WebRequest]::DefaultWebProxy = $SavedWebProxy }
                elseif ($null -ne $SavedHttpProxy) { [System.Net.Http.HttpClient]::DefaultProxy = $SavedHttpProxy }
                foreach ($Name in $Saved.Keys) { Set-Item -Path ('Function:\global:{0}' -f $Name) -Value $Saved[$Name] }
            }
            [pscustomobject]$Out
        }
    }
}

AfterAll {
    InModuleScope SendGridTools {
        Remove-Item -Path 'Function:\Invoke-SgtLoopbackQuery' -ErrorAction SilentlyContinue
    }
    Remove-Item -Path 'Function:\Format-SgtCodePoint', 'Function:\Start-SgtLoopbackListener', 'Function:\Stop-SgtLoopbackListener' -ErrorAction SilentlyContinue
    Uninstall-SgtSessionHelper
    Disable-SgtNetworkTripwire
}

# Sprint 7 step 2 measurements (M1-M3): non-ASCII text over a real loopback socket, in both directions. Each It writes MEASURE
# lines and asserts only that the listener got one request with the expected method and Authorization and that the tripwire is
# still active, never the measured value, so the same file measures any version of the module. Only 127.0.0.1 is called.
Describe 'Sprint 7 step 2 measurements' {
    It 'M1: <CaseName>' -ForEach $script:M1Case {
        $Server = Start-SgtLoopbackListener -Status 200 -ContentType 'application/json' -Body $script:Utf8.GetBytes('{}')
        $Record = $null
        try {
            $Params = @{ Port = $Server.Port; Method = $Method; Endpoint = 'sgt/measure'; Body = @{ name = $script:Sample }; Credential = $script:Cred }
            if ($HasObo) { $Params['OnBehalfOf'] = 'sgt-subuser' }
            $Query = InModuleScope SendGridTools -Parameters @{ Params = $Params } { Invoke-SgtLoopbackQuery @Params }
        }
        finally {
            $Record = Stop-SgtLoopbackListener -Server $Server
        }
        Assert-SgtNetworkTripwireActive
        $Record | Should -Not -BeNullOrEmpty
        $Record.Method | Should -Be $Method.ToUpperInvariant()
        $Record.Authorization | Should -BeTrue
        $Bytes = [byte[]]$Record.Body
        $Quote = @(for ($i = 0; $i -lt $Bytes.Length; $i++) { if ($Bytes[$i] -eq 0x22) { $i } })
        if ($Quote.Count -ge 4) {
            $Part = [byte[]]@($Bytes[($Quote[2] + 1)..($Quote[3] - 1)])
            $Hex = ($Part | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
            $IsUtf8 = (($Part | ForEach-Object { '{0:X2}' -f $_ }) -join ' ') -eq (($script:Utf8.GetBytes($script:Sample) | ForEach-Object { '{0:X2}' -f $_ }) -join ' ')
        }
        else {
            $Hex = '(fewer than four quotes in the body)'
            $IsUtf8 = $false
        }
        Write-Host ('MEASURE M1 [{0}] {1}: request Content-Type={2}; bytes={3}; utf8={4}' -f $script:Shell, $CaseName, $Record.ContentType, $Hex, $IsUtf8)
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }

    It 'M2: 200 answer <CaseName>' -ForEach $script:M2Case {
        if ($Escaped) {
            # The euro sign and the emoji as JSON escapes (a backslash built from its code point, so the file holds no escape text).
            $Slash = [string][char]92
            $Text = '{"name":"' + [string][char]0xE5 + [char]0xE4 + [char]0xF6 + [char]0xE9 + $Slash + 'u20ac' + $Slash + 'ud83d' + $Slash + 'ude00"}'
        }
        else {
            $Text = '{"name":"' + $script:Sample + '"}'
        }
        $Encoding = if ($Charset -eq 'iso-8859-1') { $script:Latin1 } else { $script:Utf8 }
        $Server = Start-SgtLoopbackListener -Status 200 -ContentType $ContentType -Body $Encoding.GetBytes($Text)
        $Record = $null
        try {
            $Query = InModuleScope SendGridTools -Parameters @{ Port = $Server.Port; Cred = $script:Cred } { Invoke-SgtLoopbackQuery -Port $Port -Method Get -Endpoint 'sgt/measure' -Credential $Cred }
        }
        finally {
            $Record = Stop-SgtLoopbackListener -Server $Server
        }
        Assert-SgtNetworkTripwireActive
        $Record | Should -Not -BeNullOrEmpty
        $Record.Method | Should -Be 'GET'
        $Record.Authorization | Should -BeTrue
        if ($null -ne $Query.Error) {
            $Seen = 'error: {0}' -f (Format-SgtCodePoint -Text ([string]$Query.Error.Exception.Message))
            $Ok = $false
        }
        else {
            $Item = @($Query.Result)[0]
            $Value = if ($Item -is [string]) { $Item } elseif ($null -ne $Item -and $null -ne $Item.PSObject.Properties['name']) { [string]$Item.name } else { $null }
            $Seen = 'name={0}' -f (Format-SgtCodePoint -Text $Value)
            $Ok = ($Value -ceq $script:Sample)
        }
        Write-Host ('MEASURE M2 [{0}] {1}: {2}; ok={3}' -f $script:Shell, $CaseName, $Seen, $Ok)
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }

    It 'M3: 400 answer <CaseName>' -ForEach $script:M3Case {
        $Text = '{"errors":[{"field":"name","message":"' + $script:Sample + '"}]}'
        $Server = Start-SgtLoopbackListener -Status 400 -ContentType $ContentType -Body $script:Utf8.GetBytes($Text)
        $Record = $null
        try {
            $Query = InModuleScope SendGridTools -Parameters @{ Port = $Server.Port; Cred = $script:Cred } { Invoke-SgtLoopbackQuery -Port $Port -Method Get -Endpoint 'sgt/measure' -Credential $Cred }
        }
        finally {
            $Record = Stop-SgtLoopbackListener -Server $Server
        }
        Assert-SgtNetworkTripwireActive
        $Record | Should -Not -BeNullOrEmpty
        $Record.Method | Should -Be 'GET'
        $Record.Authorization | Should -BeTrue
        if ($null -eq $Query.Error) {
            $Seen = 'no error thrown'
            $Ok = $false
        }
        else {
            $Message = [string]$Query.Error.Exception.Message
            # The message part of the exception text: what follows "name: " up to the end of the line or the closing quote.
            $Part = $Message
            $Start = $Message.IndexOf('name: ')
            if ($Start -ge 0) {
                $Part = $Message.Substring($Start + 6)
                $End = $Part.IndexOfAny([char[]]@([char]34, [char]10, [char]13))
                if ($End -ge 0) { $Part = $Part.Substring(0, $End) }
            }
            $Data = $null
            $Errors = $Query.Error.Exception.Data['SendGridErrors']
            if ($null -ne $Errors -and @($Errors).Count -gt 0) { $Data = [string]@($Errors)[0].Message }
            $Seen = 'exception={0}; data={1}' -f (Format-SgtCodePoint -Text $Part), (Format-SgtCodePoint -Text $Data)
            $Ok = ($Part.Contains($script:Sample) -and ($Data -ceq $script:Sample))
        }
        Write-Host ('MEASURE M3 [{0}] {1}: {2}; ok={3}' -f $script:Shell, $CaseName, $Seen, $Ok)
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}

Describe 'Sprint 7 step 2 locks' {
    It 'D178: a 200 application/json answer without a character set is decoded as UTF-8' {
        $Server = Start-SgtLoopbackListener -Status 200 -ContentType 'application/json' -Body $script:Utf8.GetBytes('{"name":"' + $script:Sample + '"}')
        $Record = $null
        try {
            $Query = InModuleScope SendGridTools -Parameters @{ Port = $Server.Port; Cred = $script:Cred } { Invoke-SgtLoopbackQuery -Port $Port -Method Get -Endpoint 'sgt/lock' -Credential $Cred }
        }
        finally {
            $Record = Stop-SgtLoopbackListener -Server $Server
        }
        Assert-SgtNetworkTripwireActive
        $Record | Should -Not -BeNullOrEmpty
        $Record.Method | Should -Be 'GET'
        $Record.Authorization | Should -BeTrue
        $Query.Error | Should -BeNullOrEmpty
        $Item = @($Query.Result)[0]
        $Item.name | Should -BeExactly $script:Sample
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }

    It 'D179: <CaseName> sends exactly the UTF-8 bytes of the text, with a UTF-8 content type' -ForEach $script:M1Case {
        $Server = Start-SgtLoopbackListener -Status 200 -ContentType 'application/json' -Body $script:Utf8.GetBytes('{}')
        $Record = $null
        try {
            $Params = @{ Port = $Server.Port; Method = $Method; Endpoint = 'sgt/lock'; Body = @{ name = $script:Sample }; Credential = $script:Cred }
            if ($HasObo) { $Params['OnBehalfOf'] = 'sgt-subuser' }
            $Query = InModuleScope SendGridTools -Parameters @{ Params = $Params } { Invoke-SgtLoopbackQuery @Params }
        }
        finally {
            $Record = Stop-SgtLoopbackListener -Server $Server
        }
        Assert-SgtNetworkTripwireActive
        $Record | Should -Not -BeNullOrEmpty
        $Record.Method | Should -Be $Method.ToUpperInvariant()
        $Record.Authorization | Should -BeTrue
        $Query.Error | Should -BeNullOrEmpty
        $Bytes = [byte[]]$Record.Body
        $Quote = @(for ($i = 0; $i -lt $Bytes.Length; $i++) { if ($Bytes[$i] -eq 0x22) { $i } })
        $Quote.Count | Should -BeGreaterOrEqual 4
        $Part = [byte[]]@($Bytes[($Quote[2] + 1)..($Quote[3] - 1)])
        ($Part | ForEach-Object { '{0:X2}' -f $_ }) -join ' ' | Should -BeExactly (($script:Utf8.GetBytes($script:Sample) | ForEach-Object { '{0:X2}' -f $_ }) -join ' ')
        $Record.ContentType | Should -BeExactly 'application/json; charset=utf-8'
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
