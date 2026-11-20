<#
.SYNOPSIS
Turns an error caught from Invoke-RestMethod into the exception the SendGrid session throws.

.DESCRIPTION
ConvertTo-SendGridException reads the HTTP status and the SendGrid errors out of an error record caught from Invoke-RestMethod,
in the shape of PowerShell 7 (an HttpResponseException) and of Windows PowerShell 5.1 (a WebException). It returns a RuntimeException
whose text names the status and the fields SendGrid reports, whose InnerException is the original exception, and whose Data holds
StatusCode and SendGridErrors. It never throws, and a body that is not JSON never gives a parse error. The text never holds the query
part of the request address, and the exception never holds the API key or the Authorization header.

.PARAMETER ErrorRecord
The error record caught from Invoke-RestMethod.

.PARAMETER Context
Query for a request to an endpoint, Connect for the request that opens the session. The context picks the text used when there is no HTTP status.

.PARAMETER RequestUri
The address that was requested. Its query part is removed from the text.

.EXAMPLE
throw (ConvertTo-SendGridException -ErrorRecord $_ -Context Query -RequestUri $Uri)

Throws SendGrid Error (HTTP 404): "resource not found" when SendGrid answered 404 with that error, with the original exception as InnerException.

#>
function ConvertTo-SendGridException {
    [CmdletBinding()]
    [OutputType([System.Management.Automation.RuntimeException])]
    param (
        # The error record caught from Invoke-RestMethod.
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord,

        # Query for a request to an endpoint, Connect for the request that opens the session.
        [Parameter(Mandatory)]
        [ValidateSet('Query', 'Connect')]
        [string]$Context,

        # The address that was requested; its query part is removed from the text.
        [Parameter()]
        [uri]$RequestUri
    )

    $Status = $null
    $Errors = @()
    $OriginalText = ''
    try {
        $Exception = $ErrorRecord.Exception
        $OriginalText = "$($Exception.Message)"

        try {
            if ($null -ne $Exception.PSObject.Properties['Response'] -and $null -ne $Exception.Response) {
                $Status = [int]$Exception.Response.StatusCode
            }
        }
        catch {
            $Status = $null
        }

        try {
            $Body = $ErrorRecord.ErrorDetails.Message
            if (-not [string]::IsNullOrWhiteSpace($Body)) {
                $Parsed = $Body | ConvertFrom-Json -ErrorAction Stop
                if ($null -ne $Parsed -and $null -ne $Parsed.PSObject.Properties['errors']) {
                    $Errors = @(foreach ($Item in @($Parsed.errors)) {
                            if ($null -eq $Item) { continue }
                            $Field = $null
                            $Message = $null
                            if ($Item -is [string]) {
                                $Message = $Item
                            }
                            else {
                                if ($null -ne $Item.PSObject.Properties['field'] -and $Item.field -is [string] -and $Item.field.Length -gt 0) {
                                    $Field = $Item.field
                                }
                                if ($null -ne $Item.PSObject.Properties['message']) { $Message = "$($Item.message)" }
                            }
                            [pscustomobject]@{ Field = $Field; Message = $Message }
                        })
                }
            }
        }
        catch {
            $Errors = @()
        }

        if ($null -ne $Status -and $Errors.Count -gt 0) {
            $List = ($Errors | ForEach-Object { if ($_.Field) { '{0}: {1}' -f $_.Field, $_.Message } else { $_.Message } }) -join ', '
            $Text = 'SendGrid Error (HTTP {0}): "{1}"' -f $Status, $List
        }
        elseif ($null -ne $Status) {
            $Text = 'SendGrid Error (HTTP {0}). {1}' -f $Status, $OriginalText
        }
        elseif ($Context -eq 'Query' -and $Errors.Count -gt 0) {
            $Text = 'SendGrid Error: "{0}"' -f (($Errors | ForEach-Object { $_.Message }) -join ', ')
        }
        elseif ($Context -eq 'Query') {
            $Text = 'Unable to query SendGrid: {0}' -f $OriginalText
        }
        else {
            $Text = 'Unable to connect to SendGrid. {0}' -f $OriginalText
        }

        # Keep the query part of the address (it can hold an e-mail address) out of the text.
        if ($null -ne $RequestUri -and $RequestUri.IsAbsoluteUri -and $RequestUri.Query.Length -gt 0) {
            $Text = $Text.Replace($RequestUri.AbsoluteUri, $RequestUri.GetLeftPart('Path'))
            $Text = $Text.Replace($RequestUri.OriginalString, $RequestUri.GetLeftPart('Path'))
            $Text = $Text.Replace($RequestUri.Query, '')
        }

        # The original exception is reachable as InnerException. In PowerShell 7 its response still holds the request, with the Authorization header.
        try {
            if ($Exception.PSObject.Properties['Response'] -and $Exception.Response -is [System.Net.Http.HttpResponseMessage] -and $null -ne $Exception.Response.RequestMessage) {
                $null = $Exception.Response.RequestMessage.Headers.Remove('Authorization')
            }
        }
        catch {
            Write-Verbose -Message 'The Authorization header could not be removed from the kept response.'
        }

        $Result = [System.Management.Automation.RuntimeException]::new($Text, $Exception)
        if ($null -ne $Status) { $Result.Data['StatusCode'] = $Status }
        if ($Errors.Count -gt 0) { $Result.Data['SendGridErrors'] = [object[]]$Errors }
        $Result
    }
    catch {
        # Reading the error must never hide the error itself.
        $Fallback = if ($Context -eq 'Query') { 'Unable to query SendGrid: {0}' } else { 'Unable to connect to SendGrid. {0}' }
        [System.Management.Automation.RuntimeException]::new(($Fallback -f $OriginalText), $ErrorRecord.Exception)
    }
}
