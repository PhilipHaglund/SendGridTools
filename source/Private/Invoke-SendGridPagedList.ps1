function Invoke-SendGridPagedList {
    <#
    .SYNOPSIS
        Reads a SendGrid list endpoint page by page and returns every object.

    .DESCRIPTION
        Invoke-SendGridPagedList calls Invoke-SendGrid with limit and offset query parameters, one page at a time,
        and streams the objects of every page. It stops after a page with fewer objects than the page size, and also
        after any page that holds no object it has not already returned, an empty page included. A server that
        ignores offset sends the first page again, which is such a page.

    .PARAMETER InvokeSplat
        The parameters Invoke-SendGrid is called with (Method, Namespace without a query string, ErrorAction,
        CallingCmdlet and optionally OnBehalfOf).

    .PARAMETER IdProperty
        The name of the property, as Invoke-SendGrid returns it, that identifies an object, for example Id or ApiKeyId.

    .PARAMETER Limit
        The page size sent as the limit query parameter. The default is 50.

    .EXAMPLE
        Invoke-SendGridPagedList -InvokeSplat @{ Method = 'Get'; Namespace = 'api_keys'; ErrorAction = 'Stop' } -IdProperty 'ApiKeyId'

        Returns every API key, 50 at a time.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        # The parameters Invoke-SendGrid is called with, without a query string in Namespace.
        [Parameter(Mandatory)]
        [hashtable]$InvokeSplat,

        # The name of the property that identifies an object in the output of Invoke-SendGrid.
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$IdProperty,

        # The page size sent as the limit query parameter.
        [Parameter()]
        [ValidateRange(1, 500)]
        [int]$Limit = 50
    )
    $Offset = 0
    $Seen = [System.Collections.Generic.HashSet[string]]::new()
    while ($true) {
        $PageSplat = $InvokeSplat.Clone()
        $PageSplat['Namespace'] = '{0}?limit={1}&offset={2}' -f $InvokeSplat['Namespace'], $Limit, $Offset
        $Page = @(Invoke-SendGrid @PageSplat)
        $New = [System.Collections.Generic.List[object]]::new()
        foreach ($Object in $Page) {
            if ($Seen.Add([string]$Object.$IdProperty)) {
                $New.Add($Object)
            }
        }
        if ($New.Count -eq 0) {
            break
        }
        foreach ($Object in $New) {
            $Object
        }
        if ($Page.Count -lt $Limit) {
            break
        }
        $Offset += $Limit
    }
}
