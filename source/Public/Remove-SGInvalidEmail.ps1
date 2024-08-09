function Remove-SGInvalidEmail {
    <#
    .SYNOPSIS
        Removes a specific invalid email from SendGrid.

    .DESCRIPTION
        Remove-SGInvalidEmail removes a specific invalid email from SendGrid based on its email address.

    .PARAMETER EmailAddress
        Specifies the email address of the invalid email to remove.

    .PARAMETER OnBehalfOf
        Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.

    .EXAMPLE
        PS C:\> Remove-SGInvalidEmail -EmailAddress invalid1@example.com

        This command removes the invalid email with the email address 'invalid1@example.com' from SendGrid.

    .EXAMPLE
        PS C:\> Remove-SGInvalidEmail -EmailAddress invalid2@example.com -OnBehalfOf 'Subuser'

        This command removes the invalid email with the email address 'invalid2@example.com' from SendGrid for the Subuser 'Subuser'.
    #>
    [CmdletBinding(
        DefaultParameterSetName = 'Default',
        SupportsShouldProcess,
        ConfirmImpact = 'High'
    )]
    param (
        # Specifies the invalid email address to remove.    
        [Parameter(
            Mandatory,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            DontShow,
            ParameterSetName = 'InputObject'
        )]
        [Object[]]$InputObject,
        # Specifies the invalid email address to remove.
        [Parameter(
            Mandatory,
            ParameterSetName = 'Default',
            Position = 0
        )]
        [Alias('Email')]
        [MailAddress[]]$EmailAddress,

        # Specifies whether to delete all emails on the invalid email address list.
        [Parameter(ParameterSetName = 'DeleteAll')]
        [switch]$DeleteAll,

        # Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'DeleteAll')]
        [string]$OnBehalfOf
    )
    process {
        if ($PSCmdlet.ParameterSetName -eq 'InputObject') {
            $EmailAddress = @()
            foreach ($Object in $InputObject) {
                switch ($Object) {
                    { $_ -is [string] } { $EmailAddress += $_; break }
                    { $_ -is [System.Management.Automation.PSCustomObject] } { $UniqueId += $_.Email; break }
                    default { Write-Error ('Failed to convert InputObject to Id.') -ErrorAction Stop }
                }
            }            
        }
        if ($PSCmdlet.ParameterSetName -eq 'DeleteAll') {
            $InvokeSplat = @{
                Method        = 'Delete'
                Namespace     = 'suppression/invalid_emails'
                ErrorAction   = 'Stop'
                CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
            }
            if ($PSBoundParameters.OnBehalfOf) {
                $InvokeSplat.Add('OnBehalfOf', $OnBehalfOf)
            }
            if ($PSCmdlet.ShouldProcess('Remove all invalid email addresses from SendGrid')) {
                try {
                    Invoke-SendGrid @InvokeSplat
                }
                catch {
                    Write-Error ('Failed to remove all SendGrid invalid email address. {0}' -f $_.Exception.Message) -ErrorAction Stop
                }
            }
        }
        else {
            foreach ($Id in $EmailAddress) {
                $InvokeSplat = @{
                    Method        = 'Delete'
                    Namespace     = "suppression/invalid_emails/$($Id.Address)"
                    ErrorAction   = 'Stop'
                    CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
                }
                if ($PSBoundParameters.OnBehalfOf) {
                    $InvokeSplat.Add('OnBehalfOf', $OnBehalfOf)
                }
                if ($PSCmdlet.ShouldProcess(('Remove invalid email address {0}' -f $Id.Address))) {
                    try {
                        Invoke-SendGrid @InvokeSplat
                    }
                    catch {
                        Write-Error ('Failed to remove SendGrid invalid email address "{0}". {0}' -f $Id.Address, $_.Exception.Message) -ErrorAction Stop
                    }
                }
            }
        }
    }
}