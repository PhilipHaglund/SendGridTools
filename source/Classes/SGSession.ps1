# The SendGridSession class manages a SendGrid session for the user. 
class SendGridSession {
    # URL endpoint to the SendGrid API.
    [uri]$EndpointURL
    # Base URL to the SendGrid API. 
    hidden [uri]$_BaseURL = 'https://api.sendgrid.com/v3'
    # Specifies if the session is connected.
    hidden [bool]$_Connected = $false
    # Remembers that the session expired, so every call until Connect or Disconnect says so.
    hidden [bool]$_Expired = $false
    # Stores the user's SendGrid API credentials.
    hidden [PSCredential]$_Credential
    # Tracks the time when the session was created.
    hidden [DateTime]$_CreateDateTime

    # Constructor function for SendGridSession.
    SendGridSession () {
        $null = [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    }

    # Constructor function for SendGridSession with an explicit base URL, such as the EU host.
    # PowerShell classes cannot chain constructors, so the TLS 1.2 line is repeated.
    SendGridSession ([uri]$BaseURL) {
        $null = [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $this._BaseURL = $BaseURL
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
            $this._Expired = $true
            throw 'The SendGrid session has expired. Run Connect-SendGrid -Force to reconnect.'
        }
        if ($this._Credential -is [PSCredential]) {
            $this.BuildEndpointURL([string]'scopes')
            try {
                $Headers = @{
                    'Authorization' = ('Bearer {0}' -f $this._Credential.GetNetworkCredential().Password)
                    'Content-Type'  = 'application/json'
                }
                if ($global:PSVersionTable.PSEdition -eq 'Desktop') {
                    $null = Invoke-SendGridDesktopRequest -Method Get -Uri $this.EndpointURL -Headers $Headers
                }
                else {
                    $null = Invoke-RestMethod -Method Get -Uri  $this.EndpointURL -Headers $Headers -MaximumRedirection 0 -ErrorAction Stop
                }
                $this._Connected = $true
                $this._Expired = $false
                $this._CreateDateTime = Get-Date # Used to refresh "session lifetime"
            }
            catch {
                $RequestUri = $this.EndpointURL
                $Refusal = Get-SendGridRedirectRefusal -ErrorRecord $_ -RequestUri $RequestUri
                $this._Connected = $false
                if ($Refusal) { throw $Refusal }
                throw (ConvertTo-SendGridException -ErrorRecord $_ -Context Connect -RequestUri $RequestUri)
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
            if ($global:PSVersionTable.PSEdition -eq 'Desktop') {
                $null = Invoke-SendGridDesktopRequest -Method Get -Uri $this.EndpointURL -Headers $Headers
            }
            else {
                $null = Invoke-RestMethod -Method Get -Uri  $this.EndpointURL -Headers $Headers -MaximumRedirection 0 -ErrorAction Stop
            }
            $this._Connected = $true
            $this._Expired = $false
            $this._CreateDateTime = Get-Date
        }
        catch {
            $RequestUri = $this.EndpointURL
            $Refusal = Get-SendGridRedirectRefusal -ErrorRecord $_ -RequestUri $RequestUri
            $this._Connected = $false
            if ($Refusal) { throw $Refusal }
            throw (ConvertTo-SendGridException -ErrorRecord $_ -Context Connect -RequestUri $RequestUri)
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
        $this._Expired = $false
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
        string, string.

    .OUTPUTS
        PSCustomObject[]
    #>
    [PSCustomObject[]] InvokeQuery ([string]$WebRequestMethod, [string]$Endpoint) {
        if ($this._Connected -eq $false) {
            if ($this._Expired) {
                throw 'The SendGrid session has expired. Run Connect-SendGrid -Force to reconnect.'
            }
            throw 'You must call the Connect-SendGrid cmdlet before calling any other cmdlets.'
        }
        $SessionLifeTime = (Get-Date).AddHours(-1)
        if ($null -eq $this._CreateDateTime -or $SessionLifeTime -gt $this._CreateDateTime) {
            $this.Disconnect()
            $this._Expired = $true
            throw 'The SendGrid session has expired. Run Connect-SendGrid -Force to reconnect.'
        }
        else {
            $this.BuildEndpointURL($Endpoint)
            try {
                $Headers = @{
                    'Authorization' = "Bearer $($this._Credential.GetNetworkCredential().Password)"
                    'Content-Type'  = 'application/json'
                }
                if ($global:PSVersionTable.PSEdition -eq 'Desktop') {
                    $Query = (Invoke-SendGridDesktopRequest -Method $WebRequestMethod -Uri $this.EndpointURL -Headers $Headers)
                }
                else {
                    $Query = (Invoke-RestMethod -Method $WebRequestMethod -Uri $this.EndpointURL -Headers $Headers -MaximumRedirection 0 -ErrorAction Stop)
                }
                $this.BuildEndpointURL($null)
                $this._CreateDateTime = Get-Date
                return $Query
            }
            catch {
                $RequestUri = $this.EndpointURL
                $Refusal = Get-SendGridRedirectRefusal -ErrorRecord $_ -RequestUri $RequestUri
                $this.BuildEndpointURL($null)
                if ($Refusal) { throw $Refusal }
                throw (ConvertTo-SendGridException -ErrorRecord $_ -Context Query -RequestUri $RequestUri)
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
        string, string, hashtable.

    .OUTPUTS
        PSCustomObject[]
    #>
    [PSCustomObject[]] InvokeQuery ([string]$WebRequestMethod, [string]$Endpoint, [hashtable]$ContentBody) {
        if ($this._Connected -eq $false) {
            if ($this._Expired) {
                throw 'The SendGrid session has expired. Run Connect-SendGrid -Force to reconnect.'
            }
            throw 'You must call the Connect-SendGrid cmdlet before calling any other cmdlets.'
        }
        foreach ($Key in $ContentBody.Keys) {
            Write-Verbose -Message ('ContentBody: Key: {0}, Type: {1}' -f $Key, $ContentBody[$Key].GetType())
        }
        $Body = $ContentBody | ConvertTo-Json -Depth 5 -ErrorAction Stop
        $SessionLifeTime = (Get-Date).AddHours(-1)
        if ($null -eq $this._CreateDateTime -or $SessionLifeTime -gt $this._CreateDateTime) {
            $this.Disconnect()
            $this._Expired = $true
            throw 'The SendGrid session has expired. Run Connect-SendGrid -Force to reconnect.'
        }
        else {
            $this.BuildEndpointURL($Endpoint)
            try {
                $Headers = @{
                    'Authorization' = "Bearer $($this._Credential.GetNetworkCredential().Password)"
                    'Content-Type'  = 'application/json; charset=utf-8'
                }
                $BodyBytes = [System.Text.UTF8Encoding]::new($false).GetBytes($Body)
                if ($global:PSVersionTable.PSEdition -eq 'Desktop') {
                    $Query = (Invoke-SendGridDesktopRequest -Method $WebRequestMethod -Uri $this.EndpointURL -Headers $Headers -Body $BodyBytes)
                }
                else {
                    $Query = (Invoke-RestMethod -Method $WebRequestMethod -Uri $this.EndpointURL -Headers $Headers -Body $BodyBytes -MaximumRedirection 0 -ErrorAction Stop)
                }
                $this.BuildEndpointURL($null)
                $this._CreateDateTime = Get-Date
                return $Query
            }
            catch {
                $RequestUri = $this.EndpointURL
                $Refusal = Get-SendGridRedirectRefusal -ErrorRecord $_ -RequestUri $RequestUri
                $this.BuildEndpointURL($null)
                if ($Refusal) { throw $Refusal }
                throw (ConvertTo-SendGridException -ErrorRecord $_ -Context Query -RequestUri $RequestUri)
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
        string, string.

    .OUTPUTS
        PSCustomObject[]
    #>
    [PSCustomObject[]] InvokeQuery ([string]$WebRequestMethod, [string]$Endpoint, [string]$OnBehalfOf) {
        if ($this._Connected -eq $false) {
            if ($this._Expired) {
                throw 'The SendGrid session has expired. Run Connect-SendGrid -Force to reconnect.'
            }
            throw 'You must call the Connect-SendGrid cmdlet before calling any other cmdlets.'
        }
        $SessionLifeTime = (Get-Date).AddHours(-1)
        if ($null -eq $this._CreateDateTime -or $SessionLifeTime -gt $this._CreateDateTime) {
            $this.Disconnect()
            $this._Expired = $true
            throw 'The SendGrid session has expired. Run Connect-SendGrid -Force to reconnect.'
        }
        else {
            $this.BuildEndpointURL($Endpoint)
            try {
                $Headers = @{
                    'Authorization' = "Bearer $($this._Credential.GetNetworkCredential().Password)"
                    'on-behalf-of'  = $OnBehalfOf
                    'Content-Type'  = 'application/json'
                }
                if ($global:PSVersionTable.PSEdition -eq 'Desktop') {
                    $Query = (Invoke-SendGridDesktopRequest -Method $WebRequestMethod -Uri $this.EndpointURL -Headers $Headers)
                }
                else {
                    $Query = (Invoke-RestMethod -Method $WebRequestMethod -Uri $this.EndpointURL -Headers $Headers -MaximumRedirection 0 -ErrorAction Stop)
                }
                $this.BuildEndpointURL($null)
                $this._CreateDateTime = Get-Date
                return $Query
            }
            catch {
                $RequestUri = $this.EndpointURL
                $Refusal = Get-SendGridRedirectRefusal -ErrorRecord $_ -RequestUri $RequestUri
                $this.BuildEndpointURL($null)
                if ($Refusal) { throw $Refusal }
                throw (ConvertTo-SendGridException -ErrorRecord $_ -Context Query -RequestUri $RequestUri)
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
        string, string, hashtable.

    .OUTPUTS
        PSCustomObject[]
    #>
    [PSCustomObject[]] InvokeQuery ([string]$WebRequestMethod, [string]$Endpoint, [hashtable]$ContentBody, [string]$OnBehalfOf) {
        if ($this._Connected -eq $false) {
            if ($this._Expired) {
                throw 'The SendGrid session has expired. Run Connect-SendGrid -Force to reconnect.'
            }
            throw 'You must call the Connect-SendGrid cmdlet before calling any other cmdlets.'
        }
        $Body = $ContentBody | ConvertTo-Json -Depth 5 -ErrorAction Stop
        $SessionLifeTime = (Get-Date).AddHours(-1)
        if ($null -eq $this._CreateDateTime -or $SessionLifeTime -gt $this._CreateDateTime) {
            $this.Disconnect()
            $this._Expired = $true
            throw 'The SendGrid session has expired. Run Connect-SendGrid -Force to reconnect.'
        }
        else {
            $this.BuildEndpointURL($Endpoint)
            try {
                $Headers = @{
                    'Authorization' = "Bearer $($this._Credential.GetNetworkCredential().Password)"
                    'on-behalf-of'  = $OnBehalfOf
                    'Content-Type'  = 'application/json; charset=utf-8'
                }
                $BodyBytes = [System.Text.UTF8Encoding]::new($false).GetBytes($Body)
                if ($global:PSVersionTable.PSEdition -eq 'Desktop') {
                    $Query = (Invoke-SendGridDesktopRequest -Method $WebRequestMethod -Uri $this.EndpointURL -Headers $Headers -Body $BodyBytes)
                }
                else {
                    $Query = (Invoke-RestMethod -Method $WebRequestMethod -Uri $this.EndpointURL -Headers $Headers -Body $BodyBytes -MaximumRedirection 0 -ErrorAction Stop)
                }
                $this.BuildEndpointURL($null)
                $this._CreateDateTime = Get-Date
                return $Query
            }
            catch {
                $RequestUri = $this.EndpointURL
                $Refusal = Get-SendGridRedirectRefusal -ErrorRecord $_ -RequestUri $RequestUri
                $this.BuildEndpointURL($null)
                if ($Refusal) { throw $Refusal }
                throw (ConvertTo-SendGridException -ErrorRecord $_ -Context Query -RequestUri $RequestUri)
            }
        }
    }

    [string]ToString() {
        return $this._Connected
    }
}