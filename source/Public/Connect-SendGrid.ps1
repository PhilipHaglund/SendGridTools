function Connect-SendGrid {
    <#
    .SYNOPSIS
        Establishes a connection with a SendGrid instance.

    .DESCRIPTION
        Connect-SendGrid, or its alias Connect-SG, initiates a connection with a SendGrid instance using an API key as the credential.
        If a connection already exists, it ensures that the connection is active, on that session's own host. If not, it creates a new connection,
        on the global host unless Region or BaseUri says otherwise. Region or BaseUri naming another host than the current session starts a new
        session and asks for the key when Credential and ApiKey are not given; if that connection fails, no session is left. In a host that cannot
        prompt (a console host started with -NonInteractive, not user interactive, or without a user interface), a new session without
        Credential or ApiKey is refused with an error, and Get-Credential is not called. -NonInteractive counts only in the console host: a
        host with its own user interface (for example Visual Studio Code) prompts as before, and a remote session leaves the prompt to the
        client. On Linux and macOS only -NonInteractive is recognised, because .NET reports every process there as user interactive, so start
        a cron or systemd job with pwsh -NonInteractive or pass -ApiKey.

    .PARAMETER Credential
        Specifies the API key to use when connecting to the SendGrid instance. The 'Username' field of the PSCredential object does not matter,
        and can be set to any string. The 'Password' field of the PSCredential object should be set to the SendGrid API key.

    .PARAMETER ApiKey
        Specifies the API key as a secure string, for a host that cannot prompt. It becomes a credential with the user name 'apikey'. It cannot be
        combined with Credential. On a refresh of an existing session on the same host it is ignored, as Credential is.

    .PARAMETER Force
        Indicates that this cmdlet forces a new connection, even if a connection already exists.

    .PARAMETER Region
        Specifies the SendGrid region to connect to, Global or EU. Global is the default for a new session. Use EU for an account that is hosted on the
        EU host. It cannot be combined with BaseUri.

    .PARAMETER BaseUri
        Specifies an explicit SendGrid API address to use instead of a region. Only https is accepted, and '/v3' is appended when the
        path does not end with it. It cannot be combined with Region.

    .EXAMPLE
        PS C:\> Connect-SendGrid -Credential $myCred

        This command attempts to establish a connection to SendGrid using the API key stored in $myCred.

    .EXAMPLE
        PS C:\> Connect-SendGrid -Credential $myCred -Region EU

        This command selects the EU region for the connection, using the API key stored in $myCred.

    .EXAMPLE
        PS C:\> Connect-SendGrid -Credential $myCred -BaseUri 'https://proxy.example.com/sendgrid'

        This command connects through an explicit base address. '/v3' is appended, so requests go to https://proxy.example.com/sendgrid/v3.

    .EXAMPLE
        PS C:\> $Key = ConvertTo-SecureString -String $env:SENDGRID_API_KEY -AsPlainText -Force
        PS C:\> Connect-SendGrid -ApiKey $Key

        This command connects with an API key that was read from an environment variable (or a vault) as a secure string, without a prompt.
        Use it in a script that runs unattended.

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

        In addition, the SendGridSession class has a built-in mechanism to limit session lifetime. It tracks the time when the session was last created
        or last used by a successful request, and if more than one hour has passed since then, the class automatically disconnects the session.
        This also removes the stored credential (API key) from memory. If you attempt to interact with the SendGrid API after the session has expired,
        you'll need to reconnect using your credentials. This is done to help ensure the security of your API key.
    #>
    [CmdletBinding(
        DefaultParameterSetName = 'Region',
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
        [switch]$Force,

        [Parameter()]
        [ValidateNotNull()]
        [securestring]$ApiKey,

        [Parameter(
            ParameterSetName = 'Region'
        )]
        [ValidateSet('Global', 'EU')]
        [string]$Region = 'Global',

        [Parameter(
            Mandatory,
            ParameterSetName = 'BaseUri'
        )]
        [uri]$BaseUri
    )

    process {
        # Checked first, before anything is resolved or touched: an existing session stays as it is.
        if ($PSBoundParameters.ContainsKey('ApiKey')) {
            if ($PSBoundParameters.ContainsKey('Credential')) {
                Write-Error -Message 'Unable to connect to SendGrid. Error detail: Use either -Credential or -ApiKey, not both.' -ErrorAction Stop
            }
            $Credential = [System.Management.Automation.PSCredential]::new('apikey', $ApiKey)
        }

        # Resolve before anything else: a bad -BaseUri must neither reach the network nor disturb an existing session.
        try {
            $ResolveParams = @{ Region = $Region }
            if ($PSBoundParameters.ContainsKey('BaseUri')) {
                $ResolveParams['BaseUri'] = $BaseUri
            }
            $Target = Resolve-SendGridBaseUri @ResolveParams
        }
        catch {
            Write-Error -Message ('Unable to connect to SendGrid. Error detail: {0}' -f $_.Exception.Message) -ErrorAction Stop
        }

        # A new session is built when forced, when none exists, or when -Region/-BaseUri names another host than the session's.
        $NewSession = $Force -or -not $script:Session -or -not ($script:Session -is [SendGridSession])
        if (-not $NewSession -and ($PSBoundParameters.ContainsKey('Region') -or $PSBoundParameters.ContainsKey('BaseUri'))) {
            $NewSession = -not [string]::Equals($script:Session._BaseURL.AbsoluteUri, $Target.AbsoluteUri, [System.StringComparison]::OrdinalIgnoreCase)
        }

        # Outside the try, so the catch below never removes an existing session; also under -WhatIf.
        if ($NewSession -and -not $Credential -and -not (Test-SendGridHostCanPrompt)) {
            Write-Error -Message 'Unable to connect to SendGrid. Error detail: This PowerShell host cannot prompt for the API key. Use -Credential or -ApiKey.' -ErrorAction Stop
        }

        try {
            if ($PSCmdlet.ShouldProcess('SendGrid Session', 'Connect')) {
                if ($NewSession) {
                    $script:Session = [SendGridSession]::new($Target)
                    if ($Credential) {
                        $script:Session.Connect($Credential)
                    }
                    else {
                        $script:Session.Connect((Get-Credential -Message 'Enter your ApiKey' -UserName 'apikey')) # Removed -Title 'Connect-SendGrid' to make it PowerShell 5.1 compatible
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