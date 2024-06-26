function Disable-SGSubuser {
    <#
    .SYNOPSIS
        Disables a Subuser within the current SendGrid instance.

    .DESCRIPTION
        Disable-SGSubuser disables a Subuser within the current SendGrid instance. 
        The Subuser is disabled with the provided username.

    .PARAMETER Username
        Specifies the ID of a specific Subuser to enable. This parameter is mandatory.

    .EXAMPLE
        PS C:\> Disable-SGSubuser -Username <username>

        This command disables a Subuser with the specified username within the current SendGrid instance.
    

    .NOTES
        To use this function, you must be connected to a SendGrid instance. Use the Connect-SendGrid function to establish a connection.

    #>
    [CmdletBinding(
        SupportsShouldProcess,
        ConfirmImpact = 'High'
    )]
    param (

        # Specifies the username for the Subuser to create.
        [Parameter(
            Mandatory,
            ValueFromPipelineByPropertyName,
            Position = 0
        )]
        [string]$Username
    )
    process {
        $InvokeSplat = @{
            Method        = 'Patch'
            Namespace     = "subusers/$Username"
            ErrorAction   = 'Stop'
            ContentBody   = @{
                disabled = $true
            }
            CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
        } 

        if ($PSCmdlet.ShouldProcess($Username)) {
            try {
                Invoke-SendGrid @InvokeSplat
            }
            catch {
                Write-Error ('Failed to disable SendGrid Subuser. {0}' -f $_.Exception.Message) -ErrorAction Stop
            }
        }
    }
}