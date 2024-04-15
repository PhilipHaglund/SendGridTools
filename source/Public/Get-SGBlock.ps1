function Get-SGBlock {
    <#
    .SYNOPSIS
        Retrieves a specific block from SendGrid.

    .DESCRIPTION
        Get-SGBlock retrieves a specific block based on the email address from SendGrid. Blocks occur when an email is rejected due to an issue with the message itself.

    .PARAMETER EmailAddress
        Specifies the email address of a specific block to retrieve.

    .PARAMETER OnBehalfOf
        Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.

    .EXAMPLE
        PS C:\> Get-SGBlock -EmailAddress block@example.com

        This command retrieves the block for the email address 'block@example.com' from SendGrid.

    .EXAMPLE
        PS C:\> Get-SGBlock -EmailAddress block@example.com -OnBehalfOf 'Subuser'

        This command retrieves the block for the email address 'block@example.com' from SendGrid for the Subuser 'Subuser'.
    #>
    [CmdletBinding()]
    param (
        # Specifies the specific email address to retrieve.
        [Parameter(
            ValueFromPipeline,
            ValueFromPipelineByPropertyName
        )]
        [MailAddress[]]$EmailAddress,

        # Refers to the start of the time range in Unix timestamp when an invalid email was created (inclusive).
        [Parameter()]
        [UnixTime]$StartTime,

        # Refers to the end of the time range in Unix timestamp when an invalid email was created (inclusive).
        [Parameter()]
        [UnixTime]$EndTime,

        # Sets the page size, i.e., the maximum number of items from the list to be returned for a single API request. If omitted, the default page size is used. The maximum page size for this endpoint is 500 items per page.
        [Parameter()]
        [int]$Limit,

        # The number of items in the list to skip over before starting to retrieve the items for the requested page. The default offset of 0 represents the beginning of the list, i.e., the start of the first page. To request the second page of the list, set the offset to the page size as determined by Limit. Use multiples of the page size as your offset to request further consecutive pages.
        [Parameter()]
        [int]$Offset,

        # Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
        [Parameter()]
        [string]$OnBehalfOf
    )
    process {
        $InvokeSplat = @{
            Method        = 'Get'
            Namespace     = "suppression/blocks"
            ErrorAction   = 'Stop'
            CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
        }
        if ($PSBoundParameters.OnBehalfOf) {
            $InvokeSplat.Add('OnBehalfOf', $OnBehalfOf)
        }
        #Generic List
        [System.Collections.Generic.List[string]]$QueryParameters = [System.Collections.Generic.List[string]]::new()

        if ($PSBoundParameters.StartTime) {
            $QueryParameters.Add("start_time=$($StartTime.ToUnixTime())")
        }
        if ($PSBoundParameters.EndTime) {
            $QueryParameters.Add("end_time=$($EndTime.ToUnixTime())")
        }
        if ($PSBoundParameters.Limit) {
            $QueryParameters.Add("limit=$limit")
        }
        if ($PSBoundParameters.Offset) {
            $QueryParameters.Add("offset=$offset")
        }

        if ($QueryParameters.Count -gt 0 -or $PSBoundParameters.EmailAddress) {
            $InvokeSplat['Namespace'] += '?' + ($QueryParameters -join '&')
        }

        if ($PSBoundParameters.EmailAddress) {
            foreach ($Email in $EmailAddress) {
                $EmailInvokeSplat = $InvokeSplat.Clone()
                $EmailInvokeSplat['Namespace'] += "&email=$($Email.Address)"
                if ($EmailInvokeSplat['Namespace'] -match ('\?\&email=')) {
                    $EmailInvokeSplat['Namespace'] = $EmailInvokeSplat['Namespace'].Replace('?&email=', '?email=')
                }
                try {
                    Invoke-SendGrid @EmailInvokeSplat
                }
                catch {
                    Write-Error ('Failed to retrieve SendGrid block. {0}' -f $_.Exception.Message) -ErrorAction Stop
                }
            }
        }
        else {
            try {
                Invoke-SendGrid @InvokeSplat
            }
            catch {
                Write-Error ('Failed to retrieve all SendGrid blocks. {0}' -f $_.Exception.Message) -ErrorAction Stop
            }
        }
    }   
}