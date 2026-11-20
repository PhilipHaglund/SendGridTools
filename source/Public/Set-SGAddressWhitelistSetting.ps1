function Set-SGAddressWhitelistSetting {
    <#
    .SYNOPSIS
        Updates the address whitelist mail settings on SendGrid.
    .DESCRIPTION
        Set-SGAddressWhitelistSetting updates the address whitelist mail settings on SendGrid.
    .PARAMETER Enabled
        Specifies whether the email address whitelist is enabled.
    .PARAMETER List
        Specifies a list of email addresses or domains to be whitelisted.
    .PARAMETER OnBehalfOf
        Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
    .EXAMPLE
        PS C:\> Set-SGAddressWhitelistSetting -Enabled -List @('example.com')
        This command updates the address whitelist mail settings on SendGrid to enable the whitelist and add 'example.com' to the whitelist.
    #>
    [CmdletBinding(
        SupportsShouldProcess
    )]
    param (
        # Specifies whether the email address whitelist is enabled.
        [Parameter()]
        [switch]$Enabled,

        # Specifies a list of email addresses or domains to be whitelisted. To clear the list, pass an empty array (e.g. @()
        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$List,

        # Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
        [Parameter()]
        [string]$OnBehalfOf
    )
    process {
        [hashtable]$ContentBody = @{}
        $InvokeSplat = @{
            Method        = 'Patch'
            Namespace     = 'mail_settings/address_whitelist'
            ErrorAction   = 'Stop'
            CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
        }
        if ($PSBoundParameters.OnBehalfOf) {
            $InvokeSplat.Add('OnBehalfOf', $OnBehalfOf)
        }

        if ($PSBoundParameters.ContainsKey('Enabled')) {
            $ContentBody.Add('enabled', $Enabled.IsPresent)
        }
        if ($PSBoundParameters.ContainsKey('List')) {
            if ($List.Count -eq 0) {
                $ContentBody.Add('list', @())
            }
            else {
                $ContentBody.Add('list', @($List))
            }
        }
        $InvokeSplat.Add('ContentBody', $ContentBody)
        if ($PSCmdlet.ShouldProcess('mail_settings/address_whitelist')) {
            try {
                Invoke-SendGrid @InvokeSplat
            }
            catch {
                Write-Error -Exception (ConvertTo-SendGridCommandException -Message ('Failed to update SendGrid address whitelist settings. {0}' -f $_.Exception.Message) -ErrorRecord $_) -ErrorAction Stop
            }
        }
    }
}