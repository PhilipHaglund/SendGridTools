function Remove-SGAlert {
    <#
    .SYNOPSIS
        Deletes an existing alert on SendGrid.

    .DESCRIPTION
        Remove-SGAlert deletes an existing alert on SendGrid based on the provided alert ID.

    .PARAMETER UniqueId
        Specifies the ID of the alert to delete.

    .PARAMETER OnBehalfOf
        Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.

    .PARAMETER InputObject
        Hidden parameter that accepts objects from the pipeline. With the current code this parameter set fails with a conversion error, because the collected IDs are assigned to the integer UniqueId variable, so nothing is deleted. Use UniqueId instead.

    .EXAMPLE
        PS C:\> Remove-SGAlert -Id 123

        This command deletes the alert with the ID 123 on SendGrid.

    .EXAMPLE
        PS C:\> Remove-SGAlert -Id 123 -OnBehalfOf 'Subuser'

        This command deletes the alert with the ID 123 on SendGrid on behalf of the Subuser 'Subuser'.
    #>
    [CmdletBinding(
        SupportsShouldProcess,
        ConfirmImpact = 'High'
    )]
    param (
        # Specifies the UniqueId of the alert to delete.
        [Parameter(
            Mandatory,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            DontShow,
            ParameterSetName = 'InputObject'
        )]
        [Object[]]$InputObject,

        # Specifies the UniqueId of the alert to delete.
        [Parameter(
            Mandatory,
            Position = 0,
            ParameterSetName = 'UniqueId'
        )]
        [Alias('Id')]
        [int]$UniqueId,

        # Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
        [Parameter()]
        [string]$OnBehalfOf
    )
    process {
        if ($PSCmdlet.ParameterSetName -eq 'InputObject') {
            $UniqueId = @()
            foreach ($Object in $InputObject) {
                switch ($Object) {
                    { $_ -is [string] } { $UniqueId += $_; break }
                    { $_ -is [int] } { $UniqueId += $_; break }
                    { $_ -is [System.Management.Automation.PSCustomObject] } { $UniqueId += $_.Id; break }
                    default { Write-Error ('Failed to convert InputObject to Id.') -ErrorAction Stop }
                }
            }
        }
        foreach ($Id in $UniqueId) {
            if ($PSCmdlet.ShouldProcess($Id)) {
                $InvokeSplat = @{
                    Method        = 'Delete'
                    Namespace     = "alerts/$Id"
                    ErrorAction   = 'Stop'
                    CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
                }
                if ($PSBoundParameters.OnBehalfOf) {
                    $InvokeSplat.Add('OnBehalfOf', $OnBehalfOf)
                }
                try {
                    Invoke-SendGrid @InvokeSplat
                }
                catch {
                    Write-Error ('Failed to delete SendGrid alert. {0}' -f $_.Exception.Message) -ErrorAction Stop
                }
            }
        }
    }
}