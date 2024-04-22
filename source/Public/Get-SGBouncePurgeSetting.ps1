function Get-SGBouncePurgeSetting {
    <#
    .SYNOPSIS
        Retrieves the bounce purge mail settings on SendGrid.
    .DESCRIPTION
        Get-SGBouncePurgeSetting retrieves the bounce purge mail settings on SendGrid.
    .EXAMPLE
        PS C:\> Get-SGBouncePurgeSetting
        This command retrieves the bounce purge mail settings on SendGrid.
    .NOTES
        To use this function, you must be connected to a SendGrid instance. Use the Connect-SendGrid function to establish a connection.
    #>
    [CmdletBinding()]
    param (
        # Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
        [Parameter()]
        [string]$OnBehalfOf
    )
    process {
        $InvokeSplat = @{
            Method        = 'Get'
            Namespace     = 'mail_settings/bounce_purge'
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
            Write-Error ('Failed to retrieve SendGrid bounce purge settings. {0}' -f $_.Exception.Message) -ErrorAction Stop
        }
    }
}