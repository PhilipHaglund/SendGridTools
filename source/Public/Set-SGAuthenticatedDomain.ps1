function Set-SGAuthenticatedDomain {
    <#
    .SYNOPSIS
        Sets properties for an Authenticated Domain within the current SendGrid instance.
    .DESCRIPTION
        Set-SGAuthenticatedDomain sets properties for an authenticated domain in the current SendGrid instance. This can include setting the domain as the default sending domain or setting a custom SPF record. You must provide the unique identifier of the domain to modify.
    .PARAMETER UniqueId
        Specifies the unique identifier for the authenticated domain to modify.
    .PARAMETER SetDefault
        Specifies whether to set the authenticated domain as the default sending domain.
    .PARAMETER SetCustomSPF
        Specifies whether to set a custom SPF record for the authenticated domain.
    .EXAMPLE
        PS C:\> Set-SGAuthenticatedDomain -UniqueId '1234567' -SetDefault
        Sets the authenticated domain with the unique identifier '1234567' as the default sending domain.
    .EXAMPLE
        PS C:\> Set-SGAuthenticatedDomain -UniqueId '1234567' -SetCustomSPF
        Sets a custom SPF record for the authenticated domain with the unique identifier '1234567'.
    .NOTES
        To use this function, you must be connected to a SendGrid instance. Use the Connect-SendGrid function to establish a connection.
    #>
    [CmdletBinding(
        SupportsShouldProcess
    )]
    param (
        # Specifies the unique identifier for the authenticated domain to modify.
        [Parameter(
            Mandatory,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            DontShow,
            ParameterSetName = 'InputObject'
        )]
        [Object[]]$InputObject,
        # Specifies the unique identifier for the authenticated domain to modify.
        [Parameter(
            Mandatory,
            Position = 0,
            ParameterSetName = 'UniqueId'
        )]
        [Alias('Id')]
        [string[]]$UniqueId,
        
        # Specifies whether to set the authenticated domain as the default sending domain.
        [Parameter()]
        [switch]$SetDefault,

        # Specifies whether to set a custom SPF record for the authenticated domain.
        [Parameter()]
        [switch]$SetCustomSPF,

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
        foreach ($UniqueId in $Id) { 
            $InvokeSplat = @{
                Method        = 'Patch'
                Namespace     = "whitelabel/domains/$UniqueId"
                ErrorAction   = 'Stop'
                CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
            }
            $ContentBody = @{}
            if ($SetDefault) {
                $ContentBody.Add('default', $true)
            }
            if ($SetCustomSPF) {
                $ContentBody.Add('custom_spf', $true)
            }
            if ($PSBoundParameters.OnBehalfOf) {
                $InvokeSplat.Add('OnBehalfOf', $OnBehalfOf)
            }
            $InvokeSplat.Add('ContentBody', $ContentBody)
            if ($PSCmdlet.ShouldProcess(('Authenticated Domain {0}' -f $UniqueId))) {
                try {
                    Invoke-SendGrid @InvokeSplat
                }
                catch {
                    Write-Error ('Failed to set properties for SendGrid Authenticated Domain. {0}' -f $_.Exception.Message) -ErrorAction Stop
                }
            }
        }
    }
}