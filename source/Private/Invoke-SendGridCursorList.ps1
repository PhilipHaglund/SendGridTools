function Invoke-SendGridCursorList {
    <#
    .SYNOPSIS
        Reads a SendGrid list endpoint that pages with an after_key cursor and returns every object.

    .DESCRIPTION
        Invoke-SendGridCursorList calls the session's InvokeQuery with GET for each page, so the session's own host
        is used for every page (an EU session reads every page from the EU host). It returns the objects in the
        result field of each page and follows _metadata.next_params.after_key to the next page until after_key is
        null or empty. It also stops, with a warning, when an after_key comes a second time and when MaxPage pages
        have been read and another after_key is given. Invoke-SendGrid is not used, because it drops _metadata.
        Each property name is written the way Invoke-SendGrid writes it (title case without underscores, for
        example added_at becomes AddedAt); the values are returned as SendGrid sends them.

    .PARAMETER Namespace
        The endpoint path below the base URL without a query string, for example send_ips/ips.

    .PARAMETER Query
        The query string sent on every page, without the leading question mark, for example include_region=true.

    .PARAMETER MaxPage
        The highest number of pages read in one call. The default is 100.

    .EXAMPLE
        Invoke-SendGridCursorList -Namespace 'send_ips/ips' -Query 'include_region=true'

        Returns every IP address of the IP Address Management API with its region.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        # The endpoint path below the base URL, without a query string.
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Namespace,

        # The query string sent on every page, without the leading question mark.
        [Parameter()]
        [string]$Query,

        # The highest number of pages read in one call.
        [Parameter()]
        [ValidateRange(1, 10000)]
        [int]$MaxPage = 100
    )
    if ($script:Session -isnot [SendGridSession]) {
        throw 'You must call the Connect-SendGrid cmdlet before calling any other cmdlets.'
    }
    $SeenKey = [System.Collections.Generic.HashSet[string]]::new()
    $AfterKey = $null
    $PageCount = 0
    while ($true) {
        $Parts = [System.Collections.Generic.List[string]]::new()
        if (-not [string]::IsNullOrEmpty($Query)) {
            $Parts.Add($Query)
        }
        if ($null -ne $AfterKey) {
            $Parts.Add(('after_key={0}' -f [uri]::EscapeDataString($AfterKey)))
        }
        $Endpoint = $Namespace
        if ($Parts.Count -gt 0) {
            $Endpoint = '{0}?{1}' -f $Namespace, ($Parts -join '&')
        }
        $Response = @($script:Session.InvokeQuery('Get', $Endpoint))
        $PageCount++
        $Next = $null
        foreach ($Page in $Response) {
            if ($null -eq $Page) {
                continue
            }
            foreach ($Item in @($Page.result)) {
                if ($null -eq $Item) {
                    continue
                }
                $Object = [ordered]@{}
                foreach ($Property in ($Item.PSObject.Properties | Sort-Object -Property Name)) {
                    $Object[(($Property.Name | ConvertTo-TitleCase) -replace '[\s_-]+')] = $Property.Value
                }
                [PSCustomObject]$Object
            }
            $Metadata = $Page.PSObject.Properties['_metadata']
            if ($null -ne $Metadata -and $null -ne $Metadata.Value -and $null -ne $Metadata.Value.next_params) {
                $Next = $Metadata.Value.next_params.after_key
            }
        }
        if ($null -eq $Next -or [string]::IsNullOrEmpty([string]$Next)) {
            break
        }
        $Next = [string]$Next
        if (-not $SeenKey.Add($Next)) {
            Write-Warning -Message ('Stopped reading {0}: the same after_key came a second time.' -f $Namespace)
            break
        }
        if ($PageCount -ge $MaxPage) {
            Write-Warning -Message ('Stopped reading {0} after {1} pages; SendGrid offers more.' -f $Namespace, $MaxPage)
            break
        }
        $AfterKey = $Next
    }
}
