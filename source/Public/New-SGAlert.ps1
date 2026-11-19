function New-SGAlert {
    <#
    .SYNOPSIS
        Creates a new alert on SendGrid.

    .DESCRIPTION
        New-SGAlert creates a new alert on SendGrid based on the provided parameters.

    .PARAMETER EmailTo
        Specifies the email address the alert will be sent to.

    .PARAMETER Frequency
        Specifies how frequently the alert will be sent. Required for the EmailStatisticsSummary alert.

    .PARAMETER Percentage
        Specifies the usage threshold at which the alert will be sent. Required for the EmailCreditUsage alert.

    .PARAMETER OnBehalfOf
        Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.

    .PARAMETER EmailCreditUsage
        Specifies that a usage limit alert is created. The alert is sent when the Percentage of the email credits has been used. This switch cannot be combined with EmailStatisticsSummary.

    .PARAMETER EmailStatisticsSummary
        Specifies that a statistics notification alert is created. The alert is sent with the Frequency you provide. This switch cannot be combined with EmailCreditUsage.

    .EXAMPLE
        PS C:\> New-SGAlert -EmailCreditUsage -EmailTo 'test@example.com' -Percentage 90

        This command creates a new 'usage_limit' alert on SendGrid that will be sent to 'test@example.com' when the usage threshold reaches 90%.

    .EXAMPLE
        PS C:\> New-SGAlert -EmailStatisticsSummary -EmailTo 'test@example.com' -Frequency 'Daily' -OnBehalfOf 'Subuser'

        This command creates a new 'stats_notification' alert on SendGrid that will be sent to 'test@example.com' daily on behalf of the Subuser 'Subuser'.
    #>
    [CmdletBinding(
        SupportsShouldProcess
    )]
    param (
        # Specifies the type of alert to Email Credit Usage.
        [Parameter(
            Mandatory,
            ParameterSetName = 'Usage',
            Position = 0
        )]
        [switch]$EmailCreditUsage,

        # Specifies the type of alert to Email Statistics Summary.
        [Parameter(
            Mandatory,
            ParameterSetName = 'Statistics',
            Position = 0
        )]
        [switch]$EmailStatisticsSummary,

        # Specifies the email address the alert will be sent to.
        [Parameter(
            Mandatory,
            ParameterSetName = 'Statistics',
            Position = 1
        )]
        [Parameter(
            Mandatory,
            ParameterSetName = 'Usage',
            Position = 1
        )]
        [MailAddress]$EmailTo,

        # Specifies how frequently the alert will be sent. Required for the EmailStatisticsSummary alert.
        [Parameter(
            Mandatory,
            ParameterSetName = 'Statistics',
            Position = 2
        )]
        [ValidateSet('Daily', 'Weekly', 'Monthly')]
        [string]$Frequency,

        # Specifies the usage threshold at which the alert will be sent. Required for the EmailCreditUsage alert.
        [Parameter(
            Mandatory,
            ParameterSetName = 'Usage',
            Position = 2
        )]
        [ValidateRange(1, 100)]
        [int]$Percentage,

        # Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
        [Parameter(ParameterSetName = 'Statistics')]
        [Parameter(ParameterSetName = 'Usage')]
        [string]$OnBehalfOf
    )
    process {
        $InvokeSplat = @{
            Method        = 'Post'
            Namespace     = 'alerts'
            ErrorAction   = 'Stop'
            CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
        }

        $ContentBody = @{
            'email_to' = $EmailTo.Address
        }
        if ($PSCmdlet.ParameterSetName -eq 'Usage') {
            $ContentBody.Add('type', 'usage_limit')
            $ContentBody.Add('Percentage', $Percentage)
        }
        else {
            $ContentBody.Add('type', 'stats_notification')
            $ContentBody.Add('frequency', $Frequency.ToLowerInvariant())
        }

        $InvokeSplat.Add('ContentBody', $ContentBody)

        if ($PSBoundParameters.OnBehalfOf) {
            $InvokeSplat.Add('OnBehalfOf', $OnBehalfOf)
        }
        if ($PSCmdlet.ShouldProcess($EmailTo.Address)) {
            try {
                Invoke-SendGrid @InvokeSplat
            }
            catch {
                Write-Error ('Failed to create SendGrid alert. {0}' -f $_.Exception.Message) -ErrorAction Stop
            }
        }
    }
}