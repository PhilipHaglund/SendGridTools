function Invoke-SGCommand {
    <#
    .SYNOPSIS
        A wrapper for the Invoke-SendGrid function.

    .DESCRIPTION
        Invoke-SGCommand is a wrapper for the Invoke-SendGrid function. It allows you to make API calls to SendGrid.

    .PARAMETER WebMethod
        Specifies the HTTP method to use for the API call. The default value is 'Get'.

    .PARAMETER Namespace
        Specifies the API path to call, relative to the session's base URL, for example 'scopes' or 'v3/scopes', or a full URL on the session's own host, for example 'https://api.eu.sendgrid.com/v3/scopes'. A full URL on any other host is refused and no request is sent.

    .PARAMETER ContentBody
        Specifies the content body for the API call. It should be a hashtable.

    .PARAMETER QueryParameters
        Specifies the query parameters to append to the request, for example limit or offset. Each item must contain the query parameter name followed by = and the value, for example limit=10.

    .PARAMETER OnBehalfOf
        Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.

    .EXAMPLE
        PS C:\> Invoke-SGCommand -WebMethod 'Get' -Namespace 'v3/mail_settings' -ContentBody @{ 'limit' = 10; 'offset' = 0 }

        This command makes a 'Get' API call to SendGrid with the URL path 'v3/mail_settings' and the content body '{ 'limit' = 10; 'offset' = 0 }'.

    .EXAMPLE
        PS C:\> Invoke-SGCommand -Namespace 'https://api.eu.sendgrid.com/v3/scopes'

        This command makes a 'Get' API call with a full URL. It works in a session connected to the EU region, and is refused in a session connected to any other host.
    #>
    [CmdletBinding(
        SupportsShouldProcess
    )]
    param (
        # Specifies the URL path for the API call.
        [Parameter(
            Mandatory,
            Position = 0
        )]
        [Alias('UrlPath', 'Path')]
        [string]$Namespace,

        # Specifies the HTTP method to use for the API call. The default value is 'Get'.
        [Parameter(
            Position = 1
        )]
        [ValidateSet('Get', 'Post', 'Put', 'Delete', 'Patch')]
        [string]$WebMethod = 'Get',

        # Specifies the content body for the API call. It should be a hashtable.
        [Parameter(
            Position = 2
        )]
        [HashTable]$ContentBody,

        # Specifies if the SGCommand takes Query parameters like limit or offset. Should contain the query parameter followed by = and the value. Example: limit=10
        [Parameter(
            Position = 3
        )]
        [System.Collections.Generic.List[string]]$QueryParameters = [System.Collections.Generic.List[string]]::new(),

        # Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
        [Parameter()]
        [string]$OnBehalfOf
    )
    process {

        if ($Namespace -match '^[A-Za-z][A-Za-z0-9+.-]*://') {
            # A full URL is accepted only on the session's own host, so the API key never goes anywhere else.
            if ($script:Session -isnot [SendGridSession]) {
                Write-Error 'You must call the Connect-SendGrid cmdlet before calling any other cmdlets.' -ErrorAction Stop
            }
            $SessionBase = $script:Session._BaseURL
            $Target = $null
            $IsSessionHost = [uri]::TryCreate($Namespace, [System.UriKind]::Absolute, [ref]$Target) -and
                $Target.Scheme -eq 'https' -and
                $Target.Host -ieq $SessionBase.Host -and
                $Target.Port -eq $SessionBase.Port
            if (-not $IsSessionHost) {
                $TargetHost = '(unreadable URL)'
                if ($Target) {
                    $TargetHost = $Target.Host
                }
                Write-Error ('Refusing to send the request to {0}: the session sends requests only to {1}.' -f $TargetHost, $SessionBase.Host) -ErrorAction Stop
            }
            $BasePath = $SessionBase.AbsolutePath.TrimEnd('/')
            $Rest = $Target.PathAndQuery
            if ($BasePath.Length -gt 0 -and $Rest.StartsWith($BasePath + '/', [System.StringComparison]::Ordinal)) {
                $Rest = $Rest.Substring($BasePath.Length)
            }
            elseif ($Rest.StartsWith('/v3/', [System.StringComparison]::Ordinal)) {
                $Rest = $Rest.Substring(3)
            }
            $ReplacedNamespace = $Rest -replace '^/'
        }
        else {
            # Remove leading '/' characters and one leading 'v3/'; the session's base URL supplies the version.
            $ReplacedNamespace = $Namespace -replace '^/+' -replace '^v3/'
        }
        $InvokeSplat = @{
            Method        = $WebMethod
            Namespace     = $ReplacedNamespace
            ErrorAction   = 'Stop'
            CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
        }
        if ($PSBoundParameters.ContentBody) {
            $InvokeSplat.Add('ContentBody', $ContentBody)
        }
        if ($PSBoundParameters.OnBehalfOf) {
            $InvokeSplat.Add('OnBehalfOf', $OnBehalfOf)
        }

        if ($QueryParameters.Count -gt 0) {
            $InvokeSplat['Namespace'] += '?' + ($QueryParameters -join '&')
        }

        if ($PSCmdlet.ShouldProcess($InvokeSplat['Namespace'], 'Invoke SendGrid API call')) {
            try {
                Invoke-SendGrid @InvokeSplat
            }
            catch {
                Write-Error -Exception (ConvertTo-SendGridCommandException -Message ('Failed to make SendGrid API call. {0}' -f $_.Exception.Message) -ErrorRecord $_) -ErrorAction Stop
            }
        }
    }
}