BeforeDiscovery {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/SessionHelpers.ps1')
    # The four errors of step 1: two JSON bodies (with and without a field), a body that is not JSON, and no response at all.
    $script:M1Error = @('400 json with field', '404 json without field', '500 not json', 'no response')
    $script:M1Case = foreach ($Target in @('Connect(credential)', 'Connect()') + @(Get-SgtOverloadCase | ForEach-Object { "InvokeQuery $($_.Name)" })) {
        foreach ($ErrorName in $script:M1Error) {
            @{ Target = $Target; ErrorName = $ErrorName }
        }
    }
    $script:M2Case = foreach ($Command in 'Get-SGApiKey -ApiKeyId', 'Send-SGMailMessage') {
        foreach ($ErrorName in $script:M1Error) {
            @{ Command = $Command; ErrorName = $ErrorName }
        }
    }
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/NetworkTripwire.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/SessionHelpers.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/RedirectFakes.ps1')
    # Import once per run: in Windows PowerShell 5.1 a class stays bound to the first loaded module instance.
    if (-not (Get-Module -Name SendGridTools)) {
        Get-Module -Name SendGridTools -ListAvailable | Select-Object -First 1 | Import-Module -ErrorAction Stop
    }
    Enable-SgtNetworkTripwire
    Assert-SgtNetworkTripwireActive
    Install-SgtSessionHelper
    Add-SgtRedirectFake
    Install-SgtRedirectBuilder
    $script:Cred = [pscredential]::new('apikey', (ConvertTo-SecureString -String 'test-key-not-real' -AsPlainText -Force))
    $script:Shell = '{0} {1}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion

    InModuleScope SendGridTools {
        function Script:New-SgtM61Record {
            # Builds the ErrorRecord that Invoke-RestMethod throws for one of the four errors, in the shape of the running shell:
            # an HttpResponseException in PowerShell 7 and a WebException with a response in Windows PowerShell 5.1.
            param([string]$ErrorName)
            $Code = switch -Wildcard ($ErrorName) { '400*' { 400 } '404*' { 404 } '500*' { 500 } default { 0 } }
            $Details = switch -Wildcard ($ErrorName) {
                '400*' { '{"errors":[{"field":"name","message":"name is required"}]}' }
                '404*' { '{"errors":[{"field":null,"message":"resource not found"}]}' }
                '500*' { '<html><body>made-up upstream failure</body></html>' }
                default { $null }
            }
            if ($Code -eq 0) {
                $Exception = [System.Net.Http.HttpRequestException]::new('No such host is known.')
            }
            elseif ($PSVersionTable.PSEdition -eq 'Core') {
                $Status = [System.Enum]::ToObject([System.Net.HttpStatusCode], $Code)
                $Message = [System.Net.Http.HttpResponseMessage]::new($Status)
                $Exception = [Microsoft.PowerShell.Commands.HttpResponseException]::new(('Response status code does not indicate success: {0} ({1}).' -f $Code, $Status), $Message)
            }
            else {
                $Status = [System.Enum]::ToObject([System.Net.HttpStatusCode], $Code)
                $Exception = [System.Net.WebException]::new(('The remote server returned an error: ({0}) {1}.' -f $Code, $Status), $null, [System.Net.WebExceptionStatus]::ProtocolError, (New-SgtFakeWebResponse -Code $Code))
            }
            $Record = [System.Management.Automation.ErrorRecord]::new($Exception, 'WebCmdletWebResponseException,Microsoft.PowerShell.Commands.InvokeRestMethodCommand', [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
            if ($Details) { $Record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new($Details) }
            $Record
        }
    }

    function script:Format-SgtM61Error {
        # One text per caught error: the message, the exception type, the type of the inner exception, the keys in Data,
        # the status code and the fields of SendGridErrors. Only made-up values reach these texts.
        param($Caught)
        if ($null -eq $Caught) { return 'no error' }
        $Exception = $Caught.Exception
        $Inner = if ($null -ne $Exception.InnerException) { $Exception.InnerException.GetType().FullName } else { 'none' }
        $Keys = @($Exception.Data.Keys | ForEach-Object { "$_" } | Sort-Object)
        $Status = if ($Exception.Data.Contains('StatusCode')) { '{0} ({1})' -f $Exception.Data['StatusCode'], $Exception.Data['StatusCode'].GetType().Name } else { 'none' }
        $Fields = if ($Exception.Data.Contains('SendGridErrors')) {
            (@($Exception.Data['SendGridErrors']) | ForEach-Object { 'Field={0}|Message={1}' -f $_.Field, $_.Message }) -join '; '
        }
        else { 'none' }
        'text "{0}"; type {1}; fqid {2}; inner {3}; data keys [{4}]; status {5}; errors [{6}]' -f $Exception.Message, $Exception.GetType().FullName, $Caught.FullyQualifiedErrorId, $Inner, ($Keys -join ', '), $Status, $Fields
    }
}

AfterAll {
    InModuleScope SendGridTools {
        Remove-Item -Path 'Function:\New-SgtFakeWebResponse', 'Function:\New-SgtM61Record' -ErrorAction SilentlyContinue
    }
    Uninstall-SgtSessionHelper
    Disable-SgtNetworkTripwire
}

# Sprint 6 step 1 measurements (M1-M3). Each It writes one MEASURE line with made-up values, types, keys and True/False only,
# and asserts nothing about the measured value, so the same file measures any version of the module.
# Invoke-RestMethod is answered by the tripwire's stub.
Describe 'Sprint 6 step 1 measurements' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'M1: <Target> with <ErrorName>' -ForEach $script:M1Case {
        $Case = Get-SgtOverloadCase | Where-Object { "InvokeQuery $($_.Name)" -eq $Target }
        $Caught = InModuleScope SendGridTools -Parameters @{ Target = $Target; ErrorName = $ErrorName; Cred = $script:Cred; Case = $Case } {
            Set-SgtNetworkStub -Throw (New-SgtM61Record -ErrorName $ErrorName)
            $Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            $Result = $null
            try {
                switch -Wildcard ($Target) {
                    'Connect(credential)' { $Session.Connect($Cred) }
                    'Connect()' { $Session.Connect() }
                    default { $null = Invoke-SgtOverload -Session $Session -Case $Case }
                }
            }
            catch { $Result = $_ }
            $Result
        }
        $Text = Format-SgtM61Error -Caught $Caught
        $ParseError = $Text -match 'JSON|Invalid object passed|primitive'
        Write-Host ('MEASURE M1 [{0}] {1} {2}: {3}; parse error shown {4}' -f $script:Shell, $Target, $ErrorName, $Text, $ParseError)
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
        $Text | Should -Not -BeNullOrEmpty
    }

    It 'M2: <Command> with <ErrorName>' -ForEach $script:M2Case {
        InModuleScope SendGridTools -Parameters @{ ErrorName = $ErrorName; Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Throw (New-SgtM61Record -ErrorName $ErrorName)
        }
        # The caller sits outside the module, as a user's script does.
        $Caught = $null
        try {
            if ($Command -eq 'Get-SGApiKey -ApiKeyId') {
                $null = Get-SGApiKey -ApiKeyId 'key-id-1'
            }
            else {
                $null = Send-SGMailMessage -From 'sender@example.com' -To 'one@example.com' -Subject 'placeholder subject' -Body 'placeholder body' -Confirm:$false
            }
        }
        catch { $Caught = $_ }
        $Text = Format-SgtM61Error -Caught $Caught
        Write-Host ('MEASURE M2 [{0}] {1} {2}: {3}' -f $script:Shell, $Command, $ErrorName, $Text)
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
        $Text | Should -Not -BeNullOrEmpty
    }

    It 'M3: Disconnect-SendGrid when removing the session throws' {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
        }
        Mock -CommandName Remove-Variable -ModuleName SendGridTools -ParameterFilter { $Name -eq 'Session' } -MockWith { throw 'made-up removal failure' }
        $Caught = $null
        $Stream = @()
        try { $Stream = @(Disconnect-SendGrid -Confirm:$false 2>&1) } catch { $Caught = $_ }
        $Record = @($Stream | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })[0]
        $Terminating = $null -ne $Caught
        if ($Terminating) { $Record = $Caught }
        $Text = Format-SgtM61Error -Caught $Record
        $ShowsScriptBlock = $Text -match '\$_\.Exception\.Message'
        $ShowsCause = $Text -match 'made-up removal failure'
        Write-Host ('MEASURE M3 [{0}] Disconnect-SendGrid: {1}; terminating {2}; shows the script block {3}; shows the cause {4}' -f $script:Shell, $Text, $Terminating, $ShowsScriptBlock, $ShowsCause)
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
        $Text | Should -Not -BeNullOrEmpty
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
