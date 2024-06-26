function Remove-SGSubuser {
    <#
    .SYNOPSIS
        Removes a specific Subuser within the current SendGrid instance.

    .DESCRIPTION
        Remove-SGSubuser removes a specific Subuser based on its username within the current SendGrid instance.

    .PARAMETER Username
        Specifies the ID of the Subuser to remove.

    .EXAMPLE
        PS C:\> Remove-SGSubuser -Username <username>
        
        This command removes the Subuser with the specified username within the current SendGrid instance.
    #>
    [CmdletBinding(
        SupportsShouldProcess,
        ConfirmImpact = 'High'
    )]
    param (
        # Specifies the ID of the Subuser to remove.
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            Position = 0
        )]
        [Alias('ID')]
        [string]$Username
    )

    process {
        $InvokeSplat = @{
            Method        = 'Delete'
            Namespace     = "subusers/$Username"
            ErrorAction   = 'Stop'
            CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
        }

        if ($PSCmdlet.ShouldProcess(('{0}' -f 'Subuser'))) {
            try {
                Invoke-SendGrid @InvokeSplat
            }
            catch {
                Write-Error ('Failed to remove SendGrid Subuser. {0}' -f $_.Exception.Message) -ErrorAction Stop
            }
        }
    }
}