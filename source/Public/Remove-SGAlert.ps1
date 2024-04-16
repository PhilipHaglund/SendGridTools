function Remove-SGAlert {
    <#
    .SYNOPSIS
        Deletes an existing alert on SendGrid.

    .DESCRIPTION
        Remove-SGAlert deletes an existing alert on SendGrid based on the provided alert ID.

    .PARAMETER AlertId
        Specifies the ID of the alert to delete.

    .PARAMETER OnBehalfOf
        Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.

    .EXAMPLE
        PS C:\> Remove-SGAlert -AlertId 123

        This command deletes the alert with the ID 123 on SendGrid.

    .EXAMPLE
        PS C:\> Remove-SGAlert -AlertId 123 -OnBehalfOf 'Subuser'

        This command deletes the alert with the ID 123 on SendGrid on behalf of the Subuser 'Subuser'.
    #>
    [CmdletBinding(
        SupportsShouldProcess = $true,
        ConfirmImpact = 'High'
    )]
    param (
        # Specifies the ID of the alert to delete.
        [Parameter(
            Mandatory,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName
        )]
        [Alias('Id')]
        [int]$AlertId,

        # Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
        [Parameter()]
        [string]$OnBehalfOf
    )
    process {
        if ($PSCmdlet.ShouldProcess($AlertId)) {
            $InvokeSplat = @{
                Method        = 'Delete'
                Namespace     = "alerts/$AlertId"
                ErrorAction   = 'Stop'
                CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
            }
            if ($PSBoundParameters.OnBehalfOf) {
                $InvokeSplat.Add('OnBehalfOf', $OnBehalfOf)
            }
            try {
                Invoke-SendGrid @InvokeSplat
            }
            catch {
                Write-Error ('Failed to delete SendGrid alert. {0}' -f $_.Exception.Message) -ErrorAction Stop
            }
        }
    }
}