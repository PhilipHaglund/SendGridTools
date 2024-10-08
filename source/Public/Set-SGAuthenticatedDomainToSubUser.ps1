﻿function Set-SGAuthenticatedDomainToSubUser {
    <#
    .SYNOPSIS
        Assign a specified Authenticated Domain to a subuser.

    .DESCRIPTION
        Authenticated domains can be associated with (i.e. assigned to) subusers from a parent account.
        This functionality allows subusers to send mail using their parent's domain authentication.
        To associate an authenticated domain with a subuser, the parent account must first authenticate and validate the domain.
        The parent may then associate the authenticated domain via the subuser management tools.

    .PARAMETER UniqueId
        Specifies the ID of the authenticated domain to assign to the subuser. This parameter is mandatory.

        .PARAMETER UserName
        Specifies username of the subuser to assign the authenticated domain to. This parameter is mandatory.

    .EXAMPLE
        PS C:\> Set-SGAuthenticatedDomainToSubUser -UniqueId '1234567' -UserName 'subuser'

        This command assigns the authenticated domain with the unique ID '1234567' to the subuser 'subuser'.

    .EXAMPLE
        PS C:\> Get-SGAuthenticatedDomain | Where-Object { $_.Domain -eq 'example.com' } | Set-SGAuthenticatedDomainToSubUser -UserName 'subuser'
        
        This command assigns the authenticated domain 'example.com' to the subuser 'subuser' using its unique ID obtained from the Get-SGAuthenticatedDomain cmdlet.
    #>
    [CmdletBinding(
        SupportsShouldProcess
    )]
    param (

        # Specifies the ID of a specific authenticated domain to assign to the subuser.
        [Parameter(
            Mandatory,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            Position = 0
        )]
        [Alias('Id')]
        [string]$UniqueId,

        # Specifies username of the subuser to assign the authenticated domain to.
        [Parameter(
            Mandatory,
            ValueFromPipelineByPropertyName,
            Position = 1
        )]
        [string]$UserName
    )
    process {
        $InvokeSplat = @{
            Method        = 'Post'
            Namespace     = "whitelabel/domains/$UniqueId/subuser"
            ErrorAction   = 'Stop'
            CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
        }
        $GetSplat = @{
            UniqueId    = $UniqueId
            ErrorAction = 'Stop'
        }
        $SGAuthenticatedDomain = Get-SGAuthenticatedDomain @GetSplat
        if ($PSCmdlet.ShouldProcess(('{0}.{1}' -f $SGAuthenticatedDomain.Subdomain, $SGAuthenticatedDomain.Domain))) {
            try {
                [hashtable]$ContentBody = @{
                    username = $UserName
                }
                $InvokeSplat.Add('ContentBody', $ContentBody)
                Invoke-SendGrid @InvokeSplat
            }
            catch {
                Write-Error ('Failed to assign authenticated domain. {0}' -f $_.Exception.Message) -ErrorAction Stop
            }
        }
    }
}
