function Set-SGForwardSpamSetting {
    <#
    .SYNOPSIS
        Updates the forward spam mail settings on SendGrid.
    .DESCRIPTION
        Set-SGForwardSpamSetting updates the forward spam mail settings on SendGrid.

    .PARAMETER Email
        Specifies the email addresses that spam reports are forwarded to. Set this parameter to $null to stop forwarding spam reports.

    .PARAMETER Enabled
        Specifies whether the spam forwarding mail setting is enabled. Use -Enabled:$false to disable it.

    .PARAMETER OnBehalfOf
        Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
    .EXAMPLE
        PS C:\> Set-SGForwardSpamSetting -Email 'example@example.com' -Enabled
        This command updates the forward spam mail settings on SendGrid.
    .NOTES
        To use this function, you must be connected to a SendGrid instance. Use the Connect-SendGrid function to establish a connection.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Adding SupportsShouldProcess would add the -WhatIf and -Confirm parameters to this public function and change behaviour; the repair is deferred so the public surface stays unchanged.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseOutputTypeCorrectly', '', Justification = 'Declaring the Hashtable output type would change the OutputType metadata exposed by Get-Command and help; the repair is deferred so the public surface stays unchanged.')]
    [CmdletBinding()]
    param (
        # The email address that you would like your spam reports forwarded to. If you do not want to forward spam reports, set this to $null.
        [Parameter()]
        [AllowNull()]
        [MailAddress[]]$Email,

        # Indicates if the spam forwarding mail setting is enabled.
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
            Namespace     = 'mail_settings/forward_spam'
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
                $ContentBody.Add('email', (($Email | ForEach-Object { $_.Address }) -join ', '))
            }
        }

        $InvokeSplat.Add('ContentBody', $ContentBody)
        $InvokeSplat
        try {
            Invoke-SendGrid @InvokeSplat
        }
        catch {
            Write-Error ('Failed to update SendGrid forward spam settings. {0}' -f $_.Exception.Message) -ErrorAction Stop
        }
    }
}