<#
.SYNOPSIS
Sends one SendGrid request in Windows PowerShell 5.1 and refuses every HTTP redirect, not only 301 and 302.

.DESCRIPTION
In Windows PowerShell 5.1, Invoke-RestMethod -MaximumRedirection 0 raises an error only for 301 and 302 and returns every other 3xx
answer as an empty or ordinary result, and it cannot report the status of a successful answer. Invoke-SendGridDesktopRequest sends the
request with Invoke-WebRequest -UseBasicParsing -MaximumRedirection 0 -ErrorAction Stop instead, with the same method, address,
headers and body. A 3xx answer is thrown as a WebException that carries the response, which Get-SendGridRedirectRefusal turns into
the refusal. Every other answer is turned into the result Invoke-RestMethod gives in Windows PowerShell 5.1: an RSS or Atom feed gives
its items, JSON gives the parsed objects (a list as one array), XML gives an XmlDocument, and anything else the text. An HTTP error
(4xx, 5xx) and a 301 or 302 are the errors Invoke-WebRequest raises, passed on unchanged.

.PARAMETER Method
The HTTP method, as given to Invoke-RestMethod.

.PARAMETER Uri
The address to send the request to.

.PARAMETER Headers
The request headers, including Authorization and Content-Type.

.PARAMETER Body
The request body. It is passed on only when given, as Invoke-RestMethod -Body is.

.EXAMPLE
$Query = (Invoke-SendGridDesktopRequest -Method Get -Uri $Uri -Headers $Headers)

Returns what Invoke-RestMethod returns in Windows PowerShell 5.1, and throws for every 3xx answer.

