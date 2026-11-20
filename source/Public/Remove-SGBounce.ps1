function Remove-SGBounce {
    <#
    .SYNOPSIS
        Removes a specific bounce from SendGrid.

    .DESCRIPTION
        Remove-SGBounce removes a specific bounce from SendGrid based on its email address.

    .PARAMETER EmailAddress
        Specifies the email address of the bounce to remove.

    .PARAMETER OnBehalfOf
        Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.

    .PARAMETER DeleteAll
        Specifies whether to delete all emails on the bounces list.

    .PARAMETER InputObject
        Specifies one or more objects to remove, typically received from the pipeline. Each object can be an email address given as a string, or an object with an Email property, such as the output of Get-SGBounce. Use EmailAddress to specify the addresses directly.

    .EXAMPLE
        PS C:\> Remove-SGBounce -EmailAddress "bounce1@example.com"

        This command removes the bounce with the email address 'bounce1@example.com' from SendGrid.

    .EXAMPLE
        PS C:\> Remove-SGBounce -EmailAddress "bounce2@example.com" -OnBehalfOf 'Subuser'

        This command removes the bounce with the email address 'bounce2@example.com' from SendGrid for the Subuser 'Subuser'.

    .EXAMPLE
        PS C:\> Remove-SGBounce -DeleteAll

        This command deletes all emails on the bounces list from SendGrid.
    #>
    [CmdletBinding(
        DefaultParameterSetName = 'Default',
        SupportsShouldProcess,
        ConfirmImpact = 'High'
    )]
    param (
        # Specifies the email address of the bounce to remove.
        [Parameter(
            Mandatory,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            DontShow,
            ParameterSetName = 'InputObject'
        )]
        [Object[]]$InputObject,

        # Specifies the email address of the bounce to remove.
        [Parameter(
            Mandatory,
            ParameterSetName = 'Default',
            Position = 0
        )]
        [Alias('Email')]
        [MailAddress[]]$EmailAddress,

        # Specifies whether to delete all emails on the bounces list.
        [Parameter(ParameterSetName = 'DeleteAll')]
        [switch]$DeleteAll,

        # Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
        [Parameter(ParameterSetName = 'Default')]
        [Parameter(ParameterSetName = 'DeleteAll')]
        [Parameter(ParameterSetName = 'InputObject')]
        [string]$OnBehalfOf
    )
    process {
        if ($PSCmdlet.ParameterSetName -eq 'InputObject') {
            $EmailAddress = @()
            foreach ($Object in $InputObject) {
                switch ($Object) {
                    { $_ -is [string] } { $EmailAddress += $_; break }
                    { $_ -is [System.Management.Automation.PSCustomObject] } {
                        $EmailProperty = $_.PSObject.Properties['Email']
                        if ($null -eq $EmailProperty -or [string]::IsNullOrWhiteSpace([string]$EmailProperty.Value)) {
                            Write-Error ('InputObject has no Email property; pass an email address or an object with an Email property.') -ErrorAction Stop
                        }
                        $EmailAddress += $EmailProperty.Value
                        break
                    }
                    default { Write-Error ('Failed to convert InputObject to an email address.') -ErrorAction Stop }
                }
            }
        }
        if ($PSCmdlet.ParameterSetName -eq 'DeleteAll') {
            $InvokeSplat = @{
                Method        = 'Delete'
                Namespace     = 'suppression/bounces'
                ErrorAction   = 'Stop'
                CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
            }
            if ($PSBoundParameters.OnBehalfOf) {
                $InvokeSplat.Add('OnBehalfOf', $OnBehalfOf)
            }
            if ($PSCmdlet.ShouldProcess('Remove all bounces from SendGrid')) {
                try {
                    Invoke-SendGrid @InvokeSplat
                }
                catch {
                    Write-Error -Exception (ConvertTo-SendGridCommandException -Message ('Failed to remove all SendGrid bounces. {0}' -f $_.Exception.Message) -ErrorRecord $_) -ErrorAction Stop
                }
            }
        }
        foreach ($Id in $EmailAddress) {
            $InvokeSplat = @{
                Method        = 'Delete'
                Namespace     = "suppression/bounces/$((ConvertTo-SendGridUriComponent $Id.Address))"
                ErrorAction   = 'Stop'
                CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
            }
            if ($PSBoundParameters.OnBehalfOf) {
                $InvokeSplat.Add('OnBehalfOf', $OnBehalfOf)
            }
            if ($PSCmdlet.ShouldProcess(('Remove bounce with email address {0}' -f $Id.Address))) {
                try {
                    Invoke-SendGrid @InvokeSplat
                }
                catch {
                    Write-Error -Exception (ConvertTo-SendGridCommandException -Message ('Failed to remove SendGrid bounce "{0}". {1}' -f $Id.Address, $_.Exception.Message) -ErrorRecord $_) -ErrorAction Stop
                }
            }
        }
    }
}