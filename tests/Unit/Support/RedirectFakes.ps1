# Fake web types for the redirect tests. Not a test file.
# Add-SgtRedirectFake defines three small C# types once per process: a fake WebResponse, a fake WebRequest and
# an exception that carries an HttpResponseMessage. They stand in for what Invoke-RestMethod throws in
# Windows PowerShell 5.1 and PowerShell 7, so no real request is needed. The C# stays at language level 5
# so that the Windows PowerShell 5.1 compiler accepts it.

function Add-SgtRedirectFake {
    if ('SgtFakeWebResponse' -as [type]) { return }
    Add-Type -AssemblyName System.Net.Http
    # The types sit in different assemblies in PowerShell 7 and in one (System.dll) in Windows PowerShell 5.1.
    $Reference = @(
        [System.Net.Http.HttpResponseMessage], [System.Net.WebResponse], [System.Net.WebRequest]
        [System.Net.WebHeaderCollection], [System.Net.HttpStatusCode], [System.Uri]
    ) | ForEach-Object { $_.Assembly.Location } | Select-Object -Unique
    $Source = @'
using System;
using System.Net;
using System.Net.Http;

public class SgtFakeWebResponse : WebResponse
{
    private WebHeaderCollection _headers = new WebHeaderCollection();
    public HttpStatusCode StatusCode { get; set; }
    public override WebHeaderCollection Headers { get { return _headers; } }
}

public class SgtFakeWebRequest : WebRequest
{
    public bool HaveResponse { get; set; }
    public bool ThrowOnGetResponse { get; set; }
    public WebResponse Response { get; set; }
    public override WebResponse GetResponse()
    {
        if (ThrowOnGetResponse) { throw new InvalidOperationException("The cached response is not readable."); }
        return Response;
    }
}

public class SgtFakeHttpResponseException : Exception
{
    public SgtFakeHttpResponseException(string message) : base(message) { }
    public HttpResponseMessage Response { get; set; }
}
'@
    # SYSLIB0014 (the obsolete WebRequest constructor) is expected in PowerShell 7 and is not part of what the tests check.
    Add-Type -TypeDefinition $Source -ReferencedAssemblies $Reference -IgnoreWarnings -WarningAction SilentlyContinue
}

function Install-SgtRedirectBuilder {
    # Defines the fixture builder both redirect test files share inside the SendGridTools module scope.
    # Each file removes it in AfterAll with Remove-Item 'Function:\New-SgtFakeWebResponse'.
    InModuleScope SendGridTools {
        function Script:New-SgtFakeWebResponse {
            param([int]$Code, [string]$Location)
            $Response = [SgtFakeWebResponse]::new()
            $Response.StatusCode = [System.Enum]::ToObject([System.Net.HttpStatusCode], $Code)
            if ($Location) { $Response.Headers['Location'] = $Location }
            $Response
        }
    }
}
