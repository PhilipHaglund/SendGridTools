# Network tripwire for unit tests. Not a test file.
# While enabled, an unmocked call to Invoke-RestMethod or Invoke-WebRequest is recorded and throws.
# A Pester Mock -ModuleName SendGridTools defines the command in module scope and wins over these
# global functions.
#
# A class method in Windows PowerShell 5.1 stays bound to the module instance that first defined the
# class, so Pester cannot mock calls that SendGridSession methods make once the module has been
# imported more than once in the run. The global functions below are reached from every instance, so
# they also carry an optional stub: when $global:SgtNetworkStub is set, the call is logged in
# $global:SgtNetworkCall (each entry has a Command key: Invoke-RestMethod or Invoke-WebRequest) and the
# stub runs instead of throwing. Tests use the stub for class calls.
#
# Invoke-WebRequest has its own stub, $global:SgtWebRequestStub: its output is returned as the raw web
# response. When only $global:SgtNetworkStub is set, Invoke-WebRequest runs that stub and wraps its output
# as a JSON response (status 200, a Content-Type header, RawContentStream with the UTF-8 JSON), so a stub
# written for Invoke-RestMethod also answers Invoke-WebRequest. No output, or one $null, returns nothing.

function Enable-SgtNetworkTripwire {
    $global:SgtUnmockedNetworkCall = [System.Collections.Generic.List[string]]::new()
    $global:SgtNetworkCall = [System.Collections.Generic.List[object]]::new()
    $global:SgtNetworkStub = $null
    $global:SgtWebRequestStub = $null
    function global:Invoke-RestMethod {
        [CmdletBinding()]
        param($Method, $Uri, $Headers, $Body, $MaximumRedirection, [Parameter(ValueFromRemainingArguments)]$Remaining)
        if ($null -ne $global:SgtNetworkStub) {
            $null = $global:SgtNetworkCall.Add(@{ Command = 'Invoke-RestMethod'; Method = "$Method"; Uri = $Uri; Headers = $Headers; Body = $Body; BodyPassed = ($null -ne $Body); MaximumRedirection = $MaximumRedirection; MaximumRedirectionPassed = $PSBoundParameters.ContainsKey('MaximumRedirection') })
            & $global:SgtNetworkStub
            return
        }
        $null = $global:SgtUnmockedNetworkCall.Add('Invoke-RestMethod')
        throw 'Unmocked network call: Invoke-RestMethod'
    }
    function global:Invoke-WebRequest {
        [CmdletBinding()]
        param($Method, $Uri, $Headers, $Body, $MaximumRedirection, [switch]$UseBasicParsing, [Parameter(ValueFromRemainingArguments)]$Remaining)
        if ($null -ne $global:SgtWebRequestStub -or $null -ne $global:SgtNetworkStub) {
            $null = $global:SgtNetworkCall.Add(@{ Command = 'Invoke-WebRequest'; Method = "$Method"; Uri = $Uri; Headers = $Headers; Body = $Body; BodyPassed = ($null -ne $Body); MaximumRedirection = $MaximumRedirection; MaximumRedirectionPassed = $PSBoundParameters.ContainsKey('MaximumRedirection'); UseBasicParsing = [bool]$UseBasicParsing })
            if ($null -ne $global:SgtWebRequestStub) {
                & $global:SgtWebRequestStub
                return
            }
            # Wrap the Invoke-RestMethod stub's output as a JSON web response.
            $Output = @(& $global:SgtNetworkStub)
            if ($Output.Count -eq 0 -or ($Output.Count -eq 1 -and $null -eq $Output[0])) {
                return
            }
            $Payload = if ($Output.Count -eq 1) { $Output[0] } else { $Output }
            $Json = ConvertTo-Json -InputObject $Payload -Depth 100 -Compress
            [pscustomobject]@{
                StatusCode        = 200
                StatusDescription = 'OK'
                Headers           = @{ 'Content-Type' = 'application/json; charset=utf-8' }
                RawContentStream  = [System.IO.MemoryStream]::new([System.Text.UTF8Encoding]::new($false).GetBytes($Json))
                BaseResponse      = $null
            }
            return
        }
        $null = $global:SgtUnmockedNetworkCall.Add('Invoke-WebRequest')
        throw 'Unmocked network call: Invoke-WebRequest'
    }
}

function Disable-SgtNetworkTripwire {
    Remove-Item -Path 'Function:\Invoke-RestMethod' -ErrorAction SilentlyContinue
    Remove-Item -Path 'Function:\Invoke-WebRequest' -ErrorAction SilentlyContinue
    Remove-Variable -Name SgtUnmockedNetworkCall, SgtNetworkCall, SgtNetworkStub, SgtWebRequestStub, SgtStubValue -Scope Global -ErrorAction SilentlyContinue
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
