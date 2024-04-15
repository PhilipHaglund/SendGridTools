function New-SGAlert {
    <#
    .SYNOPSIS
        Creates a new alert on SendGrid.

    .DESCRIPTION
        New-SGAlert creates a new alert on SendGrid based on the provided parameters.

    .PARAMETER Type
        Specifies the type of alert to create. Can be either 'usage_limit' or 'stats_notification'.

    .PARAMETER EmailTo
        Specifies the email address the alert will be sent to.

    .PARAMETER Frequency
        Specifies how frequently the alert will be sent. Required for 'stats_notification'.

    .PARAMETER Percentage
        Specifies the usage threshold at which the alert will be sent. Required for 'usage_alert'.

    .PARAMETER OnBehalfOf
        Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.

    .EXAMPLE
        PS C:\> New-SGAlert -Type 'usage_limit' -EmailTo 'test@example.com' -Percentage 90

        This command creates a new 'usage_limit' alert on SendGrid that will be sent to 'test@example.com' when the usage threshold reaches 90%.

    .EXAMPLE
        PS C:\> New-SGAlert -Type 'stats_notification' -EmailTo 'test@example.com' -Frequency 'daily' -OnBehalfOf 'Subuser'

        This command creates a new 'stats_notification' alert on SendGrid that will be sent to 'test@example.com' daily on behalf of the Subuser 'Subuser'.
    #>
    [CmdletBinding(
        SupportsShouldProcess
    )]
    param (
        # Specifies the type of alert to Email Credit Usage.
        [Parameter(
            Mandatory,
            ParameterSetName = 'Usage'
        )]
        [switch]$EmailCreditUsage,

        # Specifies the type of alert to Email Statistics Summary.
        [Parameter(
            Mandatory,
            ParameterSetName = 'Statistics'
        )]
        [switch]$EmailStatisticsSummary,

        # Specifies the email address the alert will be sent to.
        [Parameter(
            Mandatory,
            ParameterSetName = 'Statistics'
        )]
        [Parameter(
            Mandatory,
            ParameterSetName = 'Usage'
        )]
        [MailAddress]$EmailTo,

        # Specifies how frequently the alert will be sent. Required for 'stats_notification'.
        [Parameter(
            Mandatory,
            ParameterSetName = 'Statistics'
        )]
        [ValidateSet('Daily', 'Weekly', 'Monthly')]
        [string]$Frequency,

        # Specifies the usage threshold at which the alert will be sent. Required for 'usage_alert'.
        [Parameter(
            Mandatory,
            ParameterSetName = 'Usage'
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
        if ($PSBoundParameters.EmailCreditUsage) {
            $ContentBody.Add('type', 'usage_limit')
            $ContentBody.Add('Percentage', $Percentage)
        }
        else {
            $ContentBody.Add('type', 'stats_notification')
            $ContentBody.Add('frequency', $Frequency.ToLower())
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