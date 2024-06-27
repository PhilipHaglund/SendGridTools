function Get-SGTeammate {
    <#
    .SYNOPSIS
        Retrieves all or a specific Teammate from SendGrid.

    .DESCRIPTION
        Get-SGTeammate retrieves all or a specific Teammate from SendGrid. You can specify the specific username to retrieve.

    .PARAMETER Username
        Specifies the specific username to retrieve.

    .PARAMETER OnBehalfOf
        Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.

    .EXAMPLE
        PS C:\> Get-SGTeammate

        This command retrieves all teammates from SendGrid.

    .EXAMPLE
        PS C:\> Get-SGTeammate -Username name@example.com

        This command retrieves the specific teammate with the username'name@example.com' from SendGrid.
    #>
    [CmdletBinding()]
    param (
        # Specifies the specific username to retrieve.
        [Parameter(
            ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            Position = 0
        )]
        [string[]]$Username,

        # Specifies an On Behalf Of header to allow you to make API calls from a parent account on behalf of the parent's Subusers or customer accounts.
        [Parameter()]
        [string]$OnBehalfOf
    )
    process {
        $InvokeSplat = @{
            Method        = 'Get'
            Namespace     = "teammates"
            ErrorAction   = 'Stop'
            CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
        }
        if ($PSBoundParameters.OnBehalfOf) {
            $InvokeSplat.Add('OnBehalfOf', $OnBehalfOf)
        }

        if ($PSBoundParameters.Username) {
            foreach ($User in $Username) {
                $UserInvokeSplat = $InvokeSplat.Clone()
                $UserInvokeSplat['Namespace'] = "teammates/$User"
                try {
                    Invoke-SendGrid @EmailInvokeSplat
                }
                catch {
                    Write-Error ('Failed to retrieve SendGrid teammate. {0}' -f $_.Exception.Message) -ErrorAction Stop
                }
            }
        }
        else {
            try {
                Invoke-SendGrid @InvokeSplat
            }
            catch {
                Write-Error ('Failed to retrieve all SendGrid teammates. {0}' -f $_.Exception.Message) -ErrorAction Stop
            }
        }
    }   
}