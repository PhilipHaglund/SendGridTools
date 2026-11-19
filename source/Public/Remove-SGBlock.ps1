function Remove-SGBlock {
    <#
    .SYNOPSIS
        Removes a specific block from SendGrid.

    .DESCRIPTION
        Remove-SGBlock removes a specific block from SendGrid based on its email address.

    .PARAMETER EmailAddress
        Specifies the email address of the block to remove.

    .PARAMETER OnBehalfOf
        Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.

    .PARAMETER InputObject
        Specifies one or more objects to remove, typically received from the pipeline. Each object can be an email address given as a string, or an object with an Email property, such as the output of Get-SGBlock. Use EmailAddress to specify the addresses directly.

    .PARAMETER DeleteAll
        Specifies that all entries on the blocks list are deleted instead of single email addresses. This parameter cannot be combined with EmailAddress.

    .EXAMPLE
        PS C:\> Remove-SGBlock -EmailAddress "block1@example.com"

        This command removes the block with the email address 'block1@example.com' from SendGrid.

    .EXAMPLE
        PS C:\> Remove-SGBlock -EmailAddress "block2@example.com" -OnBehalfOf 'Subuser'

        This command removes the block with the email address 'block2@example.com' from SendGrid for the Subuser 'Subuser'.
    #>
    [CmdletBinding(
        DefaultParameterSetName = 'Default',
        SupportsShouldProcess,
        ConfirmImpact = 'High'
    )]
    param (
        # Specifies the email address of the block to remove.
        [Parameter(
            Mandatory,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            DontShow,
            ParameterSetName = 'InputObject'
        )]
        [Object[]]$InputObject,

        # Specifies the email address of the block to remove.
        [Parameter(
            Mandatory,
            ParameterSetName = 'Default',
            Position = 0
        )]
        [Alias('Email')]
        [MailAddress[]]$EmailAddress,

        # Specifies whether to delete all emails on the blocks list.
        [Parameter(
            ParameterSetName = 'DeleteAll',
            Mandatory,
            Position = 0
        )]
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
                Namespace     = 'suppression/blocks'
                ErrorAction   = 'Stop'
                CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
            }
            if ($PSBoundParameters.OnBehalfOf) {
                $InvokeSplat.Add('OnBehalfOf', $OnBehalfOf)
            }
            if ($PSCmdlet.ShouldProcess('Remove all blocks from SendGrid')) {
                try {
                    Invoke-SendGrid @InvokeSplat
                }
                catch {
                    Write-Error ('Failed to remove all SendGrid blocks. {0}' -f $_.Exception.Message) -ErrorAction Stop
                }
            }
        }
        else {
            foreach ($Id in $EmailAddress) {
                $InvokeSplat = @{
                    Method        = 'Delete'
                    Namespace     = "suppression/blocks/$([uri]::EscapeDataString($Id.Address))"
                    ErrorAction   = 'Stop'
                    CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
                }
                if ($PSBoundParameters.OnBehalfOf) {
                    $InvokeSplat.Add('OnBehalfOf', $OnBehalfOf)
                }
                if ($PSCmdlet.ShouldProcess(('Remove block with email address {0}' -f $Id.Address))) {
                    try {
                        Invoke-SendGrid @InvokeSplat
                    }
                    catch {
                        Write-Error ('Failed to remove SendGrid block "{0}". {1}' -f $Id.Address, $_.Exception.Message) -ErrorAction Stop
                    }
                }
            }
        }
    }
}