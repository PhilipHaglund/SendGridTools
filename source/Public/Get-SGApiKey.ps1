function Get-SGApiKey {
    <#
    .SYNOPSIS
        Retrieves all or a specific API Key within the current SendGrid instance.

    .DESCRIPTION
        Get-SGApiKey retrieves all API Keys or a specific API Key based on its ID 
        within the current SendGrid instance. If a specific API Key ID is provided, 
        the cmdlet also returns the scopes added to the key.

    .PARAMETER ApiKeyId
        Specifies the ID of a specific API Key to retrieve. If this parameter is not provided, all API Keys are retrieved. 
        When a specific API Key ID is provided, the associated scopes of the key are also retrieved.

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

        # Specifies the ID of a specific API Key to retrieve. If this parameter is not provided, all API Keys are retrieved.
        [Parameter(
            ValueFromPipeline,
            ValueFromPipelineByPropertyName
            
        )]
        [string[]]$ApiKeyId,

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
                        $InvokeResult = Invoke-SendGrid @InvokeSplat
                        if ($InvokeResult.Errors.Count -gt 0) {
                            throw $InvokeResult.Errors.Message
                        }
                        else {
                            $InvokeResult
                        }
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
                    $InvokeResult = Invoke-SendGrid @InvokeSplat
                    if ($InvokeResult.Errors.Count -gt 0) {
                        throw $InvokeResult.Errors.Message
                    }
                    else {
                        $InvokeResult
                    }
                }
                catch {
                    Write-Error ('Failed to retrieve SendGrid API Key. {0}' -f $_.Exception.Message) -ErrorAction Stop
                }
            }
        }
    }
}