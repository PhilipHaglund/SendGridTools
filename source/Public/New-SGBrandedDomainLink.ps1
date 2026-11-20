function New-SGBrandedDomainLink {
    <#
    .SYNOPSIS
        Adds a new Branded Domain Link within the current SendGrid instance.

    .DESCRIPTION
        New-SGBrandedDomainLink adds a new Branded Domain Link within the current SendGrid instance. Email link branding (formerly "Link Whitelabel")
        allows all of the click-tracked links, opens, and images in your emails to be served from your domain rather than sendgrid.net. Spam filters
        and recipient servers look at the links within emails to determine whether the email looks trustworthy. They use the reputation of the root
        domain to determine whether the links can be trusted.

    .PARAMETER Domain
        Specifies a domain. Do not provide a full domain including a subdomain here, for instance email.example.com.

    .PARAMETER SendGridSubdomain
        Specifies an optional subdomain to be used. Use when you don't want SendGrid to automatically generate a subdomain like url1234.

    .PARAMETER Default
        Specifies that the new branded domain link becomes the default one for the SendGrid instance. The current default is replaced, so a confirmation prompt is shown. Use -Force to skip that prompt.

    .PARAMETER OnBehalfOf
        Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.

    .PARAMETER Force
        Specifies that the question before -Default replaces the current default branded link is not asked, so a script without a console can set a default branded link. -Force does not change -WhatIf or -Confirm.

    .EXAMPLE
        PS C:\> New-SGBrandedDomainLink -Domain 'example.com' -SendGridSubDomain 'link'

        Adds a new branded link 'link.example.com', which is the subdomain 'link' on the domain 'example.com'.

    .EXAMPLE
        PS C:\> New-SGBrandedDomainLink -Domain 'sub.example.com'

        Adds a new branded domain link for the domain 'sub.example.com', which itself contains a subdomain, and lets SendGrid generate the link subdomain. Passing a domain that includes a subdomain is not recommended, as the Domain parameter help describes.

    .EXAMPLE
        PS C:\> New-SGBrandedDomainLink -Domain 'example.com' -SendGridSubDomain 'link' -Default -Force

        Adds the branded link 'link.example.com' and makes it the default branded link without asking first, for example in a script that runs without a console. -WhatIf still shows the link without adding it.

    .NOTES
        To use this function, you must be connected to a SendGrid instance. Use the Connect-SendGrid function to establish a connection.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseLiteralInitializerForHashtable', '', Justification = '[hashtable]::new() creates a case-sensitive table while @{} is case-insensitive; the two are not interchangeable in general, so changing the initializer could change behaviour and is deferred.')]
    [CmdletBinding(SupportsShouldProcess)]
    param (

        # Specifies a domain. Do not provide a full domain including a subdomain here, for instance email.example.com.
        [Parameter(
            Mandatory,
            Position = 0
        )]
        [ValidatePattern('^([a-zA-Z0-9]([-a-zA-Z0-9]{0,61}[a-zA-Z0-9])?\.)?([a-zA-Z0-9]{1,2}([-a-zA-Z0-9]{0,252}[a-zA-Z0-9])?)\.([a-zA-Z]{2,63})$')]
        [string]$Domain,

        # Specifies an optional subdomain to be used. Use when you don't want SendGrid to automatically generate a subdomain like url1234.
        [Parameter(
            Position = 1
        )]
        [string]$SendGridSubDomain,

        # Specifies if the domain should be the default one for the SendGrid instance.
        [Parameter()]
        [switch]$Default,

        # Specifies a On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
        [Parameter()]
        [string]$OnBehalfOf,

        # Specifies that the question before -Default replaces the current default branded link is not asked. -WhatIf and -Confirm work as without it.
        [Parameter()]
        [switch]$Force
    )

    begin {
        [hashtable]$ContentBody = [hashtable]::new()

        $ContentBody.Add('domain', $Domain)
        if ($PSBoundParameters.ContainsKey('SendGridSubdomain')) {
            Write-Verbose -Message ("SendGrid will not generate a custom subdomain. Domain to be used: $Domain")
            $ContentBody.Add('subdomain', $SendGridSubDomain)
            $ProcessMessage = "$SendGridSubDomain.$Domain"

        }
        else {
            Write-Verbose -Message ("SendGrid will automatically generate a custom branded subdomain for you. Example:url1234.$Domain")
            $ProcessMessage = $Domain
        }
        $InvokeSplat = @{
            Method        = 'Post'
            Namespace     = 'whitelabel/links'
            ErrorAction   = 'Stop'
            CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
        }
        if ($PSBoundParameters.OnBehalfOf) {
            $InvokeSplat.Add('OnBehalfOf', $OnBehalfOf)
        }
    }
    process {
        if ($PSCmdlet.ShouldProcess($ProcessMessage)) {
            if ($Default.IsPresent -and ($Force -or (Confirm-SendGridContinue -Cmdlet $PSCmdlet -Query $Domain -Caption 'Setting this domain as the default domain will remove the current default domain. Do you want to continue?'))) {
                $ContentBody.Add('default', $true)
            }
            try {
                $InvokeSplat.Add('ContentBody', $ContentBody)
                Invoke-SendGrid @InvokeSplat
            }
            catch {
                Write-Error ('Failed to create SendGrid Branded Domain Link. {0}' -f $_.Exception.Message) -ErrorAction Stop
            }
        }
    }
}