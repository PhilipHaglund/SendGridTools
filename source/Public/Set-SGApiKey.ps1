function Set-SGApiKey {
    <#
    .SYNOPSIS
        Update the name and scopes of a given API key.

    .DESCRIPTION
        Set-SGApiKey updates the name and scopes of a given API key. 

    .PARAMETER ApiKeyID
        Specifies the ID of the API Key to be updated.

    .PARAMETER Scopes
        Specifies the new scopes of the API Key.

    .PARAMETER NewName
        Specifies the new name of the API Key. This parameter is not mandatory.

    .EXAMPLE
        PS C:\> Set-SGApiKey -ApiKeyID 'R2l2W3kZSQukQv4lCkG3zW' -Scopes 'access_settings.activity.read', 'alerts.create', 'alerts.read'

        This command updates the scopes of the API Key with the specified ID within the current SendGrid instance.

    .EXAMPLE
        PS C:\> Set-SGApiKey -ApiKeyID 'R2l2W3kZSQukQv4lCkG3zW' -Scopes 'access_settings.activity.read', 'alerts.create', 'alerts.read' -NewName 'MyUpdatedKey'

        This command updates both the name and scopes of the API Key with the specified ID within the current SendGrid instance.
    #>
    [CmdletBinding(
        SupportsShouldProcess
    )]
    param (
        # Specifies the ID of the API Key to be updated.
        [Parameter(
            Mandatory = $true
        )]
        [string[]]$ApiKeyID,

        # Specifies the new scopes of the API Key.
        [Parameter()]
        [ValidateSet([SendGridScopes])]
        [string[]]$Scopes,

        # Specifies the new name of the API Key. This parameter is not mandatory.
        [Parameter()]
        [string]$NewName,

        # Specifies a On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
        [Parameter()]
        [string]$OnBehalfOf
    )
    
    process {
        if ($ApiKeyID.Count -gt 1) {
            Write-Warning ('Only one API Key can be updated at a time. Only scopes will be updated for {0} API Keys.' -f ($ApiKeyID.Count - 1))
            $PSBoundParameters.Remove('NewName')
        }
        foreach ($Id in $ApiKeyID) {
            $InvokeSplat = @{
                Method      = 'Put'
                Namespace   = "api_keys/$Id"
                ErrorAction = 'Stop'
            }
            $GetSplat = @{
                ApiKeyID    = $Id
                ErrorAction = 'Stop'
            }

            if ($PSBoundParameters.OnBehalfOf) {
                $InvokeSplat.Add('OnBehalfOf', $OnBehalfOf)
                $GetSplat.Add('OnBehalfOf', $OnBehalfOf)
            }
            $CurrentKey = Get-SGApiKey @GetSplat
            if ($PSCmdlet.ShouldProcess($Id)) {
                Write-Verbose -Message ('Updating key {0}' -f $SGApiKey.Name)

                if ($PSBoundParameters.ContainsKey('Scopes')) {
                    [hashtable]$ContentBody = @{
                        scopes = $Scopes
                    }
                }
                else {
                    [hashtable]$ContentBody = @{
                        scopes = $CurrentKey.Scopes
                    }
                }
                
                if ($PSBoundParameters.ContainsKey('NewName')) {
                    $ContentBody.Add('name', $NewName)
                    
                }
                else {
                    $ContentBody.Add('name', $CurrentKey.Name)
                }
                $InvokeSplat.Add('ContentBody', $ContentBody)
                try {
                    Invoke-SendGrid @InvokeSplat
                }
                catch {
                    Write-Error ('Failed to update SendGrid API Key. {0}' -f $_.Exception.Message) -ErrorAction Stop
                }
            }
        }
    }
}
