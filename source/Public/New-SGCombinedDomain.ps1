function New-SGCombinedDomain {
    <#
    .SYNOPSIS
        Adds a new Authenticated Domain and a new Branded Domain Link within the current SendGrid instance.

    .DESCRIPTION
        New-SGCombinedDomain adds both an authenticated domain and a branded domain link within the current SendGrid instance. 
        This allows for the setup of domain authentication and email link branding in a single step, enhancing the trustworthiness 
        and deliverability of your emails.

    .PARAMETER Domain
        Specifies the domain for both the authenticated domain and the branded domain link. 
        For the authenticated domain, do not provide a full domain including a subdomain here, for instance, email.example.com.

    .PARAMETER Subdomain
        Specifies a subdomain to be used for both the authenticated domain and the branded domain link. 
        In most cases, it's "email" for authenticated domains and "link" for branded domain links.

    .PARAMETER DisableAutomaticSecurity
        Specifies if automatic security features (like DKIM and SPF records) should be disabled for the authenticated domain.

    .PARAMETER CustomDkimSelector
        Specifies a custom DKIM selector to be used for the authenticated domain.

    .PARAMETER CustomSPF
        Indicates whether a custom SPF record should be used for the authenticated domain.
    .PARAMETER Force
        Specifies if the current domain should be created despite it contains a subdomain (email.example.com) for the branded domain link.
    .EXAMPLE
        PS C:\> New-SGCombinedDomain -Domain 'example.com' -Subdomain 'email' -DisableAutomaticSecurity -CustomDkimSelector 'exm'
        Adds a new authenticated domain 'example.com' with the subdomain 'email', disables automatic security, and uses a custom DKIM selector 'exm'. 
        Also adds a new branded domain link with the same domain and subdomain.
    .EXAMPLE
        PS C:\> New-SGCombinedDomain -Domain 'example.com' -Subdomain 'link' -Force
        Adds a new authenticated domain 'example.com' with the subdomain 'link' and forces the creation despite the domain containing a subdomain. 
        Also adds a new branded domain link with the same domain and subdomain.
    .NOTES
        To use this function, you must be connected to a SendGrid instance. Use the Connect-SendGrid function to establish a connection.
    #>
    [CmdletBinding(
        SupportsShouldProcess
    )]
    param (
        [Parameter(
            Mandatory,
            Position = 0
        )]
        [string]$Domain,

        # Specifies an optional subdomain to be used. Use when you don't want SendGrid to automatically generate a subdomain like url1234 and em1234.
        [Parameter(
            Position = 1
        )]
        [string]$SendGridSubDomain,

        # Specify whether to not allow SendGrid to manage your SPF records, DKIM keys, and DKIM key rotation. Default is that SendGrid manages those records.
        [Parameter(
            Position = 2
        )]
        [switch]$DisableAutomaticSecurity,

        # Add a custom DKIM selector. Accepts three letters or numbers.
        [Parameter(
            Position = 3
        )]
        [ValidatePattern('^[a-zA-Z\d]{3}$')]
        [string]$CustomDkimSelector,

        # Specifies whether to use a custom SPF or allow SendGrid to manage your SPF. This option is only available to authenticated domains set up for manual security (DisableAutomaticSecurity).
        [switch]$CustomSPF,

        # Specifies a On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
        [Parameter()]
        [string]$OnBehalfOf
    )

    process {
        [hashtable]$AuthDomainSplat = @{
            Domain = $Domain
            SendGridSubDomain = $Subdomain
            DisableAutomaticSecurity = $DisableAutomaticSecurity.IsPresent
            CustomDkimSelector = $CustomDkimSelector
            CustomSPF = $CustomSPF.IsPresent
            OnBehalfOf = $OnBehalfOf
            ErrorAction = 'Stop'
        }
        [hashtable]$BrandedDomainSplat = @{
            Domain = $Domain
            SendGridSubDomain = $Subdomain
            ErrorAction = 'Stop'
        }
        # Remove empty Hashtables
        Remove-EmptyHashtable -Hashtable $AuthDomainSplat
        Remove-EmptyHashtable -Hashtable $BrandedDomainSplat
        if ($AuthDomainSplat['CustomSPF'] -eq $false -and -not $DisableAutomaticSecurity.IsPresent) {
            $AuthDomainSplat.Remove('CustomSPF')
            $AuthDomainSplat.Remove('DisableAutomaticSecurity')
        }
        if ($CustomSPF.IsPresent -and $DisableAutomaticSecurity.IsPresent -eq $false) {
            throw 'The CustomSPF parameter can only be used with the DisableAutomaticSecurity parameter.'
        }
        if ($PSCmdlet.ShouldProcess($Domain)) {
            # Add the new authenticated domain
            New-SGAuthenticatedDomain @AuthDomainSplat
            
            # Add the new branded domain link
            New-SGBrandedDomainLink @BrandedDomainSplat
        }
    }
}