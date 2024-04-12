function Remove-SGSuppressionGroup {
    <#
    .SYNOPSIS
        Deletes a suppression group.

    .DESCRIPTION
        The Remove-SGSuppressionGroup function deletes a suppression group in SendGrid.
        
    .PARAMETER GroupId
        Specifies the ID of the suppression group.

    .PARAMETER OnBehalfOf
        Specifies a On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.

    .EXAMPLE
        PS C:\> Remove-SGSuppressionGroup -GroupId 123
        This command deletes the suppression group with the ID 123.
    #>
    [CmdletBinding(
        SupportsShouldProcess,
        ConfirmImpact = 'High'
    )]
    param (
        # Specifies the ID of the suppression group.
        [Parameter(
            Mandatory,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName
        )]
        [Alias('Id')]
        [int]$GroupId,

        # Specifies a On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
        [Parameter()]
        [string]$OnBehalfOf
    )
    process {
        $InvokeSplat = @{
            Method        = 'Delete'
            Namespace     = "asm/groups/$GroupId"
            ErrorAction   = 'Stop'
            CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
        }
        if ($PSBoundParameters.ContainsKey('OnBehalfOf')) {
            $InvokeSplat.OnBehalfOf = $OnBehalfOf
        }
        if ($PSCmdlet.ShouldProcess(('Delete suppression group with ID {0}.' -f $GroupId))) {
            try {
                Invoke-SendGrid @InvokeSplat
            }
            catch {
                Write-Error ('Failed to delete suppression group. {0}' -f $_.Exception.Message) -ErrorAction Stop
            }
        }
    }
}