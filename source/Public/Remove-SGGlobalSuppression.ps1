function Remove-SGGlobalSuppression {
    <#
    .SYNOPSIS
        Removes a specific email address from the global suppressions list in SendGrid.

    .DESCRIPTION
        Remove-SGSGlobalSuppression removes a specific email address from the global suppressions list in SendGrid.

    .PARAMETER EmailAddress
        Specifies the email address to remove from the global suppressions list.

    .PARAMETER OnBehalfOf
        Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.

    .EXAMPLE
        PS C:\> Remove-SGSGlobalSuppression -EmailAddress 'test@example.com'
        This command removes the email address 'test@example.com' from the global suppressions list in SendGrid.

    .EXAMPLE
        PS C:\> Remove-SGSGlobalSuppression -EmailAddress 'test@example.com' -OnBehalfOf 'Subuser'
        This command removes the email address 'test@example.com' from the global suppressions list in SendGrid for the Subuser 'Subuser'.
    #>
    [CmdletBinding(
        SupportsShouldProcess,
        ConfirmImpact = 'High'
    )]
    param (
        # Specifies the email address to remove from the global suppressions list.
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            Position = 0
        )]
        [Alias('Email')]
        [string]$EmailAddress,

        # Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
        [Parameter(ParameterSetName = 'Default')]
        [string]$OnBehalfOf
    )
    process {
        $InvokeSplat = @{
            Method        = 'Delete'
            Namespace     = "suppression/unsubscribes/$EmailAddress"
            ErrorAction   = 'Stop'
            CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
        }
        if ($PSBoundParameters.OnBehalfOf) {
            $InvokeSplat.Add('OnBehalfOf', $OnBehalfOf)
        }
        if ($PSCmdlet.ShouldProcess(('Remove email address {0} from global suppressions list.' -f $EmailAddress))) {
            try {
                Invoke-SendGrid @InvokeSplat
            }
            catch {
                Write-Error ('Failed to remove email address "{0}" from global suppressions list. {0}' -f $EmailAddress, $_.Exception.Message) -ErrorAction Stop
            }
        }
    }
}
