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

    .EXAMPLE
        PS C:\> Get-SMSGAuthenticatedDomain
        
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
        PS C:\> Get-SMSGAuthenticatedDomain -UniqueId 12589712
        
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

        This command retrieves the Authenticated Domain with the UniqueId '12589712' within the current SendGrid instance.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    param (

        # Specifies the UniqueId of a specific Authenticated Domain to retrieve. If this parameter is not provided, all Authenticated Domains are retrieved.
        [Parameter(
            Mandatory,
            ParameterSetName = 'UniqueId'
        )]
        [string]$UniqueId
    )
    process {
        if ($PSBoundParameters.UniqueId) {
            try {
                Invoke-SendGrid -Method 'Get' -Namespace "whitelabel/domains/$UniqueId" -ErrorAction Stop
            }
            catch {
                Write-Error ('Failed to retrieve SendGrid Authenticated Domain. {0}' -f $_.Exception.Message) -ErrorAction Stop
            }
        }
        else {
            try {
                Invoke-SendGrid -Method 'Get' -Namespace "whitelabel/domains" -ErrorAction Stop
            }
            catch {
                Write-Error ('Failed to retrieve SendGrid Authenticated Domains. {0}' -f $_.Exception.Message) -ErrorAction Stop
            }
        }
    }
}