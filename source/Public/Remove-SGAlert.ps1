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
        Hidden parameter that accepts ids, or objects with an Id property, from the pipeline. One request is sent for each item.

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
            $IdList = [System.Collections.Generic.List[int]]::new()
            foreach ($Object in $InputObject) {
                $Candidate = if ($null -ne $Object -and $Object.PSObject.Properties['Id']) { $Object.Id } else { $Object }
                $Parsed = 0
                if (-not [int]::TryParse("$Candidate", [ref]$Parsed)) {
                    Write-Error ('Failed to convert InputObject to Id.') -ErrorAction Stop
                }
                $IdList.Add($Parsed)
            }
        }
        else {
            $IdList = @($UniqueId)
        }
        foreach ($Id in $IdList) {
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
                    Write-Error -Exception (ConvertTo-SendGridCommandException -Message ('Failed to delete SendGrid alert. {0}' -f $_.Exception.Message) -ErrorRecord $_) -ErrorAction Stop
                }
            }
        }
    }
}