BeforeDiscovery {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/SessionHelpers.ps1')
    $script:Targets = @(
        @{ Label = 'Connect(credential)'; Target = 'Connect(credential)'; Case = $null }
        @{ Label = 'Connect()'; Target = 'Connect()'; Case = $null }
    ) + @(Get-SgtOverloadCase | ForEach-Object { @{ Label = "InvokeQuery $($_.Name)"; Target = 'InvokeQuery'; Case = $_ } })
    $script:RedirectForms = foreach ($Target in $script:Targets) {
        foreach ($Form in 'Message', 'MaximumRedirect', 'UnreadableCache') {
            @{ Label = $Target.Label; Target = $Target.Target; Case = $Target.Case; Form = $Form }
        }
    }
    $script:UnchangedCases = foreach ($Target in $script:Targets) {
        foreach ($Form in 'Message', 'WebException') {
            foreach ($Code in 400, 401, 404) {
                foreach ($WithDetails in $true, $false) {
                    @{ Label = $Target.Label; Target = $Target.Target; Case = $Target.Case; Form = $Form; Code = $Code; WithDetails = $WithDetails }
                }
            }
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
    InModuleScope SendGridTools {
        function Script:New-SgtFormRecord {
            # Builds the ErrorRecord that Invoke-RestMethod throws, in one of the measured forms.
            # UnreadableCache is the 5.1 form whose cached response cannot be read.
            param([ValidateSet('Message', 'WebException', 'MaximumRedirect', 'UnreadableCache')][string]$Form, [int]$Code, [string]$Location, [string]$Details)
            $Id = 'WebCmdletWebResponseException,Microsoft.PowerShell.Commands.InvokeRestMethodCommand'
            $Target = $null
            switch ($Form) {
                'Message' {
                    $Exception = [SgtFakeHttpResponseException]::new('Response status code does not indicate success.')
                    $Exception.Response = [System.Net.Http.HttpResponseMessage]::new([System.Enum]::ToObject([System.Net.HttpStatusCode], $Code))
                    if ($Location) { $Exception.Response.Headers.Location = [uri]$Location }
                }
                'WebException' {
                    $Exception = [System.Net.WebException]::new('web failure', $null, [System.Net.WebExceptionStatus]::ProtocolError, (New-SgtFakeWebResponse -Code $Code -Location $Location))
                }
                { $_ -in 'MaximumRedirect', 'UnreadableCache' } {
                    $Exception = [System.InvalidOperationException]::new('The maximum redirection count has been exceeded.')
                    $Id = 'MaximumRedirectExceeded,Microsoft.PowerShell.Commands.InvokeRestMethodCommand'
                    $Target = [SgtFakeWebRequest]::new()
                    $Target.HaveResponse = $true
                    $Target.ThrowOnGetResponse = ($Form -eq 'UnreadableCache')
                    $Target.Response = New-SgtFakeWebResponse -Code $Code -Location $Location
                    $Details = 'The maximum redirection count has been exceeded. To increase the number of redirections allowed, supply a higher value to the -MaximumRedirection parameter.'
                }
            }
            $Record = [System.Management.Automation.ErrorRecord]::new($Exception, $Id, [System.Management.Automation.ErrorCategory]::InvalidOperation, $Target)
            if ($Details) { $Record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new($Details) }
            $Record
        }
        function Script:Invoke-SgtSessionTarget {
            # Runs one target and returns the session, the thrown message and the number of calls made.
            param([string]$Target, $Case, [pscredential]$Credential)
            $Session = switch ($Target) {
                # Start connected, so that the assertion on _Connected after a refusal can fail.
                'Connect(credential)' { New-SgtTestSession -Credential $Credential -AgeHours 0 }
                default { New-SgtTestSession -Credential $Credential -AgeHours 0 }
            }
            $Message = $null
            try {
                switch ($Target) {
                    'Connect(credential)' { $Session.Connect($Credential) }
                    'Connect()' { $Session.Connect() }
                    default { $null = Invoke-SgtOverload -Session $Session -Case $Case }
                }
            }
            catch { $Message = $_.Exception.Message }
            [pscustomobject]@{ Session = $Session; Message = $Message }
        }
    }
}

AfterAll {
    InModuleScope SendGridTools {
        Remove-Item -Path 'Function:\New-SgtFakeWebResponse', 'Function:\New-SgtFormRecord', 'Function:\Invoke-SgtSessionTarget' -ErrorAction SilentlyContinue
    }
    Uninstall-SgtSessionHelper
    Disable-SgtNetworkTripwire
}

Describe 'SendGridSession refuses a redirect' {
    BeforeAll {
        $script:Expected = 'SendGrid answered with a redirect to other.example.net; the request was refused so that the API key is not sent there.'
        $script:Location = 'https://other.example.net/v3/scopes?token=abc'
    }

    AfterEach {
        InModuleScope SendGridTools { Reset-SgtNetworkStub }
    }

    It 'Sends -MaximumRedirection 0 from <Label>' -ForEach $script:Targets {
        InModuleScope SendGridTools -Parameters @{ Target = $Target; Case = $Case; Cred = $script:Cred } {
            Set-SgtNetworkStub -Response ([pscustomobject]@{ ok = 'mock-response' })
            $Result = Invoke-SgtSessionTarget -Target $Target -Case $Case -Credential $Cred
            $Result.Message | Should -BeNullOrEmpty
            $Calls = Get-SgtNetworkCall
            $Calls.Count | Should -Be 1
            $Calls[0].MaximumRedirectionPassed | Should -BeTrue
            $Calls[0].MaximumRedirection | Should -Be 0
        }
    }

    It 'Refuses a redirect in <Label> (<Form>)' -ForEach $script:RedirectForms {
        InModuleScope SendGridTools -Parameters @{ Target = $Target; Case = $Case; Form = $Form; Cred = $script:Cred; Expected = $script:Expected; Location = $script:Location } {
            Set-SgtNetworkStub -Throw (New-SgtFormRecord -Form $Form -Code 302 -Location $Location)
            $Result = Invoke-SgtSessionTarget -Target $Target -Case $Case -Credential $Cred
            $Want = if ($Form -eq 'UnreadableCache') { 'SendGrid answered with a redirect to an unknown host; the request was refused so that the API key is not sent there.' } else { $Expected }
            $Result.Message | Should -BeExactly $Want
            $Result.Message | Should -Not -Match 'v3|scopes|token|test-key-not-real'
            if ($Target -like 'Connect*') {
                $Result.Session._Connected | Should -BeFalse
            }
            else {
                $Result.Session.EndpointURL | Should -BeNullOrEmpty
            }
        }
    }

    It 'Refuses a redirect in <Label> (HttpResponseException)' -ForEach $script:Targets -Skip:($PSVersionTable.PSEdition -ne 'Core') {
        InModuleScope SendGridTools -Parameters @{ Target = $Target; Case = $Case; Cred = $script:Cred; Expected = $script:Expected; Location = $script:Location } {
            $Message = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::Found)
            $Message.Headers.Location = [uri]$Location
            $Exception = [Microsoft.PowerShell.Commands.HttpResponseException]::new('Response status code does not indicate success: 302 (Found).', $Message)
            Set-SgtNetworkStub -Throw ([System.Management.Automation.ErrorRecord]::new($Exception, 'WebCmdletWebResponseException,Microsoft.PowerShell.Commands.InvokeRestMethodCommand', [System.Management.Automation.ErrorCategory]::InvalidOperation, $null))
            $Result = Invoke-SgtSessionTarget -Target $Target -Case $Case -Credential $Cred
            $Result.Message | Should -BeExactly $Expected
            if ($Target -like 'Connect*') {
                $Result.Session._Connected | Should -BeFalse
            }
            else {
                $Result.Session.EndpointURL | Should -BeNullOrEmpty
            }
        }
    }

    It 'Keeps today''s message for <Code> in <Label> (<Form>, details: <WithDetails>)' -ForEach $script:UnchangedCases {
        InModuleScope SendGridTools -Parameters @{ Target = $Target; Case = $Case; Form = $Form; Code = $Code; WithDetails = $WithDetails; Cred = $script:Cred } {
            $Details = if ($WithDetails) { '{"errors":[{"message":"bad request"}]}' } else { $null }
            $Record = New-SgtFormRecord -Form $Form -Code $Code -Details $Details
            Set-SgtNetworkStub -Throw $Record
            $Result = Invoke-SgtSessionTarget -Target $Target -Case $Case -Credential $Cred
            if ($Target -like 'Connect*') {
                $Result.Message | Should -BeExactly ('Unable to connect to SendGrid. {0}' -f $Record.Exception.Message)
            }
            elseif ($WithDetails) {
                $Result.Message | Should -BeExactly 'SendGrid Error: "bad request"'
            }
            else {
                $Result.Message | Should -BeExactly ('Unable to query SendGrid: {0}' -f $Record.Exception.Message)
            }
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
