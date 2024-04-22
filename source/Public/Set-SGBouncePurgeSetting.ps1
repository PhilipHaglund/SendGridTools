function Set-SGBouncePurgeSetting {
    <#
    .SYNOPSIS
        Updates the bounce purge mail settings on SendGrid.
    .DESCRIPTION
        Set-SGBouncePurgeSetting updates the bounce purge mail settings on SendGrid.
    .PARAMETER Enabled
        Specifies whether the bounce purge mail setting is enabled.
    .PARAMETER SoftBounces
        The number of days after which SendGrid will purge all contacts from your soft bounces suppression lists.
    .PARAMETER HardBounces
        The number of days after which SendGrid will purge all contacts from your hard bounces suppression lists.
    .PARAMETER OnBehalfOf
        Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
    .EXAMPLE
        PS C:\> Set-SGBouncePurgeSetting -Enabled $true -SoftBounces 5 -HardBounces 10
        This command updates the bounce purge mail settings on SendGrid to enable the setting and set the purge days for soft and hard bounces.
    #>
    [CmdletBinding()]
    param (
        # Specifies whether the bounce purge mail setting is enabled.
        [Parameter()]
        [switch]$Enabled,
        
        # The number of days after which SendGrid will purge all contacts from your soft bounces suppression lists.
        [Parameter()]
        [int]$SoftBounces,

        # The number of days after which SendGrid will purge all contacts from your hard bounces suppression lists.
        [Parameter()]
        [int]$HardBounces,

        # Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
        [Parameter()]
        [string]$OnBehalfOf
    )
    process {
        [hashtable]$ContentBody = @{}
        $InvokeSplat = @{
            Method        = 'Patch'
            Namespace     = 'mail_settings/bounce_purge'
            ErrorAction   = 'Stop'
            CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
        }
        if ($PSBoundParameters.OnBehalfOf) {
            $InvokeSplat.Add('OnBehalfOf', $OnBehalfOf)
        }
        
        if ($PSBoundParameters.ContainsKey('Enabled')) {
            $ContentBody.Add('enabled', $Enabled.IsPresent)
        }
        if ($PSBoundParameters.ContainsKey('SoftBounces')) {
            $ContentBody.Add('soft_bounces', $SoftBounces)
        }
        if ($PSBoundParameters.ContainsKey('HardBounces')) {
            $ContentBody.Add('hard_bounces', $HardBounces)
        }
        
        $InvokeSplat.Add('ContentBody', $ContentBody)
        
        try {
            Invoke-SendGrid @InvokeSplat
        }
        catch {
            Write-Error ('Failed to update SendGrid bounce purge settings. {0}' -f $_.Exception.Message) -ErrorAction Stop
        }
    }
}