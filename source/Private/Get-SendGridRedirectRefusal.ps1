<#
.SYNOPSIS
Returns the refusal text when an Invoke-RestMethod error is a refused HTTP redirect, and nothing otherwise.

.DESCRIPTION
The SendGrid session calls Invoke-RestMethod with -MaximumRedirection 0 so that the API key is never sent to a host that SendGrid
redirects to. A refused redirect is thrown in a different shape in PowerShell 7 (an exception with a Response that holds an
HttpResponseMessage) and in Windows PowerShell 5.1 (a MaximumRedirectExceeded error whose TargetObject is the request, or a
WebException with a Response). Get-SendGridRedirectRefusal hides that difference. It returns the refusal text, which names only the
host the redirect points to, when the error is a redirect (any 3xx status), and $null for every other error. It never throws. Windows
PowerShell 5.1 raises a catchable error only for a 301 or 302 answer; it returns another 3xx answer as an empty result, which no error handler sees.

.PARAMETER ErrorRecord
The error record caught from Invoke-RestMethod.

.PARAMETER RequestUri
The address that was requested. A relative Location header is resolved against it to find the host.

.EXAMPLE
Get-SendGridRedirectRefusal -ErrorRecord $_ -RequestUri $Uri

Returns the refusal text when the caught error is a refused redirect, and $null when it is any other error.

#>
function Get-SendGridRedirectRefusal {
    [CmdletBinding()]
    [OutputType([string])]
    param (
        # The error record caught from Invoke-RestMethod.
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord,

        # The address that was requested, used to resolve a relative Location header.
        [Parameter()]
        [uri]$RequestUri
    )

    $Refusal = 'SendGrid answered with a redirect to {0}; the request was refused so that the API key is not sent there.'
    $IsRedirect = $false
    $RedirectHost = 'an unknown host'
    try {
        $Response = $null
        $Exception = $ErrorRecord.Exception
        if ($null -ne $Exception -and $null -ne $Exception.PSObject.Properties['Response'] -and $null -ne $Exception.Response) {
            $Response = $Exception.Response
        }
        elseif ("$($ErrorRecord.FullyQualifiedErrorId)" -like 'MaximumRedirectExceeded*') {
            $IsRedirect = $true
        }

        # Once the error is known to be a redirect, a failure to read the response must still give the refusal.
        try {
            if ($IsRedirect) {
                $Request = $ErrorRecord.TargetObject
                if ($Request -is [System.Net.WebRequest] -and $Request.HaveResponse -eq $true) {
                    # Measured: returns the cached response and sends no new request.
                    $Response = $Request.GetResponse()
                }
            }
            if ($null -ne $Response) {
                $Status = [int]$Response.StatusCode
                if ($Status -ge 300 -and $Status -le 399) {
                    $IsRedirect = $true
                }
            }
            if (-not $IsRedirect) {
                return $null
            }

            if ($null -ne $Response -and $null -ne $Response.Headers) {
                $LocationText = $null
                if ($null -ne $Response.Headers.PSObject.Properties['Location']) {
                    $LocationValue = $Response.Headers.Location
                    $LocationText = if ($LocationValue -is [uri]) { $LocationValue.OriginalString } else { "$LocationValue" }
                }
                else {
                    $LocationText = "$($Response.Headers['Location'])"
                }
                $RequestIsAbsolute = $null -ne $RequestUri -and $RequestUri.IsAbsoluteUri
                $Target = $null
                if (-not $LocationText) {
                    $Target = $null
                }
                elseif ($LocationText -match '^[A-Za-z][A-Za-z0-9+.-]*:') {
                    $null = [uri]::TryCreate($LocationText, [UriKind]::Absolute, [ref]$Target)
                }
                elseif ($LocationText.StartsWith('//')) {
                    if ($RequestIsAbsolute) {
                        $null = [uri]::TryCreate($RequestUri.Scheme + ':' + $LocationText, [UriKind]::Absolute, [ref]$Target)
                    }
                }
                elseif ($RequestIsAbsolute) {
                    $Relative = $null
                    if ([uri]::TryCreate($LocationText, [UriKind]::Relative, [ref]$Relative)) {
                        $Target = [uri]::new($RequestUri, $Relative)
                    }
                }
                if ($null -ne $Target -and $Target.IsAbsoluteUri -and $Target.Scheme -in 'http', 'https' -and $Target.Host) {
                    $RedirectHost = $Target.Host
                }
            }
        }
        catch {
            if (-not $IsRedirect) {
                return $null
            }
            $RedirectHost = 'an unknown host'
        }
        $Refusal -f $RedirectHost
    }
    catch {
        if ($IsRedirect) {
            return $Refusal -f 'an unknown host'
        }
        return $null
    }
}
