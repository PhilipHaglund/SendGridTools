# The SendGridSession class manages a SendGrid session for the user. 
class SendGridSession {
    # URL endpoint to the SendGrid API.
    [uri]$EndpointURL
    # Base URL to the SendGrid API. 
    hidden [uri]$_BaseURL = 'https://api.sendgrid.com/v3'
    # Specifies if the session is connected.
    hidden [bool]$_Connected = $false
    # Stores the user's SendGrid API credentials.
    hidden [PSCredential]$_Credential
    # Tracks the time when the session was created.
    hidden [DateTime]$_CreateDateTime

    # Constructor function for SendGridSession.
    SendGridSession () {
        $null = [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    }
    
    <#
    .SYNOPSIS
        Constructs the URL for accessing the SendGrid API.

    .DESCRIPTION
        This private method builds a URL for accessing a specific resource in the SendGrid API.

    .PARAMETER Resource
        The specific resource to access in the SendGrid API.
    #>
    hidden [void]BuildEndpointURL([string]$Resource) {
        if ($null -eq $Resource -or $Resource -eq [String]::Empty) {
            # Remove old Endpoint URL to avoid old resource
            $this.EndpointURL = $null
        }
        else {
            [Text.StringBuilder]$URLBuild = [Text.StringBuilder]::new()
        
            $null = $URLBuild.Append($this._BaseURL)
            $null = $URLBuild.Append('/')
            $null = $URLBuild.Append($Resource)

            $this.EndpointURL = [uri]$URLBuild.ToString()
        }
    }

    <#
    .SYNOPSIS
        Connects to the SendGrid API.

    .DESCRIPTION
        This function establishes a connection to the SendGrid API by using the user's stored credentials.
    #>
    [void] Connect () {
        $SessionLifeTime = (Get-Date).AddHours(-1)
        if ($null -eq $this._CreateDateTime -or $SessionLifeTime -gt $this._CreateDateTime) {
            $this.Disconnect()
            throw 'Session lifetime exceeded, reconnect.'
        }
        if ($this._Credential -is [PSCredential]) {
            $this.BuildEndpointURL([string]'scopes')
            try {
                $Headers = @{
                    'Authorization' = ('Bearer {0}' -f $this._Credential.GetNetworkCredential().Password)
                    'Content-Type'  = 'application/json'
                }
                $null = Invoke-RestMethod -Method Get -Uri  $this.EndpointURL -Headers $Headers -ErrorAction Stop
                $this._Connected = $true
                $this._CreateDateTime = Get-Date # Used to refresh "session lifetime"
            }
            catch {
                $this._Connected = $false
                throw ('Unable to connect to SendGrid. {0}' -f $_.Exception.Message)
            }
        }
        else {
            $this._Connected = $false
            throw ('Unable to connect to SendGrid. No credentials saved in context.')
        }
    }
    <#
    .SYNOPSIS
        Connects to the SendGrid API with specified credentials.

    .DESCRIPTION
        This function establishes a connection to the SendGrid API by using the specified credentials.

    .PARAMETER Credential
        The user's SendGrid API credentials.
    #>
    [void] Connect ([PSCredential]$Credential) {
        $this._Credential = $Credential
        $this.BuildEndpointURL([string]'scopes')
        try {
            $Headers = @{
                'Authorization' = ('Bearer {0}' -f $this._Credential.GetNetworkCredential().Password)
                'Content-Type'  = 'application/json'
            }
            $null = Invoke-RestMethod -Method Get -Uri  $this.EndpointURL -Headers $Headers -ErrorAction Stop
            $this._Connected = $true
            $this._CreateDateTime = Get-Date
        }
        catch {
            $this._Connected = $false
            throw ('Unable to connect to SendGrid. {0}' -f $_.Exception.Message)
        }
    }

    <#
    .SYNOPSIS
        Disconnects from the SendGrid API.

    .DESCRIPTION
        This function disconnects the current session from the SendGrid API.
    #>
    [void] Disconnect () {
        $this.BuildEndpointURL($null)
        $this._Credential = $null
        $this._Connected = $false
        $this._CreateDateTime = 0
    }

    <#
    .SYNOPSIS
        Sends a query to the SendGrid API.

    .DESCRIPTION
        This method sends a query to the SendGrid API and returns the results. 

    .PARAMETER WebRequestMethod
        The HTTP method to use for the query (GET, POST, etc.).

    .PARAMETER Endpoint
        The specific endpoint in the SendGrid API to send the query to.

    .INPUTS
        Microsoft.PowerShell.Commands.WebRequestMethod, string.

    .OUTPUTS
        PSCustomObject[]
    #>
    [PSCustomObject[]] InvokeQuery ([Microsoft.PowerShell.Commands.WebRequestMethod]$WebRequestMethod, [string]$Endpoint) {
        if ($this._Connected -eq $false) {
            throw 'You must call the Connect-SendGrid cmdlet before calling any other cmdlets.'
        }
        $SessionLifeTime = (Get-Date).AddHours(-1)
        if ($null -eq $this._CreateDateTime -or $SessionLifeTime -gt $this._CreateDateTime) {
            $this.Disconnect()
            return 'Session lifetime exceeded, reconnect.'
        }
        else {
            $this.BuildEndpointURL($Endpoint)
            try {
                $Headers = @{
                    'Authorization' = "Bearer $($this._Credential.GetNetworkCredential().Password)"
                    'Content-Type'  = 'application/json'
                }
                $Query = (Invoke-RestMethod -Method $WebRequestMethod -Uri $this.EndpointURL -Headers $Headers -ErrorAction Stop)
                $this.BuildEndpointURL($null)
                $this._CreateDateTime = Get-Date
                return $Query
            }
            catch {
                $this.BuildEndpointURL($null)
                if ($null -ne $_.ErrorDetails.Message) {
                    throw ('SendGrid Error: "{0}"' -f ($_.ErrorDetails.Message | ConvertFrom-Json | Select-Object -ExpandProperty errors | Select-Object -ExpandProperty message) -join ', ' )
                }
                else {
                    throw ('Unable to query SendGrid: {0}' -f $_.Exception.Message)
                }
            }
        }
    }
    
    <#
    .SYNOPSIS
        Sends a query to the SendGrid API.

    .DESCRIPTION
        This method sends a query to the SendGrid API and returns the results. 

    .PARAMETER WebRequestMethod
        The HTTP method to use for the query (GET, POST, etc.).

    .PARAMETER Endpoint
        The specific endpoint in the SendGrid API to send the query to.

    .PARAMETER ContentBody
        The payload to send to the specified endpoint.

    .INPUTS
        Microsoft.PowerShell.Commands.WebRequestMethod, string, hashtable.

    .OUTPUTS
        PSCustomObject[]
    #>
    [PSCustomObject[]] InvokeQuery ([Microsoft.PowerShell.Commands.WebRequestMethod]$WebRequestMethod, [string]$Endpoint, [hashtable]$ContentBody) {
        foreach ($Key in $ContentBody.Keys) {
            Write-Verbose -Message ('ContentBody: Key: {0}, Value: {1}, Type:{2}' -f $Key, $ContentBody[$Key], $ContentBody[$Key].GetType())
        }
        $Body = $ContentBody | ConvertTo-Json -Depth 5 -ErrorAction Stop
        $SessionLifeTime = (Get-Date).AddHours(-1)
        if ($null -eq $this._CreateDateTime -or $SessionLifeTime -gt $this._CreateDateTime) {
            $this.Disconnect()
            return 'Session lifetime exceeded, reconnect.'
        }
        else {
            $this.BuildEndpointURL($Endpoint)
            try {
                $Headers = @{
                    'Authorization' = "Bearer $($this._Credential.GetNetworkCredential().Password)"
                    'Content-Type'  = 'application/json'
                }
                $Query = (Invoke-RestMethod -Method $WebRequestMethod -Uri $this.EndpointURL -Headers $Headers -Body $Body -ErrorAction Stop)
                $this.BuildEndpointURL($null)
                $this._CreateDateTime = Get-Date
                return $Query
            }
            catch {
                $this.BuildEndpointURL($null)
                if ($null -ne $_.ErrorDetails.Message) {
                    throw ('SendGrid Error: "{0}"' -f ($_.ErrorDetails.Message | ConvertFrom-Json | Select-Object -ExpandProperty errors | Select-Object -ExpandProperty message) -join ', ' )
                }
                else {
                    throw ('Unable to query SendGrid: {0}' -f $_.Exception.Message)
                }
            }
        }
    }

    <#
    .SYNOPSIS
        Sends a query to the SendGrid API using on behalf of.

    .DESCRIPTION
        This method sends a query to the SendGrid API and returns the results using on behalf of.

    .PARAMETER WebRequestMethod
        The HTTP method to use for the query (GET, POST, etc.).

    .PARAMETER Endpoint
        The specific endpoint in the SendGrid API to send the query to.

    .PARAMETER OnBehalfOf
        The username of the subuser to send the query on behalf of.

    .INPUTS
        Microsoft.PowerShell.Commands.WebRequestMethod, string.

    .OUTPUTS
        PSCustomObject[]
    #>
    [PSCustomObject[]] InvokeQuery ([Microsoft.PowerShell.Commands.WebRequestMethod]$WebRequestMethod, [string]$Endpoint, [string]$OnBehalfOf) {
        if ($this._Connected -eq $false) {
            throw 'You must call the Connect-SendGrid cmdlet before calling any other cmdlets.'
        }
        $SessionLifeTime = (Get-Date).AddHours(-1)
        if ($null -eq $this._CreateDateTime -or $SessionLifeTime -gt $this._CreateDateTime) {
            $this.Disconnect()
            return 'Session lifetime exceeded, reconnect.'
        }
        else {
            $this.BuildEndpointURL($Endpoint)
            try {
                $Headers = @{
                    'Authorization' = "Bearer $($this._Credential.GetNetworkCredential().Password)"
                    'on-behalf-of'  = $OnBehalfOf
                    'Content-Type'  = 'application/json'
                }
                $Query = (Invoke-RestMethod -Method $WebRequestMethod -Uri $this.EndpointURL -Headers $Headers -ErrorAction Stop)
                $this.BuildEndpointURL($null)
                $this._CreateDateTime = Get-Date
                return $Query
            }
            catch {
                $this.BuildEndpointURL($null)
                if ($null -ne $_.ErrorDetails.Message) {
                    throw ('SendGrid Error: "{0}"' -f ($_.ErrorDetails.Message | ConvertFrom-Json | Select-Object -ExpandProperty errors | Select-Object -ExpandProperty message) -join ', ' )
                }
                else {
                    throw ('Unable to query SendGrid: {0}' -f $_.Exception.Message)
                }
            }
        }
    }

    <#
    .SYNOPSIS
        Sends a query to the SendGrid API.

    .DESCRIPTION
        This method sends a query to the SendGrid API and returns the results. 

    .PARAMETER WebRequestMethod
        The HTTP method to use for the query (GET, POST, etc.).

    .PARAMETER Endpoint
        The specific endpoint in the SendGrid API to send the query to.

    .PARAMETER ContentBody
        The payload to send to the specified endpoint.
    
    .PARAMETER OnBehalfOf
        The username of the subuser or account-id to send the query on behalf of.

    .INPUTS
        Microsoft.PowerShell.Commands.WebRequestMethod, string, hashtable.

    .OUTPUTS
        PSCustomObject[]
    #>
    [PSCustomObject[]] InvokeQuery ([Microsoft.PowerShell.Commands.WebRequestMethod]$WebRequestMethod, [string]$Endpoint, [hashtable]$ContentBody, [string]$OnBehalfOf) {
        $Body = $ContentBody | ConvertTo-Json -Depth 5 -ErrorAction Stop
        $SessionLifeTime = (Get-Date).AddHours(-1)
        if ($null -eq $this._CreateDateTime -or $SessionLifeTime -gt $this._CreateDateTime) {
            $this.Disconnect()
            return 'Session lifetime exceeded, reconnect.'
        }
        else {
            $this.BuildEndpointURL($Endpoint)
            try {
                $Headers = @{
                    'Authorization' = "Bearer $($this._Credential.GetNetworkCredential().Password)"
                    'on-behalf-of'  = $OnBehalfOf
                    'Content-Type'  = 'application/json'
                }
                $Query = (Invoke-RestMethod -Method $WebRequestMethod -Uri $this.EndpointURL -Headers $Headers -Body $Body -ErrorAction Stop)
                $this.BuildEndpointURL($null)
                $this._CreateDateTime = Get-Date
                return $Query
            }
            catch {
                $this.BuildEndpointURL($null)
                if ($null -ne $_.ErrorDetails.Message) {
                    throw ('SendGrid Error: "{0}"' -f ($_.ErrorDetails.Message | ConvertFrom-Json | Select-Object -ExpandProperty errors | Select-Object -ExpandProperty message) -join ', ' )
                }
                else {
                    throw ('Unable to query SendGrid: {0}' -f $_.Exception.Message)
                }
            }
        }
    }

    [string]ToString() {
        return $this._Connected
    }
}