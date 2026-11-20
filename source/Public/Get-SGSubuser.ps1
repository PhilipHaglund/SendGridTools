function Get-SGSubuser {
    <#
    .SYNOPSIS
        Retrieves all or a specific Subuser within the current SendGrid instance.

    .DESCRIPTION
        Get-SGSubuser retrieves all Subusers or a specific Subuser based on its username
        within the current SendGrid instance. Due to limitations in the SendGrid API, when retrieving all users it won't display disabled users.

    .PARAMETER Username
        Specifies the username of a specific Subuser to retrieve. If this parameter is not provided, all Subusers are retrieved. Only a Subuser whose username equals the value is returned.

    .PARAMETER Limit
        The number of results you would like to get in each request.
        Default: none

    .PARAMETER Offset
        The number of Subusers to skip.
        Default: none

    .PARAMETER IncludeRegion
        Adds the region of each Subuser to the output, as the Region property, by sending include_region=true.
        Without it the request has no region query and the output has no Region property.
        It has no effect together with -Username, because SendGrid does not report the region of a single subuser.

    .PARAMETER Region
        Returns only the Subusers in the given region: All, Global or EU. It sends region=all, region=global or
        region=eu together with include_region=true, so the output also has the Region property.
        It has no effect together with -Username, because SendGrid does not report the region of a single subuser.

    .EXAMPLE
        PS C:\> Get-SGSubuser

        This command retrieves all users within the current SendGrid instance.

    .EXAMPLE
        PS C:\> Get-SGSubuser -Username <username>

        This command retrieves the user with the specified username within the current SendGrid instance.

    .EXAMPLE
        PS C:\> Get-SGSubuser -Limit 2

        This command retrieves the first two Subusers within the current SendGrid instance.

    .EXAMPLE
        PS C:\> Get-SGSubuser -IncludeRegion

        This command retrieves all Subusers with the region of each, global or eu, in the Region property.

    .EXAMPLE
        PS C:\> Get-SGSubuser -Region EU

        This command retrieves the Subusers in SendGrid's EU region, with the Region property.
    #>
    [CmdletBinding(
        SupportsShouldProcess
    )]
    param (

        # Specifies the username of a specific Subuser to retrieve. If this parameter is not provided, all Subusers are retrieved. Only a Subuser whose username equals the value is returned.
        [Parameter(
            ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            Position = 0
        )]
        [Alias('Id')]
        [string]$Username,

        # Specifies the page size, i.e. maximum number of items from the list to be returned for a single API request.
        [Parameter()]
        [int]$Limit,

        # Specifies the number of items in the list to skip over before starting to retrieve the items for the requested page.
        [Parameter()]
        [int]$Offset,

        # Adds the region of each Subuser to the output by sending include_region=true.
        [Parameter()]
        [switch]$IncludeRegion,

        # Returns only the Subusers in the given region (All, Global or EU) and adds the region to the output.
        [Parameter()]
        [ValidateSet('All', 'Global', 'EU')]
        [string]$Region
    )

    begin {
        $WarnedAboutRegion = $false
    }

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
            $QueryParameters.Add(('username={0}' -f [uri]::EscapeDataString($Username)))
        }
        if ($PSBoundParameters.Limit) {
            $QueryParameters.Add("limit=$limit")
        }
        if ($PSBoundParameters.Offset) {
            $QueryParameters.Add("offset=$offset")
        }
        if ($IncludeRegion.IsPresent -or $PSBoundParameters.ContainsKey('Region')) {
            if ($PSBoundParameters.Username) {
                if (-not $WarnedAboutRegion) {
                    $WarnedAboutRegion = $true
                    Write-Warning -Message 'SendGrid does not report the region of a single subuser: -IncludeRegion and -Region apply only when -Username is not given.'
                }
            }
            else {
                $QueryParameters.Add('include_region=true')
                if ($PSBoundParameters.ContainsKey('Region')) {
                    $QueryParameters.Add(('region={0}' -f $Region.ToLowerInvariant()))
                }
            }
        }

        if ($QueryParameters.Count -gt 0) {
            $InvokeSplat['Namespace'] += '?' + ($QueryParameters -join '&')
        }

        if ($PSCmdlet.ShouldProcess(('{0}' -f 'Subusers'))) {
            try {
                if ($PSBoundParameters.Username) {
                    # SendGrid's username filter also returns names that start with the value (D96).
                    Invoke-SendGrid @InvokeSplat | Where-Object { "$($_.Username)" -eq $Username }
                }
                else {
                    Invoke-SendGrid @InvokeSplat
                }
            }
            catch {
                Write-Error ('Failed to retrieve SendGrid Subuser. {0}' -f $_.Exception.Message) -ErrorAction Stop
            }
        }
    }
}