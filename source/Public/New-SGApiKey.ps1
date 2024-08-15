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
            Mandatory,
            Position = 0
        )]
        [Parameter(
            ParameterSetName = 'FullAccess',
            Mandatory,
            Position = 0
        )]
        [string]$Name,

        [Parameter(
            ParameterSetName = 'Scopes',
            Mandatory,
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
        [string[]]$Scope,

        [Parameter(
            ParameterSetName = 'FullAccess',
            Mandatory,
            Position = 1
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
            $ContentBody.Add('scopes', $Scope)
        }
    }
    process {
        $InvokeSplat = @{
            Method        = 'Post'
            Namespace     = 'api_keys'
            ErrorAction   = 'Stop'
            CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
        }
        if ($PSBoundParameters.OnBehalfOf) {
            $InvokeSplat.Add('OnBehalfOf', $OnBehalfOf)
        }
        $InvokeSplat.Add('ContentBody', $ContentBody)
        if ($PSCmdlet.ParameterSetName -eq 'FullAccess') {
            if ($PSCmdlet.ShouldContinue("You are about to create an API key ($Name) with Full Access. Do you want to continue?", $MyInvocation.MyCommand.Name)) {
                try {
                    Invoke-SendGrid @InvokeSplat
                }
                catch {
                    Write-Error ('Failed to create a FullAccess SendGrid API key. {0}' -f $_.Exception.Message) -ErrorAction Stop
                }
            }
        }
        else {
            if ($PSCmdlet.ShouldProcess($Name)) {
                try {
                    Invoke-SendGrid @InvokeSplat
                }
                catch {
                    Write-Error ('Failed to create SendGrid API key. {0}' -f $_.Exception.Message) -ErrorAction Stop
                }
            }
        }
    }
}
