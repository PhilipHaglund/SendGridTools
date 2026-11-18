function Set-SGEnforcedTls {
    <#
    .SYNOPSIS
        Updates the Enforced TLS settings on SendGrid.
    .DESCRIPTION
        Set-SGEnforcedTls updates the Enforced TLS settings on SendGrid. The setting applies to all mail from the account, or from the subuser named with -OnBehalfOf. Only the settings you specify are sent, so the others keep their values.

        With -RequireTls, a recipient that does not support TLS does not get the mail: SendGrid drops it as a block. With -RequireValidCert, a recipient whose server has no valid certificate does not get the mail either. Check the effect on your mail flow before you enable them.

        At least one of -RequireTls, -RequireValidCert or -Version is required. The command asks for confirmation by default, because the change affects delivery of all mail.

    .PARAMETER RequireTls
        Specifies whether SendGrid requires the recipient to support TLS. Use -RequireTls:$false to stop requiring it. A recipient that does not support TLS does not get the mail when this is on.

    .PARAMETER RequireValidCert
        Specifies whether SendGrid requires the recipient's server to present a valid certificate. Use -RequireValidCert:$false to stop requiring it. A recipient without a valid certificate does not get the mail when this is on.

    .PARAMETER Version
        Specifies the minimum TLS version that SendGrid accepts when it delivers mail. Valid values are 1.1, 1.2 and 1.3. It is sent to SendGrid as a number.

    .PARAMETER OnBehalfOf
        Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
    .EXAMPLE
        PS C:\> Set-SGEnforcedTls -RequireTls -Version 1.2
        This command requires TLS 1.2 or later for all mail from the account.
    .EXAMPLE
        PS C:\> Set-SGEnforcedTls -RequireTls:$false
        This command stops requiring TLS for all mail from the account.
    .NOTES
        To use this function, you must be connected to a SendGrid instance. Use the Connect-SendGrid function to establish a connection.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Tls is an acronym, not a plural noun, and the name Set-SGEnforcedTls is the specified public surface, so renaming it is not possible.')]
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        # Specifies whether SendGrid requires the recipient to support TLS.
        [Parameter()]
        [switch]$RequireTls,

        # Specifies whether SendGrid requires the recipient's server to present a valid certificate.
        [Parameter()]
        [switch]$RequireValidCert,

        # Specifies the minimum TLS version that SendGrid accepts.
        [Parameter()]
        [ValidateSet('1.1', '1.2', '1.3')]
        [string]$Version,

        # Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
        [Parameter()]
        [string]$OnBehalfOf
    )
    process {
        $ContentBody = @{}
        $InvokeSplat = @{
            Method        = 'Patch'
            Namespace     = 'user/settings/enforced_tls'
            ErrorAction   = 'Stop'
            CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
        }

        if ($PSBoundParameters.OnBehalfOf) {
            $InvokeSplat.Add('OnBehalfOf', $OnBehalfOf)
        }

        if ($PSBoundParameters.ContainsKey('RequireTls')) {
            $ContentBody.Add('require_tls', $RequireTls.IsPresent)
        }

        if ($PSBoundParameters.ContainsKey('RequireValidCert')) {
            $ContentBody.Add('require_valid_cert', $RequireValidCert.IsPresent)
        }

        if ($PSBoundParameters.ContainsKey('Version')) {
            $ContentBody.Add('version', [double]::Parse($Version, [cultureinfo]::InvariantCulture))
        }

        if ($ContentBody.Count -eq 0) {
            Write-Error -Message 'Set-SGEnforcedTls needs at least one of -RequireTls, -RequireValidCert or -Version.' -ErrorAction Stop
        }

        $InvokeSplat.Add('ContentBody', $ContentBody)

        $Target = 'Enforced TLS settings of the SendGrid account'
        if ($PSBoundParameters.OnBehalfOf) {
            $Target = 'Enforced TLS settings of subuser {0}' -f $OnBehalfOf
        }

        if ($PSCmdlet.ShouldProcess($Target, 'Update')) {
            try {
                Invoke-SendGrid @InvokeSplat
            }
            catch {
                Write-Error ('Failed to update SendGrid Enforced TLS settings. {0}' -f $_.Exception.Message) -ErrorAction Stop
            }
        }
    }
}
