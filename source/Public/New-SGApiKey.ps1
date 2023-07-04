function New-SGApiKey {
    <#
    .SYNOPSIS
        Creates a new API Key for the current SendGrid instance.

    .DESCRIPTION
        New-SGApiKey creates a new API key for the SendGrid instance. The API key can be given full access, restricted access, or billing access.
        The created API key can then be used to authenticate access to SendGrid services.

    .PARAMETER Name
        Specifies the name to describe this API Key.

    .PARAMETER Scopes
        Specifies the individual permissions that you are giving to this API Key.

    .PARAMETER FullAccessKey
        Specifies to create a full access API Key. This will nullify the Scopes parameter.

    .EXAMPLE
        PS C:\> New-SGApiKey -Name 'MyAPIKey' -Scopes @('mail.send', 'alerts.create', 'alerts.read')

        Creates a new API key with the name 'MyAPIKey' and assigns 'mail.send', 'alerts.create', 'alerts.read' scopes to the key.

    .EXAMPLE
        PS C:\> New-SGApiKey -Name 'MyFullAccessKey' -FullAccessKey

        Creates a new full access API key with the name 'MyFullAccessKey'. This will prompt for confirmation.

    .NOTES
        To use this function, you must be connected to a SendGrid instance. Use the Connect-SendGrid function to establish a connection.
        There is a limit of 100 API Keys on your account. Omitting the Scopes field from your request will create a key with "Full Access" permissions by default.
    #>
    [CmdletBinding(
        SupportsShouldProcess,
        DefaultParameterSetName = 'Scopes')]
    param (
        [Parameter(
            ParameterSetName = 'Scopes',
            Mandatory
        )]
        [Parameter(
            ParameterSetName = 'FullAccess',
            Mandatory
        )]
        [string]$Name,

        [Parameter(
            ParameterSetName = 'Scopes'
        )]
        [ValidateSet([SendGridScopes])]
        [string[]]$Scopes,

        [Parameter(
            ParameterSetName = 'FullAccess',
            Mandatory
        )]
        [switch]$FullAccessKey
    )
    begin {
        [hashtable]$ContentBody = @{
            name   = $Name
        }
        if ($PSCmdlet.ParameterSetName -eq 'Scopes') {
            $ContentBody.Add('scopes', $Scopes)
        }
    }
    
    process {
        if ($PSCmdlet.ParameterSetName -eq 'FullAccess') {
            if ($PSCmdlet.ShouldContinue("You are about to create an API key ($Name) with Full Access. Do you want to continue?", $MyInvocation.MyCommand.Name)) {
                try {
                    $ContentBody
                    Invoke-SendGrid -Method 'Post' -Namespace 'api_keys' -ContentBody $ContentBody -ErrorAction Stop
                }
                catch {
                    Write-Error ('Failed to create a FullAccess SendGrid API key. {0}' -f $_.Exception.Message) -ErrorAction Stop
                }
            }
        }
        else {
            if ($PSCmdlet.ShouldProcess($Name)) {
                try {
                    Invoke-SendGrid -Method 'Post' -Namespace 'api_keys' -ContentBody $ContentBody -ErrorAction Stop
                    $ContentBody
                }
                catch {
                    Write-Error ('Failed to create SendGrid API key. {0}' -f $_.Exception.Message) -ErrorAction Stop
                }
            }
        }
    }
}
