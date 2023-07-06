function Remove-SGApiKey {
    <#
    .SYNOPSIS
        Deletes a given API key.

    .DESCRIPTION
        Remove-SGApiKey deletes the API key with the given ID. 

    .PARAMETER ApiKeyID
        Specifies the ID of the API Key to be deleted.

    .EXAMPLE
        PS C:\> Remove-SGApiKey -ApiKeyID 'R2l2W3kZSQukQv4lCkG3zW'

        This command deletes the API Key with the specified ID within the current SendGrid instance.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        # Specifies the ID of the API Key to be deleted.
        [Parameter(
            Mandatory = $true
        )]
        [string]$ApiKeyID
    )
    
    process {
        if ($PSCmdlet.ShouldProcess($ApiKeyID)) {
            try {
                # Deletes the API Key
                Invoke-SendGrid -Method 'Delete' -Namespace "api_keys/$ApiKeyID" -ErrorAction Stop
            }
            catch {
                Write-Error ('Failed to delete SendGrid API Key. {0}' -f $_.Exception.Message) -ErrorAction Stop
            }
        }
    }
}
