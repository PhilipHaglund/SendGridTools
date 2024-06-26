function Remove-SGSpamReport {
    <#
    .SYNOPSIS
        Removes a specific spam report from SendGrid.

    .DESCRIPTION
        Remove-SGSpamReport removes a specific spam report from SendGrid based on its ID.

    .PARAMETER ReportId
        Specifies the ID of the spam report to remove.

    .PARAMETER OnBehalfOf
        Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.

    .EXAMPLE
        PS C:\> Remove-SGSpamReport -EmailAddress spam1@example.com
        This command removes the spam report with the email address spam1@example.com from SendGrid. 

    .EXAMPLE
        PS C:\> Remove-SGSpamReport -EmailAddress spam2@example.com -OnBehalfOf 'Subuser'
        This command removes the spam report with the email address spam2@example.com from SendGrid for the Subuser 'Subuser'.
    #>
    [CmdletBinding(
        DefaultParameterSetName = 'Default',
        SupportsShouldProcess,
        ConfirmImpact = 'High'
    )]
    param (
        # Specifies the invalid email address to remove.
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            ParameterSetName = 'Default',
            Position = 0
        )]
        [Alias('Email')]
        [MailAddress[]]$EmailAddress,

        # Specifies whether to delete all emails on the invalid email address list.
        [Parameter(ParameterSetName = 'DeleteAll')]
        [switch]$DeleteAll,

        # Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'DeleteAll')]
        [string]$OnBehalfOf
    )
    process {
        if ($PSCmdlet.ParameterSetName -eq 'DeleteAll') {
            $InvokeSplat = @{
                Method        = 'Delete'
                Namespace     = 'suppression/spam_reports'
                ErrorAction   = 'Stop'
                CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
            }
            if ($PSBoundParameters.OnBehalfOf) {
                $InvokeSplat.Add('OnBehalfOf', $OnBehalfOf)
            }
            if ($PSCmdlet.ShouldProcess('Remove all email addresses from SendGrid spam reports.')) {
                try {
                    Invoke-SendGrid @InvokeSplat
                }
                catch {
                    Write-Error ('Failed to remove all email addresses from SendGrid spam reports. {0}' -f $_.Exception.Message) -ErrorAction Stop
                }
            }
        }
        foreach ($Id in $EmailAddress) {
            $InvokeSplat = @{
                Method        = 'Delete'
                Namespace     = "suppression/spam_reports/$($Id.Address)"
                ErrorAction   = 'Stop'
                CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
            }
            if ($PSBoundParameters.OnBehalfOf) {
                $InvokeSplat.Add('OnBehalfOf', $OnBehalfOf)
            }
            if ($PSCmdlet.ShouldProcess(('Remove email address {0} from spam report.' -f $Id.Address))) {
                try {
                    Invoke-SendGrid @InvokeSplat
                }
                catch {
                    Write-Error ('Failed to remove email address "{0}" from SendGrid spam report. {0}' -f $Id.Address, $_.Exception.Message) -ErrorAction Stop
                }
            }
        }
    }
}