function Set-SGAuthenticatedDomainToSubUser {
    <#
    .SYNOPSIS
        Assign a specified Authenticated Domain to a subuser.

    .DESCRIPTION
        Authenticated domains can be associated with (i.e. assigned to) subusers from a parent account.
        This functionality allows subusers to send mail using their parent's domain authentication.
        To associate an authenticated domain with a subuser, the parent account must first authenticate and validate the domain.
        The parent may then associate the authenticated domain via the subuser management tools.

    .PARAMETER UnqieId
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

        # Specifies the ID of a specific API Key to retrieve. If this parameter is not provided, all API Keys are retrieved.
        [Parameter(
            Mandatory,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName
        )]
        [string]$UniqueId,

        # Specifies username of the subuser to assign the authenticated domain to.
        [Parameter(
            Mandatory
        )]
        [string]$UserName
    )
    process {
        $InvokeSplat = @{
            Method      = 'Post'
            Namespace   = "whitelabel/domains/$UniqueId/subuser"
            ErrorAction = 'Stop'
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
                
                $InvokeResult = Invoke-SendGrid @InvokeSplat
                if ($InvokeResult.Errors.Count -gt 0) {
                    throw $InvokeResult.Errors.Message
                }
                else {
                    $InvokeResult
                }
            }
            catch {
                Write-Error ('Failed to assign authenticated domain. {0}' -f $_.Exception.Message) -ErrorAction Stop
            }
        }
    }
}
