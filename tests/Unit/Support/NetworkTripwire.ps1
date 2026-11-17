# Network tripwire for unit tests. Not a test file.
# While enabled, an unmocked call to Invoke-RestMethod or Invoke-WebRequest is recorded and throws.
# A Pester Mock -ModuleName SendGridTools defines the command in module scope and wins over these
# global functions.
#
# A class method in Windows PowerShell 5.1 stays bound to the module instance that first defined the
# class, so Pester cannot mock calls that SendGridSession methods make once the module has been
# imported more than once in the run. The global functions below are reached from every instance, so
# they also carry an optional stub: when $global:SgtNetworkStub is set, the call is logged in
# $global:SgtNetworkCall and the stub runs instead of throwing. Tests use the stub for class calls.

function Enable-SgtNetworkTripwire {
    $global:SgtUnmockedNetworkCall = [System.Collections.Generic.List[string]]::new()
    $global:SgtNetworkCall = [System.Collections.Generic.List[object]]::new()
    $global:SgtNetworkStub = $null
    function global:Invoke-RestMethod {
        [CmdletBinding()]
        param($Method, $Uri, $Headers, $Body, [Parameter(ValueFromRemainingArguments)]$Remaining)
        if ($null -ne $global:SgtNetworkStub) {
            $null = $global:SgtNetworkCall.Add(@{ Method = "$Method"; Uri = $Uri; Headers = $Headers; Body = $Body; BodyPassed = ($null -ne $Body) })
            & $global:SgtNetworkStub
            return
        }
        $null = $global:SgtUnmockedNetworkCall.Add('Invoke-RestMethod')
        throw 'Unmocked network call: Invoke-RestMethod'
    }
    function global:Invoke-WebRequest {
        [CmdletBinding()]
        param($Uri, [Parameter(ValueFromRemainingArguments)]$Remaining)
        $null = $global:SgtUnmockedNetworkCall.Add('Invoke-WebRequest')
        throw 'Unmocked network call: Invoke-WebRequest'
    }
}

function Disable-SgtNetworkTripwire {
    Remove-Item -Path 'Function:\Invoke-RestMethod' -ErrorAction SilentlyContinue
    Remove-Item -Path 'Function:\Invoke-WebRequest' -ErrorAction SilentlyContinue
    Remove-Variable -Name SgtUnmockedNetworkCall, SgtNetworkCall, SgtNetworkStub, SgtStubValue -Scope Global -ErrorAction SilentlyContinue
}

function Assert-SgtNetworkTripwireActive {
    # Fails the caller when the tripwire is not in place: both commands must resolve to the global functions
    # and the state variable must exist. A broken or removed Enable-SgtNetworkTripwire fails here, before any test.
    foreach ($Name in 'Invoke-RestMethod', 'Invoke-WebRequest') {
        $Found = Get-Command -Name $Name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -eq $Found -or $Found.CommandType -ne 'Function') {
            throw "Network tripwire is not active: $Name does not resolve to the tripwire function (found: $(if ($Found) { $Found.CommandType } else { 'nothing' }))."
        }
    }
    if (-not (Test-Path -Path 'Variable:\global:SgtUnmockedNetworkCall')) {
        throw 'Network tripwire is not active: the state variable SgtUnmockedNetworkCall does not exist.'
    }
}

function Get-SgtUnmockedNetworkCall {
    if (-not (Test-Path -Path 'Variable:\global:SgtUnmockedNetworkCall')) {
        throw 'Network tripwire state is missing: the tripwire was never enabled or has been disabled, so "no call" would prove nothing.'
    }
    $global:SgtUnmockedNetworkCall.ToArray()
}
