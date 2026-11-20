BeforeDiscovery {
    # One entry per catch block under source/Public that writes an error: Line is the line of
    # tests/Unit/Fixtures/CommandErrorText.e155c0c.txt. Mode says how the stub answers:
    #   T  every call throws the 404 error
    #   G  a Get call answers with a made-up object and every other call throws (a command that reads before it writes)
    #   D  the first call answers with a made-up object (a dynamic parameter reads first) and every later call throws
    # Params are made-up values only; '<cred>' and '<secure>' become a credential and a secure string at run time.
    # Exact is set for a block that does not wrap a SendGrid call: the text and the inner exception are asserted, not the status.
    # SkipReason is set for a block that cannot be reached without a console or a network.
    $script:Entries = @(
        @{ Line = 1; Command = 'Add-SGEmailAddressToSuppressionGroup'; Mode = 'T'; Params = @{ UniqueId = 1001; EmailAddresses = 'one@example.com' }; Prefix = 'Failed to add email addresses to suppression group. ' }
        @{ Line = 2; Command = 'Add-SGGlobalSuppression'; Mode = 'T'; Params = @{ EmailAddress = 'one@example.com' }; Prefix = 'Failed to add email address "one@example.com" to the global suppressions list. ' }
        @{ Line = 3; Command = 'Confirm-SGAuthenticatedDomain'; Mode = 'G'; Params = @{ UniqueId = '1001' }; Prefix = 'Failed to validate SendGrid Authenticated Domain. ' }
        @{ Line = 4; Command = 'Confirm-SGBrandedDomainLink'; Mode = 'G'; Params = @{ UniqueId = '1001' }; Prefix = 'Failed to validate SendGrid Branded Domain Link. ' }
        @{ Line = 5; Command = 'Connect-SendGrid'; Mode = 'T'; Params = @{ Credential = '<cred>'; BaseUri = 'http://example.com/v3' }; Prefix = 'Unable to connect to SendGrid. Error detail: '; Exact = 'Unable to connect to SendGrid. Error detail: The base URI must use https; the scheme given is ''http''.' }
        @{ Line = 6; Command = 'Connect-SendGrid'; Mode = 'T'; Params = @{ Credential = '<cred>' }; Prefix = 'Unable to connect to SendGrid. Error detail: ' }
        @{ Line = 7; Command = 'Disable-SGSubuser'; Mode = 'T'; Params = @{ Username = 'sgt-test-item' }; Prefix = 'Failed to disable SendGrid Subuser. ' }
        @{ Line = 8; Command = 'Disconnect-SendGrid'; Mode = 'T'; Params = @{}; Prefix = 'Unable to disconnect from SendGrid. '; Exact = 'Unable to disconnect from SendGrid. made-up removal failure' }
        @{ Line = 9; Command = 'Enable-SGSubuser'; Mode = 'T'; Params = @{ Username = 'sgt-test-item' }; Prefix = 'Failed to enable SendGrid Subuser. ' }
        @{ Line = 10; Command = 'Get-SGAddressWhitelistSetting'; Mode = 'T'; Params = @{}; Prefix = 'Failed to retrieve SendGrid address whitelist settings. ' }
        @{ Line = 11; Command = 'Get-SGAlert'; Mode = 'T'; Params = @{ AlertId = '1001' }; Prefix = 'Failed to retrieve SendGrid alert. ' }
        @{ Line = 12; Command = 'Get-SGAlert'; Mode = 'T'; Params = @{}; Prefix = 'Failed to retrieve SendGrid alert(s). ' }
        @{ Line = 13; Command = 'Get-SGApiKey'; Mode = 'T'; Params = @{ ApiKeyId = 'key-id-1' }; Prefix = 'Failed to retrieve SendGrid API Key. ' }
        @{ Line = 14; Command = 'Get-SGApiKey'; Mode = 'T'; Params = @{}; Prefix = 'Failed to retrieve SendGrid API Key. ' }
        @{ Line = 15; Command = 'Get-SGAuthenticatedDomain'; Mode = 'T'; Params = @{}; Prefix = 'Failed to make SendGrid API call. '; Wrapped = $true }
        @{ Line = 16; Command = 'Get-SGAuthenticatedDomain'; Mode = 'T'; Params = @{ Id = '1001' }; Prefix = 'Failed to retrieve SendGrid Authenticated Domain. ' }
        @{ Line = 17; Command = 'Get-SGAuthenticatedDomain'; Mode = 'D'; Params = @{}; Prefix = 'Failed to retrieve all SendGrid Authenticated Domain. ' }
        @{ Line = 18; Command = 'Get-SGBlock'; Mode = 'T'; Params = @{ EmailAddress = 'one@example.com' }; Prefix = 'Failed to retrieve SendGrid block. ' }
        @{ Line = 19; Command = 'Get-SGBlock'; Mode = 'T'; Params = @{}; Prefix = 'Failed to retrieve all SendGrid blocks. ' }
        @{ Line = 20; Command = 'Get-SGBounce'; Mode = 'T'; Params = @{ EmailAddress = 'one@example.com' }; Prefix = 'Failed to retrieve SendGrid bounce. ' }
        @{ Line = 21; Command = 'Get-SGBounce'; Mode = 'T'; Params = @{}; Prefix = 'Failed to retrieve all SendGrid bounces. ' }
        @{ Line = 22; Command = 'Get-SGBounceByClassification'; Mode = 'T'; Params = @{}; Prefix = 'Failed to retrieve SendGrid bounce classifications. ' }
        @{ Line = 23; Command = 'Get-SGBouncePurgeSetting'; Mode = 'T'; Params = @{}; Prefix = 'Failed to retrieve SendGrid bounce purge settings. ' }
        @{ Line = 24; Command = 'Get-SGBrandedDomainLink'; Mode = 'T'; Params = @{ UniqueId = '1001' }; Prefix = 'Failed to retrieve SendGrid SendGrid Branded Domain Link. ' }
        @{ Line = 25; Command = 'Get-SGBrandedDomainLink'; Mode = 'D'; Params = @{}; Prefix = 'Failed to retrieve all SendGrid SendGrid Branded Domain Links. ' }
        @{ Line = 26; Command = 'Get-SGDesign'; Mode = 'T'; Params = @{}; Prefix = 'Failed to retrieve SendGrid Design. ' }
        @{ Line = 27; Command = 'Get-SGEmailActivity'; Mode = 'T'; Params = @{ SendGridFilter = 'status="delivered"' }; Prefix = 'Failed to retrieve SendGrid email activity. ' }
        @{ Line = 28; Command = 'Get-SGEnforcedTls'; Mode = 'T'; Params = @{}; Prefix = 'Failed to retrieve SendGrid Enforced TLS settings. ' }
        @{ Line = 29; Command = 'Get-SGForwardBounceSetting'; Mode = 'T'; Params = @{}; Prefix = 'Failed to retrieve SendGrid forward bounce settings. ' }
        @{ Line = 30; Command = 'Get-SGForwardSpamSetting'; Mode = 'T'; Params = @{}; Prefix = 'Failed to retrieve SendGrid forward spam settings. ' }
        @{ Line = 31; Command = 'Get-SGGlobalSuppression'; Mode = 'T'; Params = @{ EmailAddress = 'one@example.com' }; Prefix = 'Failed to retrieve SendGrid suppression report. ' }
        @{ Line = 32; Command = 'Get-SGGlobalSuppression'; Mode = 'T'; Params = @{}; Prefix = 'Failed to retrieve all SendGrid suppression reports. ' }
        @{ Line = 33; Command = 'Get-SGIPAddress'; Mode = 'T'; Params = @{ IncludeRegion = $true }; Prefix = 'Failed to retrieve SendGrid IPs. ' }
        @{ Line = 34; Command = 'Get-SGIPAddress'; Mode = 'T'; Params = @{}; Prefix = 'Failed to retrieve SendGrid IPs. ' }
        @{ Line = 35; Command = 'Get-SGInvalidEmail'; Mode = 'T'; Params = @{ EmailAddress = 'one@example.com' }; Prefix = 'Failed to retrieve SendGrid invalid email. ' }
        @{ Line = 36; Command = 'Get-SGInvalidEmail'; Mode = 'T'; Params = @{}; Prefix = 'Failed to retrieve SendGrid invalid emails. ' }
        @{ Line = 37; Command = 'Get-SGMailSetting'; Mode = 'T'; Params = @{}; Prefix = 'Failed to retrieve SendGrid mail settings. ' }
        @{ Line = 38; Command = 'Get-SGPermissionScopes'; Mode = 'T'; Params = @{}; Prefix = 'Failed to retrieve permission scopes in SendGrid. ' }
        @{ Line = 39; Command = 'Get-SGSpamReport'; Mode = 'T'; Params = @{ EmailAddress = 'one@example.com' }; Prefix = 'Failed to retrieve SendGrid spam report. ' }
        @{ Line = 40; Command = 'Get-SGSpamReport'; Mode = 'T'; Params = @{}; Prefix = 'Failed to retrieve SendGrid spam reports. ' }
        @{ Line = 41; Command = 'Get-SGSubuser'; Mode = 'T'; Params = @{}; Prefix = 'Failed to retrieve SendGrid Subuser. ' }
        @{ Line = 42; Command = 'Get-SGSuppression'; Mode = 'T'; Params = @{}; Prefix = 'Failed to retrieve suppressions. ' }
        @{ Line = 43; Command = 'Get-SGSuppressionGroup'; Mode = 'T'; Params = @{}; Prefix = 'Failed to retrieve suppression group(s). ' }
        @{ Line = 44; Command = 'Get-SGTeammate'; Mode = 'T'; Params = @{ Username = 'sgt-test-item' }; Prefix = 'Failed to retrieve SendGrid teammate. ' }
        @{ Line = 45; Command = 'Get-SGTeammate'; Mode = 'T'; Params = @{}; Prefix = 'Failed to retrieve all SendGrid teammates. ' }
        @{ Line = 46; Command = 'Invoke-SGCommand'; Mode = 'T'; Params = @{ Namespace = 'scopes' }; Prefix = 'Failed to make SendGrid API call. ' }
        @{ Line = 47; Command = 'New-SGAlert'; Mode = 'T'; Params = @{ EmailCreditUsage = $true; EmailTo = 'one@example.com'; Percentage = 50 }; Prefix = 'Failed to create SendGrid alert. ' }
        @{ Line = 48; Command = 'New-SGApiKey'; Mode = 'T'; Params = @{ Name = 'sgt-test-key'; FullAccessKey = $true; Force = $true }; Prefix = 'Failed to create a FullAccess SendGrid API key. ' }
        @{ Line = 49; Command = 'New-SGApiKey'; Mode = 'T'; Params = @{ Name = 'sgt-test-key'; Scope = 'mail.send' }; Prefix = 'Failed to create SendGrid API key. ' }
        @{ Line = 50; Command = 'New-SGAuthenticatedDomain'; Mode = 'T'; Params = @{ Domain = 'example.com' }; Prefix = 'Failed to add SendGrid Authenticated Domain. ' }
        @{ Line = 51; Command = 'New-SGBrandedDomainLink'; Mode = 'T'; Params = @{ Domain = 'example.com' }; Prefix = 'Failed to create SendGrid Branded Domain Link. ' }
        @{ Line = 52; Command = 'New-SGSubuser'; Mode = 'T'; Params = @{ Username = 'sgt-test-item'; Email = 'one@example.com'; Password = '<secure>'; Ips = '192.0.2.10' }; Prefix = 'Failed to create SendGrid Subuser. ' }
        @{ Line = 53; Command = 'New-SGSuppressionGroup'; Mode = 'T'; Params = @{ Name = 'sgt-test-item'; Description = 'placeholder description' }; Prefix = 'Failed to create a new suppression group. ' }
        @{ Line = 54; Command = 'Remove-SGAlert'; Mode = 'T'; Params = @{ UniqueId = 1001 }; Prefix = 'Failed to delete SendGrid alert. ' }
        @{ Line = 55; Command = 'Remove-SGApiKey'; Mode = 'G'; Params = @{ UniqueId = 'key-id-1' }; Prefix = 'Failed to delete SendGrid API Key. ' }
        @{ Line = 56; Command = 'Remove-SGAuthenticatedDomain'; Mode = 'G'; Params = @{ UniqueId = '1001' }; Prefix = 'Failed to remove SendGrid Authenticated Domain. ' }
        @{ Line = 57; Command = 'Remove-SGBlock'; Mode = 'T'; Params = @{ DeleteAll = $true }; Prefix = 'Failed to remove all SendGrid blocks. ' }
        @{ Line = 58; Command = 'Remove-SGBlock'; Mode = 'T'; Params = @{ EmailAddress = 'one@example.com' }; Prefix = 'Failed to remove SendGrid block "one@example.com". ' }
        @{ Line = 59; Command = 'Remove-SGBounce'; Mode = 'T'; Params = @{ DeleteAll = $true }; Prefix = 'Failed to remove all SendGrid bounces. ' }
        @{ Line = 60; Command = 'Remove-SGBounce'; Mode = 'T'; Params = @{ EmailAddress = 'one@example.com' }; Prefix = 'Failed to remove SendGrid bounce "one@example.com". ' }
        @{ Line = 61; Command = 'Remove-SGBrandedDomainLink'; Mode = 'G'; Params = @{ UniqueId = '1001' }; Prefix = 'Failed to remove SendGrid Branded Domain Link. ' }
        @{ Line = 62; Command = 'Remove-SGGlobalSuppression'; Mode = 'T'; Params = @{ InputObject = 'not an address' }; Prefix = 'Failed to convert InputObject to an email address.'; Exact = 'Failed to convert InputObject to an email address.' }
        @{ Line = 63; Command = 'Remove-SGGlobalSuppression'; Mode = 'T'; Params = @{ EmailAddress = 'one@example.com' }; Prefix = 'Failed to remove email address "one@example.com" from global suppressions list. ' }
        @{ Line = 64; Command = 'Remove-SGInvalidEmail'; Mode = 'T'; Params = @{ DeleteAll = $true }; Prefix = 'Failed to remove all SendGrid invalid email address. ' }
        @{ Line = 65; Command = 'Remove-SGInvalidEmail'; Mode = 'T'; Params = @{ EmailAddress = 'one@example.com' }; Prefix = 'Failed to remove SendGrid invalid email address "one@example.com". ' }
        @{ Line = 66; Command = 'Remove-SGSpamReport'; Mode = 'T'; Params = @{ DeleteAll = $true }; Prefix = 'Failed to remove all email addresses from SendGrid spam reports. ' }
        @{ Line = 67; Command = 'Remove-SGSpamReport'; Mode = 'T'; Params = @{ EmailAddress = 'one@example.com' }; Prefix = 'Failed to remove email address "one@example.com" from SendGrid spam report. ' }
        @{ Line = 68; Command = 'Remove-SGSubuser'; Mode = 'T'; Params = @{ Username = 'sgt-test-item' }; Prefix = 'Failed to remove SendGrid Subuser. ' }
        @{ Line = 69; Command = 'Remove-SGSuppressionGroup'; Mode = 'T'; Params = @{ UniqueId = 1001 }; Prefix = 'Failed to delete suppression group. ' }
        @{ Line = 70; Command = 'Send-SGMailMessage'; Mode = 'T'; Params = @{ From = 'sender@example.com'; To = 'one@example.com'; Subject = 'placeholder subject'; Body = 'placeholder body' }; Prefix = 'Failed to send email via SendGrid API. ' }
        @{ Line = 71; Command = 'Set-SGAddressWhitelistSetting'; Mode = 'T'; Params = @{ Enabled = $true }; Prefix = 'Failed to update SendGrid address whitelist settings. ' }
        @{ Line = 72; Command = 'Set-SGAlert'; Mode = 'T'; Params = @{ AlertId = 1001; Frequency = 'Weekly' }; Prefix = 'Failed to retrieve SendGrid alert. Failed to retrieve SendGrid alert. ' }
        @{ Line = 73; Command = 'Set-SGAlert'; Mode = 'G'; Params = @{ AlertId = 1001; Frequency = 'Weekly' }; Prefix = 'Failed to update SendGrid alert. ' }
        @{ Line = 74; Command = 'Set-SGApiKey'; Mode = 'G'; Params = @{ UniqueId = 'key-id-1'; NewName = 'sgt-test-key' }; Prefix = 'Failed to update SendGrid API Key. ' }
        @{ Line = 75; Command = 'Set-SGAuthenticatedDomain'; Mode = 'T'; Params = @{ UniqueId = '1001' }; Prefix = 'Failed to set properties for SendGrid Authenticated Domain. ' }
        @{ Line = 76; Command = 'Set-SGAuthenticatedDomainToSubUser'; Mode = 'G'; Params = @{ UniqueId = '1001'; UserName = 'sgt-test-item' }; Prefix = 'Failed to assign authenticated domain. ' }
        @{ Line = 77; Command = 'Set-SGBouncePurgeSetting'; Mode = 'T'; Params = @{ Enabled = $true }; Prefix = 'Failed to update SendGrid bounce purge settings. ' }
        @{ Line = 78; Command = 'Set-SGBrandedDomainLink'; Mode = 'T'; Params = @{ UniqueId = '1001' }; Prefix = 'Failed to set properties for SendGrid Branded Domain Link. ' }
        @{ Line = 79; Command = 'Set-SGEnforcedTls'; Mode = 'T'; Params = @{ RequireTls = $true }; Prefix = 'Failed to update SendGrid Enforced TLS settings. ' }
        @{ Line = 80; Command = 'Set-SGForwardBounceSetting'; Mode = 'T'; Params = @{ Enabled = $true }; Prefix = 'Failed to update SendGrid forward bounce settings. ' }
        @{ Line = 81; Command = 'Set-SGForwardSpamSetting'; Mode = 'T'; Params = @{ Enabled = $true }; Prefix = 'Failed to update SendGrid forward spam settings. ' }
        @{ Line = 82; Command = 'Set-SGSuppressionGroup'; Mode = 'T'; Params = @{ UniqueId = 1001; Name = 'sgt-test-item' }; Prefix = 'Failed to update suppression group. ' }
    )
    foreach ($Entry in $script:Entries) {
        $Entry['Label'] = '{0:00} {1} {2}' -f $Entry.Line, $Entry.Command, (($Entry.Params.Keys | Sort-Object) -join ',')
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
    $script:Secure = ConvertTo-SecureString -String 'placeholder-not-real' -AsPlainText -Force
    $script:FixturePath = Join-Path -Path $PSScriptRoot -ChildPath '../Fixtures/CommandErrorText.e155c0c.txt'

    InModuleScope SendGridTools {
        function Script:New-SgtPathRecord {
            # Builds the ErrorRecord that Invoke-RestMethod throws for a 404 with one SendGrid error that names a field,
            # in the shape of the running shell: an HttpResponseException in PowerShell 7 and a WebException with a
            # response in Windows PowerShell 5.1.
            $Code = 404
            $Details = '{"errors":[{"field":"name","message":"resource not found"}]}'
            $Status = [System.Enum]::ToObject([System.Net.HttpStatusCode], $Code)
            if ($PSVersionTable.PSEdition -eq 'Core') {
                $Message = [System.Net.Http.HttpResponseMessage]::new($Status)
                $Exception = [Microsoft.PowerShell.Commands.HttpResponseException]::new(('Response status code does not indicate success: {0} ({1}).' -f $Code, $Status), $Message)
            }
            else {
                $Exception = [System.Net.WebException]::new(('The remote server returned an error: ({0}) {1}.' -f $Code, $Status), $null, [System.Net.WebExceptionStatus]::ProtocolError, (New-SgtFakeWebResponse -Code $Code))
            }
            $Record = [System.Management.Automation.ErrorRecord]::new($Exception, 'WebCmdletWebResponseException,Microsoft.PowerShell.Commands.InvokeRestMethodCommand', [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
            $Record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new($Details)
            $Record
        }
        function Script:Set-SgtPathStub {
            # Mode T: every call throws. G: a Get call answers, every other call throws. D: the first call answers, later calls throw.
            param([string]$Mode)
            $global:SgtNetworkCall.Clear()
            $global:SgtStubValue = New-SgtPathRecord
            $global:SgtStubMode = $Mode
            $global:SgtGetValue = [pscustomobject]@{
                id = 1001; api_key_id = 'key-id-1'; name = 'sgt-test-item'; type = 'stats_notification'
                domain = 'example.com'; subdomain = 'em1234'; valid = $false; scopes = @('mail.send')
            }
            $global:SgtNetworkStub = {
                $Call = $global:SgtNetworkCall[-1]
                $Answer = switch ($global:SgtStubMode) {
                    'G' { $Call.Method -eq 'Get' }
                    'D' { $global:SgtNetworkCall.Count -eq 1 }
                    default { $false }
                }
                if ($Answer) { $global:SgtGetValue } else { throw $global:SgtStubValue }
            }
        }
    }
}

AfterAll {
    InModuleScope SendGridTools {
        Remove-Item -Path 'Function:\New-SgtFakeWebResponse', 'Function:\New-SgtPathRecord', 'Function:\Set-SgtPathStub' -ErrorAction SilentlyContinue
    }
    Remove-Variable -Name SgtStubMode, SgtGetValue -Scope Global -ErrorAction SilentlyContinue
    Uninstall-SgtSessionHelper
    Disable-SgtNetworkTripwire
}

Describe 'The error path of every command' {
    BeforeAll {
        Mock -CommandName Confirm-SendGridContinue -ModuleName SendGridTools -MockWith { $true }
    }

    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It '<Label> keeps the text, the status, the fields and the cause' -ForEach $script:Entries {
        if ($SkipReason) { Set-ItResult -Skipped -Because $SkipReason; return }
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Mode = $Mode; Command = $Command } {
            $script:Session = if ($Command -eq 'Connect-SendGrid') { $null } else { New-SgtTestSession -Credential $Cred -AgeHours 0 }
            Set-SgtPathStub -Mode $Mode
        }
        $Splat = @{}
        foreach ($Name in $Params.Keys) {
            $Value = $Params[$Name]
            if ($Value -is [string] -and $Value -eq '<cred>') { $Value = $script:Cred }
            elseif ($Value -is [string] -and $Value -eq '<secure>') { $Value = $script:Secure }
            $Splat[$Name] = $Value
        }
        # Read from the attribute, not from .Parameters: that would run a dynamic parameter block, which calls SendGrid.
        $Binding = @((Get-Command -Name $Command).ScriptBlock.Attributes | Where-Object { $_ -is [System.Management.Automation.CmdletBindingAttribute] })
        if ($Binding.Count -eq 1 -and $Binding[0].SupportsShouldProcess) { $Splat['Confirm'] = $false }
        $Caught = $null
        if ($Command -eq 'Disconnect-SendGrid') {
            # The error of this command is non-terminating, so it is read from the error stream.
            Mock -CommandName Remove-Variable -ModuleName SendGridTools -ParameterFilter { $Name -eq 'Session' } -MockWith { throw 'made-up removal failure' }
            $Stream = @(Disconnect-SendGrid @Splat -ErrorAction Continue 2>&1)
            $Records = @($Stream | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Records.Count | Should -Be 1
            $Caught = $Records[0]
        }
        else {
            try { $null = & $Command @Splat } catch { $Caught = $_ }
        }
        $Caught | Should -Not -BeNullOrEmpty
        if ($Wrapped) {
            # PowerShell wraps an error raised in a dynamic parameter block; the command's own error is the first
            # WriteErrorException in the chain of inner exceptions.
            $Caught.Exception.Message | Should -BeLike 'Cannot retrieve the dynamic parameters for the cmdlet.*'
            $Caught.Exception.Message | Should -BeLike ('*' + $Prefix + 'SendGrid Error (HTTP 404): "name: resource not found"*')
            $Inner = $Caught.Exception
            for ($Depth = 0; $Depth -lt 10 -and $null -ne $Inner -and $Inner -isnot [Microsoft.PowerShell.Commands.WriteErrorException]; $Depth++) {
                $Next = $Inner.InnerException
                if ($null -eq $Next -and $null -ne $Inner.ErrorRecord -and -not [object]::ReferenceEquals($Inner.ErrorRecord.Exception, $Inner)) { $Next = $Inner.ErrorRecord.Exception }
                $Inner = $Next
            }
            $Inner | Should -Not -BeNullOrEmpty
            $Caught = [pscustomobject]@{ Exception = $Inner; FullyQualifiedErrorId = "Microsoft.PowerShell.Commands.WriteErrorException,$Command" }
        }
        if ($Exact) {
            $Caught.Exception.Message | Should -BeExactly $Exact
        }
        else {
            $Caught.Exception.Message | Should -BeExactly ($Prefix + 'SendGrid Error (HTTP 404): "name: resource not found"')
        }
        $Caught.Exception | Should -BeOfType [Microsoft.PowerShell.Commands.WriteErrorException]
        $Caught.FullyQualifiedErrorId | Should -BeExactly "Microsoft.PowerShell.Commands.WriteErrorException,$Command"
        $Caught.Exception.InnerException | Should -Not -BeNullOrEmpty
        if (-not $Exact) {
            $Caught.Exception.Data['StatusCode'] | Should -Be 404
            $Caught.Exception.Data['StatusCode'] | Should -BeOfType [int]
            @($Caught.Exception.Data['SendGridErrors']).Count | Should -Be 1
            @($Caught.Exception.Data['SendGridErrors'])[0].Field | Should -BeExactly 'name'
            @($Caught.Exception.Data['SendGridErrors'])[0].Message | Should -BeExactly 'resource not found'
        }
        Should -Invoke -CommandName Confirm-SendGridContinue -ModuleName SendGridTools -Times 0 -Exactly
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}

Describe 'The table of error paths' {
    BeforeAll {
        $script:Fixture = @(Get-Content -LiteralPath $script:FixturePath)
    }

    It 'Has one entry or one listed skip for every line of the fixture' -ForEach @(@{ EntryLine = @($script:Entries | ForEach-Object { $_.Line }) }) {
        $script:Fixture.Count | Should -BeGreaterThan 0
        $Lines = @($EntryLine | Sort-Object)
        ($Lines -join ',') | Should -BeExactly ((1..$script:Fixture.Count) -join ',')
    }

    It '<Label> is the command of its fixture line, with the text of that line' -ForEach $script:Entries {
        $Line = $script:Fixture[$Line - 1]
        $Line | Should -Not -BeNullOrEmpty
        $File, $Expression = $Line -split '\|', 2
        $File | Should -BeExactly ($Command + '.ps1')
        $Literal = (($Expression -replace "^\('", '') -replace '\{\d\}.*$', '') -replace "'\)$", ''
        $Prefix.StartsWith($Literal) | Should -BeTrue -Because "the prefix '$Prefix' must start with the literal text '$Literal' of the fixture line"
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
