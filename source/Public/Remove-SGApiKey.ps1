function Remove-SGApiKey {
    <#
    .SYNOPSIS
        Deletes a given API key.

    .DESCRIPTION
        Remove-SGApiKey deletes the API key with the given ID. 

    .PARAMETER ApiKeyID
        Specifies the ID of the API Key to be deleted.

    .EXAMPLE
        PS C:\> Remove-SGApiKey -ApiKeyId 'R2l2W3kZSQukQv4lCkG3zW'

        This command deletes the API Key with the specified ID within the current SendGrid instance.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        # Specifies the ID of the API Key to be deleted.
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName
        )]
        [string[]]$ApiKeyId,
        
        # Specifies a On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
        [Parameter()]
        [string]$OnBehalfOf
    )
    
    process {
        foreach ($Id in $ApiKeyID) {
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
