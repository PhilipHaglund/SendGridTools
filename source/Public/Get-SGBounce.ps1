function Get-SGBounce {
    <#
    .SYNOPSIS
        Retrieves all or specific bounces from SendGrid.

    .DESCRIPTION
        Get-SGBounce retrieves all bounces or a specific bounce based on its unique ID from SendGrid. Bounces occur when an email is rejected by the recipient's mail server.

    .PARAMETER UniqueId
        Specifies the UniqueId of a specific bounce to retrieve. If this parameter is not provided, all bounces are retrieved.

    .PARAMETER OnBehalfOf
        Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.

    .EXAMPLE
        PS C:\> Get-SGBounce

        Email             : bounce1@example.com
        Status            : 5.1.1
        Reason            : Invalid Recipient
        Created           : 2022-03-04 15:34:34
        Updated           : 2022-03-04 15:34:34
        UniqueId          : 13508031
        UserId            : 8262273

        Email             : bounce2@example.com
        Status            : 5.1.1
        Reason            : Invalid Recipient
        Created           : 2021-11-12 07:38:27
        Updated           : 2021-11-12 07:38:27
        UniqueId          : 12589712
        UserId            : 8262273
        ...

        This command retrieves all bounces from SendGrid.

    .EXAMPLE
        PS C:\> Get-SGBounce -EmailAddress bounce2@example.com

        Email             : bounce2@example.com
        Status            : 5.1.1
        Reason            : Invalid Recipient
        Created           : 2021-11-12 07:38:27
        Updated           : 2021-11-12 07:38:27
        UniqueId          : 12589712
        UserId            : 8262273

        This command retrieves the bounce with the UniqueId '12589712' from SendGrid.

    .EXAMPLE
        PS C:\> Get-SGBounce -EmailAddress bounce2@example.com -OnBehalfOf 'Subuser'

        Email             : bounce2@example.com
        Status            : 5.1.1
        Reason            : Invalid Recipient
        Created           : 2021-11-12 07:38:27
        Updated           : 2021-11-12 07:38:27
        UniqueId          : 12589712
        UserId            : 8262273
        Username          : Subuser

        This command retrieves the bounce with the UniqueId '12589712' from SendGrid for the Subuser 'Subuser'.
    #>
    [CmdletBinding()]
    param (
        # Specifies the specific email address to retrieve. If this parameter is not provided, all bounces are retrieved.
        [Parameter(
            ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            Position = 0
        )]
        [MailAddress[]]$EmailAddress,

        # Refers to the start of the time range in Unix timestamp when an invalid email was created (inclusive).
        [Parameter(
            Position = 1
        )]
        [UnixTime]$StartTime,

        # Refers to the end of the time range in Unix timestamp when an invalid email was created (inclusive).
        [Parameter(
            Position = 2
        )]
        [UnixTime]$EndTime,

        # Sets the page size, i.e., the maximum number of items from the list to be returned for a single API request. If omitted, the default page size is used. The maximum page size for this endpoint is 500 items per page.
        [Parameter(
            Position = 3
        )]
        [int]$Limit,

        # The number of items in the list to skip over before starting to retrieve the items for the requested page. The default offset of 0 represents the beginning of the list, i.e., the start of the first page. To request the second page of the list, set the offset to the page size as determined by Limit. Use multiples of the page size as your offset to request further consecutive pages.
        [Parameter(
            Position = 4
        )]
        [int]$Offset,

        # Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
        [Parameter()]
        [string]$OnBehalfOf
    )
    process {
        $InvokeSplat = @{
            Method        = 'Get'
            Namespace     = 'suppression/bounces'
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
        else {
            $QueryParameters.Add("limit=100")
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
                    Write-Error ('Failed to retrieve SendGrid bounce. {0}' -f $_.Exception.Message) -ErrorAction Stop
                }
            }
        }
        else {
            try {
                Invoke-SendGrid @InvokeSplat
            }
            catch {
                Write-Error ('Failed to retrieve all SendGrid bounces. {0}' -f $_.Exception.Message) -ErrorAction Stop
            }
        }
    }   
}