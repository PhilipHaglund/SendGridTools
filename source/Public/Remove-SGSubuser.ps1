function Remove-SGSubuser {
    <#
    .SYNOPSIS
        Removes a specific Subuser within the current SendGrid instance.

    .DESCRIPTION
        Remove-SGSubuser removes a specific Subuser based on its username within the current SendGrid instance.

    .PARAMETER Username
        Specifies the username of the Subuser to remove.

    .EXAMPLE
        PS C:\> Remove-SGSubuser -Username <username>

        This command removes the Subuser with the specified username within the current SendGrid instance.
    #>
    [CmdletBinding(
        SupportsShouldProcess,
        ConfirmImpact = 'High'
    )]
    param (
        # Specifies the username of the Subuser to remove.
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            Position = 0
        )]
        [string]$Username
    )

    process {
        $InvokeSplat = @{
            Method        = 'Delete'
            Namespace     = "subusers/$([uri]::EscapeDataString($Username))"
            ErrorAction   = 'Stop'
            CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
        }

        if ($PSCmdlet.ShouldProcess($Username)) {
            try {
                Invoke-SendGrid @InvokeSplat
            }
            catch {
                Write-Error -Exception (ConvertTo-SendGridCommandException -Message ('Failed to remove SendGrid Subuser. {0}' -f $_.Exception.Message) -ErrorRecord $_) -ErrorAction Stop
            }
        }
    }
}