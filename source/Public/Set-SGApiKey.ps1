function Set-SGApiKey {
    <#
    .SYNOPSIS
        Update the name and scopes of a given API key.

    .DESCRIPTION
        Set-SGApiKey updates the name and scopes of a given API key. 

    .PARAMETER UniqueId
        Specifies the ID of the API Key to be updated.

    .PARAMETER Scopes
        Specifies the new scopes of the API Key.

    .PARAMETER NewName
        Specifies the new name of the API Key. This parameter is not mandatory.

    .EXAMPLE
        PS C:\> Set-SGApiKey -UniqueId 'R2l2W3kZSQukQv4lCkG3zW' -Scopes 'access_settings.activity.read', 'alerts.create', 'alerts.read'

        This command updates the scopes of the API Key with the specified ID within the current SendGrid instance.

    .EXAMPLE
        PS C:\> Set-SGApiKey -UniqueId 'R2l2W3kZSQukQv4lCkG3zW' -Scopes 'access_settings.activity.read', 'alerts.create', 'alerts.read' -NewName 'MyUpdatedKey'

        This command updates both the name and scopes of the API Key with the specified ID within the current SendGrid instance.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        # Specifies the ID of the API Key to be updated.
        [Parameter(
            Mandatory = $true
        )]
        [string]$UniqueId,

        # Specifies the new scopes of the API Key.
        [Parameter(
            Mandatory = $true
        )]
        [ValidateSet([SendGridScopes])]
        [string[]]$Scopes,

        # Specifies the new name of the API Key. This parameter is not mandatory.
        [Parameter(
            Mandatory = $false
        )]
        [string]$NewName
    )
    
    process {
        $SGApiKey = Get-SGApiKey -UniqueId $UniqueId -ErrorAction Stop
        if ($PSCmdlet.ShouldProcess($UniqueId)) {
            Write-Verbose -Message ('Updating key {0}' -f $SGApiKey.Name)

            [hashtable]$ContentBody = @{
                scopes = $Scopes
            }
            if ($PSBoundParameters.ContainsKey('NewName')) {
                $ContentBody.Add('name', $NewName)
            }

            try {
                Invoke-SendGrid -Method 'Put' -Namespace "api_keys/$ApiKeyID" -ContentBody $ContentBody -ErrorAction Stop
            }
            catch {
                Write-Error ('Failed to update SendGrid API Key. {0}' -f $_.Exception.Message) -ErrorAction Stop
            }
        }
    }
}
