function Set-SGApiKeyName {
    <#
    .SYNOPSIS
        Update the name of a given API key.

    .DESCRIPTION
        Set-SGApiKeyName updates the name of a given API key. 

    .PARAMETER ApiKeyID
        Specifies the ID of the API Key to be updated.

    .PARAMETER NewName
        Specifies the new name of the API Key.

    .EXAMPLE
        PS C:\> Set-SGApiKeyName -ApiKeyID 'R2l2W3kZSQukQv4lCkG3zW' -NewName 'MyUpdatedKey'

        This command updates the name of the API Key with the specified ID within the current SendGrid instance.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        # Specifies the ID of the API Key to be updated.
        [Parameter(
            Mandatory = $true
        )]
        [string]$ApiKeyID,

        # Specifies the new name of the API Key.
        [Parameter(
            Mandatory = $true
        )]
        [string]$NewName
    )
    
    process {
        if ($PSCmdlet.ShouldProcess($ApiKeyID)) {
            Write-Verbose -Message ('Updating key {0}' -f $ApiKeyID)

            [hashtable]$ContentBody = @{
                name = $NewName
            }

            try {
                Invoke-SendGrid -Method 'Patch' -Namespace "api_keys/$ApiKeyID" -ContentBody $ContentBody -ErrorAction Stop
            }
            catch {
                Write-Error ('Failed to update SendGrid API Key name. {0}' -f $_.Exception.Message) -ErrorAction Stop
            }
        }
    }
}
