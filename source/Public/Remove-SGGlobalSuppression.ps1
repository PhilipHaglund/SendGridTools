function Remove-SGGlobalSuppression {
    <#
    .SYNOPSIS
        Removes a specific email address from the global suppressions list in SendGrid.

    .DESCRIPTION
        Remove-SGSGlobalSuppression removes a specific email address from the global suppressions list in SendGrid.

    .PARAMETER EmailAddress
        Specifies the email address to remove from the global suppressions list.

    .PARAMETER OnBehalfOf
        Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.

    .EXAMPLE
        PS C:\> Remove-SGSGlobalSuppression -EmailAddress 'test@example.com'
        This command removes the email address 'test@example.com' from the global suppressions list in SendGrid.

    .EXAMPLE
        PS C:\> Remove-SGSGlobalSuppression -EmailAddress 'test@example.com' -OnBehalfOf 'Subuser'
        This command removes the email address 'test@example.com' from the global suppressions list in SendGrid for the Subuser 'Subuser'.
    #>
    [CmdletBinding(
        SupportsShouldProcess,
        ConfirmImpact = 'High',
        DefaultParameterSetName = 'Default'
    )]
    param (
        # Specifies the email address to remove from the global suppressions list.
        [Parameter(
            Mandatory,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            DontShow,
            ParameterSetName = 'InputObject'
        )]
        [Object[]]$InputObject,
        
        # Specifies the email address to remove from the global suppressions list.
        [Parameter(
            Mandatory,
            ParameterSetName = 'Default',
            Position = 0
        )]
        [Alias('Email')]
        [MailAddress[]]$EmailAddress,

        # Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'InputObject')]
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
        foreach ($Id in $EmailAddress) {
            $InvokeSplat = @{
                Method        = 'Delete'
                Namespace     = "suppression/unsubscribes/$Id"
                ErrorAction   = 'Stop'
                CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
            }
            if ($PSBoundParameters.OnBehalfOf) {
                $InvokeSplat.Add('OnBehalfOf', $OnBehalfOf)
            }
            if ($PSCmdlet.ShouldProcess(('Remove email address {0} from global suppressions list.' -f $Id))) {
                try {
                    Invoke-SendGrid @InvokeSplat
                }
                catch {
                    Write-Error ('Failed to remove email address "{0}" from global suppressions list. {0}' -f $Id, $_.Exception.Message) -ErrorAction Stop
                }
            }
        }
    }
}
