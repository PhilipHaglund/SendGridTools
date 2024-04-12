function Set-SGSuppressionGroup {
    <#
    .SYNOPSIS
        Updates a suppression group.

    .DESCRIPTION
        The Set-SGSuppressionGroup function updates a suppression group in SendGrid.
        
    .PARAMETER GroupId
        Specifies the ID of the suppression group.

    .PARAMETER Name
        Specifies the name of the suppression group.

    .PARAMETER Description
        Specifies the description of the suppression group.

    .PARAMETER IsDefault
        Specifies whether the suppression group is the default group.

    .PARAMETER OnBehalfOf
        Specifies a On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.

    .EXAMPLE
        PS C:\> Set-SGSuppressionGroup -GroupId 123 -Name 'My Group' -Description 'This is my group.' -IsDefault $false
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
            ValueFromPipelineByPropertyName
        )]
        [Alias('Id')]
        [int]$GroupId,

        # Specifies the name of the suppression group.
        [Parameter()]
        [string]$Name,

        # Specifies the description of the suppression group.
        [Parameter()]
        [string]$Description,

        # Specifies whether the suppression group is the default group.
        [Parameter()]
        [bool]$IsDefault,

        # Specifies a On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
        [Parameter()]
        [string]$OnBehalfOf
    )
    process {
        $InvokeSplat = @{
            Method        = 'Patch'
            Namespace     = "asm/groups/$GroupId"
            ErrorAction   = 'Stop'
            CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
        }
        if ($PSBoundParameters.ContainsKey('OnBehalfOf')) {
            $InvokeSplat.OnBehalfOf = $OnBehalfOf
        }
        $InvokeSplat['ContentBody'] = @{
            'name' = $Name
            'description' = $Description
            'is_default' = $IsDefault
        }
        if ($PSCmdlet.ShouldProcess(('Update suppression group with ID {0}.' -f $GroupId))) {
            try {
                Invoke-SendGrid @InvokeSplat
            }
            catch {
                Write-Error ('Failed to update suppression group. {0}' -f $_.Exception.Message) -ErrorAction Stop
            }
        }
    }
}