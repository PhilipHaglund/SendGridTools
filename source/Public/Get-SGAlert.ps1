function Get-SGAlert {
    <#
    .SYNOPSIS
        Retrieves a specific alert or all alerts from SendGrid.

    .DESCRIPTION
        Get-SGAlert retrieves a specific alert or all alerts from SendGrid based on the provided parameters.

    .PARAMETER AlertId
        Specifies the ID of the alert to retrieve.

    .PARAMETER OnBehalfOf
        Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.

    .EXAMPLE
        PS C:\> Get-SGAlert -AlertId "123"

        This command retrieves the alert with the ID '123' from SendGrid.

    .EXAMPLE
        PS C:\> Get-SGAlert -OnBehalfOf 'Subuser'

        This command retrieves all alerts from SendGrid for the Subuser 'Subuser'.
    #>
    [CmdletBinding()]
    param (
        # Specifies the ID of the alert to retrieve.
        [Parameter(
            ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            Position = 0
        )]
        [Alias('Id')]
        [string[]]$AlertId,

        # Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
        [Parameter(ParameterSetName = 'Default')]
        [string]$OnBehalfOf
    )
    process {
        $InvokeSplat = @{
            Method        = 'Get'
            Namespace     = 'alerts'
            ErrorAction   = 'Stop'
            CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
        }
        if ($PSBoundParameters.OnBehalfOf) {
            $InvokeSplat.Add('OnBehalfOf', $OnBehalfOf)
        }
        if ($PSBoundParameters.AlertId) {
            foreach ($Alert in $AlertId) {
                $InvokeSplat['Namespace'] = "alerts/$Alert"
                try {
                    Invoke-SendGrid @InvokeSplat
                }
                catch {
                    Write-Error ('Failed to retrieve SendGrid alert. {0}' -f $_.Exception.Message) -ErrorAction Stop
                }
            }
        }
        else {
            try {
                Invoke-SendGrid @InvokeSplat
            }
            catch {
                Write-Error ('Failed to retrieve SendGrid alert(s). {0}' -f $_.Exception.Message) -ErrorAction Stop
            }
        }
    }
}