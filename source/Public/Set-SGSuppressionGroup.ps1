function Set-SGSuppressionGroup {
    <#
    .SYNOPSIS
        Updates a suppression group.

    .DESCRIPTION
        The Set-SGSuppressionGroup function updates a suppression group in SendGrid.

    .PARAMETER UniqueId
        Specifies the ID of the suppression group.

    .PARAMETER Name
        Specifies the name of the suppression group.

    .PARAMETER Description
        Specifies the description of the suppression group.

    .PARAMETER IsDefault
        Specifies whether the suppression group is the default group.

    .PARAMETER OnBehalfOf
        Specifies a On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.

    .PARAMETER InputObject
        Hidden parameter that accepts ids, or objects with an Id property, from the pipeline. One request is sent for each item.

    .EXAMPLE
        PS C:\> Set-SGSuppressionGroup -Id 123 -Name 'My Group' -Description 'This is my group.' -IsDefault:$false
        This command updates the suppression group with the ID 123.
    #>
    [CmdletBinding(
        SupportsShouldProcess = $true
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

        # Specifies the name of the suppression group.
        [Parameter(
            Position = 1
        )]
        [string]$Name,

        # Specifies the description of the suppression group.
        [Parameter(
            Position = 2
        )]
        [string]$Description,

        # Specifies whether the suppression group is the default group.
        [Parameter()]
        [switch]$IsDefault,

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
        $Body = @{}
        if ($PSBoundParameters.ContainsKey('Name')) {
            $Body['name'] = $Name
        }
        if ($PSBoundParameters.ContainsKey('Description')) {
            $Body['description'] = $Description
        }
        if ($PSBoundParameters.ContainsKey('IsDefault')) {
            $Body['is_default'] = $IsDefault.IsPresent
        }
        foreach ($Id in $IdList) {
            $InvokeSplat = @{
                Method        = 'Patch'
                Namespace     = "asm/groups/$Id"
                ErrorAction   = 'Stop'
                CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
                ContentBody   = $Body
            }
            if ($PSBoundParameters.ContainsKey('OnBehalfOf')) {
                $InvokeSplat.OnBehalfOf = $OnBehalfOf
            }
            if ($PSCmdlet.ShouldProcess(('Update suppression group with ID {0}.' -f $Id))) {
                try {
                    Invoke-SendGrid @InvokeSplat
                }
                catch {
                    Write-Error -Exception (ConvertTo-SendGridCommandException -Message ('Failed to update suppression group. {0}' -f $_.Exception.Message) -ErrorRecord $_) -ErrorAction Stop
                }
            }
        }
    }
}