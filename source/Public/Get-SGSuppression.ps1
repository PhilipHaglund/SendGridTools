function Get-SGSuppression {
    <#
    .SYNOPSIS
        Retrieves all suppressions or suppressions for a specific email address.

    .DESCRIPTION
        The Get-SGSuppression function retrieves all suppressions or suppressions for a specific email address from SendGrid.
        
    .PARAMETER EmailAddress
        Specifies the email address to search suppression groups for.

    .PARAMETER OnBehalfOf
        Specifies a On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.

    .EXAMPLE
        PS C:\> Get-SGSuppression
        This command retrieves all suppressions.

    .EXAMPLE
        PS C:\> Get-SGSuppression -EmailAddress 'test@example.com'
        This command retrieves all suppressions for the email address 'test@example.com'.
    #>
    [CmdletBinding()]
    param (
        # Specifies the email address to search suppression groups for.
        [Parameter()]
        [MailAddress]$EmailAddress,

        # Specifies a On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
        [Parameter()]
        [string]$OnBehalfOf
    )
    process {
        $InvokeSplat = @{
            Method        = 'Get'
            Namespace     = 'asm/suppressions'
            ErrorAction   = 'Stop'
            CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
        }

        if ($PSBoundParameters.ContainsKey('EmailAddress')) {
            #TODO: SHOULD EXPAND THE PSOBJECT "SUPRESSIONS"
            $InvokeSplat.Namespace += '/{0}' -f $EmailAddress.Address
        }

        if ($PSBoundParameters.ContainsKey('OnBehalfOf')) {
            $InvokeSplat.OnBehalfOf = $OnBehalfOf
        }

        try {
            Invoke-SendGrid @InvokeSplat
        }
        catch {
            Write-Error ('Failed to retrieve suppressions. {0}' -f $_.Exception.Message) -ErrorAction Stop
        }
    }
}