function Disconnect-SendGrid {
    <#
    .SYNOPSIS
        Disconnects from the current established SendGrid instance.
        
    .DESCRIPTION
        Disconnect-SendGrid, or its alias Disconnect-SG, disconnects the current session with a SendGrid instance. 
        The function checks if a session exists and, if so, disconnects it.

    .EXAMPLE
        PS C:\> Disconnect-SendGrid
        
        This command attempts to disconnect an active connection to SendGrid.

    .NOTES
        To use this function, you must first be connected to a SendGrid instance. Use the Connect-SendGrid function to establish a connection.
    #>
    [CmdletBinding(
        SupportsShouldProcess
    )]
    [Alias('Disconnect-SG')]
    param ()
    
    process {
        if ($script:Session -is [SendGridSession]) {
            if ($PSCmdlet.ShouldProcess('SendGrid Session', 'Disconnect')) {
                try {
                    $script:Session.Disconnect()
                    Remove-Variable -Name Session -Scope Script
                }
                catch {
                    Write-Error -Message ('Unable to disconnect from SendGrid. {0}' -f { $_.Exception.Message })
                }
            }
        }
        else {
            Write-Warning -Message 'No active SendGrid session was found.'
        }
    }
}