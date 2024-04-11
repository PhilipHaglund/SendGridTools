function Get-SGBounceByClassification {
    <#
    .SYNOPSIS
        Retrieves bounce totals by classification from SendGrid.

    .DESCRIPTION
        Get-SGBounceByClassification retrieves the total number of bounces by classification in descending order for each day from SendGrid. Bounces can be classified as permanent or temporary failures to deliver the message.

    .PARAMETER StartDate
        Specifies the start date of the time range when a bounce was created (inclusive) in YYYY-MM-DD format.

    .PARAMETER EndDate
        Specifies the end date of the time range when a bounce was created (inclusive) in YYYY-MM-DD format.

    .PARAMETER OnBehalfOf
        Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.


    .EXAMPLE
        PS C:\> Get-SGBounceByClassification

        Classification     : 5.1.1
        TotalBounces       : 100

        Classification     : 4.0.0
        TotalBounces       : 50

        This command retrieves the bounce totals by classification for the time range from '2022-01-01' to '2022-01-31' from SendGrid.

    .EXAMPLE
        PS C:\> Get-SGBounceByClassification -StartDate '2022-01-01' -EndDate '2022-01-31' -OnBehalfOf 'Subuser'

        Classification     : 5.1.1
        TotalBounces       : 100

        Classification     : 4.0.0
        TotalBounces       : 50
        Username           : Subuser

        This command retrieves the bounce totals by classification for the time range from '2022-01-01' to '2022-01-31' from SendGrid for the Subuser 'Subuser'.
    #>
    [CmdletBinding()]
    param (
        # Specifies the Classification of the bounce.
        [Parameter()]
        [ValidateSet('Content', 'Frequency or Volume Too High', 'Invalid Address', 'Mailbox Unavailable', 'Reputation', 'Technical Failure', 'Unclassified')]
        [string]$Classification,
        
        # Specifies the start date of the time range when a bounce was created (inclusive). Both datetime and unix timestamp formats are accepted.
        [Parameter()]
        [UnixTime]$StartDate,

        # Specifies the end date of the time time range when a bounce was created (inclusive). Both datetime and unix timestamp formats are accepted.
        [Parameter()]
        [UnixTime]$EndDate,

        # Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
        [Parameter()]
        [string]$OnBehalfOf
    )
    process {
        $InvokeSplat = @{
            Method        = 'Get'
            Namespace     = 'suppression/bounces/classifications'
            ErrorAction   = 'Stop'
            CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
        }
        if ($PSBoundParameters.Classification) {
            $InvokeSplat['Namespace'] = "suppression/bounces/classifications/$Classification"
        }
        if ($PSBoundParameters.OnBehalfOf) {
            $InvokeSplat.Add('OnBehalfOf', $OnBehalfOf)
        }

        #Generic List
        [System.Collections.Generic.List[string]]$QueryParameters = [System.Collections.Generic.List[string]]::new()

        if ($PSBoundParameters.StartDate) {
            $QueryParameters.Add("start_date=$($StartDate.ToSendGridTime())")
        }
        if ($PSBoundParameters.EndDate) {
            $QueryParameters.Add("end_date=$($EndDate.ToSendGridTime())")
        }
        if ($QueryParameters.Count -gt 0) {
            $InvokeSplat['Namespace'] += '?' + ($QueryParameters -join '&')
        }

        try {
            Invoke-SendGrid @InvokeSplat
        }
        catch {
            Write-Error ('Failed to retrieve SendGrid bounce classifications. {0}' -f $_.Exception.Message) -ErrorAction Stop
        }
    }
}