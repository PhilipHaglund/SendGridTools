function New-SGAuthenticatedDomain {
    <#
    .SYNOPSIS
        Adds a new Authenticated Domain to the current SendGrid instance.

    .DESCRIPTION
        New-SGAuthenticatedDomain allows you to add a new Authenticated Domain to the current SendGrid instance. An authenticated domain allows 
        you to remove the "via" or "sent on behalf of" message that your recipients see when they read your emails. Authenticating a domain allows 
        you to replace sendgrid.net with your personal sending domain. You will be required to create a subdomain so that SendGrid can generate 
        the DNS records which you must give to your host provider.

        This function uses a dynamic parameter, `CustomSPF`, which is available only when `DisableAutomaticSecurity` switch is set. The "CustomSPF"
        parameter allows to specify whether to use a custom SPF or allow SendGrid to manage your SPF. This option is only available to authenticated 
        domains set up for manual security.

    .PARAMETER Domain
        Specifies a domain. It's recommended to provide a full domain including a subdomain, for instance email.example.com.

    .PARAMETER SendGridSubdomain
        Specifies an optional subdomain to be used. Use when you don't want SendGrid to automatically generate a subdomain like em1234.

    .PARAMETER SubUser
        Specifies a subuser to be used, this is optional.
    
    .PARAMETER DisableAutomaticSecurity
        Specify whether to not allow SendGrid to manage your SPF records, DKIM keys, and DKIM key rotation. Default is that SendGrid manages 
        those records.

    .PARAMETER CustomDkimSelector
        Add a custom DKIM selector. Accepts three letters or numbers.

    .PARAMETER Force
        Specifies if the current domain (parameter Domain) should be created despite it contains a subdomain (email.example.com).

    .PARAMETER CustomSPF
        This is a dynamic parameter and only becomes available when the 'DisableAutomaticSecurity' switch is set.
        Specifies whether to use a custom SPF or allow SendGrid to manage your SPF. This option is only available to authenticated domains set up for manual security.

    .PARAMETER OnBehalfOf
        Specifies a On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.

    .PARAMETER Default
        Specifies if the domain should be the default one for the SendGrid instance.

    .EXAMPLE
        PS C:\> New-SGAuthenticatedDomain -Domain 'example.com' -Subdomain 'email'

        Adds a new authenticated domain 'example.com' with the subdomain 'email' using the specified API key.

    .EXAMPLE
        PS C:\> New-SGAuthenticatedDomain -Domain 'example.com' -Subdomain 'email' -DisableAutomaticSecurity -CustomDkimSelector 'exm'

        Adds a new authenticated domain 'example.com' with the subdomain 'email', disables automatic security, and uses a custom DKIM selector 'exm' with the specified API key.

    .EXAMPLE
        PS C:\> New-SGAuthenticatedDomain -Domain 'sub.example.com' -Subdomain 'email' -Force

        Adds a new authenticated domain 'email.sub.example.com' with the subdomain 'email' and forces the creation despite the domain containing a subdomain.

    .EXAMPLE
        PS C:\> New-SGAuthenticatedDomain -Domain 'example.com' -Subdomain 'email' -DisableAutomaticSecurity -CustomSPF

        Adds a new authenticated domain 'example.com' with the subdomain 'email', disables automatic security, and uses a custom SPF record with the specified API key.

    .NOTES
        To use this function, you must be connected to a SendGrid instance. Use the Connect-SendGrid function to establish a connection.
    #>
    [CmdletBinding(
        SupportsShouldProcess
    )]
    param (

        # Specifies a domain. It's recommended to provide a full domain including a subdomain, for instance email.example.com.
        [Parameter(
            Mandatory,
            Position = 0
        )]
        [ValidatePattern('^([a-zA-Z0-9]([-a-zA-Z0-9]{0,61}[a-zA-Z0-9])?\.)?([a-zA-Z0-9]{1,2}([-a-zA-Z0-9]{0,252}[a-zA-Z0-9])?)\.([a-zA-Z]{2,63})$')]
        [string]$Domain,

        # Specifies an optional subdomain to be used. Use when you don't want SendGrid to automatically generate a subdomain like em1234.
        [Parameter(
            Position = 1
        )]
        [string]$SendGridSubdomain,

        # The username associated with this domain. This is optional.
        [Parameter(
            Position = 2
        )]
        [Alias('SubUser')]
        [string]$Username,

        # Specify whether to not allow SendGrid to manage your SPF records, DKIM keys, and DKIM key rotation. Default is that SendGrid manages those records.
        [Parameter(
            Position = 3
        )]
        [switch]$DisableAutomaticSecurity,

        # Add a custom DKIM selector. Accepts three letters or numbers.
        [Parameter(
            Position = 4
        )]
        [ValidatePattern('^[a-zA-Z\d]{3}$')]
        $CustomDkimSelector,

        # Specifies if the domain should be the default one for the SendGrid instance.
        [Parameter()]
        [switch]$Default,

        # Specifies a On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
        [Parameter()]
        [string]$OnBehalfOf
    )
    DynamicParam {
        $ParamDictionary = [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()
        $IPAddressParamAttribute = [System.Management.Automation.ParameterAttribute]::new()
        $IPAddressParamAttribute.Position = 2
        $IPAddressParamAttribute.ParameterSetName = $PSCmdlet.ParameterSetName

        # Add the parameter attributes to an attribute collection
        $IPAddressAttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
        $IPAddressAttributeCollection.Add($IPAddressParamAttribute)

        # Add ValidateSet to the parameter
        $script:IPAddresses = Get-SGIPAddress
        $StatusValidateSet = [System.Management.Automation.ValidateSetAttribute]::new([string[]]$IPAddresses.Ip)
        $IPAddressAttributeCollection.Add($StatusValidateSet)

        # Create the actual IPAddress parameter
        $IPAddressParam = [System.Management.Automation.RuntimeDefinedParameter]::new('IPAddress', [string[]], $IPAddressAttributeCollection)

        # Push the parameter(s) into a parameter dictionary
        $ParamDictionary.Add('IPAddress', $IPAddressParam)
        
        if ($DisableAutomaticSecurity) {
            # Specify whether to use a custom SPF or allow SendGrid to manage your SPF. This option is only available to authenticated domains set up for manual security.
            $CustomSPFParamAttribute = [System.Management.Automation.ParameterAttribute]::new()
            $CustomSPFParamAttribute.Position = 5

            # Add the parameter attributes to an attribute collection
            $AttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
            $AttributeCollection.Add($CustomSPFParamAttribute)

            # Create the actual CustomSPF parameter
            $CustomSPFParam = [System.Management.Automation.RuntimeDefinedParameter]::new('CustomSPF', [switch], $AttributeCollection)

            # Push the parameter(s) into a parameter dictionary            
            $ParamDictionary.Add('CustomSPF', $CustomSPFParam)
        }

        # Return the dictionary
        return $ParamDictionary
    }
    begin {
        [hashtable]$ContentBody = [hashtable]::new()

        $ContentBody.Add('domain', $Domain)

        if ($PSBoundParameters.ContainsKey('SendGridSubdomain')) {
            Write-Verbose -Message ("SendGrid will not generate a custom subdomain. Domain to be used: $Domain") -Verbose
            $ContentBody.Add('subdomain', $Subdomain)
            $ProcessMessage = "$Subdomain.$Domain"
            
        }
        else {
            Write-Verbose -Message ("SendGrid will automatically generate a custom subdomain for you. Example:em1234.$Domain") -Verbose
            $ProcessMessage = $Domain
        }

        if ($PSBoundParameters.ContainsKey('CustomDkimSelector')) {
            $ContentBody.Add('custom_dkim_selector', $CustomDkimSelector)
        }
        if ($PSBoundParameters.ContainsKey('SubUser')) {
            $ContentBody.Add('username', $SubUser)
        }
        if ($PSBoundParameters.ContainsKey('DisableAutomaticSecurity')) {
            $ContentBody.Add('automatic_security', $false)
        }
        else {
            $ContentBody.Add('automatic_security', $true)
        }
        if ($PSBoundParameters.ContainsKey('CustomSPF')) {
            $ContentBody.Add('custom_spf', $true)
        }
        if ($PSBoundParameters.ContainsKey('Username')) {
            $ContentBody.Add('username', $Username)
        }
        if ($PSBoundParameters.ContainsKey('IPAddress')) {
            $ContentBody.Add('ips', @($IPAddress))
        }
        $InvokeSplat = @{
            Method        = 'Post'
            Namespace     = 'whitelabel/domains'
            ErrorAction   = 'Stop'
            CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
        }
        if ($PSBoundParameters.OnBehalfOf) {
            $InvokeSplat.Add('OnBehalfOf', $OnBehalfOf)
        }
    }    
    process {
        if ($PSCmdlet.ShouldProcess($ProcessMessage)) {
            if ($PSBoundParameters.ContainsKey('Default') -and $PSCmdlet.ShouldContinue($Domain,'Setting this domain as the default domain will remove the current default domain. Do you want to continue?')) {
                $ContentBody.Add('default', $true)
            }
            try {
                $InvokeSplat.Add('ContentBody', $ContentBody)
                Invoke-SendGrid @InvokeSplat
            }
            catch {
                Write-Error ('Failed to add SendGrid Authenticated Domain. {0}' -f $_.Exception.Message) -ErrorAction Stop
            }
        }
    }
}