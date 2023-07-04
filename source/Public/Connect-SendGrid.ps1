function Connect-SendGrid {
    <#
    .SYNOPSIS
        Establishes a connection with a SendGrid instance.
        
    .DESCRIPTION
        Connect-SendGrid, or its alias Connect-SG, initiates a connection with a SendGrid instance using an API key as the credential.
        If a connection already exists, it ensures that the connection is active. If not, it creates a new connection.

    .PARAMETER Credential
        Specifies the API key to use when connecting to the SendGrid instance. While the username is always 'apikey' in a SendGrid API connection, 
        the password in this context would be your specific SendGrid API key. 

    .EXAMPLE
        PS C:\> Connect-SendGrid -Credential $myCred
        
        This command attempts to establish a connection to SendGrid using the API key stored in $myCred.

    .NOTES
        A SendGrid API key is required to make a successful connection. Ensure your API key has adequate permissions for the tasks you intend to perform.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [Alias('Connect-SG')]
    param (
        # Username is does not matter. Use 'apikey' if unsure when connecting to SendGrid using API.
        [Parameter()]
        [AllowNull()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential = [System.Management.Automation.PSCredential]
    )
    
    process {
        if ($PSCmdlet.ShouldProcess($Credential)) {
            if ($script:Session -is [PSSendGridSession]) {
                $script:Session.Connect()
            }
            else {
                $script:Session = [PSSendGridSession]::new()
                $script:Session.Connect($Credential)
            }
        }
    }
}