function Get-SGInvalidEmail {
    <#
    .SYNOPSIS
        Retrieves all or specific invalid emails from SendGrid.

    .DESCRIPTION
        Get-SGInvalidEmail retrieves all invalid emails or a specific invalid email based on its email address from SendGrid. Invalid emails occur when you attempt to send email to an address that is formatted in a manner that does not meet internet email format standards or the email does not exist at the recipient’s mail server.

    .PARAMETER EmailAddress
        Specifies the email address of a specific invalid email to retrieve. If this parameter is not provided, all invalid emails are retrieved.

    .PARAMETER StartTime
        Refers to the start of the time range in Unix timestamp when an invalid email was created (inclusive).

    .PARAMETER EndTime
        Refers to the end of the time range in Unix timestamp when an invalid email was created (inclusive).

    .PARAMETER Limit
        Sets the page size, i.e., the maximum number of items from the list to be returned for a single API request. If omitted, the default page size is used. The maximum page size for this endpoint is 500 items per page.

    .PARAMETER Offset
        The number of items in the list to skip over before starting to retrieve the items for the requested page. The default offset of 0 represents the beginning of the list, i.e., the start of the first page. To request the second page of the list, set the offset to the page size as determined by Limit. Use multiples of the page size as your offset to request further consecutive pages.

    .PARAMETER OnBehalfOf
        Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.

    .EXAMPLE
        PS C:\> Get-SGInvalidEmail

        Email             : invalid1@example.com
        Created           : 2022-03-04 15:34:34
        Updated           : 2022-03-04 15:34:34

        Email             : invalid2@example.com
        Created           : 2021-11-12 07:38:27
        Updated           : 2021-11-12 07:38:27
        ...

        This command retrieves all invalid emails from SendGrid.

    .EXAMPLE
        PS C:\> Get-SGInvalidEmail -EmailAddress invalid2@example.com

        Email             : invalid2@example.com
        Created           : 2021-11-12 07:38:27
        Updated           : 2021-11-12 07:38:27

        This command retrieves the invalid email with the email address 'invalid2@example.com' from SendGrid.

    .EXAMPLE
        PS C:\> Get-SGInvalidEmail -StartTime 1646486400 -EndTime 1678022400 -Limit 100 -Offset 200

        Email             : invalid3@example.com
        Created           : 2022-01-01 00:00:00
        Updated           : 2022-01-01 00:00:00

        Email             : invalid4@example.com
        Created           : 2022-02-01 00:00:00
        Updated           : 2022-02-01 00:00:00
        ...

        This command retrieves invalid emails from SendGrid created between the specified start and end times, with a limit of 100 items per page and an offset of 200.

    .EXAMPLE
        PS C:\> Get-SGInvalidEmail -EmailAddress invalid5@example.com -OnBehalfOf 'Subuser'

        Email             : invalid5@example.com
        Created           : 2022-03-01 00:00:00
        Updated           : 2022-03-01 00:00:00
        Username          : Subuser

        This command retrieves the invalid email with the email address 'invalid5@example.com' from SendGrid for the Subuser 'Subuser'.
    #>
    [CmdletBinding()]
    param (
        # Specifies the specific email address to retrieve. If this parameter is not provided, all invalid emails are retrieved.
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
            Namespace     = 'suppression/invalid_emails'
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
                    Write-Error ('Failed to retrieve SendGrid invalid email. {0}' -f $_.Exception.Message) -ErrorAction Stop
                }
            }
        }
        else {
            try {
                Invoke-SendGrid @InvokeSplat
            }
            catch {
                Write-Error ('Failed to retrieve SendGrid invalid emails. {0}' -f $_.Exception.Message) -ErrorAction Stop
            }
        }
    }
}