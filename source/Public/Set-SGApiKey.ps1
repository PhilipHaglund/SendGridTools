function Set-SGApiKey {
    <#
    .SYNOPSIS
        Update the name and scopes of a given API key.

    .DESCRIPTION
        Set-SGApiKey updates the name and scopes of a given API key.

    .PARAMETER UniqueId
        Specifies the ID of the API Key to be updated.

    .PARAMETER Scopes
        Specifies the new scopes of the API Key. Tab completion offers the known scopes; SendGrid decides whether a scope is valid.

    .PARAMETER NewName
        Specifies the new name of the API Key. This parameter is not mandatory.

    .PARAMETER InputObject
        Specifies one or more objects to update, typically received from the pipeline. Each object can be an ID given as a string or integer, or an object with an Id property, such as the output of Get-SGApiKey. Use UniqueId to specify the IDs directly.

    .PARAMETER OnBehalfOf
        Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.

    .EXAMPLE
        PS C:\> Set-SGApiKey -Id '<api-key-id>' -Scopes 'access_settings.activity.read', 'alerts.create', 'alerts.read'

        This command updates the scopes of the API Key with the specified ID within the current SendGrid instance.

    .EXAMPLE
        PS C:\> Set-SGApiKey -Id '<api-key-id>' -Scopes 'access_settings.activity.read', 'alerts.create', 'alerts.read' -NewName 'MyUpdatedKey'

        This command updates both the name and scopes of the API Key with the specified ID within the current SendGrid instance.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'CommandName, ParameterName, CommandAst and FakeBoundParameters are the fixed positional parameters PowerShell passes to an ArgumentCompleter script block; the signature is dictated by the engine and cannot be trimmed.')]
    [CmdletBinding(
        SupportsShouldProcess
    )]
    param (
        # Specifies the UniqueId of the API Key to be updated.
        [Parameter(
            Mandatory,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            DontShow,
            ParameterSetName = 'InputObject'
        )]
        [Object[]]$InputObject,

        # Specifies the UniqueId of the API Key to be updated.
        [Parameter(
            Mandatory,
            Position = 0,
            ParameterSetName = 'UniqueId'
        )]
        [Alias('Id')]
        [string[]]$UniqueId,

        # Specifies the new scopes of the API Key.
        [Parameter(
            Position = 1
        )]
        #[ValidateSet([SendGridScopes])] Removed to make it PowerShell 5.1 compatible
        [ArgumentCompleter({
                param(
                    [string]$CommandName,
                    [string]$ParameterName,
                    [string]$WordToComplete,
                    $CommandAst,
                    $FakeBoundParameters
                )
                $ReturnedValue = [SendGridScopes]::ValidScopes()

                if ($WordToComplete) {
                    $ReturnedValue | Where-Object { $_ -like "$WordToComplete*" }
                }
                else {
                    $ReturnedValue
                } })]
        [string[]]$Scopes,

        # Specifies the new name of the API Key. This parameter is not mandatory.
        [Parameter()]
        [string]$NewName,

        # Specifies a On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
        [Parameter()]
        [string]$OnBehalfOf
    )
    process {
        if ($PSCmdlet.ParameterSetName -eq 'InputObject') {
            $UniqueId = @()
            foreach ($Object in $InputObject) {
                switch ($Object) {
                    { $_ -is [string] } { $UniqueId += $_; break }
                    { $_ -is [int] -or $_ -is [long] } { $UniqueId += $_; break }
                    { $_ -is [System.Management.Automation.PSCustomObject] } { $UniqueId += $_.Id; break }
                    default { Write-Error ('Failed to convert InputObject to Id.') -ErrorAction Stop }
                }
            }
        }
        if ($UniqueId.Count -gt 1 -and $PSBoundParameters.ContainsKey('NewName')) {
            Write-Warning ('Only one API Key can renamed per Set-SGApiKey. Scopes will be updated for {0} API Keys.' -f ($UniqueId.Count - 1))
            $PSBoundParameters.Remove('NewName')
        }
        foreach ($Id in $UniqueId) {
            $InvokeSplat = @{
                Method        = 'Put'
                Namespace     = "api_keys/$Id"
                ErrorAction   = 'Stop'
                CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
            }
            # The read asks no question of its own and runs under -WhatIf, so the command asks once and its What if line names the object (D50).
            $GetSplat = @{
                ApiKeyID    = $Id
                ErrorAction = 'Stop'
                Confirm     = $false
                WhatIf      = $false
            }

            if ($PSBoundParameters.OnBehalfOf) {
                $InvokeSplat.Add('OnBehalfOf', $OnBehalfOf)
                $GetSplat.Add('OnBehalfOf', $OnBehalfOf)
            }
            $CurrentKey = Get-SGApiKey @GetSplat
            if ($PSCmdlet.ShouldProcess($Id)) {
                Write-Verbose -Message ('Updating key {0}' -f $CurrentKey.Name)

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
