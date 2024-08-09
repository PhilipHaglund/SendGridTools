function Set-SGBrandedDomainLink {
    <#
    .SYNOPSIS
        Sets properties for a Branded Domain Link within the current SendGrid instance.
    .DESCRIPTION
        Set-SGBrandedDomainLink sets properties for a branded domain link in the current SendGrid instance. This can include setting the link as the default branded domain link. You must provide the unique identifier of the domain link to modify.
    .PARAMETER UniqueId
        Specifies the unique identifier for the branded domain link to modify.
    .PARAMETER SetDefault
        Specifies whether to set the branded domain link as the default.
    .EXAMPLE
        PS C:\> Set-SGBrandedDomainLink -UniqueId '1234567' -SetDefault
        Sets the branded domain link with the unique identifier '1234567' as the default branded domain link.
    .NOTES
        To use this function, you must be connected to a SendGrid instance. Use the Connect-SendGrid function to establish a connection.
    #>
    [CmdletBinding(
        SupportsShouldProcess
    )]
    param (
        # Specifies the unique identifier for the branded domain link to modify.    
        [Parameter(
            Mandatory,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            DontShow,
            ParameterSetName = 'InputObject'
        )]
        # Specifies the unique identifier for the branded domain link to modify.
        [Parameter(
            Mandatory,
            Position = 0,
            ParameterSetName = 'UniqueId'
        )]
        [Alias('Id')]
        [string[]]$UniqueId,
        
        # Specifies whether to set the branded domain link as the default.
        [Parameter()]
        [switch]$SetDefault,
        
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
                Method        = 'Patch'
                Namespace     = "whitelabel/links/$Id"
                ErrorAction   = 'Stop'
                CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
            }
            $ContentBody = @{}
            if ($SetDefault) {
                $ContentBody.Add('default', $true)
            }
            if ($PSBoundParameters.OnBehalfOf) {
                $InvokeSplat.Add('OnBehalfOf', $OnBehalfOf)
            }
            $InvokeSplat.Add('ContentBody', $ContentBody)
            if ($PSCmdlet.ShouldProcess(('Branded Domain Link {0}' -f $Id))) {
                    try {
                        Invoke-SendGrid @InvokeSplat
                    }
                    catch {
                        Write-Error ('Failed to set properties for SendGrid Branded Domain Link. {0}' -f $_.Exception.Message) -ErrorAction Stop
                    }
                }
            }
        }
    }