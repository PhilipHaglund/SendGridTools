function Remove-SGApiKey {
    <#
    .SYNOPSIS
        Deletes a given API key.

    .DESCRIPTION
        Remove-SGApiKey deletes the API key with the given ID.

    .PARAMETER UniqueId
        Specifies the ID of the API Key to be deleted.

    .PARAMETER InputObject
        Specifies one or more objects to delete, typically received from the pipeline. Each object can be an ID given as a string or integer, or an object with an Id property, such as the output of Get-SGApiKey. Use UniqueId to specify the IDs directly.

    .PARAMETER OnBehalfOf
        Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.

    .EXAMPLE
        PS C:\> Remove-SGApiKey -Id '<api-key-id>'

        This command deletes the API Key with the specified ID within the current SendGrid instance.
    #>
    [CmdletBinding(
        SupportsShouldProcess,
        ConfirmImpact = 'High'
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
        foreach ($Id in $UniqueId) {
            $InvokeSplat = @{
                Method        = 'Delete'
                Namespace     = "api_keys/$Id"
                ErrorAction   = 'Stop'
                CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
            }
            $GetSplat = @{
                ApiKeyID    = $Id
                ErrorAction = 'Stop'
            }

            if ($PSBoundParameters.OnBehalfOf) {
                $InvokeSplat.Add('OnBehalfOf', $OnBehalfOf)
                $GetSplat.Add('OnBehalfOf', $OnBehalfOf)
            }
            $SGApiKey = Get-SGApiKey @GetSplat
            if ($PSCmdlet.ShouldProcess('ApiKey: {0}' -f $SGApiKey.Name)) {
                try {
                    Invoke-SendGrid @InvokeSplat
                }
                catch {
                    Write-Error ('Failed to delete SendGrid API Key. {0}' -f $_.Exception.Message) -ErrorAction Stop
                }
            }
        }
    }
}
