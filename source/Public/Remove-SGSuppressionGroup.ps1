function Remove-SGSuppressionGroup {
    <#
    .SYNOPSIS
        Deletes a suppression group.

    .DESCRIPTION
        The Remove-SGSuppressionGroup function deletes a suppression group in SendGrid.

    .PARAMETER UniqueId
        Specifies the ID of the suppression group.

    .PARAMETER OnBehalfOf
        Specifies a On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.

    .PARAMETER InputObject
        Hidden parameter that accepts ids, or objects with an Id property, from the pipeline. One request is sent for each item.

    .EXAMPLE
        PS C:\> Remove-SGSuppressionGroup -Id 123
        This command deletes the suppression group with the ID 123.
    #>
    [CmdletBinding(
        SupportsShouldProcess,
        ConfirmImpact = 'High'
    )]
    param (
        # Specifies the ID of the suppression group.
        [Parameter(
            Mandatory,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            DontShow,
            ParameterSetName = 'InputObject'
        )]
        [Object[]]$InputObject,

        # Specifies the ID of the suppression group.
        [Parameter(
            Mandatory,
            Position = 0,
            ParameterSetName = 'UniqueId'
        )]
        [Alias('Id')]
        [int]$UniqueId,

        # Specifies a On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
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
            $InvokeSplat = @{
                Method        = 'Delete'
                Namespace     = "asm/groups/$Id"
                ErrorAction   = 'Stop'
                CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
            }
            if ($PSBoundParameters.ContainsKey('OnBehalfOf')) {
                $InvokeSplat.OnBehalfOf = $OnBehalfOf
            }
            if ($PSCmdlet.ShouldProcess(('Delete suppression group with ID {0}.' -f $Id))) {
                try {
                    Invoke-SendGrid @InvokeSplat
                }
                catch {
                    Write-Error -Exception (ConvertTo-SendGridCommandException -Message ('Failed to delete suppression group. {0}' -f $_.Exception.Message) -ErrorRecord $_) -ErrorAction Stop
                }
            }
        }
    }
}