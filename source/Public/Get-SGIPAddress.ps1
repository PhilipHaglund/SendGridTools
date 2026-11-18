function Get-SGIPAddress {
    <#
    .SYNOPSIS
        Retrieves the IP addresses associated with the current SendGrid instance.

    .DESCRIPTION
        Get-SGIPAddress retrieves the IP addresses associated with the current SendGrid instance.
        Without -IncludeRegion it reads /v3/ips and the output has no Region property.
        With -IncludeRegion it reads another API, the IP Address Management
        API (/v3/send_ips/ips), whose objects have other properties, among them Region, and it reads every page
        of that list.

    .PARAMETER IncludeRegion
        Reads the IP Address Management API (send_ips/ips with include_region=true) instead of /v3/ips, follows
        every page, and returns its objects, which have other properties than the default output, among them Region.
        Time values such as AddedAt and UpdatedAt are Unix seconds, as SendGrid sends them.

    .EXAMPLE
        PS C:\> Get-SGIPAddress

        This command retrieves the IP addresses associated with the current SendGrid instance.

    .EXAMPLE
        PS C:\> Get-SGIPAddress -IncludeRegion

        This command retrieves every IP address from the IP Address Management API with its region in the Region
        property. The objects have other properties than the output without -IncludeRegion.

    .NOTES
        To use this function, you must be connected to a SendGrid instance. Use the Connect-SendGrid function to establish a connection.

    #>
    [CmdletBinding()]
    param (
        # Reads the IP Address Management API, send_ips/ips with include_region=true, whose objects have Region.
        [Parameter()]
        [switch]$IncludeRegion
    )

    process {
        if ($IncludeRegion.IsPresent) {
            try {
                Invoke-SendGridCursorList -Namespace 'send_ips/ips' -Query 'include_region=true' -ErrorAction Stop
            }
            catch {
                Write-Error ('Failed to retrieve SendGrid IPs. {0}' -f $_.Exception.Message) -ErrorAction Stop
            }
            return
        }

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