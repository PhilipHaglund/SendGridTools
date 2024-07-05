function Get-SGBrandedDomainLink {
    <#
    .SYNOPSIS
        Retrieves all or specific Branded Domain Links within the current SendGrid instance.
        
    .DESCRIPTION
        Get-SGBrandedDomainLink retrieves all Branded Domain Links or a specific Branded Domain Link based on its unique ID 
        within the current SendGrid instance. Branded Domain Links allow all of the click-tracked links, opens, and images in your 
        emails to be served from your domain rather than sendgrid.net, which aids in spam filter and recipient server assessments 
        of email trustworthiness. 

    .PARAMETER UniqueId
        Specifies the UniqueId of a specific Branded Domain Link to retrieve. If this parameter is not provided, all Branded Domain Links are retrieved.

    .EXAMPLE
        PS C:\> Get-SGBrandedDomainLink
        
        Domain            : sending.example.com
        Subdomain         : sg
        User              : Top Account
        Valid             : True
        Default           : False
        ValidationAttempt : 2022-03-04 15:34:34
        DNS               : @{DomainCNAME=; OwnerCNAME=}
        UniqueId          : 13508031
        UserId            : 8262273

        Domain            : email.example.com
        Subdomain         : url6142
        User              : Top Account
        Valid             : True
        Default           : False
        ValidationAttempt : 2021-11-12 07:38:12
        DNS               : @{DomainCNAME=; OwnerCNAME=}
        UniqueId          : 12589712
        UserId            : 8262273
        ...

        This command retrieves all Branded Domain Links within the current SendGrid instance.

    .EXAMPLE
        PS C:\> Get-SGBrandedDomainLink -UniqueId '12589712'

        Domain            : email.example.com
        Subdomain         : url6142
        User              : Top Account
        Valid             : True
        Default           : False
        ValidationAttempt : 2021-11-12 07:38:12
        DNS               : @{DomainCNAME=; OwnerCNAME=}
        UniqueId          : 12589712
        UserId            : 8262273

        This command retrieves the Branded Domain Link with the UniqueId '12589712' within the current SendGrid instance.

    .EXAMPLE
        PS C:\> Get-SGBrandedDomainLink -OnBehalfOf 'Subuser'

        Domain            : email.example.com
        Subdomain         : url6142
        User              : Top Account
        Valid             : True
        Default           : False
        ValidationAttempt : 2021-11-12 07:38:12
        DNS               : @{DomainCNAME=; OwnerCNAME=}
        UniqueId          : 12589712
        UserId            : 8262273

        This command retrieves all Branded Domain Links within the current SendGrid instance on behalf of the specified subuser.

    .NOTES
        To use this function, you must be connected to a SendGrid instance. Use the Connect-SendGrid function to establish a connection.
    #>
    [CmdletBinding(
        SupportsShouldProcess
    )]
    param (

        # Specifies a UniqueId to retrieve
        [Parameter(
            ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            Position = 0
        )]
        [Alias('Id')]
        [string]$UniqueId,

        # Specifies if the DNS records should be shown.
        [Parameter()]
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
            $script:SGDomains = Invoke-SGCommand -Namespace 'whitelabel/links' # Can't reference self Get-SGAuthenticatedDomain.
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
            Namespace     = 'whitelabel/links'
            ErrorAction   = 'Stop'
            CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
        }

        # Get-SGBrandedDomainLink -ShowDNS'
        if ($PSBoundParameters.ShowDNS) {
            $InvokeSplat['CallingCmdlet'] = "$($PSCmdlet.MyInvocation.MyCommand.Name) -ShowDNS"
        }

        if ($PSBoundParameters.OnBehalfOf) {
            $InvokeSplat.Add('OnBehalfOf', $OnBehalfOf)
        }
        if ($PSCmdlet.ParameterSetName -eq 'DomainNameSet') {
            $UniqueId = ($script:SGDomains | Where-Object { $_.Domain -eq ($PSBoundParameters['DomainName']) }).Id
        }
        if ($PSBoundParameters.UniqueId) {
            foreach ($Id in $UniqueId) {
                if ($PSCmdlet.ShouldProcess(('{0}' -f $Id))) {
                    $InvokeSplat['Namespace'] = "whitelabel/links/$Id"
                    try {
                        Invoke-SendGrid @InvokeSplat
                    }
                    catch {
                        Write-Error ('Failed to retrieve SendGrid SendGrid Branded Domain Link. {0}' -f $_.Exception.Message) -ErrorAction Stop
                    }
                }
            }
        }
        else {
            if ($PSCmdlet.ShouldProcess(('{0}' -f 'All Branded Domain Links'))) {
                try {
                    Invoke-SendGrid @InvokeSplat
                }
                catch {
                    Write-Error ('Failed to retrieve all SendGrid SendGrid Branded Domain Links. {0}' -f $_.Exception.Message) -ErrorAction Stop
                }
            }
        }
    }
}