function Get-SGSubuser {
    <#
    .SYNOPSIS
        Retrieves all or a specific Subuser within the current SendGrid instance.

    .DESCRIPTION
        Get-SGSubuser retrieves all Subusers or a specific Subuser based on its username
        within the current SendGrid instance. Due to limitations in the Sendgrid API, when retriev ing all users it wont display disabled users.

    .PARAMETER Username
        Specifies the ID of a specific Subuser to retrieve. If this parameter is not provided, all Subusers are retrieved.

    .PARAMETER Limit
        The number of results you would like to get in each request.
        Default: none

    .PARAMETER Offset
        The number of Subusers to skip.
        Default: none

    .EXAMPLE
        PS C:\> Get-SGSubuser
        
        This command retrieves all users within the current SendGrid instance.

    .EXAMPLE
        PS C:\> Get-SGSubuser -Username <username>
        
        This command retrieves the user with the specified username within the current SendGrid instance.
    
    .EXAMPLE
        PS C:\> Get-SGSubuser -Limit 2
        
        This command retrieves the first two Subusers within the current SendGrid instance.
    #>
    [CmdletBinding(
        SupportsShouldProcess
    )]
    param (

        # Specifies the ID of a specific Subuser to retrieve. If this parameter is not provided, all Subusers are retrieved.
        [Parameter(
            ValueFromPipeline,
            ValueFromPipelineByPropertyName
        )]
        [string]$Username,

        # Specifies the page size, i.e. maximum number of items from the list to be returned for a single API request.
        [Parameter()]
        [int]$Limit,

        # Specifies the number of items in the list to skip over before starting to retrieve the items for the requested page.
        [Parameter()]
        [int]$Offset
    )

    process {
        $InvokeSplat = @{
            Method        = 'Get'
            Namespace     = 'subusers'
            ErrorAction   = 'Stop'
            CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
        } 
        
        #Generic List
        [System.Collections.Generic.List[string]]$QueryParameters = [System.Collections.Generic.List[string]]::new()

        if ($PSBoundParameters.Username) {
            $InvokeSplat['Namespace'] += "/$username"
        }
        if ($PSBoundParameters.Limit) {
            $QueryParameters.Add("limit=$limit")
        }
        if ($PSBoundParameters.Offset) {
            $QueryParameters.Add("offset=$offset")
        }

        if ($QueryParameters.Count -gt 0) {
            $InvokeSplat['Namespace'] += '?' + ($QueryParameters -join '&')
        }

        if ($PSCmdlet.ShouldProcess(('{0}' -f 'Subusers'))) {
            try {
                Invoke-SendGrid @InvokeSplat
            }
            catch {
                Write-Error ('Failed to retrieve SendGrid Subuser. {0}' -f $_.Exception.Message) -ErrorAction Stop
            }
        }
    }
}