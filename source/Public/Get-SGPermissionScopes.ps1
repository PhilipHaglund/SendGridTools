function Get-SGPermissionScopes {
    <#
    .SYNOPSIS
        Retrieves all permission scopes that the current SendGrid session (apikey) has permission to.
        
    .DESCRIPTION
        Get-SGPermissionScopes queries SendGrid for all permission scopes that the current session, identified by the API key, has access to. 
        Permission scopes define the specific actions that are permitted in a session. This information can be useful for diagnosing 
        authorization issues or for configuring new sessions with the appropriate permissions.

    .EXAMPLE
        PS C:\> Get-SGPermissionScopes

        This command retrieves all permission scopes that the current session (apikey) has permission to.

    .NOTES
        To use this function, you must be connected to a SendGrid instance. Use the Connect-SendGrid function to establish a connection.
    #>
    [CmdletBinding()]
    param ()
    process {
        $InvokeSplat = @{
            Method      = 'Get'
            Namespace   = 'scopes'
            ErrorAction = 'Stop'
        }
        try {
            $InvokeResult = Invoke-SendGrid @InvokeSplat
            if ($InvokeResult.Errors.Count -gt 0) {
                throw $InvokeResult.Errors.Message
            }
            else {
                $InvokeResult
            }
        }
        catch {
            Write-Error ('Failed to retrieve permission scopes in SendGrid. {0}' -f $_.Exception.Message) -ErrorAction Stop
        }
        
    }
}