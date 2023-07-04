function Remove-SGBrandedDomainLink {
    <#
    .SYNOPSIS
        Removes a Branded Domain Link from the current Sendgrid instance.

    .DESCRIPTION
        Remove-SGBrandedDomainLink removes a branded domain link from the current SendGrid instance. Branded Domain Links allows all of the click-tracked links, 
        opens, and images in your emails to be served from your domain rather than sendgrid.net. It improves the trustworthiness of your emails. You must provide 
        the unique identifier of the branded link to be removed. Please note that you might need to remove the DNS records manually after removing the branded link.

    .PARAMETER UniqueId
        Specifies the unique identifier for the branded link to remove.

    .EXAMPLE
        PS C:\> Remove-SGBrandedDomainLink -UniqueId '1234567'

        Removes the branded domain link with the unique identifier '1234567'.

    .EXAMPLE
        PS C:\> Get-SGBrandedDomainLink | Where-Object { $_.Domain -eq 'example.com' } | Remove-SGBrandedDomainLink

        Removes the branded domain link 'example.com' using its unique identifier obtained from the Get-SGBrandedDomainLink cmdlet.

    .NOTES
        To use this function, you must be connected to a SendGrid instance. Use the Connect-SendGrid function to establish a connection.
    #>
    [CmdletBinding(
        SupportsShouldProcess,
        ConfirmImpact = 'High')]
    param (

        # Specifies a the UniqueId for the branded link to remove.
        [Parameter(
            Mandatory,
            ValueFromPipelineByPropertyName
            )]
        [string]$UniqueId
    )
    process {
        $SGBrandedDomainLink = Get-SGBrandedDomainLink -UniqueId $UniqueId -ErrorAction Sop
        Write-Verbose -Message ("Don't forget to remove DNS records:") -Verbose
        $SGBrandedDomainLink

        if ($PSCmdlet.ShouldProcess(('{0}.{1}' -f $SGBrandedDomainLink.Subdomain, $SGBrandedDomainLink.Domain))) {
            try {
                Invoke-SendGrid -Method 'Delete' -Namespace "whitelabel/links/$UniqueId" -ErrorAction Stop
            }
            catch {
                Write-Error ('Failed to remove SendGrid Branded Domain Link. {0}' -f $_.Exception.Message) -ErrorAction Stop
            }
        }
    }
}