function Get-SGBounce {
    <#
    .SYNOPSIS
        Retrieves all or specific bounces from SendGrid.

    .DESCRIPTION
        Get-SGBounce retrieves all bounces or a specific bounce based on its unique ID from SendGrid. Bounces occur when an email is rejected by the recipient's mail server.

    .PARAMETER EmailAddress
        Specifies one or more email addresses whose bounces are retrieved. If this parameter is not provided, all bounces are retrieved. An empty value is refused.

    .PARAMETER OnBehalfOf
        Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.

    .PARAMETER StartTime
        Specifies the start of the time range (inclusive) to retrieve entries for. The value is converted to a Unix timestamp before it is sent to SendGrid.

    .PARAMETER EndTime
        Specifies the end of the time range (inclusive) to retrieve entries for. The value is converted to a Unix timestamp before it is sent to SendGrid.

    .PARAMETER Limit
        Sets the page size. The value is sent as the limit query parameter of a single request; if omitted, 100 is requested. The module does not check an upper bound for the value.

    .PARAMETER Offset
        Specifies the number of items to skip before the first returned item. The default of 0 starts at the beginning of the list; use multiples of Limit to request further consecutive pages.

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
        # Specifies the specific email address to retrieve. If this parameter is not provided, all bounces are retrieved. An empty value is refused.
        [Parameter(
            ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            Position = 0
        )]
        [ValidateNotNullOrEmpty()]
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

        # Sets the page size. The value is sent as the limit query parameter of a single request; if omitted, 100 is requested. The module does not check an upper bound for the value.
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

        if ($PSBoundParameters.ContainsKey('EmailAddress')) {
            foreach ($Email in $EmailAddress) {
                $EmailQuery = @($QueryParameters) + ('email={0}' -f [uri]::EscapeDataString($Email.Address))
                $EmailInvokeSplat = $InvokeSplat.Clone()
                $EmailInvokeSplat['Namespace'] += '?' + ($EmailQuery -join '&')
                try {
                    Invoke-SendGrid @EmailInvokeSplat
                }
                catch {
                    Write-Error -Exception (ConvertTo-SendGridCommandException -Message ('Failed to retrieve SendGrid bounce. {0}' -f $_.Exception.Message) -ErrorRecord $_) -ErrorAction Stop
                }
            }
        }
        else {
            if ($QueryParameters.Count -gt 0) {
                $InvokeSplat['Namespace'] += '?' + ($QueryParameters -join '&')
            }
            try {
                Invoke-SendGrid @InvokeSplat
            }
            catch {
                Write-Error -Exception (ConvertTo-SendGridCommandException -Message ('Failed to retrieve all SendGrid bounces. {0}' -f $_.Exception.Message) -ErrorRecord $_) -ErrorAction Stop
            }
        }
    }
}