function Get-SGBlock {
    <#
    .SYNOPSIS
        Retrieves a specific block from SendGrid.

    .DESCRIPTION
        Get-SGBlock retrieves a specific block based on the email address from SendGrid. Blocks occur when an email is rejected due to an issue with the message itself.

    .PARAMETER EmailAddress
        Specifies the email address of a specific block to retrieve. An empty value is refused.

    .PARAMETER OnBehalfOf
        Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.

    .PARAMETER StartTime
        Specifies the start of the time range (inclusive) to retrieve entries for. The value is converted to a Unix timestamp before it is sent to SendGrid.

    .PARAMETER EndTime
        Specifies the end of the time range (inclusive) to retrieve entries for. The value is converted to a Unix timestamp before it is sent to SendGrid.

    .PARAMETER Limit
        Sets the page size. The value is sent as the limit query parameter of a single request; if omitted, 100 is requested. The module does not check an upper bound for the value. A value below 1 is refused.

    .PARAMETER Offset
        Specifies the number of items to skip before the first returned item. The default of 0 starts at the beginning of the list; use multiples of Limit to request further consecutive pages. A value below 0 is refused.

    .EXAMPLE
        PS C:\> Get-SGBlock -EmailAddress block@example.com

        This command retrieves the block for the email address 'block@example.com' from SendGrid.

    .EXAMPLE
        PS C:\> Get-SGBlock -EmailAddress block@example.com -OnBehalfOf 'Subuser'

        This command retrieves the block for the email address 'block@example.com' from SendGrid for the Subuser 'Subuser'.
    #>
    [CmdletBinding()]
    param (
        # Specifies the specific email address to retrieve. An empty value is refused.
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

        # Sets the page size. The value is sent as the limit query parameter of a single request; if omitted, 100 is requested. The module does not check an upper bound for the value. A value below 1 is refused.
        [Parameter(
            Position = 3
        )]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Limit,

        # The number of items in the list to skip over before starting to retrieve the items for the requested page. The default offset of 0 represents the beginning of the list, i.e., the start of the first page. To request the second page of the list, set the offset to the page size as determined by Limit. Use multiples of the page size as your offset to request further consecutive pages. A value below 0 is refused.
        [Parameter(
            Position = 4
        )]
        [ValidateRange(0, [int]::MaxValue)]
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
        if ($PSBoundParameters.ContainsKey('Limit')) {
            $QueryParameters.Add("limit=$limit")
        }
        else {
            $QueryParameters.Add("limit=100")
        }
        if ($PSBoundParameters.ContainsKey('Offset')) {
            $QueryParameters.Add("offset=$offset")
        }

        if ($PSBoundParameters.ContainsKey('EmailAddress')) {
            foreach ($Email in $EmailAddress) {
                $EmailQuery = @($QueryParameters) + ('email={0}' -f (ConvertTo-SendGridUriComponent $Email.Address))
                $EmailInvokeSplat = $InvokeSplat.Clone()
                $EmailInvokeSplat['Namespace'] += '?' + ($EmailQuery -join '&')
                try {
                    Invoke-SendGrid @EmailInvokeSplat
                }
                catch {
                    Write-Error -Exception (ConvertTo-SendGridCommandException -Message ('Failed to retrieve SendGrid block. {0}' -f $_.Exception.Message) -ErrorRecord $_) -ErrorAction Stop
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
                Write-Error -Exception (ConvertTo-SendGridCommandException -Message ('Failed to retrieve all SendGrid blocks. {0}' -f $_.Exception.Message) -ErrorRecord $_) -ErrorAction Stop
            }
        }
    }
}