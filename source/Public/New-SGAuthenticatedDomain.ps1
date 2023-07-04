function New-SGAuthenticatedDomain {
    <#
    .SYNOPSIS
        Adds a new Authenticated Domain to the current Sendgrid instance.

    .DESCRIPTION
        New-SGAuthenticatedDomain allows you to add a new Authenticated Domain to the current SendGrid instance. An authenticated domain allows 
        you to remove the "via" or "sent on behalf of" message that your recipients see when they read your emails. Authenticating a domain allows 
        you to replace sendgrid.net with your personal sending domain. You will be required to create a subdomain so that SendGrid can generate 
        the DNS records which you must give to your host provider.

        This function uses a dynamic parameter, `CustomSPF`, which is available only when `DisableAutomaticSecurity` switch is set. The "CustomSPF"
        parameter allows to specify whether to use a custom SPF or allow SendGrid to manage your SPF. This option is only available to authenticated 
        domains set up for manual security.

    .PARAMETER Domain
        Specifies a domain. It's not recommended to provide a full domain including a subdomain, for instance email.example.com.

    .PARAMETER Subdomain
        Specifies a subdomain to be used, in most cases it's "email".

    .PARAMETER DisableAutomaticSecurity
        Specify whether to not allow SendGrid to manage your SPF records, DKIM keys, and DKIM key rotation. Default is that SendGrid manages 
        those records.

    .PARAMETER CustomDkimSelector
        Add a custom DKIM selector. Accepts three letters or numbers. Defaults to 'sg'.

    .PARAMETER Force
        Specifies if the current domain (parameter Domain) should be created despite it contains a subdomain (email.example.com).

    .PARAMETER CustomSPF
        This is a dynamic parameter and only becomes available when the 'DisableAutomaticSecurity' switch is set.
        Specifies whether to use a custom SPF or allow SendGrid to manage your SPF. This option is only available to authenticated domains set up for manual security.

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
    [CmdletBinding(SupportsShouldProcess)]
    param (

        # Specifies a domain. It's not recommended to provide a full domain including a subdomain, for instance email.example.com.
        [Parameter(Mandatory)]
        [ValidatePattern('^([a-zA-Z0-9]([-a-zA-Z0-9]{0,61}[a-zA-Z0-9])?\.)?([a-zA-Z0-9]{1,2}([-a-zA-Z0-9]{0,252}[a-zA-Z0-9])?)\.([a-zA-Z]{2,63})$')]
        [string]$Domain,

        # Specifies a subdomain to be used, in most cases it's "email".
        [Parameter()]
        [string]$Subdomain,

        # Specify whether to not allow SendGrid to manage your SPF records, DKIM keys, and DKIM key rotation. Default is that SendGrid manages those records.
        [Parameter()]
        [switch]$DisableAutomaticSecurity,

        # Add a custom DKIM selector. Accepts three letters or numbers. Defaults to 'sg'.
        [Parameter()]
        [ValidatePattern('^[a-zA-Z\d]{3}$')]
        $CustomDkimSelector = 'sg',

        # Specifies if the current domain (parameter Domain) should be created despite it contains a subdomain (email.example.com).
        [Parameter()]
        [switch]$Force
    )
    DynamicParam {
        if ($DisableAutomaticSecurity) {
            # Specify whether to use a custom SPF or allow SendGrid to manage your SPF. This option is only available to authenticated domains set up for manual security.
            $CustomSPFParamAttribute = [System.Management.Automation.ParameterAttribute]::new()
            $CustomSPFParamAttribute.Position = 4

            # Add the parameter attributes to an attribute collection
            $AttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
            $AttributeCollection.Add($CustomSPFParamAttribute)

            # Create the actual CustomSPF parameter
            $CustomSPFParam = [System.Management.Automation.RuntimeDefinedParameter]::new('CustomSPF', [switch], $AttributeCollection)

            # Push the parameter(s) into a parameter dictionary
            $ParamDictionary = [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()
            $ParamDictionary.Add('CustomSPF', $CustomSPFParam)

            # Return the dictionary
            return $ParamDictionary
        }
    }
    begin {
        [hashtable]$ContentBody = [hashtable]::new()
        $ContentBody.Add('domain', $Domain)
        if ($Domain -match '.*\..*\..*' -and -not $PSBoundParameters.ContainsKey('Subdomain')) {
            Write-Verbose -Message ("Sendgrid will automatically generate a custom subdomain for you. Example:em1234.$Subdomain.$Domain") -Verbose
            $ProcessMessage = $Domain
        }
        elseif ($Domain -match '.*\..*\..*' -and $PSBoundParameters.ContainsKey('Subdomain') -and -not $Force.IsPresent) {
            Write-Warning -Message "It's not recommended to use a double custom subdomain. If you know what you are doing, re-run with -Force. Terminating function..."
            break
        }
        elseif ($Domain -match '.*\..*\..*' -and $PSBoundParameters.ContainsKey('Subdomain') -and $Force.IsPresent) {
            Write-Verbose -Message "Running with force using double subdomain. Sendgrid will automatically generate a subdomain for you. Example:em1234.$Subdomain.$Domain" -Verbose
            $ProcessMessage = "$Subdomain.$Domain"
        }
        else {
            Write-Verbose -Message ("Sendgrid will automatically generate a custom subdomain for you. Example:em1234.$Subdomain.$Domain") -Verbose
            $ContentBody.Add('subdomain', $Subdomain)
            $ProcessMessage = "$Domain"
            
        }
        $ContentBody.Add('custom_dkim_selector', $CustomDkimSelector)
        $ContentBody.Add('default', $false)

        
        if ($PSBoundParameters.ContainsKey('DisableAutomaticSecurity')) {
            $ContentBody.Add('automatic_security', $false)
        }
        else {
            $ContentBody.Add('automatic_security', $true)
        }
        if ($PSBoundParameters.ContainsKey('CustomSPF')) {
            $ContentBody.Add('custom_spf', $true)
        }
        else {
            $ContentBody.Add('custom_spf', $false)
        }
    }    
    process {
        if ($PSCmdlet.ShouldProcess($ProcessMessage)) {
            try {
                Invoke-SendGrid -Method 'Post' -Namespace 'whitelabel/domains' -ContentBody $ContentBody -ErrorAction Stop
            }
            catch {
                Write-Error ('Failed to add SendGrid Authenticated Domain. {0}' -f $_.Exception.Message) -ErrorAction Stop
            }
        }
    }
}