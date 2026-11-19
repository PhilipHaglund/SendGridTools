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

# Sprint 5 step 1 measurements (M1-M5). Each It writes one MEASURE line with command names, made-up queries and
# paths, error types and True/False only, and asserts nothing about the measured value, so the same file measures
# any version of the module. Get-SGTeammate -Username and the questions of Remove-SGSubuser run in a new process
# whose host answers choice prompts with Yes, throws on any other prompt and never reads a console.
Describe 'Sprint 5 step 1 measurements' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'M1: the query <Command> sends for a+b@example.com, <Name>' -ForEach @(
        foreach ($Command in 'Get-SGBlock', 'Get-SGBounce', 'Get-SGGlobalSuppression', 'Get-SGInvalidEmail', 'Get-SGSpamReport') {
            @{ Command = $Command; Name = 'without -Limit'; Limit = 0 }
            @{ Command = $Command; Name = 'with -Limit 10'; Limit = 10 }
        }
    ) {
        $Result = InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Command = $Command; Limit = $Limit } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ email = 'placeholder@example.com' })
            $Params = @{ EmailAddress = 'a+b@example.com' }
            if ($Limit) { $Params['Limit'] = $Limit }
            $Caught = $null
            try { $null = & $Command @Params } catch { $Caught = $_ }
            $Calls = Get-SgtNetworkCall
            $Query = if ($Calls.Count) { ([uri]$Calls[0].Uri).Query } else { '' }
            'requests {0}; query {1}; raw plus in query {2}; threw {3}' -f $Calls.Count, $Query, ($Query -like '*a+b@*'), ($null -ne $Caught)
        }
        Write-Host ('MEASURE M1 [{0} {1}] {2} {3}: {4}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Command, $Name, $Result)
        $Result | Should -Not -BeNullOrEmpty
    }

    It 'M2: the path <Command> sends for the name a b+c' -ForEach @(
        @{ Command = 'Disable-SGSubuser' }
        @{ Command = 'Enable-SGSubuser' }
        @{ Command = 'Remove-SGSubuser' }
    ) {
        $Result = InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Command = $Command } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })
            $Caught = $null
            try { $null = & $Command -Username 'a b+c' -Confirm:$false } catch { $Caught = $_ }
            $Calls = Get-SgtNetworkCall
            $Path = if ($Calls.Count) { ([uri]$Calls[0].Uri).AbsolutePath } else { '' }
            'requests {0}; method {1}; path {2}; threw {3}' -f $Calls.Count, $(if ($Calls.Count) { $Calls[0].Method } else { '' }), $Path, ($null -ne $Caught)
        }
        Write-Host ('MEASURE M2 [{0} {1}] {2}: {3}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Command, $Result)
        $Result | Should -Not -BeNullOrEmpty
    }

    It 'M2: the path Get-SGTeammate sends for the name a b+c' {
        # A new process: before the fix the -Username branch calls Invoke-SendGrid without parameters, and a real host would ask for them.
        $Script = @'
try { $null = Get-SGTeammate -Username 'a b+c' } catch { 'threw {0}' -f $_.Exception.GetType().FullName }
foreach ($Call in $global:SgtNetworkCall) { 'path {0}' -f ([uri]$Call.Uri).AbsolutePath }
'@
        $Run = Invoke-SgtInCountingHost -Script $Script -AnswerJson '{"username":"placeholder-name"}'
        $Thrown = @($Run.Output | Where-Object { $_ -like 'threw *' })
        $Paths = @($Run.Output | Where-Object { $_ -like 'path *' })
        $Result = 'requests {0}; {1}; threw {2}; {3}; prompts {4}; unmocked calls {5}' -f $Run.NetworkCallCount, $(if ($Paths.Count) { $Paths -join ', ' } else { 'path none' }), ($Thrown.Count -gt 0), $(if ($Thrown.Count) { 'error type ' + $Thrown[0].Substring(6) } else { 'error type none' }), $Run.PromptCount, $Run.UnmockedCall.Count
        Write-Host ('MEASURE M2 [{0} {1}] Get-SGTeammate: {2}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Result)
        $Run.UnmockedCall | Should -BeNullOrEmpty
        $Result | Should -Not -BeNullOrEmpty
    }

    It 'M3: the target Remove-SGSubuser names under <Name>' -ForEach @(
        @{ Name = '-WhatIf'; Script = 'Remove-SGSubuser -Username ''a b+c'' -WhatIf'; Answer = $null }
        @{ Name = '-Confirm'; Script = '$null = Remove-SGSubuser -Username ''a b+c'' -Confirm'; Answer = '{"id":1001}' }
    ) {
        $Run = if ($Answer) { Invoke-SgtInCountingHost -Script $Script -AnswerJson $Answer } else { Invoke-SgtInCountingHost -Script $Script }
        $Text = @($Run.HostLine) + @($Run.Prompt)
        $Result = 'What if lines {0}; prompts {1}; the name is named {2}; the target is the word Subuser alone {3}; requests {4}; threw {5}' -f @($Run.HostLine | Where-Object { $_ -like 'What if:*' }).Count, $Run.PromptCount,
            (@($Text | Where-Object { $_ -like '*a b+c*' }).Count -gt 0), (@($Text | Where-Object { $_ -match '"Subuser"' }).Count -gt 0), $Run.NetworkCallCount, $Run.Threw
        Write-Host ('MEASURE M3 [{0} {1}] Remove-SGSubuser {2}: {3}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Name, $Result)
        $Run.UnmockedCall | Should -BeNullOrEmpty
        $Result | Should -Not -BeNullOrEmpty
    }

    It 'M4: <Command> for <Name> in the pipeline' -ForEach @(
        foreach ($Command in 'Remove-SGBlock', 'Remove-SGBounce', 'Remove-SGInvalidEmail', 'Remove-SGSpamReport') {
            @{ Command = $Command; Name = 'an object without Email'; Kind = 'NoEmail' }
            @{ Command = $Command; Name = 'an object with an empty Email'; Kind = 'EmptyEmail' }
            @{ Command = $Command; Name = 'a string'; Kind = 'String' }
            @{ Command = $Command; Name = 'an object with Email'; Kind = 'Object' }
        }
    ) {
        $Result = InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Command = $Command; Kind = $Kind } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 1001 })
            $Item = switch ($Kind) {
                'NoEmail' { [pscustomobject]@{ Name = 'placeholder' } }
                'EmptyEmail' { [pscustomobject]@{ Email = '' } }
                'String' { 'a+b@example.com' }
                'Object' { [pscustomobject]@{ Email = 'a+b@example.com' } }
            }
            $Caught = $null
            try { $null = $Item | & $Command -Confirm:$false -ErrorAction Stop } catch { $Caught = $_ }
            $Calls = Get-SgtNetworkCall
            $Path = if ($Calls.Count) { ([uri]$Calls[0].Uri).AbsolutePath } else { 'none' }
            $Type = if ($Caught) { $Caught.Exception.GetType().FullName } else { 'none' }
            $Says = if ($Caught) { "$($Caught.Exception.Message)" -like '*InputObject has no Email property*' } else { $false }
            'requests {0}; path {1}; threw {2}; error type {3}; says InputObject has no Email property {4}' -f $Calls.Count, $Path, ($null -ne $Caught), $Type, $Says
        }
        Write-Host ('MEASURE M4 [{0} {1}] {2}, {3}: {4}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Command, $Name, $Result)
        $Result | Should -Not -BeNullOrEmpty
    }

    It 'M5: the query Get-SGDesign sends for <Name>' -ForEach @(
        @{ Name = '-PageSize 50'; Params = @{ PageSize = 50 } }
        @{ Name = '-PageToken a+b'; Params = @{ PageToken = 'a+b' } }
        @{ Name = '-Summary'; Params = @{ Summary = [switch]::new($true) } }
        @{ Name = '-Summary:$false'; Params = @{ Summary = [switch]::new($false) } }
        @{ Name = 'no parameters'; Params = @{} }
    ) {
        $Result = InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Params = $Params } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
            Set-SgtNetworkStub -Response ([pscustomobject]@{ id = 'placeholder-id' })
            $Caught = $null
            try { $null = Get-SGDesign @Params } catch { $Caught = $_ }
            $Calls = Get-SgtNetworkCall
            $Query = if ($Calls.Count) { ([uri]$Calls[0].Uri).Query } else { '' }
            'requests {0}; query {1}; threw {2}' -f $Calls.Count, $(if ($Query) { $Query } else { 'none' }), ($null -ne $Caught)
        }
        Write-Host ('MEASURE M5 [{0} {1}] Get-SGDesign {2}: {3}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Name, $Result)
        $Result | Should -Not -BeNullOrEmpty
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
