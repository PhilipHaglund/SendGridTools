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
        [switch]$FullAccessKey,

        # Specifies a On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
        [Parameter()]
        [string]$OnBehalfOf
    )
    begin {
        [hashtable]$ContentBody = @{
            name = $Name
        }
        if ($PSCmdlet.ParameterSetName -eq 'Scopes') {
            $ContentBody.Add('scopes', $Scopes)
        }
    }
    process {
        $InvokeSplat = @{
            Method      = 'Post'
            Namespace   = 'api_keys'
            ErrorAction = 'Stop'
        }
        if ($PSBoundParameters.OnBehalfOf) {
            $InvokeSplat.Add('OnBehalfOf', $OnBehalfOf)
        }
        $InvokeSplat.Add('ContentBody', $ContentBody)
        if ($PSCmdlet.ParameterSetName -eq 'FullAccess') {
            if ($PSCmdlet.ShouldContinue("You are about to create an API key ($Name) with Full Access. Do you want to continue?", $MyInvocation.MyCommand.Name)) {
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
                    Write-Error ('Failed to create a FullAccess SendGrid API key. {0}' -f $_.Exception.Message) -ErrorAction Stop
                }
            }
        }
        else {
            if ($PSCmdlet.ShouldProcess($Name)) {
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
                    Write-Error ('Failed to create SendGrid API key. {0}' -f $_.Exception.Message) -ErrorAction Stop
                }
            }
        }
    }
}
