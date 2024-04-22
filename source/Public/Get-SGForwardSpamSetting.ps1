function Get-SGForwardSpamSetting {
    <#
    .SYNOPSIS
        Retrieves the forward spam mail settings on SendGrid.
    .DESCRIPTION
        Get-SGForwardSpamSetting retrieves the forward spam mail settings on SendGrid.
    .EXAMPLE
        PS C:\> Get-SGForwardSpamSetting
        This command retrieves the forward spam mail settings on SendGrid.
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
            Namespace     = 'mail_settings/forward_spam'
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
            Write-Error ('Failed to retrieve SendGrid forward spam settings. {0}' -f $_.Exception.Message) -ErrorAction Stop
        }
    }
}