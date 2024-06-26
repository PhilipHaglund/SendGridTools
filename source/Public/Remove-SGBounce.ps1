function Remove-SGBounce {
    <#
    .SYNOPSIS
        Removes a specific bounce from SendGrid.

    .DESCRIPTION
        Remove-SGBounce removes a specific bounce from SendGrid based on its email address.

    .PARAMETER EmailAddress
        Specifies the email address of the bounce to remove.

    .PARAMETER OnBehalfOf
        Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.

    .PARAMETER DeleteAll
        Specifies whether to delete all emails on the bounces list.

    .EXAMPLE
        PS C:\> Remove-SGBounce -EmailAddress "bounce1@example.com"

        This command removes the bounce with the email address 'bounce1@example.com' from SendGrid.

    .EXAMPLE
        PS C:\> Remove-SGBounce -EmailAddress "bounce2@example.com" -OnBehalfOf 'Subuser'

        This command removes the bounce with the email address 'bounce2@example.com' from SendGrid for the Subuser 'Subuser'.

    .EXAMPLE
        PS C:\> Remove-SGBounce -DeleteAll $true

        This command deletes all emails on the bounces list from SendGrid.
    #>
    [CmdletBinding(
        DefaultParameterSetName = 'Default',
        SupportsShouldProcess,
        ConfirmImpact = 'High'
    )]
    param (
        # Specifies the email address of the bounce to remove.
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            ParameterSetName = 'Default',
            Position = 0
        )]
        [Alias('Email')]
        [MailAddress[]]$EmailAddress,

        # Specifies whether to delete all emails on the bounces list.
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
                Namespace     = 'suppression/bounces'
                ErrorAction   = 'Stop'
                CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
            }
            if ($PSBoundParameters.OnBehalfOf) {
                $InvokeSplat.Add('OnBehalfOf', $OnBehalfOf)
            }
            if ($PSCmdlet.ShouldProcess('Remove all bounces from SendGrid')) {
                try {
                    Invoke-SendGrid @InvokeSplat
                }
                catch {
                    Write-Error ('Failed to remove all SendGrid bounces. {0}' -f $_.Exception.Message) -ErrorAction Stop
                }
            }
        }
        foreach ($Id in $EmailAddress) {
            $InvokeSplat = @{
                Method        = 'Delete'
                Namespace     = "suppression/bounces/$($Id.Address)"
                ErrorAction   = 'Stop'
                CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
            }
            if ($PSBoundParameters.OnBehalfOf) {
                $InvokeSplat.Add('OnBehalfOf', $OnBehalfOf)
            }
            if ($PSCmdlet.ShouldProcess(('Remove bounce with email address {0}' -f $Id.Address))) {
                try {
                    Invoke-SendGrid @InvokeSplat
                }
                catch {
                    Write-Error ('Failed to remove SendGrid bounce "{0}". {0}' -f $Id.Address, $_.Exception.Message) -ErrorAction Stop
                }
            }
        }
    }
}