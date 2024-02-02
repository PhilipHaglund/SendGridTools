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
            ValueFromPipelineByPropertyName
        )]
        [string]$Username,

        # Specifies the email address to contact this subuser.
        [Parameter(
            Mandatory,
            ValueFromPipelineByPropertyName
        )]
        [MailAddress]$Email,

        # Specifies the password for the Subuser to create.
        [Parameter(
            Mandatory,
            ValueFromPipelineByPropertyName
        )]
        [SecureString]$Password,

        # Specifies the IP addresses that you would like to allow this Subuser to access.
        [Parameter(
            Mandatory,
            ValueFromPipelineByPropertyName
        )]
        [IPAddress[]]$Ips

    )

    begin {
        [hashtable]$ContentBody = @{
            username = $Username
            email    = $Email
            password = (ConvertFrom-SecureString -SecureString $Password -AsPlainText)
            ips      = @($Ips)
        }
    }
    process {
        $InvokeSplat = @{
            Method      = 'Post'
            Namespace   = 'subusers'
            ErrorAction = 'Stop'
        } 

        $InvokeSplat.Add('ContentBody', $ContentBody)
        if ($PSCmdlet.ShouldProcess($Username)) {
            try {
                #Invoke-SendGrid @InvokeSplat
                $InvokeSplat
            }
            catch {
                Write-Error ('Failed to create SendGrid Subuser. {0}' -f $_.Exception.Message) -ErrorAction Stop
            }
        }
    }
}

#{ 'ips':["167.89.80.214"], 'username':"kalletest_omnicit", 'email':"philip@gonjer.com", 'password':"Gonjer.com123!"#","passwordConfirm":"Gonjer.com123!\"#" }