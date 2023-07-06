﻿function Get-SGApiKey {
    <#
    .SYNOPSIS
        Retrieves all or a specific API Key within the current SendGrid instance.

    .DESCRIPTION
        Get-SGApiKey retrieves all API Keys or a specific API Key based on its ID 
        within the current SendGrid instance. If a specific API Key ID is provided, 
        the cmdlet also returns the scopes added to the key.

    .PARAMETER ApiKeyID
        Specifies the ID of a specific API Key to retrieve. If this parameter is not provided, all API Keys are retrieved. 
        When a specific API Key ID is provided, the associated scopes of the key are also retrieved.

    .EXAMPLE
        PS C:\> Get-SGApiKey
        
        This command retrieves all API Keys within the current SendGrid instance.

    .EXAMPLE
        PS C:\> Get-SGApiKey -ApiKeyID <apiKeyId>
        
        This command retrieves the API Key with the specified ID within the current SendGrid instance and returns 
        the scopes added to the key.
    #>
    [CmdletBinding()]
    param (

        # Specifies the ID of a specific API Key to retrieve. If this parameter is not provided, all API Keys are retrieved.
        [Parameter(
            Mandatory,
            ParameterSetName = 'ApiKeyID'
        )]
        [string]$ApiKeyID
    )

    process {
        if ($PSBoundParameters.ApiKeyID) {
            try {
                Invoke-SendGrid -Method 'Get' -Namespace "api_keys/$ApiKeyID" -ErrorAction Stop
            }
            catch {
                Write-Error ('Failed to retrieve SendGrid API Key. {0}' -f $_.Exception.Message) -ErrorAction Stop
            }
        }
        else {
            try {
                Invoke-SendGrid -Method 'Get' -Namespace 'api_keys' -ErrorAction Stop
            }
            catch {
                Write-Error ('Failed to retrieve SendGrid API Keys. {0}' -f $_.Exception.Message) -ErrorAction Stop
            }
        }
    }
}
