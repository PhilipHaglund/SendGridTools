function Connect-SendGrid {
    <#
    .SYNOPSIS
        Establishes a connection with a SendGrid instance.
        
    .DESCRIPTION
        Connect-SendGrid, or its alias Connect-SG, initiates a connection with a SendGrid instance using an API key as the credential.
        If a connection already exists, it ensures that the connection is active. If not, it creates a new connection.

    .PARAMETER Credential
        Specifies the API key to use when connecting to the SendGrid instance. The 'Username' field of the PSCredential object does not matter, 
        and can be set to any string. The 'Password' field of the PSCredential object should be set to the SendGrid API key.

    .PARAMETER Force
        Indicates that this cmdlet forces a new connection, even if a connection already exists.

    .EXAMPLE
        PS C:\> Connect-SendGrid -Credential $myCred

        This command attempts to establish a connection to SendGrid using the API key stored in $myCred.

    .EXAMPLE
        PS C:\> Connect-SendGrid

        This command attempts to establish a connection to SendGrid. It will prompt for the API key since no credential was supplied.

    .EXAMPLE
        PS C:\> Connect-SendGrid -Force

        This command attempts to forcefully establish a new connection to SendGrid. It will prompt for the API key.

    .EXAMPLE
        PS C:\> Connect-SendGrid -Credential $myCred -Force

        This command attempts to forcefully establish a new connection to SendGrid using the API key stored in $myCred. 
        Even if a connection already exists, it will create a new one.

    .NOTES
        A SendGrid API key is required to make a successful connection. Ensure your API key has adequate permissions for the tasks you intend to perform.
        The API key should be provided as the 'Password' field of the PSCredential object.

        The provided API key (credential) is stored in a script-scoped variable within the module. This means it's only accessible by functions 
        within the same module and not accessible externally by other scripts or modules. This provides a degree of isolation and security.

        PowerShell does not store script or private variables in plain text in memory, but rather as secure strings, which means the actual API key 
        is not easily retrievable through memory inspection tools. However, please note that this doesn't provide complete security. In environments 
        where highly sensitive information is handled, it's recommended to use more secure methods of storing and using credentials, such as Azure Key Vault.

        The API key stored in the session will persist only as long as the PowerShell session remains active. 
        Once the PowerShell session is closed, the variable storing the API key is discarded.

        In addition, the PSSendGridSession class has a built-in mechanism to limit session lifetime. It tracks the time when the session was last created
        or refreshed, and if the last successful connection attempt was more than 12 hours ago, the class automatically disconnects the session. 
        This also removes the stored credential (API key) from memory. If you attempt to interact with the SendGrid API after the session has expired, 
        you'll need to reconnect using your credentials. This is done to help ensure the security of your API key.
    #>
    [CmdletBinding(
        SupportsShouldProcess
    )]
    [Alias('Connect-SG')]
    param (
        # Username does not matter. Use 'apikey' if unsure when connecting to SendGrid using API.
        [Parameter(
            Position = 0
        )]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]$Credential,

        [Parameter(
            Position = 1
        )]
        [switch]$Force
    )
    
    process {
        try {
            if ($PSCmdlet.ShouldProcess('SendGrid Session', 'Connect')) {
                if ($Force -or -not $script:Session -or -not ($script:Session -is [PSSendGridSession])) {
                    $script:Session = [PSSendGridSession]::new()
                    if ($Credential) {
                        $script:Session.Connect($Credential)
                    }
                    else {
                        $script:Session.Connect((Get-Credential -Message 'Enter your ApiKey' -UserName 'apikey' -Title 'Connect-SendGrid'))
                    }
                    Write-Verbose -Message 'Connection to SendGrid established.' -Verbose
                }
                else {
                    $script:Session.Connect()
                    Write-Verbose -Message 'Existing connection to SendGrid refreshed.' -Verbose
                }
            }
        }
        catch {
            if ($script:Session) {
                Write-Verbose -Message 'Encountered an error while connecting to SendGrid. Cleaning up...'
            }
            Remove-Variable -Name Session -Scope Script
            Write-Error -Message ('Unable to connect to SendGrid. Error detail: {0}' -f $_.Exception.Message) -ErrorAction Stop
        }
    }
}