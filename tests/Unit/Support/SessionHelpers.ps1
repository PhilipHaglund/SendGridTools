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
        function Script:Reset-SgtNetworkStub {
            $global:SgtNetworkStub = $null
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
        Remove-Item -Path 'Function:\New-SgtTestSession', 'Function:\New-SgtErrorRecord', 'Function:\Invoke-SgtOverload', 'Function:\Get-SgtLeakText', 'Function:\Invoke-SgtTarget', 'Function:\Set-SgtNetworkStub', 'Function:\Reset-SgtNetworkStub', 'Function:\Get-SgtNetworkCall' -ErrorAction SilentlyContinue
    }
}
