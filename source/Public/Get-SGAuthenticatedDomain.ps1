function Get-SGAuthenticatedDomain {
    <#
    .SYNOPSIS
        Retrieves all or specific Authenticated Domains within the current SendGrid instance.
        
    .DESCRIPTION
        Get-SGAuthenticatedDomain retrieves all Authenticated Domains or a specific Authenticated Domain based on its unique ID 
        within the current SendGrid instance. An authenticated domain allows you to replace sendgrid.net with your personal sending domain, 
        thereby removing the "via" or "sent on behalf of" message that recipients see when they read your emails. 

    .PARAMETER UniqueId
        Specifies the UniqueId of a specific Authenticated Domain to retrieve. If this parameter is not provided, all Authenticated Domains are retrieved.

    .PARAMETER OnBehalfOf
        Specifies a On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.

    .EXAMPLE
        PS C:\> Get-SGAuthenticatedDomain
        
        Domain            : sending.example.com
        Subdomain         : em4963
        User              : Top Account
        Valid             : True
        AutomaticSecurity : True
        Default           : False
        ValidationAttempt : 2022-03-04 15:34:34
        DNS               : @{MailCNAME=; DKIM1=; DKIM2=}
        IPAddresses       : {}
        UniqueId          : 13508031
        UserId            : 8262273

        Domain            : email.example.com
        Subdomain         : em200
        User              : Top Account
        Valid             : True
        AutomaticSecurity : True
        Default           : False
        ValidationAttempt : 2021-11-12 07:38:27
        DNS               : @{MailCNAME=; DKIM1=; DKIM2=}
        IPAddresses       : {}
        UniqueId          : 12589712
        UserId            : 8262273
        ...

        This command retrieves all Authenticated Domains within the current SendGrid instance.

    .EXAMPLE
        PS C:\> Get-SGAuthenticatedDomain -UniqueId 12589712
        
        Domain            : email.example.com
        Subdomain         : em200
        User              : Top Account
        Valid             : True
        AutomaticSecurity : True
        Default           : False
        ValidationAttempt : 2021-11-12 07:38:27
        DNS               : @{MailCNAME=; DKIM1=; DKIM2=}
        IPAddresses       : {}
        UniqueId          : 12589712
        UserId            : 8262273
        Username          : Top Account

        This command retrieves the Authenticated Domain with the UniqueId '12589712' within the current SendGrid instance.

        .EXAMPLE
        PS C:\> Get-SGAuthenticatedDomain -UniqueId 12589712 -OnBehalfOf 'Subuser'

        Domain            : email.example.com
        Subdomain         : em200
        User              : Top Account
        Valid             : True
        AutomaticSecurity : True
        Default           : False
        ValidationAttempt : 2021-11-12 07:38:27
        DNS               : @{MailCNAME=; DKIM1=; DKIM2=}
        IPAddresses       : {}
        UniqueId          : 12589712
        UserId            : 8262273
        Username          : Subuser

        This command retrieves the Authenticated Domain with the UniqueId '12589712' within for the Subuser 'Subuser' within the current SendGrid instance.
    #>
    [CmdletBinding(
        SupportsShouldProcess
    )]
    param (
        # Specifies the UniqueId of a specific Authenticated Domain to retrieve. If this parameter is not provided, all Authenticated Domains are retrieved.
        [Parameter(
            ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            Position = 0
        )]
        [Alias('Id')]
        [string[]]$UniqueId,

        # Specifies if the DNS records should be shown.
        [Parameter(
            Position = 1
        )]
        [switch]$ShowDNS,

        # Specifies a On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
        [Parameter()]
        [string]$OnBehalfOf
    )
    DynamicParam {
        # Create a dictionary to hold the dynamic parameters
        $ParamDictionary = [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()
        if ($null -eq $UniqueId) {
            # Create the Equal parameter attribute
            $DomainNameParamAttribute = [System.Management.Automation.ParameterAttribute]::new()
            $DomainNameParamAttribute.ParameterSetName = 'DomainNameSet'

            # Add the parameter attributes to an attribute collection
            $DomainNameAttributeCollection = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
            $DomainNameAttributeCollection.Add($DomainNameParamAttribute)

            # Add ValidateSet to the parameter
            $script:SGDomains = Invoke-SGCommand -Namespace 'whitelabel/domains' # Can't reference self Get-SGAuthenticatedDomain.
            $DomainNameValidateSet = [System.Management.Automation.ValidateSetAttribute]::new([string[]]$script:SGDomains.Domain)
            $DomainNameAttributeCollection.Add($DomainNameValidateSet)

            # Add Alias to the parameter
            $DomainNameAliasAttribute = [System.Management.Automation.AliasAttribute]::new('Domain')
            $DomainNameAttributeCollection.Add($DomainNameAliasAttribute)

            # Create the actual parameter(s)
            $DomainNameParam = [System.Management.Automation.RuntimeDefinedParameter]::new('DomainName', [string[]], $DomainNameAttributeCollection)

            # Push the parameter(s) into a parameter dictionary
            $ParamDictionary.Add('DomainName', $DomainNameParam)
        }
        return $ParamDictionary
    }
    process {
        $InvokeSplat = @{
            Method        = 'Get'
            Namespace     = 'whitelabel/domains'
            ErrorAction   = 'Stop'
            CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
        }
        # Get-SGAuthenticatedDomain -ShowDNS'
        if ($PSBoundParameters.ShowDNS) {
            $InvokeSplat['CallingCmdlet'] = "$($PSCmdlet.MyInvocation.MyCommand.Name) -ShowDNS"
        }
        if ($PSBoundParameters.OnBehalfOf) {
            $InvokeSplat.Add('OnBehalfOf', $OnBehalfOf)
        }
        if ($PSCmdlet.ParameterSetName -eq 'DomainNameSet') {
            $UniqueId = ($script:SGDomains | Where-Object { $_.Domain -eq ($PSBoundParameters['DomainName']) }).Id
        }
        if ($null -ne $UniqueId) {
            foreach ($Id in $UniqueId) {
                if ($PSCmdlet.ShouldProcess(('{0}' -f $Id))) {
                    $InvokeSplat['Namespace'] = "whitelabel/domains/$Id"
                    try {
                        Invoke-SendGrid @InvokeSplat
                    }
                    catch {
                        Write-Error ('Failed to retrieve SendGrid Authenticated Domain. {0}' -f $_.Exception.Message) -ErrorAction Stop
                    }
                }
            }
        }
        else {
            if ($PSCmdlet.ShouldProcess(('All Authenticated Domains'))) {
                try {
                    Invoke-SendGrid @InvokeSplat
                }
                catch {
                    Write-Error ('Failed to retrieve all SendGrid Authenticated Domain. {0}' -f $_.Exception.Message) -ErrorAction Stop
                }
            }
        }
    }   
}