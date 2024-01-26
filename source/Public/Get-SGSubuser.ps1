function Get-SGSubuser {
    <#
    .SYNOPSIS
        Retrieves all or a specific Subuser within the current SendGrid instance.

    .DESCRIPTION
        Get-SGSubuser retrieves all Subusers or a specific Subuser based on its username
        within the current SendGrid instance. If a specific Subuser username is provided,
        the cmdlet also returns the Subuser's assigned IPs.

    .PARAMETER $UniqueId
        Specifies the ID of a specific Subuser to retrieve. If this parameter is not provided, all Subusers are retrieved.

    .PARAMETER OnBehalfOf
        Specifies a On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.

    .EXAMPLE
        PS C:\> Get-SGApiKey
        
        This command retrieves all API Keys within the current SendGrid instance.

    .EXAMPLE
        PS C:\> Get-SGApiKey -ApiKeyId <apiKeyId>
        
        This command retrieves the API Key with the specified ID within the current SendGrid instance and returns 
        the scopes added to the key.
    
    .EXAMPLE
        PS C:\> Get-SGApiKey -OnBehalfOf 'Subuser'
        
        This command retrieves all API Keys within the current SendGrid instance on behalf of the specified subuser.
    #>
    [CmdletBinding(
        SupportsShouldProcess
    )]
    param (

        # Specifies the UniqueId of a
        [Parameter(
            ValueFromPipeline,
            ValueFromPipelineByPropertyName
        )]
        [string[]]$UniqueId,

        # Specifies a On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
        [Parameter()]
        [string]$OnBehalfOf
    )

    process {
        $InvokeSplat = @{
            Method      = 'Get'
            Namespace   = 'api_keys'
            ErrorAction = 'Stop'
        }
        if ($PSBoundParameters.OnBehalfOf) {
            $InvokeSplat.Add('OnBehalfOf', $OnBehalfOf)
        }
        if ($PSBoundParameters.ApiKeyId) {
            foreach ($Id in $ApiKeyID) {
                if ($PSCmdlet.ShouldProcess(('{0}' -f $Id))) {
                    $InvokeSplat['Namespace'] = "api_keys/$Id"
                    try {
                        Invoke-SendGrid @InvokeSplat
                    }
                    catch {
                        Write-Error ('Failed to retrieve SendGrid API Key. {0}' -f $_.Exception.Message) -ErrorAction Stop
                    }
                }
            }
        }
        else {
            if ($PSCmdlet.ShouldProcess(('{0}' -f 'All API Keys'))) {
                try {
                    Invoke-SendGrid @InvokeSplat
                }
                catch {
                    Write-Error ('Failed to retrieve SendGrid API Key. {0}' -f $_.Exception.Message) -ErrorAction Stop
                }
            }
        }
    }
}