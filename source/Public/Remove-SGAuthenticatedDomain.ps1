function Remove-SGAuthenticatedDomain {
    <#
    .SYNOPSIS
        Removes an Authenticated Domain within the current Sendgrid instance.

    .DESCRIPTION
        Remove-SGAuthenticatedDomain removes an authenticated domain from the current SendGrid instance. An authenticated domain allows you 
        to remove the "via" or "sent on behalf of" message that your recipients see when they read your emails. Authenticating a domain allows 
        you to replace sendgrid.net with your personal sending domain. You must provide the unique identifier of the domain to be removed. 
        Please note that you might need to remove the DNS records manually after removing the domain.

    .PARAMETER UniqueId
        Specifies the unique identifier for the authenticated domain to remove.

    .EXAMPLE
        PS C:\> Remove-SGAuthenticatedDomain -UniqueId '1234567'

        Removes the authenticated domain with the unique identifier '1234567'.

    .EXAMPLE
        PS C:\> Get-SGAuthenticatedDomain | Where-Object { $_.Domain -eq 'example.com' } | Remove-SGAuthenticatedDomain

        Removes the authenticated domain 'example.com' using its unique identifier obtained from the Get-SGAuthenticatedDomain cmdlet.

    .NOTES
        To use this function, you must be connected to a SendGrid instance. Use the Connect-SendGrid function to establish a connection.
    #>
    [CmdletBinding(
        SupportsShouldProcess,
        ConfirmImpact = 'High')]
    param (

        # Specifies the unique identifier for the authenticated domain to remove.
        [Parameter(
            Mandatory,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            Position = 0
        )]
        [Alias('Id')]
        [string[]]$UniqueId,

        # Specifies a On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
        [Parameter()]
        [string]$OnBehalfOf
    )   
    process {
        foreach ($Id in $UniqueId) { 
            $InvokeSplat = @{
                Method        = 'Delete'
                Namespace     = "whitelabel/domains/$Id"
                ErrorAction   = 'Stop'
                CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
            }
            $GetSplat = @{
                UniqueId    = $Id
                ErrorAction = 'Stop'
            }
            if ($PSBoundParameters.OnBehalfOf) {
                $InvokeSplat.Add('OnBehalfOf', $OnBehalfOf)
                $GetSplat.Add('OnBehalfOf', $OnBehalfOf)
            }
            $SGAuthenticatedDomain = Get-SGAuthenticatedDomain @GetSplat -ShowDNS
            
            Write-Verbose -Message ("Don't forget to remove DNS records.") -Verbose
            $SGAuthenticatedDomain

            if ($PSCmdlet.ShouldProcess(('{0}.{1}' -f $SGAuthenticatedDomain.Subdomain, $SGAuthenticatedDomain.Domain))) {
                try {
                    Invoke-SendGrid @InvokeSplat
                }
                catch {
                    Write-Error ('Failed to remove SendGrid Authenticated Domain. {0}' -f $_.Exception.Message) -ErrorAction Stop
                }
            }
        }
    }
}