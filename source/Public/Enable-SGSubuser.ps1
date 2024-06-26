function Enable-SGSubuser {
    <#
    .SYNOPSIS
        Enables a Subuser within the current SendGrid instance.

    .DESCRIPTION
        Enable-SGSubuser enables a Subuser within the current SendGrid instance. 
        The Subuser is enabled with the provided username.

    .PARAMETER Username
        Specifies the ID of a specific Subuser to enable. This parameter is mandatory.

    .EXAMPLE
        PS C:\> Enable-SGSubuser -Username <username>
        
        This command enables a Subuser with the specified username within the current SendGrid instance.

    .NOTES
        To use this function, you must be connected to a SendGrid instance. Use the Connect-SendGrid function to establish a connection.

    #>
    [CmdletBinding(
        SupportsShouldProcess
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
                disabled = $false
            }
            CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
        } 

        if ($PSCmdlet.ShouldProcess($Username)) {
            try {
                Invoke-SendGrid @InvokeSplat
            }
            catch {
                Write-Error ('Failed to enable SendGrid Subuser. {0}' -f $_.Exception.Message) -ErrorAction Stop
            }
        }
    }
}