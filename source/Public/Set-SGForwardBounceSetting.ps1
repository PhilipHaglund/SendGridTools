function Set-SGForwardBounceSetting {
    <#
    .SYNOPSIS
        Updates the forward bounce mail settings on SendGrid.
    .DESCRIPTION
        Set-SGForwardBounceSetting updates the forward bounce mail settings on SendGrid.
    .EXAMPLE
        PS C:\> Set-SGForwardBounceSetting -Email 'example@example.com' -Enabled $true This command updates the forward bounce mail settings on SendGrid.
    .NOTES
        To use this function, you must be connected to a SendGrid instance. Use the Connect-SendGrid function to establish a connection.
    #>
    [CmdletBinding()]
    param (
        # The email address that you would like your bounce reports forwarded to. If you do not want to forward bounce reports, set this to $null.
        [Parameter()]
        [AllowNull()]
        [MailAddress]$Email,

        # Indicates if the bounce forwarding mail setting is enabled.
        [Parameter()]
        [switch]$Enabled,

        # Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
        [Parameter()]
        [string]$OnBehalfOf

    )
    process {
        $ContentBody = @{}
        $InvokeSplat = @{
            Method        = 'Patch'
            Namespace     = 'mail_settings/forward_bounce'
            ErrorAction   = 'Stop'
            CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
        }

        if ($PSBoundParameters.OnBehalfOf) {
            $InvokeSplat.Add('OnBehalfOf', $OnBehalfOf)
        }

        if ($PSBoundParameters.ContainsKey('Enabled')) {
            $ContentBody.Add('enabled', $Enabled.IsPresent)
        }

        if ($PSBoundParameters.ContainsKey('Email')) {
            if ($null -eq $Email) {
                $ContentBody.Add('email', '')
            }
            else {
                $ContentBody.Add('email', $Email.Address)
            }
        }

        $InvokeSplat.Add('ContentBody', $ContentBody)
        try {
            Invoke-SendGrid @InvokeSplat
        }
        catch {
            Write-Error ('Failed to update SendGrid forward bounce settings. {0}' -f $_.Exception.Message) -ErrorAction Stop
        }
    }
}