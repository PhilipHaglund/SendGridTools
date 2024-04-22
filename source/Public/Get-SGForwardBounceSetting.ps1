function Get-SGForwardBounceSetting {
    <#
    .SYNOPSIS
        Retrieves the forward bounce mail settings on SendGrid.
    .DESCRIPTION
        Get-SGForwardBounceSetting retrieves the forward bounce mail settings on SendGrid.
    .EXAMPLE
        PS C:\> Get-SGForwardBounceSetting
        This command retrieves the forward bounce mail settings on SendGrid.
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
            Namespace     = 'mail_settings/forward_bounce'
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
            Write-Error ('Failed to retrieve SendGrid forward bounce settings. {0}' -f $_.Exception.Message) -ErrorAction Stop
        }
    }
}