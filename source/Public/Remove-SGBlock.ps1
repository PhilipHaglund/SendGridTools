function Remove-SGBlock {
    <#
    .SYNOPSIS
        Removes a specific block from SendGrid.

    .DESCRIPTION
        Remove-SGBlock removes a specific block from SendGrid based on its email address.

    .PARAMETER EmailAddress
        Specifies the email address of the block to remove.

    .PARAMETER OnBehalfOf
        Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.

    .EXAMPLE
        PS C:\> Remove-SGBlock -EmailAddress "block1@example.com"

        This command removes the block with the email address 'block1@example.com' from SendGrid.

    .EXAMPLE
        PS C:\> Remove-SGBlock -EmailAddress "block2@example.com" -OnBehalfOf 'Subuser'

        This command removes the block with the email address 'block2@example.com' from SendGrid for the Subuser 'Subuser'.
    #>
    [CmdletBinding(
        DefaultParameterSetName = 'Default',
        SupportsShouldProcess,
        ConfirmImpact = 'High'
    )]
    param (
        # Specifies the email address of the block to remove.
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
        [Parameter(
            ParameterSetName = 'DeleteAll',
            Mandatory = $true,
            Position = 0
        )]
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
                Namespace     = 'suppression/blocks'
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
        else {
            foreach ($Id in $EmailAddress) {
                $InvokeSplat = @{
                    Method        = 'Delete'
                    Namespace     = "suppression/blocks/$($Id.Address)"
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
}