#>
function Invoke-SendGridDesktopRequest {
    [CmdletBinding()]
    param (
        # The HTTP method, as given to Invoke-RestMethod.
        [Parameter(Mandatory)]
        [string]$Method,

        # The address to send the request to.
        [Parameter(Mandatory)]
        [uri]$Uri,

        # The request headers.
        [Parameter(Mandatory)]
        [hashtable]$Headers,

        # The request body, passed on only when given.
        [Parameter()]
        [object]$Body
    )

    # Invoke-WebRequest draws a progress bar in Windows PowerShell 5.1; keep it quiet in this function only.
    $ProgressPreference = 'SilentlyContinue'
    $Request = @{
        Method             = $Method
        Uri                = $Uri
        Headers            = $Headers
        UseBasicParsing    = $true
        MaximumRedirection = 0
        ErrorAction        = 'Stop'
    }
    if ($PSBoundParameters.ContainsKey('Body')) {
        $Request['Body'] = $Body
    }
    $Response = Invoke-WebRequest @Request
    if ($null -eq $Response) {
        return
    }

    $Status = [int]$Response.StatusCode
    if ($Status -ge 300 -and $Status -le 399) {
        # Thrown in the shape of a protocol error with the response, so Get-SendGridRedirectRefusal reads the status and Location.
        $WebResponse = if ($Response.BaseResponse -is [System.Net.WebResponse]) { $Response.BaseResponse } else { $null }
        $Message = 'The remote server answered with a redirect: ({0}) {1}.' -f $Status, $Response.StatusDescription
        throw [System.Net.WebException]::new($Message, $null, [System.Net.WebExceptionStatus]::ProtocolError, $WebResponse)
    }

    # The body bytes and the Content-Type header, as Invoke-RestMethod reads them.
    $Bytes = [byte[]]@()
    if ($null -ne $Response.RawContentStream) {
        $Bytes = $Response.RawContentStream.ToArray()
    }
    $ContentType = ''
    if ($null -ne $Response.Headers) {
        $HeaderValue = $Response.Headers['Content-Type']
        if ($null -ne $HeaderValue) {
            $ContentType = (@($HeaderValue) | ForEach-Object { "$_" }) -join ', '
        }
    }

    # 1. An RSS or Atom feed gives its items, one by one (Invoke-RestMethod checks this first, for every answer).
    $XmlSettings = [System.Xml.XmlReaderSettings]::new()
    $XmlSettings.CheckCharacters = $false
    $XmlSettings.CloseInput = $false
    $XmlSettings.IgnoreProcessingInstructions = $true
    $XmlSettings.MaxCharactersFromEntities = 1024
    $XmlSettings.DtdProcessing = [System.Xml.DtdProcessing]::Ignore
    $XmlSettings.XmlResolver = $null
    $FeedItems = [System.Collections.Generic.List[object]]::new()
    $IsFeed = $false
    try {
        $Reader = [System.Xml.XmlReader]::Create([System.IO.MemoryStream]::new($Bytes), $XmlSettings)
        $ReadCount = 0
        while ($ReadCount -lt 10 -and $Reader.Read()) {
            if ([string]::Equals('rss', $Reader.Name, [StringComparison]::OrdinalIgnoreCase) -or [string]::Equals('feed', $Reader.Name, [StringComparison]::OrdinalIgnoreCase)) {
                $IsFeed = $true
                break
            }
            $ReadCount++
        }
        if ($IsFeed) {
            $Document = [System.Xml.XmlDocument]::new()
            $null = $Reader.Read()
            while (-not $Reader.EOF) {
                if ($Reader.NodeType -eq [System.Xml.XmlNodeType]::Element -and ([string]::Equals('Item', $Reader.Name, [StringComparison]::OrdinalIgnoreCase) -or [string]::Equals('Entry', $Reader.Name, [StringComparison]::OrdinalIgnoreCase))) {
                    $FeedItems.Add($Document.ReadNode($Reader))
                }
                else {
                    $null = $Reader.Read()
                }
            }
        }
    }
    catch [System.Xml.XmlException] {
        # Not a feed; Invoke-RestMethod goes on in the same way and writes nothing.
        $null = $_
    }
    if ($IsFeed) {
        foreach ($Item in $FeedItems) { $PSCmdlet.WriteObject($Item, $false) }
        return
    }

    # 2. The text, decoded with the character set of Content-Type, or ISO-8859-1 when it names none
    #    (the rule of HttpWebResponse.CharacterSet that Invoke-RestMethod reads).
    $CharacterSet = $null
    if (-not [string]::IsNullOrEmpty($ContentType)) {
        $CharacterSet = ''
        $Search = $ContentType.ToLowerInvariant()
        if ($Search.Trim().StartsWith('text/')) {
            $CharacterSet = 'ISO-8859-1'
        }
        $Index = $Search.IndexOf(';')
        if ($Index -gt 0) {
            while (($Index = $Search.IndexOf('charset', $Index)) -ge 0) {
                $Index += 7
                if ($Search[$Index - 8] -eq [char]';' -or $Search[$Index - 8] -eq [char]' ') {
                    while ($Index -lt $Search.Length -and $Search[$Index] -eq [char]' ') { $Index++ }
                    if ($Index -lt $Search.Length - 1 -and $Search[$Index] -eq [char]'=') {
                        $Index++
                        $End = $Search.IndexOf(';', $Index)
                        $CharacterSet = if ($End -gt $Index) { $ContentType.Substring($Index, $End - $Index).Trim() } else { $ContentType.Substring($Index).Trim() }
                        break
                    }
                }
            }
        }
    }
    $CodePage = if ([string]::IsNullOrEmpty($CharacterSet)) { 'ISO-8859-1' } else { $CharacterSet }
    try {
        $Encoding = [System.Text.Encoding]::GetEncoding($CodePage)
    }
    catch {
        $Encoding = [System.Text.Encoding]::GetEncoding(0)
    }
    $Text = $Encoding.GetString($Bytes)

    # 3. JSON first when Content-Type names JSON, XML first otherwise; the text when neither parses.
    $Signature = ($ContentType -split ';', 2)[0]
    $IsJson = $false
    if (-not [string]::IsNullOrEmpty($Signature)) {
        $IsJson = @('application/json', 'text/json', 'application/x-javascript', 'text/x-javascript', 'application/javascript', 'text/javascript') -contains $Signature.ToLowerInvariant()
    }
    $Order = if ($IsJson) { 'Json', 'Xml' } else { 'Xml', 'Json' }
    foreach ($Kind in $Order) {
        $Parsed = $null
        if ($Kind -eq 'Json') {
            try {
                $Parsed = ConvertFrom-Json -InputObject $Text -ErrorAction Stop
            }
            catch {
                $Parsed = $null
            }
        }
        else {
            try {
                $XmlReader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($Text), $XmlSettings)
                $XmlDocument = [System.Xml.XmlDocument]::new()
                $XmlDocument.PreserveWhitespace = $true
                $XmlDocument.Load($XmlReader)
                $Parsed = $XmlDocument
            }
            catch {
                $Parsed = $null
            }
        }
        if ($null -ne $Parsed) {
            # One object, not enumerated: a JSON list stays one array, as Invoke-RestMethod writes it in Windows PowerShell 5.1.
            $PSCmdlet.WriteObject($Parsed, $false)
            return
        }
    }
    $PSCmdlet.WriteObject($Text, $false)
}
