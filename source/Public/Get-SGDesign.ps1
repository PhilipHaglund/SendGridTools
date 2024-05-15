function Get-SGDesign {
    <#
    .SYNOPSIS
        WARNING NOT FULLY TESTED
        Retrieves a list of designs stored in the Twilio SendGrid Design Library.

    .DESCRIPTION
        Get-SGDesign retrieves a list of designs stored in the Twilio SendGrid Design Library. 
        This function does not return the pre-built Twilio SendGrid designs.

    .PARAMETER PageSize
        Specifies the number of results to return. The default is 100.

    .PARAMETER PageToken
        Specifies the token corresponding to a specific page of results, as provided by metadata.

    .PARAMETER Summary
        Set to false to return all fields. The default is true.

    .EXAMPLE
        PS C:\> Get-SGDesign -PageSize 50 -PageToken 'token'
        This command retrieves a specific page of designs with a page size of 50.
    .EXAMPLE
        PS C:\> Get-SGDesign -PageSize 100 -Summary $false -OnBehalfOf 'Subuser'
        This command retrieves all fields of the first page of designs with a page size of 100 on behalf of the Subuser 'Subuser'.
    #>
    [CmdletBinding()]
    param (
        [Parameter()]
        [int]$PageSize = 100,
        [Parameter()]
        [string]$PageToken,
        [Parameter()]
        [switch]$Summary
    )
    process {
        $InvokeSplat = @{
            Method        = 'Get'
            Namespace     = 'designs'
            ErrorAction   = 'Stop'
            CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
        }

        #Generic List
        [System.Collections.Generic.List[string]]$QueryParameters = [System.Collections.Generic.List[string]]::new()

        if ($PSBoundParameters.PageSize) {
            $QueryParameters.Add("page_size=$($PageSize))")
        }
        if ($PSBoundParameters.PageToken) {
            $QueryParameters.Add("page_token=$($PageToken)")
        }
        if ($PSBoundParameters.Summary) {
            $QueryParameters.Add("summary=$($Summary.IsPresent)")
        }

        if ($QueryParameters.Count) {
            $InvokeSplat['Namespace'] += '?' + ($QueryParameters -join '&')
        }
        try {
            Invoke-SendGrid @InvokeSplat
        }
        catch {
            Write-Error ('Failed to retrieve SendGrid Design. {0}' -f $_.Exception.Message) -ErrorAction Stop
        }
    }
}