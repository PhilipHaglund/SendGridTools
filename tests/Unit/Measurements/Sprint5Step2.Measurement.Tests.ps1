BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/NetworkTripwire.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/PromptCountingHost.ps1')
    # Import once per run: in Windows PowerShell 5.1 a class stays bound to the first loaded module instance.
    if (-not (Get-Module -Name SendGridTools)) {
        Get-Module -Name SendGridTools -ListAvailable | Select-Object -First 1 | Import-Module -ErrorAction Stop
    }
    Enable-SgtNetworkTripwire
    Assert-SgtNetworkTripwireActive
    $script:PublicPath = Join-Path -Path $PSScriptRoot -ChildPath '../../../source/Public'

    function Get-SgtStep2RuleCount {
        # Runs PSScriptAnalyzer on a script text and returns 'none' or 'Rule xN, ...' sorted by rule name.
        param([string]$Text)
        $Found = @(Invoke-ScriptAnalyzer -ScriptDefinition $Text)
        if ($Found.Count -eq 0) { return 'none' }
        (@($Found | Group-Object -Property RuleName | Sort-Object -Property Name | ForEach-Object { '{0} x{1}' -f $_.Name, $_.Count })) -join ', '
    }

    function Remove-SgtStep2Suppression {
        # Removes every SuppressMessageAttribute for the two rules of step 2, wherever it stands.
        param([string]$Text)
        $Text -replace "\[Diagnostics\.CodeAnalysis\.SuppressMessageAttribute\('(PSAvoidShouldContinueWithoutForce|PSReviewUnusedParameter)'[^\]]*\)\]\s*", ''
    }

    function Add-SgtStep2UnusedProbe {
        # Adds a parameter the function never reads, as the first parameter of the function's own param block.
        param([string]$Text)
        $Regex = [regex]'(?m)^    param \(\r?\n'
        $Regex.Replace($Text, ('$0' + "        [Parameter()]`r`n        [string]`$SgtUnusedProbe,`r`n"), 1)
    }
}

AfterAll {
    Disable-SgtNetworkTripwire
}

