# Shared helpers for the transport unit tests. Not a test file.
# Get-SgtOverloadCase runs at discovery and in tests. Install-SgtSessionHelper defines small helper
# functions inside the SendGridTools module scope so tests can build sessions and call overloads.

function Get-SgtOverloadCase {
    $Body = @{ Key = 'value' }
    @(
        @{ Name = '(method, endpoint)'; Method = 'Get'; Endpoint = 'scopes'; HasBody = $false; HasObo = $false; Body = $null; Obo = $null }
        @{ Name = '(method, endpoint, body)'; Method = 'Post'; Endpoint = 'mail/send'; HasBody = $true; HasObo = $false; Body = $Body; Obo = $null }
        @{ Name = '(method, endpoint, onBehalfOf)'; Method = 'Patch'; Endpoint = 'user/profile'; HasBody = $false; HasObo = $true; Body = $null; Obo = 'subuser-placeholder' }
        @{ Name = '(method, endpoint, body, onBehalfOf)'; Method = 'Delete'; Endpoint = 'templates/abc'; HasBody = $true; HasObo = $true; Body = $Body; Obo = 'subuser-placeholder' }
    )
}

function Install-SgtSessionHelper {
    InModuleScope SendGridTools {
        function Script:New-SgtTestSession {
            param([pscredential]$Credential, [double]$AgeHours = 0, [bool]$Connected = $true)
            $Session = [SendGridSession]::new()
            $Session._Credential = $Credential
            $Session._Connected = $Connected
            $Session._CreateDateTime = (Get-Date).AddHours(-1 * $AgeHours)
            $Session
        }
        function Script:Set-SgtNetworkStub {
            # Makes the tripwire answer Invoke-RestMethod: return -Response, or throw -Throw. Calls are logged.
            param($Response, $Throw)
            $global:SgtNetworkCall.Clear()
            if ($PSBoundParameters.ContainsKey('Throw')) {
                $global:SgtStubValue = $Throw
                $global:SgtNetworkStub = { throw $global:SgtStubValue }
            }
            else {
                $global:SgtStubValue = $Response
                $global:SgtNetworkStub = { $global:SgtStubValue }
            }
        }
        function Script:Set-SgtPagedNetworkStub {
            # Makes the tripwire answer list calls page by page from -Items, reading limit and offset from the last logged Uri.
            # -Shape List returns the slice as an array, -Shape Result wraps it as { result = [...] }.
            # -IgnoreOffset always returns the first page. A single-item Uri (not ending in domains or api_keys) returns that item.
            param([object[]]$Items, [ValidateSet('List', 'Result')][string]$Shape, [switch]$IgnoreOffset)
            $global:SgtNetworkCall.Clear()
            $global:SgtPagedItems = @($Items)
            $global:SgtPagedShape = $Shape
            $global:SgtPagedIgnoreOffset = [bool]$IgnoreOffset
            $global:SgtNetworkStub = {
                $Uri = "$($global:SgtNetworkCall[-1].Uri)"
                $All = @($global:SgtPagedItems)
                $IdName = if ($global:SgtPagedShape -eq 'List') { 'id' } else { 'api_key_id' }
                $Path = ($Uri -split '\?')[0]
                $Last = ($Path -split '/')[-1]
                if ($Uri -match '[?&]limit=(\d+)') {
                    $Limit = [int]$Matches[1]
                    $Offset = 0
                    if (-not $global:SgtPagedIgnoreOffset -and $Uri -match '[?&]offset=(\d+)') {
                        $Offset = [int]$Matches[1]
                    }
                    $Slice = @($All | Select-Object -Skip $Offset -First $Limit)
                }
                elseif ($Last -in 'domains', 'api_keys') {
                    $Slice = $All
                }
                else {
                    $Slice = @($All | Where-Object { "$($_.$IdName)" -eq $Last })
                    $Slice[0]
                    return
                }
                if ($global:SgtPagedShape -eq 'List') {
                    # Invoke-RestMethod unrolls a JSON array into the pipeline.
                    $Slice
                }
                else {
                    [pscustomobject]@{ result = @($Slice) }
                }
            }
        }
        function Script:New-SgtFixtureItem {
            # Clones the one element in a fixture file -Count times; domains get id and domain, keys get api_key_id and name.
            param([ValidateSet('Domain', 'Key')][string]$Kind, [int]$Count, [string]$Path)
            $Base = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
            $Element = if ($Kind -eq 'Domain') { @($Base)[0] } else { @($Base.result)[0] }
            $Json = $Element | ConvertTo-Json -Depth 6
            for ($n = 1; $n -le $Count; $n++) {
                $Item = $Json | ConvertFrom-Json
                if ($Kind -eq 'Domain') {
                    $Item.id = 1000 + $n
                    $Item.domain = "domain-$n.example.com"
                }
                else {
                    $Item.api_key_id = "key-id-$n"
                    $Item.name = "sgt-test-key-$n"
                }
                $Item
            }
        }
        function Script:Get-SgtListCall {
            # The logged calls that carry a limit query parameter, one object per call (wrap in @() at the call site).
            $global:SgtNetworkCall | Where-Object { "$($_.Uri)" -match '[?&]limit=' }
        }
        function Script:Get-SgtExpectedOffset {
            # The offsets a full read of -Count items asks for with a page size of 50: one call per full page plus one that ends the list.
            param([int]$Count, [int]$Limit = 50)
            for ($Page = 0; $Page -le [math]::Floor($Count / $Limit); $Page++) { $Page * $Limit }
        }
        function Script:Reset-SgtNetworkStub {
            $global:SgtNetworkStub = $null
            $global:SgtPagedItems = $null
            $global:SgtPagedShape = $null
            $global:SgtPagedIgnoreOffset = $null
            $global:SgtStubValue = $null
            $global:SgtNetworkCall.Clear()
        }
        function Script:Get-SgtNetworkCall {
            , @($global:SgtNetworkCall)
        }
        function Script:New-SgtErrorRecord {
            param([string]$Message, [string]$Details)
            $Record = [System.Management.Automation.ErrorRecord]::new([System.Exception]::new($Message), 'SgtTestError', [System.Management.Automation.ErrorCategory]::NotSpecified, $null)
            if ($Details) {
                $Record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new($Details)
            }
            $Record
        }
        function Script:Get-SgtLeakText {
            # Runs the action with verbose and debug on, merges every stream and returns all text a user could see.
            param([scriptblock]$Action)
            # A class method may be bound to another module instance (Windows PowerShell 5.1), which reads the
            # global preference, so set it there as well and restore it afterwards.
            $SavedVerbose = $global:VerbosePreference
            $SavedDebug = $global:DebugPreference
            $global:VerbosePreference = 'Continue'
            $global:DebugPreference = 'Continue'
            $VerbosePreference = 'Continue'
            $DebugPreference = 'Continue'
            $Thrown = $null
            $Streams = try { & $Action *>&1 } catch { $Thrown = $_ } finally { $global:VerbosePreference = $SavedVerbose; $global:DebugPreference = $SavedDebug }
            $Text = [System.Collections.Generic.List[string]]::new()
            $Text.Add(($Streams | Out-String))
            # Output objects (not records) are also serialised, so a nested dictionary shows in full and in key order.
            $Output = [System.Collections.Generic.List[object]]::new()
            foreach ($Object in @($Streams)) {
                if ($null -eq $Object -or $Object -is [System.Management.Automation.InformationalRecord] -or $Object -is [System.Management.Automation.ErrorRecord] -or $Object -is [System.Management.Automation.InformationRecord]) { continue }
                $Output.Add($Object)
                try { $Text.Add((ConvertTo-Json -InputObject $Object -Depth 6 -Compress)) } catch { $Text.Add([string]$Object) }
            }
            if ($Thrown) {
                $Text.Add([string]$Thrown.Exception.Message)
                $Text.Add([string]$Thrown.ToString())
                $Text.Add(($Thrown | Out-String))
            }
            [pscustomobject]@{ Text = ($Text -join "`n"); Output = $Output.ToArray(); Threw = ($null -ne $Thrown); Verbose = (($Streams | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $_.Message }) -join "`n") }
        }
        function Script:Invoke-SgtTarget {
            param([string]$Target, [hashtable]$Case, [pscredential]$Credential)
            switch ($Target) {
                'Connect(credential)' { [SendGridSession]::new().Connect($Credential) }
                'Connect()' { (New-SgtTestSession -Credential $Credential -AgeHours 0).Connect() }
                'InvokeQuery' { Invoke-SgtOverload -Session (New-SgtTestSession -Credential $Credential -AgeHours 0) -Case $Case }
                'Invoke-SendGrid' {
                    $script:Session = New-SgtTestSession -Credential $Credential -AgeHours 0
                    $Params = @{ Method = $Case.Method; Namespace = $Case.Endpoint }
                    if ($Case.HasBody) { $Params['ContentBody'] = $Case.Body }
                    if ($Case.HasObo) { $Params['OnBehalfOf'] = $Case.Obo }
                    Invoke-SendGrid @Params
                }
            }
        }
        function Script:Invoke-SgtOverload {
            param($Session, [hashtable]$Case)
            if ($Case.HasBody -and $Case.HasObo) {
                $Session.InvokeQuery($Case.Method, $Case.Endpoint, $Case.Body, $Case.Obo)
            }
            elseif ($Case.HasBody) {
                $Session.InvokeQuery($Case.Method, $Case.Endpoint, $Case.Body)
            }
            elseif ($Case.HasObo) {
                $Session.InvokeQuery($Case.Method, $Case.Endpoint, $Case.Obo)
            }
            else {
                $Session.InvokeQuery($Case.Method, $Case.Endpoint)
            }
        }
    }
}

function Uninstall-SgtSessionHelper {
    InModuleScope SendGridTools {
        Remove-Item -Path 'Function:\New-SgtTestSession', 'Function:\New-SgtErrorRecord', 'Function:\Invoke-SgtOverload', 'Function:\Get-SgtLeakText', 'Function:\Invoke-SgtTarget', 'Function:\Set-SgtNetworkStub', 'Function:\Set-SgtPagedNetworkStub', 'Function:\New-SgtFixtureItem', 'Function:\Get-SgtExpectedOffset', 'Function:\Get-SgtListCall','Function:\Reset-SgtNetworkStub', 'Function:\Get-SgtNetworkCall' -ErrorAction SilentlyContinue
    }
}
