function Get-SGSuppressionGroup {
    <#
    .SYNOPSIS
        Retrieves suppression groups.

    .DESCRIPTION
        The Get-SGSuppressionGroup function retrieves all suppression groups or a specific suppression group in SendGrid.
        
    .PARAMETER GroupId
        Specifies the ID of the suppression group.

    .EXAMPLE
        PS C:\> Get-SGSuppressionGroup
        This command retrieves all suppression groups.

    .EXAMPLE
        PS C:\> Get-SGSuppressionGroup -GroupId 123
        This command retrieves the suppression group with the ID 123.
    #>
    [CmdletBinding()]
    param (
        # Specifies the ID of the suppression group.
        [Parameter(
            ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            Position = 0
        )]
        [Alias('Id')]
        [int]$GroupId,

        # Specifies a On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
        [Parameter()]
        [string]$OnBehalfOf
    )
    process {
        $InvokeSplat = @{
            Method        = 'Get'
            Namespace     = 'asm/groups'
            ErrorAction   = 'Stop'
            CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
        }
        if ($PSBoundParameters.ContainsKey('OnBehalfOf')) {
            $InvokeSplat.OnBehalfOf = $OnBehalfOf
        }
        if ($PSBoundParameters.ContainsKey('GroupId')) {
            $InvokeSplat.Namespace += "/$GroupId"
        }
        try {
            Invoke-SendGrid @InvokeSplat
        }
        catch {
            Write-Error ('Failed to retrieve suppression group(s). {0}' -f $_.Exception.Message) -ErrorAction Stop
        }
    }
}