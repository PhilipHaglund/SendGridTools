function New-SGSubuser {
    <#
    .SYNOPSIS
        Creates a new Subuser within the current SendGrid instance.

    .DESCRIPTION
        New-SGSubuser creates a new Subuser within the current SendGrid instance. 
        The Subuser is created with the provided username and email address to contact this subuser.

    .PARAMETER Username
        Specifies the ID of a specific Subuser to retrieve. If this parameter is not provided, all Subusers are retrieved.

    .PARAMETER Email
        Specifies the email address to contact this subuser.
    .PARAMETER Password
        Specifies the password for the Subuser to create.

    .PARAMETER Ips
        Specifies the IP addresses that you would like to allow this Subuser to access.

    .EXAMPLE
        PS C:\> New-SGSubuser -Username <username> -Email <email> -Password <securestring> -Ips <ipaddress>
        
        This command creates a new Subuser with the specified username, email address, password, and IP address within the current SendGrid instance.

    .NOTES
        To use this function, you must be connected to a SendGrid instance. Use the Connect-SendGrid function to establish a connection.

    #>
    [CmdletBinding(
        SupportsShouldProcess
    )]
    param (

        # Specifies the username for the Subuser to create.
        [Parameter(
            Mandatory,
            ValueFromPipelineByPropertyName,
            Position = 0
        )]
        [string]$Username,

        # Specifies the email address to contact this subuser.
        [Parameter(
            Mandatory,
            ValueFromPipelineByPropertyName,
            Position = 1
        )]
        [MailAddress]$Email,

        # Specifies the password for the Subuser to create.
        [Parameter(
            Mandatory,
            ValueFromPipelineByPropertyName,
            Position = 2
        )]
        [SecureString]$Password,

        # Specifies the IP addresses that you would like to allow this Subuser to access.
        [Parameter(
            Mandatory,
            ValueFromPipelineByPropertyName,
            Position = 3
        )]
        [IPAddress[]]$Ips

    )

    begin {
        [hashtable]$ContentBody = [ordered]@{
            username = $Username
            email    = $Email.Address
            password = (ConvertFrom-SecureString -SecureString $Password -AsPlainText)
            ips      = @($IPs.IPAddressToString)
        }
    }
    process {
        $InvokeSplat = @{
            Method        = 'Post'
            Namespace     = 'subusers'
            ErrorAction   = 'Stop'
            CallingCmdlet = $PSCmdlet.MyInvocation.MyCommand.Name
        } 

        $InvokeSplat.Add('ContentBody', $ContentBody)
        if ($PSCmdlet.ShouldProcess($Username)) {
            try {
                $InvokeSplat
                Invoke-SendGrid @InvokeSplat
            }
            catch {
                Write-Error ('Failed to create SendGrid Subuser. {0}' -f $_.Exception.Message) -ErrorAction Stop
            }
        }
    }
}