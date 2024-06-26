function New-SGSuppressionGroup {
    <#
    .SYNOPSIS
        Creates a new suppression group.

    .DESCRIPTION
        The New-SGSuppressionGroup function creates a new suppression group in SendGrid.
        
    .PARAMETER Name
        Specifies the name of the suppression group.

    .PARAMETER Description
        Specifies the description of the suppression group.

    .PARAMETER IsDefault
        Specifies whether the suppression group is the default group.

    .EXAMPLE
        PS C:\> New-SGSuppressionGroup -Name 'My Group' -Description 'This is my group.' -IsDefault $false
        This command creates a new suppression group named 'My Group' with the specified description and is not set as the default group.
    #>
    [CmdletBinding(
        SupportsShouldProcess
    )]
    param (
        # Specifies the name of the suppression group.
        [Parameter(
            Mandatory,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            Position = 0
        )]
        [string]$Name,

        # Specifies the description of the suppression group.
        [Parameter(
            Mandatory,
            Position = 1
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
        $InvokeSplat = @{
            Method        = 'Post'
            Namespace     = "asm/groups"
            ErrorAction   = 'Stop'
            CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
        }

        $InvokeSplat['ContentBody'] = @{
            'name'                              = $Name
            'description'                       = $Description
            'is_default'                        = $IsDefault.IsPresent
        }
        if ($PSBoundParameters.OnBehalfOf) {
            $InvokeSplat.Add('OnBehalfOf', $OnBehalfOf)
        }
        if ($PSCmdlet.ShouldProcess(('Create a new suppression group named {0}.' -f $Name))) {
            try {
                Invoke-SendGrid @InvokeSplat
            }
            catch {
                Write-Error ('Failed to create a new suppression group. {0}' -f $_.Exception.Message) -ErrorAction Stop
            }
        }
    }
}