BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/NetworkTripwire.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/SessionHelpers.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/PromptCountingHost.ps1')
    # Import once per run: in Windows PowerShell 5.1 a class stays bound to the first loaded module instance.
    if (-not (Get-Module -Name SendGridTools)) {
        Get-Module -Name SendGridTools -ListAvailable | Select-Object -First 1 | Import-Module -ErrorAction Stop
    }
    Enable-SgtNetworkTripwire
    Assert-SgtNetworkTripwireActive
    Install-SgtSessionHelper
    $script:Cred = [pscredential]::new('apikey', (ConvertTo-SecureString -String 'test-key-not-real' -AsPlainText -Force))
}

AfterAll {
    Uninstall-SgtSessionHelper
    Disable-SgtNetworkTripwire
}

# Sprint 4 step 2 measurements (D15, D16, D20). Each It writes one MEASURE line with type names, made-up error
# texts, counts and True/False only, and asserts nothing about the measured value, so the same file measures
# any version of the module.
Describe 'Sprint 4 step 2 measurements' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'D15: the error <Level> gives its caller when the transport throws <Name>' -ForEach @(
        @{ Level = 'Invoke-SendGrid'; Name = 'an exception with an inner exception' }
        @{ Level = 'Invoke-SendGrid'; Name = 'an error record with a JSON errors body' }
        @{ Level = 'Invoke-SendGrid'; Name = 'an error record with a body that is not JSON' }
        @{ Level = 'Remove-SGGlobalSuppression'; Name = 'an exception with an inner exception' }
        @{ Level = 'Remove-SGGlobalSuppression'; Name = 'an error record with a JSON errors body' }
        @{ Level = 'Remove-SGGlobalSuppression'; Name = 'an error record with a body that is not JSON' }
        @{ Level = 'Invoke-SendGrid'; Name = 'a typed exception with an inner exception from the session' }
        @{ Level = 'Remove-SGGlobalSuppression'; Name = 'a typed exception with an inner exception from the session' }
    ) {
        $Result = InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Level = $Level; Name = $Name } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            $Thrown = switch ($Name) {
                'an exception with an inner exception' { [System.InvalidOperationException]::new('sgt-test-transport-text', [System.TimeoutException]::new('sgt-test-inner-text')) }
                'an error record with a JSON errors body' { New-SgtErrorRecord -Message 'sgt-test-transport-text' -Details '{"errors":[{"field":null,"message":"sgt-test-api-text"}]}' }
                'an error record with a body that is not JSON' { New-SgtErrorRecord -Message 'sgt-test-transport-text' -Details '<html>sgt-test-gateway-text</html>' }
            }
            Set-SgtNetworkStub -Throw $Thrown
            if ($Name -eq 'a typed exception with an inner exception from the session') {
                # A session whose InvokeQuery throws a typed exception itself: the class is defined at run time, in module
                # scope, where SendGridSession is known. The request never reaches the transport.
                $script:Session = & ([scriptblock]::Create('class SgtMeasureThrowingSession : SendGridSession { [PSCustomObject[]] InvokeQuery ([string]$WebRequestMethod, [string]$Endpoint) { throw [System.InvalidOperationException]::new(''sgt-test-session-text'', [System.TimeoutException]::new(''sgt-test-inner-text'')) } }; [SgtMeasureThrowingSession]::new()'))
            }
            $Caught = $null
            try {
                if ($Level -eq 'Invoke-SendGrid') {
                    $null = Invoke-SendGrid -Method Get -Namespace 'things'
                }
                else {
                    $null = Remove-SGGlobalSuppression -EmailAddress 'one@example.com' -Confirm:$false
                }
            }
            catch {
                $Caught = $_
            }
            if ($null -eq $Caught) {
                'no error'
            }
            else {
                $Inner = if ($Caught.Exception.InnerException) { $Caught.Exception.InnerException.GetType().FullName } else { 'none' }
                'type {0}; message "{1}"; inner exception {2}; error id {3}; category {4}; stack names InvokeQuery: {5}; calls {6}' -f $Caught.Exception.GetType().FullName, $Caught.Exception.Message, $Inner, $Caught.FullyQualifiedErrorId, $Caught.CategoryInfo.Category, ("$($Caught.ScriptStackTrace)" -match 'InvokeQuery'), (Get-SgtNetworkCall).Count
            }
        }
        Write-Host ('MEASURE D15 [{0} {1}] {2}, {3}: {4}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Level, $Name, $Result)
        $Result | Should -Not -BeNullOrEmpty
    }

    It 'D16: the error <Level> gives its caller for <Name> in errors' -ForEach @(
        @{ Level = 'Invoke-SendGrid'; Name = 'one error'; Json = '{"errors":[{"field":null,"message":"sgt-test-error-one"}]}' }
        @{ Level = 'Invoke-SendGrid'; Name = 'two errors'; Json = '{"errors":[{"field":null,"message":"sgt-test-error-one"},{"field":null,"message":"sgt-test-error-two"}]}' }
        @{ Level = 'Remove-SGGlobalSuppression'; Name = 'one error'; Json = '{"errors":[{"field":null,"message":"sgt-test-error-one"}]}' }
        @{ Level = 'Remove-SGGlobalSuppression'; Name = 'two errors'; Json = '{"errors":[{"field":null,"message":"sgt-test-error-one"},{"field":null,"message":"sgt-test-error-two"}]}' }
        @{ Level = 'Invoke-SendGrid'; Name = 'one error without a message'; Json = '{"errors":[{"field":"sgt-test-field"}]}' }
        @{ Level = 'Invoke-SendGrid'; Name = 'two errors, the first without a message'; Json = '{"errors":[{"field":"sgt-test-field"},{"field":null,"message":"sgt-test-error-two"}]}' }
    ) {
        $Result = InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Level = $Level; Json = $Json } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ($Json | ConvertFrom-Json)
            $Caught = $null
            try {
                if ($Level -eq 'Invoke-SendGrid') {
                    $null = Invoke-SendGrid -Method Get -Namespace 'things'
                }
                else {
                    $null = Remove-SGGlobalSuppression -EmailAddress 'one@example.com' -Confirm:$false
                }
            }
            catch {
                $Caught = $_
            }
            if ($null -eq $Caught) {
                'no error'
            }
            else {
                'type {0}; message "{1}"; target object type {2}' -f $Caught.Exception.GetType().FullName, $Caught.Exception.Message, $(if ($null -ne $Caught.TargetObject) { $Caught.TargetObject.GetType().FullName } else { 'none' })
            }
        }
        Write-Host ('MEASURE D16 [{0} {1}] {2}, {3}: {4}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Level, $Name, $Result)
        $Result | Should -Not -BeNullOrEmpty
    }

    # D20 is measured in a new process whose host counts the choice prompts and answers Yes at once; no console is
    # read. Without an answer the module has no session there, so a request stops at the connect-first error after
    # ShouldProcess. With an answer it has a test session and the stub gives that answer to every request, so the
    # questions asked while the answer is read are counted too.
    It 'D20: how many times the host is asked for <Name>' -ForEach @(
        @{ Name = 'Invoke-SendGrid with ConfirmPreference Low at the caller'; Script = '$ConfirmPreference = ''Low''; Invoke-SendGrid -Method Get -Namespace ''things''' }
        @{ Name = 'Invoke-SendGrid with ConfirmPreference Medium at the caller'; Script = '$ConfirmPreference = ''Medium''; Invoke-SendGrid -Method Get -Namespace ''things''' }
        @{ Name = 'Invoke-SendGrid with ConfirmPreference High at the caller'; Script = '$ConfirmPreference = ''High''; Invoke-SendGrid -Method Get -Namespace ''things''' }
        @{ Name = 'Invoke-SendGrid with WhatIfPreference at the caller'; Script = '$WhatIfPreference = $true; Invoke-SendGrid -Method Get -Namespace ''things''' }
        @{ Name = 'Remove-SGGlobalSuppression -Confirm'; Script = 'Remove-SGGlobalSuppression -EmailAddress ''one@example.com'' -Confirm' }
        @{ Name = 'Remove-SGGlobalSuppression -WhatIf'; Script = 'Remove-SGGlobalSuppression -EmailAddress ''one@example.com'' -WhatIf' }
        @{ Name = 'Add-SGGlobalSuppression -Confirm'; Script = 'Add-SGGlobalSuppression -EmailAddress ''one@example.com'' -Confirm' }
        @{ Name = 'Invoke-SendGrid with ConfirmPreference Low, a session and an answer with two properties'; Script = '$ConfirmPreference = ''Low''; $null = Invoke-SendGrid -Method Get -Namespace ''things'''; Answer = '{"first_name":"sgt-test-one","second_name":"sgt-test-two"}' }
        @{ Name = 'Add-SGGlobalSuppression -Confirm with a session and an answer with one property'; Script = '$null = Add-SGGlobalSuppression -EmailAddress ''one@example.com'' -Confirm'; Answer = '{"recipient_emails":["one@example.com"]}' }
        @{ Name = 'Remove-SGGlobalSuppression -Confirm with a session and an answer with one property'; Script = '$null = Remove-SGGlobalSuppression -EmailAddress ''one@example.com'' -Confirm'; Answer = '{"name":"sgt-test-name"}' }
        @{ Name = 'Set-SGApiKey -Confirm with a session and an answer with three properties (it reads the key first)'; Script = '$null = Set-SGApiKey -UniqueId ''placeholder-id'' -Scopes ''mail.send'' -Confirm'; Answer = '{"api_key_id":"placeholder-id","name":"placeholder-name","scopes":["alerts.read"]}' }
        @{ Name = 'Add-SGGlobalSuppression -WhatIf with a session and an answer with one property'; Script = '$null = Add-SGGlobalSuppression -EmailAddress ''one@example.com'' -WhatIf'; Answer = '{"recipient_emails":["one@example.com"]}' }
    ) {
        $HostParams = @{ Script = $Script }
        if ($Answer) { $HostParams['AnswerJson'] = $Answer }
        $Run = Invoke-SgtInCountingHost @HostParams
        $Result = 'prompts {0}; host lines {1}; threw {2}; error type {3}; error message "{4}"; calls {5}; unmocked calls {6}' -f $Run.PromptCount, $Run.HostLine.Count, $Run.Threw, $(if ($Run.ThrownType) { $Run.ThrownType } else { 'none' }), $Run.ThrownMessage, $Run.NetworkCallCount, $Run.UnmockedCall.Count
        Write-Host ('MEASURE D20 [{0} {1}] {2}: {3}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Name, $Result)
        $Run.UnmockedCall | Should -BeNullOrEmpty
        $Result | Should -Not -BeNullOrEmpty
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
