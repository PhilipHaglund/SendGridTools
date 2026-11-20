function Get-SGDesign {
    <#
    .SYNOPSIS
        WARNING NOT FULLY TESTED
        Retrieves a list of designs stored in the Twilio SendGrid Design Library.

    .DESCRIPTION
        Get-SGDesign retrieves a list of designs stored in the Twilio SendGrid Design Library.
        This function does not return the pre-built Twilio SendGrid designs.

    .PARAMETER PageSize
        Specifies the number of results to return. The value is sent when the parameter is given; without it SendGrid returns its default page size of 100. A value below 1 is refused.

    .PARAMETER PageToken
        Specifies the token corresponding to a specific page of results, as provided by metadata.

    .PARAMETER Summary
        Sends summary=true when given, or summary=false with -Summary:$false to return all fields. Without the parameter no summary value is sent and SendGrid applies its default, which returns the summary fields.

    .EXAMPLE
        PS C:\> Get-SGDesign -PageSize 50 -PageToken 'token'
        This command retrieves a specific page of designs with a page size of 50.
    .EXAMPLE
        PS C:\> Get-SGDesign -PageSize 100 -Summary:$false
        This command retrieves all fields of the first page of designs with a page size of 100.
    #>
    [CmdletBinding()]
    param (
        # Specifies the number of results to return. The value is sent when the parameter is given; without it SendGrid returns its default page size of 100. A value below 1 is refused.
        [Parameter(
            Position = 0
        )]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$PageSize = 100,
        [Parameter(
            Position = 1
        )]
        [string]$PageToken,
        [Parameter(
            Position = 2
        )]
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

        if ($PSBoundParameters.ContainsKey('PageSize')) {
            $QueryParameters.Add("page_size=$($PageSize)")
        }
        if ($PSBoundParameters.PageToken) {
            $QueryParameters.Add('page_token=' + (ConvertTo-SendGridUriComponent $PageToken))
        }
        if ($PSBoundParameters.ContainsKey('Summary')) {
            $QueryParameters.Add('summary=' + ([string]$Summary.IsPresent).ToLowerInvariant())
        }

        if ($QueryParameters.Count) {
            $InvokeSplat['Namespace'] += '?' + ($QueryParameters -join '&')
        }
        try {
            Invoke-SendGrid @InvokeSplat
        }
        catch {
            Write-Error -Exception (ConvertTo-SendGridCommandException -Message ('Failed to retrieve SendGrid Design. {0}' -f $_.Exception.Message) -ErrorRecord $_) -ErrorAction Stop
        }
    }
}