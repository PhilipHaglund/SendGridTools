function Get-SGEnforcedTls {
    <#
    .SYNOPSIS
        Retrieves the Enforced TLS settings on SendGrid.
    .DESCRIPTION
        Get-SGEnforcedTls retrieves the Enforced TLS settings on SendGrid. Enforced TLS controls whether recipients must support TLS to receive your mail (RequireTls), whether their certificate must be valid (RequireValidCert), and the minimum TLS version that is accepted (Version).

    .PARAMETER OnBehalfOf
        Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
    .EXAMPLE
        PS C:\> Get-SGEnforcedTls
        This command retrieves the Enforced TLS settings on SendGrid.
    .EXAMPLE
        PS C:\> Get-SGEnforcedTls -OnBehalfOf 'subuser-placeholder'
        This command retrieves the Enforced TLS settings of a subuser.
    .NOTES
        To use this function, you must be connected to a SendGrid instance. Use the Connect-SendGrid function to establish a connection.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Tls is an acronym, not a plural noun, and the name Get-SGEnforcedTls is the specified public surface, so renaming it is not possible.')]
    [CmdletBinding()]
    param (
        # Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
        [Parameter()]
        [string]$OnBehalfOf
    )
    process {
        $InvokeSplat = @{
            Method        = 'Get'
            Namespace     = 'user/settings/enforced_tls'
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
            Write-Error ('Failed to retrieve SendGrid Enforced TLS settings. {0}' -f $_.Exception.Message) -ErrorAction Stop
        }
    }
}
