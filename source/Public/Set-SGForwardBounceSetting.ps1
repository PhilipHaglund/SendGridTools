function Set-SGForwardBounceSetting {
    <#
    .SYNOPSIS
        Updates the forward bounce mail settings on SendGrid.
    .DESCRIPTION
        Set-SGForwardBounceSetting updates the forward bounce mail settings on SendGrid.

    .PARAMETER Email
        Specifies the email address that bounce reports are forwarded to. Set this parameter to $null to stop forwarding bounce reports.

    .PARAMETER Enabled
        Specifies whether the bounce forwarding mail setting is enabled. Use -Enabled:$false to disable it.

    .PARAMETER OnBehalfOf
        Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
    .EXAMPLE
        PS C:\> Set-SGForwardBounceSetting -Email 'example@example.com' -Enabled
        This command updates the forward bounce mail settings on SendGrid.
    .NOTES
        To use this function, you must be connected to a SendGrid instance. Use the Connect-SendGrid function to establish a connection.
    #>
    [CmdletBinding(
        SupportsShouldProcess
    )]
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
        if ($PSCmdlet.ShouldProcess('mail_settings/forward_bounce')) {
            try {
                Invoke-SendGrid @InvokeSplat
            }
            catch {
                Write-Error -Exception (ConvertTo-SendGridCommandException -Message ('Failed to update SendGrid forward bounce settings. {0}' -f $_.Exception.Message) -ErrorRecord $_) -ErrorAction Stop
            }
        }
    }
}