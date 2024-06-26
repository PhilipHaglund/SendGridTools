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
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)]
        [string]$Domain,

        [Parameter(Mandatory)]
        [string]$Subdomain,

        [switch]$DisableAutomaticSecurity,

        [string]$CustomDkimSelector,

        [switch]$CustomSPF,

        [switch]$Force
    )

    # Add the new authenticated domain
    New-SGAuthenticatedDomain -Domain $Domain -Subdomain $Subdomain -DisableAutomaticSecurity:$DisableAutomaticSecurity.IsPresent -CustomDkimSelector $CustomDkimSelector -CustomSPF:$CustomSPF.IsPresent

    # Add the new branded domain link
    New-SGBrandedDomainLink -Domain $Domain -Subdomain $Subdomain -Force:$Force.IsPresent
}