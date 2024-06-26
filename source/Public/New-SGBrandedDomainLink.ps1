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

    .PARAMETER Subdomain
        Specifies a subdomain to be used, in most cases it's "link".

    .PARAMETER Force
        Specifies if the current domain (parameter Domain) should be created despite it contains a subdomain (email.example.com).

    .EXAMPLE
        PS C:\> New-SGBrandedDomainLink -Domain 'example.com' -Subdomain 'link'

        Adds a new branded domain link 'sub.example.com' with the subdomain 'link' using the specified API key.

    .EXAMPLE
        PS C:\> New-SGBrandedDomainLink -Domain 'sub.example.com' -Force

        Adds a new branded domain link 'url123.sub.example.com' and forces the creation despite the domain containing a subdomain.

    .NOTES
        To use this function, you must be connected to a SendGrid instance. Use the Connect-SendGrid function to establish a connection.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (

        # Specifies a domain. Do not provide a full domain including a subdomain here, for instance email.example.com.
        [Parameter(
            Mandatory,
            Position = 0
        )]
        [ValidatePattern('^([a-zA-Z0-9]([-a-zA-Z0-9]{0,61}[a-zA-Z0-9])?\.)?([a-zA-Z0-9]{1,2}([-a-zA-Z0-9]{0,252}[a-zA-Z0-9])?)\.([a-zA-Z]{2,63})$')]
        [string]$Domain,

        # Specifies a subdomain to be used, in most cases it's "link".
        [Parameter(
            Position = 1
        )]
        [string]$Subdomain = 'link',

        # Specifies a On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
        [Parameter()]
        [string]$OnBehalfOf,

        # Specifies if the current domain (parameter Domain) should be created despite it contains a subdomain (email.example.com).
        [Parameter()]
        [switch]$Force
    )
    
    begin {
        [hashtable]$ContentBody = [hashtable]::new()
        $ContentBody.Add('domain', $Domain)
        if ($Domain -match '.*\..*\..*' -and -not $Force.IsPresent) {
            Write-Warning -Message "It's not recommended to use a double custom subdomain. SendGrid will automatically generate a subdomain for you. If you know what you are doing, re-run with -Force. Terminating function..."
            break
        }
        elseif ($Force.IsPresent) {
            Write-Verbose -Message ('SendGrid will automatically generate a custom subdomain for you.') -Verbose
            $ProcessMessage = $Domain
        }
        else {
            $ContentBody.Add('subdomain', $Subdomain)
            $ProcessMessage = "$Subdomain.$Domain"
        }
        $ContentBody.Add('default', $false)
    }    
    process {
        $InvokeSplat = @{
            Method        = 'Post'
            Namespace     = 'whitelabel/links'
            ErrorAction   = 'Stop'
            CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
        }
        if ($PSBoundParameters.OnBehalfOf) {
            $InvokeSplat.Add('OnBehalfOf', $OnBehalfOf)
        }
        $InvokeSplat.Add('ContentBody', $ContentBody)
        if ($PSCmdlet.ShouldProcess($ProcessMessage)) {
            try {
                Invoke-SendGrid @InvokeSplat
            }
            catch {
                Write-Error ('Failed to create SendGrid Branded Domain Link. {0}' -f $_.Exception.Message) -ErrorAction Stop
            }
        }
    }
}