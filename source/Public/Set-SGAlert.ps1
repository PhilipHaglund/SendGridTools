function Set-SGAlert {
    <#
    .SYNOPSIS
        Updates an existing alert on SendGrid.

    .DESCRIPTION
        Set-SGAlert updates an existing alert on SendGrid based on the provided parameters.

    .PARAMETER AlertId
        Specifies the ID of the alert to update.

    .PARAMETER EmailTo
        Specifies the new email address the alert will be sent to.

    .PARAMETER Frequency
        Specifies the new frequency at which the alert will be sent. Required for 'stats_notification'.

    .PARAMETER Percentage
        Specifies the new usage threshold at which the alert will be sent. Required for 'usage_alert'.

    .PARAMETER OnBehalfOf
        Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.

    .EXAMPLE
        PS C:\> Set-SGAlert -AlertId 123 -EmailTo 'test@example.com' -Percentage 90

        This command updates the alert with the ID 123 on SendGrid to be sent to 'test@example.com' when the usage threshold reaches 90%.

    .EXAMPLE
        PS C:\> Set-SGAlert -AlertId 123 -EmailTo 'test@example.com' -Frequency 'daily' -OnBehalfOf 'Subuser'

        This command updates the alert with the ID 123 on SendGrid to be sent to 'test@example.com' daily on behalf of the Subuser 'Subuser'.
    #>
    [CmdletBinding(
        SupportsShouldProcess
    )]
    param (
        # Specifies the ID of the alert to update.
        [Parameter(
            Mandatory,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName
        )]
        [Alias('Id')]
        [int]$AlertId,

        # Specifies the new email address the alert will be sent to.
        [Parameter()]
        [MailAddress]$EmailTo,

        # Specifies the new frequency at which the alert will be sent. Required for 'stats_notification'.
        [Parameter()]
        [ValidateSet('Daily', 'Weekly', 'Monthly')]
        [string]$Frequency,

        # Specifies the new usage threshold at which the alert will be sent. Required for 'usage_alert'.
        [Parameter()]
        [ValidateRange(1, 100)]
        [int]$Percentage,

        # Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
        [Parameter()]
        [string]$OnBehalfOf
    )
    process {
        if ($PSCmdlet.ShouldProcess(('Update alert with ID {0}.' -f $AlertId))) {
            try {
                $Verify = Get-SGAlert -AlertId $AlertId -OnBehalfOf $OnBehalfOf
            }
            catch {
                Write-Error ('Failed to retrieve SendGrid alert. {0}' -f $_.Exception.Message) -ErrorAction Stop
            }

            $ContentBody = @{}

            switch ($Verify.Type) {
                'usage_alert' {
                    if ($PSBoundParameters.Percentage) {
                        $ContentBody.Add('percentage', $Percentage)
                    }
                    elseif ($PSBoundParameters.Frequency) {
                        Write-Verbose ('The alert with ID {0} is a usage_alert alert and does not require a frequency to be updated. Will ignore' -f $AlertId)
                    }
                    elseif ($PSBoundParameters.EmailTo) {
                        # Fail safe
                    }
                    else {
                        Write-Error ('The alert with ID {0} is a usage_alert alert and requires a percentage to be updated.' -f $AlertId) -ErrorAction Stop
                    }
                    break;
                }
                'stats_notification' {
                    if ($PSBoundParameters.Percentage) {
                        Write-Verbose ('The alert with ID {0} is a stats_notification alert and does not require a percentage to be updated. Will be ignored' -f $AlertId)
                    }
                    elseif ($PSBoundParameters.Frequency) {
                        $ContentBody.Add('frequency', $Frequency.ToLower())
                    }
                    elseif ($PSBoundParameters.EmailTo) {
                        # Fail safe
                    }
                    else {
                        Write-Error ('The alert with ID {0} is a stats_notification alert and requires a frequency to be updated.' -f $AlertId) -ErrorAction Stop
                    }
                    break;
                }
                Default {
                    Write-Error ('The alert with ID {0} is an unknown type. Create an issue on GitHub.' -f $AlertId) -ErrorAction Stop
                    break;
                }
            }

            if ($PSBoundParameters.EmailTo) {
                $ContentBody.Add('email_to', $EmailTo.Address)
            }

            $InvokeSplat = @{
                Method        = 'Patch'
                Namespace     = "alerts/$AlertId"
                ErrorAction   = 'Stop'
                CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
            }
            if ($PSBoundParameters.OnBehalfOf) {
                $InvokeSplat.Add('OnBehalfOf', $OnBehalfOf)
            }

            $InvokeSplat['ContentBody'] = $ContentBody
        
            try {
                Invoke-SendGrid @InvokeSplat
            }
            catch {
                Write-Error ('Failed to update SendGrid alert. {0}' -f $_.Exception.Message) -ErrorAction Stop
            }
        }
    }
}