# Sprint 5 step 2 measurements (M1-M3). Each It writes one MEASURE line with command names, counts, rule names and
# True/False only, and asserts nothing about the measured value, so the same file measures any version of the module.
# The questions run in a new process whose host answers every choice prompt with Yes, counts them, throws on any
# other prompt and never reads a console. A -Force case on a version without -Force measures a binding error.
Describe 'Sprint 5 step 2 measurements' {
    It 'M1: <Command> <Name>' -ForEach @(
        foreach ($Command in 'New-SGAuthenticatedDomain', 'New-SGBrandedDomainLink') {
            foreach ($Switches in '-Default', '-Default -Confirm:$false', '-Default -Confirm', '-Default -WhatIf', '-Default -Force', '-Default -Force -Confirm:$false', '-Default -Force -Confirm', '-Default -Force -WhatIf') {
                @{ Command = $Command; Name = $Switches }
            }
        }
    ) {
        $Script = @"
try { `$null = $Command -Domain 'example.com' $Name } catch { 'threw {0}' -f `$_.Exception.GetType().FullName }
foreach (`$Call in `$global:SgtNetworkCall) { 'default {0}' -f ("`$(`$Call.Body)" -match '"default"\s*:\s*true') }
"@
        $Run = Invoke-SgtInCountingHost -Script $Script -AnswerJson '{"id":1001}'
        $Thrown = @($Run.Output | Where-Object { $_ -like 'threw *' })
        $DefaultSent = @($Run.Output | Where-Object { $_ -eq 'default True' }).Count -gt 0
        $Result = 'prompts {0}; What if lines {1}; requests {2}; default sent {3}; threw {4}; unmocked calls {5}' -f $Run.PromptCount,
            @($Run.HostLine | Where-Object { $_ -like 'What if:*' }).Count, $Run.NetworkCallCount, $DefaultSent, ($Thrown.Count -gt 0 -or $Run.Threw), $Run.UnmockedCall.Count
        Write-Host ('MEASURE M1 [{0} {1}] {2} {3}: {4}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Command, $Name, $Result)
        $Run.UnmockedCall | Should -BeNullOrEmpty
        $Result | Should -Not -BeNullOrEmpty
    }

    It 'M2: New-SGApiKey -FullAccessKey <Name>' -ForEach @(
        foreach ($Switches in 'without parameters', '-WhatIf', '-Confirm', '-Confirm:$false', '-Force', '-Force -WhatIf', '-Force -Confirm') {
            @{ Name = $Switches }
        }
    ) {
        $Switches = if ($Name -eq 'without parameters') { '' } else { $Name }
        $Script = @"
try { `$null = New-SGApiKey -Name 'placeholder-key' -FullAccessKey $Switches } catch { 'threw {0}' -f `$_.Exception.GetType().FullName }
"@
        $Run = Invoke-SgtInCountingHost -Script $Script -AnswerJson '{"name":"placeholder-key"}'
        $Thrown = @($Run.Output | Where-Object { $_ -like 'threw *' })
        $Result = 'prompts {0}; What if lines {1}; requests {2}; threw {3}; unmocked calls {4}' -f $Run.PromptCount,
            @($Run.HostLine | Where-Object { $_ -like 'What if:*' }).Count, $Run.NetworkCallCount, ($Thrown.Count -gt 0 -or $Run.Threw), $Run.UnmockedCall.Count
        Write-Host ('MEASURE M2 [{0} {1}] New-SGApiKey -FullAccessKey {2}: {3}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Name, $Result)
        $Run.UnmockedCall | Should -BeNullOrEmpty
        $Result | Should -Not -BeNullOrEmpty
    }

    It 'M3: PSScriptAnalyzer on <Command>' -ForEach @(
        @{ Command = 'New-SGAuthenticatedDomain' }
        @{ Command = 'New-SGBrandedDomainLink' }
        @{ Command = 'New-SGApiKey' }
        @{ Command = 'Set-SGApiKey' }
    ) {
        $Text = [System.IO.File]::ReadAllText((Join-Path -Path $script:PublicPath -ChildPath "$Command.ps1"))
        $Stripped = Remove-SgtStep2Suppression -Text $Text
        $Probe = @(Invoke-ScriptAnalyzer -ScriptDefinition (Add-SgtStep2UnusedProbe -Text $Text) | Where-Object { $_.RuleName -eq 'PSReviewUnusedParameter' -and $_.Message -like '*SgtUnusedProbe*' }).Count -gt 0
        $Result = 'as committed {0}; without the step 2 suppressions {1}; an unused function parameter reported as committed {2}' -f (Get-SgtStep2RuleCount -Text $Text), (Get-SgtStep2RuleCount -Text $Stripped), $Probe
        Write-Host ('MEASURE M3 [{0} {1}] {2}: {3}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Command, $Result)
        $Result | Should -Not -BeNullOrEmpty
    }

    It 'M3: what PSScriptAnalyzer respects for the completer of <Command>, <Name>' -ForEach @(
        foreach ($Command in 'New-SGAuthenticatedDomain', 'New-SGApiKey', 'Set-SGApiKey') {
            @{ Command = $Command; Name = 'suppression on the completer param block' }
            @{ Command = $Command; Name = 'completer without a param block, reading the word to complete from args' }
        }
    ) {
        $Text = Remove-SgtStep2Suppression -Text ([System.IO.File]::ReadAllText((Join-Path -Path $script:PublicPath -ChildPath "$Command.ps1")))
        $CompleterParam = '(?s)param\(\s*\[string\]\$CommandName,\s*\[string\]\$ParameterName,\s*\[string\]\$WordToComplete,\s*\$CommandAst,\s*\$FakeBoundParameters\s*\)'
        if ($Text -notmatch $CompleterParam) {
            $Result = 'not applicable, the completer no longer has the five-parameter param block'
        }
        else {
            $Variant = if ($Name -like 'suppression*') {
                $Text -replace $CompleterParam, "[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'measurement')]`r`n$&"
            }
            else {
                $Text -replace $CompleterParam, '$$WordToComplete = $$args[2]'
            }
            $Probe = @(Invoke-ScriptAnalyzer -ScriptDefinition (Add-SgtStep2UnusedProbe -Text $Variant) | Where-Object { $_.RuleName -eq 'PSReviewUnusedParameter' -and $_.Message -like '*SgtUnusedProbe*' }).Count -gt 0
            $Result = 'findings {0}; an unused function parameter reported {1}' -f (Get-SgtStep2RuleCount -Text $Variant), $Probe
        }
        Write-Host ('MEASURE M3 [{0} {1}] {2}, {3}: {4}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Command, $Name, $Result)
        $Result | Should -Not -BeNullOrEmpty
    }

    It 'M3: control, an unused parameter in a minimal function <Name>' -ForEach @(
        @{ Name = 'that reads its other parameter by name'; Text = "function Test-SgtProbe {`r`n    [CmdletBinding()]`r`n    param (`r`n        [string]`$Used`r`n    )`r`n    `$Used`r`n}`r`n" }
        @{ Name = 'that also reads PSBoundParameters'; Text = "function Test-SgtProbe {`r`n    [CmdletBinding()]`r`n    param (`r`n        [string]`$Used`r`n    )`r`n    `$Used`r`n    `$PSBoundParameters.Count`r`n}`r`n" }
    ) {
        $Probe = @(Invoke-ScriptAnalyzer -ScriptDefinition (Add-SgtStep2UnusedProbe -Text $Text) | Where-Object { $_.RuleName -eq 'PSReviewUnusedParameter' -and $_.Message -like '*SgtUnusedProbe*' }).Count -gt 0
        $Result = 'an unused function parameter reported {0}' -f $Probe
        Write-Host ('MEASURE M3 [{0} {1}] control, minimal function {2}: {3}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Name, $Result)
        $Result | Should -Not -BeNullOrEmpty
    }

    It 'M3: an unused parameter in <Command> with PSBoundParameters renamed in the measured text, <Name>' -ForEach @(
        foreach ($Command in 'New-SGAuthenticatedDomain', 'New-SGBrandedDomainLink', 'New-SGApiKey', 'Set-SGApiKey') {
            @{ Command = $Command; Name = 'as committed' }
            @{ Command = $Command; Name = 'without the step 2 suppressions' }
        }
    ) {
        # PSReviewUnusedParameter skips a script block that reads PSBoundParameters (control above). The rename is made in
        # the measured text only, so that the suppressions decide alone whether an unused parameter is reported.
        $Text = [System.IO.File]::ReadAllText((Join-Path -Path $script:PublicPath -ChildPath "$Command.ps1"))
        if ($Name -like 'without*') { $Text = Remove-SgtStep2Suppression -Text $Text }
        $Text = $Text -replace '\$PSBoundParameters\b', '$SgtBoundProbe'
        $Probe = @(Invoke-ScriptAnalyzer -ScriptDefinition (Add-SgtStep2UnusedProbe -Text $Text) | Where-Object { $_.RuleName -eq 'PSReviewUnusedParameter' -and $_.Message -like '*SgtUnusedProbe*' }).Count -gt 0
        $Result = 'an unused function parameter reported {0}' -f $Probe
        Write-Host ('MEASURE M3 [{0} {1}] {2}, PSBoundParameters renamed, {3}: {4}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Command, $Name, $Result)
        $Result | Should -Not -BeNullOrEmpty
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
