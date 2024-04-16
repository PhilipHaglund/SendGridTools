function Invoke-SGCommand {
    <#
    .SYNOPSIS
        A wrapper for the Invoke-SendGrid function.

    .DESCRIPTION
        Invoke-SGCommand is a wrapper for the Invoke-SendGrid function. It allows you to make API calls to SendGrid.

    .PARAMETER WebMethod
        Specifies the HTTP method to use for the API call. The default value is 'Get'.

    .PARAMETER Namespace
        Specifies the URL path for the API call.

    .PARAMETER ContentBody
        Specifies the content body for the API call. It should be a hashtable.

    .EXAMPLE
        PS C:\> Invoke-SGCommand -WebMethod 'Get' -Namespace 'v3/mail_settings' -ContentBody @{ 'limit' = 10; 'offset' = 0 }

        This command makes a 'Get' API call to SendGrid with the URL path 'v3/mail_settings' and the content body '{ 'limit' = 10; 'offset' = 0 }'.
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
        [Parameter()]
        [ValidateSet('Get', 'Post', 'Put', 'Delete', 'Patch')]
        [string]$WebMethod = 'Get',

        # Specifies the content body for the API call. It should be a hashtable.
        [Parameter()]
        [HashTable]$ContentBody,

        # Specifies if the SGCommand takes Query parameters like limit or offset. Should contain the query parameter followed by = and the value. Example: limit=10
        [System.Collections.Generic.List[string]]$QueryParameters = [System.Collections.Generic.List[string]]::new(),

        # Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
        [Parameter()]
        [string]$OnBehalfOf
    )
    process {

        # Replace the character(s) '/', '/v3/', and 'v3/' with an empty string if it begins with them.
        $ReplacedNamespace = $Namespace -replace '^/|/v3/|v3/|https:\/\/api\.sendgrid\.com/v3/|https://api.sendgrid.com' -replace '^/'
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
                Write-Error ('Failed to make SendGrid API call. {0}' -f $_.Exception.Message) -ErrorAction Stop
            }
        }
    }
}