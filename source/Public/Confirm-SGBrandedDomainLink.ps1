function Confirm-SGBrandedDomainLink {
    <#
    .SYNOPSIS
        Validates the branded domain links within the current SendGrid instance.
        
    .DESCRIPTION
        Confirm-SGBrandedDomainLink is used to validate the branded domain links within the current SendGrid instance.
        An authenticated domain allows you to remove the "via”" or "sent on behalf of" message that your recipients see when they read your emails.
        Authenticating a domain allows you to replace sendgrid.net with your personal sending domain.
        You will be required to create a subdomain so that SendGrid can generate the DNS records which you must give to your host provider.

        This function should be executed after the external DNS records have been applied.

    .PARAMETER UniqueId
        Specifies the unique ID of the branded link to validate. This parameter is mandatory.

    .EXAMPLE
        PS C:\> Confirm-SGBrandedDomainLink -UniqueId '1234567'
        
        This command validates the branded domain link with the unique ID '1234567' in the current SendGrid instance.
    
    .NOTES
        This function requires an active SendGrid instance to work properly. Make sure to check the validity of the UniqueId parameter.
    #>
    [CmdletBinding(
        SupportsShouldProcess
    )]
    param (
        # Specifies the unique ID of the branded link to validate. This parameter is mandatory.
        [Parameter(
            Mandatory,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            DontShow,
            ParameterSetName = 'InputObject'
        )]
        [Object[]]$InputObject,
        
        # Specifies the unique ID of the branded link to validate. This parameter is mandatory.
        [Parameter(
            Mandatory,
            Position = 0,
            ParameterSetName = 'UniqueId'
        )]
        [Alias('Id')]
        [string[]]$UniqueId,

        # Specifies a On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
        [Parameter()]
        [string]$OnBehalfOf
    )   
    process {
        if ($PSCmdlet.ParameterSetName -eq 'InputObject') {
            $UniqueId = @()
            foreach ($Object in $InputObject) {
                switch ($Object) {
                    { $_ -is [string] } { $UniqueId += $_; break }
                    { $_ -is [int] } { $UniqueId += $_; break }
                    { $_ -is [System.Management.Automation.PSCustomObject] } { $UniqueId += $_.Id; break }
                    default { Write-Error ('Failed to convert InputObject to Id.') -ErrorAction Stop }
                }
            }            
        }
        foreach ($Id in $UniqueId) {
            $InvokeSplat = @{
                Method        = 'Post'
                Namespace     = "whitelabel/links/$Id/validate"
                ErrorAction   = 'Stop'
                CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
            }
            $GetSplat = @{
                UniqueId    = $Id
                ErrorAction = 'Stop'
            }
            if ($PSBoundParameters.OnBehalfOf) {
                $InvokeSplat.Add('OnBehalfOf', $OnBehalfOf)
                $GetSplat.Add('OnBehalfOf', $OnBehalfOf)
            }
            $SGBrandedDomainLink = Get-SGBrandedDomainLink @GetSplat
            $SGBrandedDomainLink

            if ($PSCmdlet.ShouldProcess(('{0}.{1}' -f $SGBrandedDomainLink.Subdomain, $SGBrandedDomainLink.Domain))) {

                if ($SGBrandedDomainLink.Valid -eq $true) {
                    Write-Verbose -Message ('Branded Link Domain already validated!') -Verbose
                }
                else {
                    try {
                        Invoke-SendGrid @InvokeSplat
                    }
                    catch {
                        Write-Error ('Failed to validate SendGrid Branded Domain Link. {0}' -f $_.Exception.Message) -ErrorAction Stop
                    }
                }
            }
        }
    }
}