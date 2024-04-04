function Get-SGIPAddress {
    <#
    .SYNOPSIS
        Retrieves the IP addresses associated with the current SendGrid instance.

    .DESCRIPTION
        Get-SGIPAddress retrieves the IP addresses associated with the current SendGrid instance.

    .EXAMPLE
        PS C:\> Get-SGIPAddress

        This command retrieves the IP addresses associated with the current SendGrid instance.

    .NOTES
        To use this function, you must be connected to a SendGrid instance. Use the Connect-SendGrid function to establish a connection.

    #>
    [CmdletBinding()]
    param ()

    process {
        $InvokeSplat = @{
            Method        = 'Get'
            Namespace     = 'ips'
            ErrorAction   = 'Stop'
            CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
        } 
        
        try {
            Invoke-SendGrid @InvokeSplat
        }
        catch {
            Write-Error ('Failed to retrieve SendGrid IPs. {0}' -f $_.Exception.Message) -ErrorAction Stop
        }
    }
}