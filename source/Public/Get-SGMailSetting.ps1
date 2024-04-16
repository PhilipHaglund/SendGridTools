function Get-SGMailSetting {
    <#
    .SYNOPSIS
        Retrieves a paginated list of all mail settings on SendGrid.

    .DESCRIPTION
        Get-SGMailSetting retrieves a paginated list of all mail settings on SendGrid.

    .PARAMETER Limit
        Specifies the page size, i.e. maximum number of items from the list to be returned for a single API request.

    .PARAMETER Offset
        Specifies the number of items in the list to skip over before starting to retrieve the items for the requested page.

    .PARAMETER OnBehalfOf
        Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.

    .EXAMPLE
        PS C:\> Get-SGMailSetting -Limit 10 -Offset 0

        This command retrieves the first page of mail settings on SendGrid with a page size of 10.

    .EXAMPLE
        PS C:\> Get-SGMailSetting -Limit 10 -Offset 10 -OnBehalfOf 'Subuser'

        This command retrieves the second page of mail settings on SendGrid with a page size of 10 on behalf of the Subuser 'Subuser'.
    #>
    [CmdletBinding()]
    param (
        # Specifies the page size, i.e. maximum number of items from the list to be returned for a single API request.
        [Parameter()]
        [int]$Limit,

        # Specifies the number of items in the list to skip over before starting to retrieve the items for the requested page.
        [Parameter()]
        [int]$Offset,

        # Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
        [Parameter()]
        [string]$OnBehalfOf
    )
    process {
        $InvokeSplat = @{
            Method        = 'Get'
            Namespace     = 'mail_settings'
            ErrorAction   = 'Stop'
            CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
        }

        if ($PSBoundParameters.OnBehalfOf) {
            $InvokeSplat.Add('OnBehalfOf', $OnBehalfOf)
        }
        #Generic List
        [System.Collections.Generic.List[string]]$QueryParameters = [System.Collections.Generic.List[string]]::new()

        if ($PSBoundParameters.Limit) {
            $QueryParameters.Add("limit=$limit")
        }
        if ($PSBoundParameters.Offset) {
            $QueryParameters.Add("offset=$offset")
        }

        if ($QueryParameters.Count -gt 0) {
            $InvokeSplat['Namespace'] += '?' + ($QueryParameters -join '&')
        }
        
        try {
            Invoke-SendGrid @InvokeSplat
        }
        catch {
            Write-Error ('Failed to retrieve SendGrid mail settings. {0}' -f $_.Exception.Message) -ErrorAction Stop
        }
    }
}