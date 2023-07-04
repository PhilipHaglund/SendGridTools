﻿function Confirm-SGBrandedDomainLink {
    <#
    .SYNOPSIS
        Validates the branded domain links within the current SendGrid instance.
        
    .DESCRIPTION
        Confirm-SGBrandedDomainLink is used to validate the branded domain links within the current SendGrid instance.
        An authenticated domain allows you to remove the "via”" or "sent on behalf of" message that your recipients see when they read your emails.
        Authenticating a domain allows you to replace sendgrid.net with your personal sending domain.
        You will be required to create a subdomain so that SendGrid can generate the DNS records which you must give to your host provider.

        This function should be executed after the external DNS records have been applied.

    .PARAMETER UniqueId
        Specifies the unique ID of the branded link to validate. This parameter is mandatory.

    .EXAMPLE
        PS C:\> Confirm-SGBrandedDomainLink -UniqueId '1234567'
        
        This command validates the branded domain link with the unique ID '1234567' in the current SendGrid instance.
    
    .NOTES
        This function requires an active SendGrid instance to work properly. Make sure to check the validity of the UniqueId parameter.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (

        # Specifies the unique ID of the branded link to validate. This parameter is mandatory.
        [Parameter(
            Mandatory,
            ValueFromPipelineByPropertyName
        )]
        [string]$UniqueId
    )   
    process {
        $SGBrandedDomainLink = Get-SGBrandedDomainLink -UniqueId $UniqueId -Credential $Credential
        $SGBrandedDomainLink

        if ($PSCmdlet.ShouldProcess(('{0}.{1}' -f $SGBrandedDomainLink.Subdomain, $SGBrandedDomainLink.Domain))) {

            if ($SGBrandedDomainLink.Valid -eq $true) {
                Write-Verbose -Message ('Branded Link Domain already validated!') -Verbose
            }
            else {
                try {
                    Invoke-SendGrid -Method 'Post' -Namespace "whitelabel/links/$UniqueId/validate" -ErrorAction Stop
                }
                catch {
                    Write-Error ('Failed to validate SendGrid Branded Domain Link. {0}' -f $_.Exception.Message) -ErrorAction Stop
                }
            }
        }
    }
}