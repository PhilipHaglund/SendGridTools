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

# Sprint 5 step 3 measurements (M1-M3). Each It writes one MEASURE line with key names, made-up targets, error types
# and True/False only, and asserts nothing about the measured value, so the same file measures any version of the
# module. -SandboxMode on a version without it measures a binding error. The -WhatIf target is read in a new process
# whose host records the What if line, answers any choice prompt with Yes and never reads a console.
Describe 'Sprint 5 step 3 measurements' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'M1: the keys in the body of <Name>, <Mode>' -ForEach @(
        foreach ($Shape in 'Default minimal', 'Default with every parameter that reaches the body', 'SeparateTo minimal', 'SeparateTo with every parameter that reaches the body') {
            foreach ($Mode in 'without -SandboxMode', 'with -SandboxMode') {
                @{ Name = $Shape; Mode = $Mode }
            }
        }
    ) {
        $Result = InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Name = $Name; Mode = $Mode } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ placeholder = 'accepted' })
            $Params = @{
                From    = 'sender@example.com'
                To      = 'one@example.com'
                Subject = 'placeholder subject'
                Body    = 'placeholder body'
                Confirm = $false
            }
            if ($Name -like 'SeparateTo*') {
                $Params['To'] = @('one@example.com', 'two@example.com')
                $Params['SeparateTo'] = [switch]::new($true)
            }
            if ($Name -like '*every parameter*') {
                if ($Name -like 'Default*') {
                    $Params['CC'] = 'copy@example.com'
                    $Params['BCC'] = 'blind@example.com'
                }
                $Params['BodyAsHtml'] = [switch]::new($true)
                $Params['Attachment'] = [System.Net.Mail.Attachment]::new([System.IO.MemoryStream]::new([byte[]](104, 105)), 'note.txt', 'text/plain')
                $Params['Priority'] = 'High'
                $Params['ReplyTo'] = 'reply@example.com'
                $Params['SendAt'] = (Get-Date).AddHours(1)
                $Params['TemplateId'] = 'd-placeholder'
                $Params['Categories'] = 'sgt-cat'
            }
            if ($Mode -eq 'with -SandboxMode') { $Params['SandboxMode'] = [switch]::new($true) }
            $Caught = $null
            try { $null = Send-SGMailMessage @Params } catch { $Caught = $_ }
            $Calls = @(Get-SgtNetworkCall | ForEach-Object { $_ })
            if ($Calls.Count) {
                $Sent = $Calls[0].Body | ConvertFrom-Json
                $Keys = (@($Sent.PSObject.Properties.Name | Sort-Object) -join ', ')
                $Personal = @($Sent.personalizations)
                $PersonalKeys = (@($Personal[0].PSObject.Properties.Name | Sort-Object) -join ', ')
                $HasMail = $null -ne $Sent.PSObject.Properties['mail_settings']
                $MailKeys = if ($HasMail) { (@($Sent.mail_settings.PSObject.Properties.Name | Sort-Object) -join ', ') } else { 'none' }
                $Enable = if ($HasMail -and $Sent.mail_settings.sandbox_mode) { "$($Sent.mail_settings.sandbox_mode.enable)" } else { 'none' }
            }
            else {
                $Keys = 'none'; $PersonalKeys = 'none'; $Personal = @(); $HasMail = $false; $MailKeys = 'none'; $Enable = 'none'
            }
            $Type = if ($Caught) { $Caught.Exception.GetType().FullName } else { 'none' }
            $ErrorId = if ($Caught) { $Caught.FullyQualifiedErrorId } else { 'none' }
            'requests {0}; keys {1}; personalizations {2} with keys {3}; mail_settings sent {4}; mail_settings keys {5}; sandbox_mode.enable {6}; threw {7}; error type {8}; error id {9}' -f $Calls.Count, $Keys, $Personal.Count, $PersonalKeys, $HasMail, $MailKeys, $Enable, ($null -ne $Caught), $Type, $ErrorId
        }
        Write-Host ('MEASURE M1 [{0} {1}] Send-SGMailMessage {2}, {3}: {4}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Name, $Mode, $Result)
        $Result | Should -Not -BeNullOrEmpty
    }

    It 'M2: the ShouldProcess target of <Name>, <Mode>' -ForEach @(
        foreach ($Shape in 'Default minimal', 'Default with CC and BCC', 'SeparateTo') {
            foreach ($Mode in 'without -SandboxMode', 'with -SandboxMode') {
                @{ Name = $Shape; Mode = $Mode }
            }
        }
    ) {
        $Extra = switch ($Name) {
            'Default minimal' { "-To 'one@example.com'" }
            'Default with CC and BCC' { "-To 'one@example.com' -CC 'copy@example.com' -BCC 'blind@example.com'" }
            'SeparateTo' { "-To 'one@example.com', 'two@example.com' -SeparateTo" }
        }
        $Switch = if ($Mode -eq 'with -SandboxMode') { '-SandboxMode' } else { '' }
        $Script = @"
try { Send-SGMailMessage -From 'sender@example.com' $Extra -Subject 'placeholder subject' -Body 'placeholder body' $Switch -WhatIf } catch { 'threw {0}' -f `$_.Exception.GetType().FullName }
"@
        $Run = Invoke-SgtInCountingHost -Script $Script
        $WhatIf = @($Run.HostLine | Where-Object { $_ -like 'What if:*' })
        $Target = if ($WhatIf.Count -and $WhatIf[0] -match 'on target "(.*)"\.?\s*$') { $Matches[1] } else { 'none' }
        $Thrown = @($Run.Output | Where-Object { $_ -like 'threw *' })
        $Result = 'What if lines {0}; target {1}; prompts {2}; requests {3}; threw {4}; error type {5}; unmocked calls {6}' -f $WhatIf.Count, $Target, $Run.PromptCount, $Run.NetworkCallCount,
            ($Thrown.Count -gt 0 -or $Run.Threw), $(if ($Thrown.Count) { $Thrown[0].Substring(6) } elseif ($Run.Threw) { $Run.ThrownType } else { 'none' }), $Run.UnmockedCall.Count
        Write-Host ('MEASURE M2 [{0} {1}] Send-SGMailMessage {2}, {3}: {4}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Name, $Mode, $Result)
        $Run.UnmockedCall | Should -BeNullOrEmpty
        $Result | Should -Not -BeNullOrEmpty
    }

    It 'M3: -SandboxMode in the parameter set <Name>' -ForEach @(
        @{ Name = 'Default' }
        @{ Name = 'SeparateTo' }
    ) {
        $Result = InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Name = $Name } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ placeholder = 'accepted' })
            $Params = @{ From = 'sender@example.com'; To = 'one@example.com'; Subject = 'placeholder subject'; Body = 'placeholder body'; SandboxMode = [switch]::new($true); Confirm = $false }
            if ($Name -eq 'SeparateTo') { $Params['SeparateTo'] = [switch]::new($true) }
            $Caught = $null
            try { $null = Send-SGMailMessage @Params } catch { $Caught = $_ }
            $Calls = @(Get-SgtNetworkCall | ForEach-Object { $_ })
            $Binding = $null -ne $Caught -and $Caught.Exception -is [System.Management.Automation.ParameterBindingException]
            'requests {0}; threw {1}; binding error {2}; error type {3}; error id {4}' -f $Calls.Count, ($null -ne $Caught), $Binding,
                $(if ($Caught) { $Caught.Exception.GetType().FullName } else { 'none' }), $(if ($Caught) { $Caught.FullyQualifiedErrorId } else { 'none' })
        }
        Write-Host ('MEASURE M3 [{0} {1}] Send-SGMailMessage -SandboxMode, {2}: {3}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Name, $Result)
        $Result | Should -Not -BeNullOrEmpty
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
