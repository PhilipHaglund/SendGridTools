BeforeDiscovery {
    # M1: the thirteen commands of step 4 with an id that holds reserved characters, and the companion parameters each needs.
    $script:M1Case = @(
        @{ Command = 'Get-SGAlert'; Params = @{ AlertId = 'a/b?c#d' } }
        @{ Command = 'Get-SGApiKey'; Params = @{ ApiKeyId = 'a/b?c#d' } }
        @{ Command = 'Remove-SGApiKey'; Params = @{ UniqueId = 'a/b?c#d' } }
        @{ Command = 'Set-SGApiKey'; Params = @{ UniqueId = 'a/b?c#d'; NewName = 'sgt-name' } }
        @{ Command = 'Confirm-SGAuthenticatedDomain'; Params = @{ UniqueId = 'a/b?c#d' } }
        @{ Command = 'Get-SGAuthenticatedDomain'; Params = @{ Id = 'a/b?c#d' } }
        @{ Command = 'Remove-SGAuthenticatedDomain'; Params = @{ UniqueId = 'a/b?c#d' } }
        @{ Command = 'Set-SGAuthenticatedDomain'; Params = @{ UniqueId = 'a/b?c#d'; SetDefault = $true } }
        @{ Command = 'Set-SGAuthenticatedDomainToSubUser'; Params = @{ UniqueId = 'a/b?c#d'; UserName = 'sgt-subuser' } }
        @{ Command = 'Confirm-SGBrandedDomainLink'; Params = @{ UniqueId = 'a/b?c#d' } }
        @{ Command = 'Get-SGBrandedDomainLink'; Params = @{ UniqueId = 'a/b?c#d' } }
        @{ Command = 'Remove-SGBrandedDomainLink'; Params = @{ UniqueId = 'a/b?c#d' } }
        @{ Command = 'Set-SGBrandedDomainLink'; Params = @{ UniqueId = 'a/b?c#d'; SetDefault = $true } }
    )

    # M2: paging and time parameters of the seven list commands, one case each.
    $script:M2Case = [System.Collections.Generic.List[hashtable]]::new()
    $Suppression = 'Get-SGBlock', 'Get-SGBounce', 'Get-SGGlobalSuppression', 'Get-SGInvalidEmail', 'Get-SGSpamReport'
    foreach ($Command in $Suppression + 'Get-SGMailSetting') {
        $script:M2Case.Add(@{ Command = $Command; CaseName = 'none'; Params = @{} })
        foreach ($Value in 0, -1, 1) {
            $script:M2Case.Add(@{ Command = $Command; CaseName = "-Limit $Value"; Params = @{ Limit = $Value } })
        }
        foreach ($Value in 0, -1, 5) {
            $script:M2Case.Add(@{ Command = $Command; CaseName = "-Offset $Value"; Params = @{ Offset = $Value } })
        }
    }
    foreach ($Command in $Suppression) {
        foreach ($Name in 'StartTime', 'EndTime') {
            foreach ($Entry in @(@('0', 0), @("'1970-01-01'", '1970-01-01'), @("'2024-06-30'", '2024-06-30'), @('$null', $null))) {
                $script:M2Case.Add(@{ Command = $Command; CaseName = "-$Name $($Entry[0])"; Params = @{ $Name = $Entry[1] } })
            }
        }
    }
    $script:M2Case.Add(@{ Command = 'Get-SGDesign'; CaseName = 'none'; Params = @{} })
    foreach ($Value in 0, -1, 1) {
        $script:M2Case.Add(@{ Command = 'Get-SGDesign'; CaseName = "-PageSize $Value"; Params = @{ PageSize = $Value } })
    }

    # M3: the four filter shapes of Get-SGEmailActivity with a value that holds reserved characters.
    $script:M3Case = @(
        @{ Operator = '-Property Subject -NE'; Params = @{ Property = 'Subject'; NE = $true } }
        @{ Operator = '-Property Subject -EQ'; Params = @{ Property = 'Subject'; EQ = $true } }
        @{ Operator = '-Property Subject -Like'; Params = @{ Property = 'Subject'; Like = $true } }
        @{ Operator = '-Property TemplateId -Contains'; Params = @{ Property = 'TemplateId'; Contains = $true } }
    )
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/NetworkTripwire.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/SessionHelpers.ps1')
    # Import once per run: in Windows PowerShell 5.1 a class stays bound to the first loaded module instance.
    if (-not (Get-Module -Name SendGridTools)) {
        Get-Module -Name SendGridTools -ListAvailable | Select-Object -First 1 | Import-Module -ErrorAction Stop
    }
    Enable-SgtNetworkTripwire
    Assert-SgtNetworkTripwireActive
    Install-SgtSessionHelper
    $script:Cred = [pscredential]::new('apikey', (ConvertTo-SecureString -String 'test-key-not-real' -AsPlainText -Force))
    $script:Shell = '{0} {1}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion
    $script:FilterValue = "a!b'c(d)e*f"

    function script:Invoke-SgtM64Command {
        # Calls the command with the parameters (-Confirm:$false where the command has -Confirm) and returns the namespaces the
        # command handed to Invoke-SendGrid or Invoke-SendGridPagedList, in order, and the error it ended with, if any.
        param([string]$Command, [hashtable]$Params)
        $global:SgtM64Namespace = [System.Collections.Generic.List[string]]::new()
        $Splat = $Params.Clone()
        if ((Get-Command -Name $Command).Parameters.ContainsKey('Confirm')) {
            $Splat['Confirm'] = $false
        }
        $Refusal = $null
        $Caught = $null
        try {
            $null = & $Command @Splat -ErrorAction Stop 2>&1
        }
        catch {
            $Caught = $_
        }
        $Namespace = @($global:SgtM64Namespace)
        # A binding refusal happens before the command runs: no namespace was recorded and the error id says so.
        if ($null -ne $Caught -and $Namespace.Count -eq 0 -and $Caught.FullyQualifiedErrorId -match 'ParameterBinding|Validation|CannotConvert|Argument') {
            $Refusal = $Caught.FullyQualifiedErrorId
        }
        [pscustomobject]@{
            Namespace = $Namespace
            Refusal   = $Refusal
            ErrorId   = if ($null -ne $Caught) { $Caught.FullyQualifiedErrorId } else { $null }
            Message   = if ($null -ne $Caught) { $Caught.Exception.Message } else { $null }
        }
    }
}

AfterAll {
    Remove-Item -Path 'Function:\Invoke-SgtM64Command' -ErrorAction SilentlyContinue
    Remove-Variable -Name SgtM64Namespace -Scope Global -ErrorAction SilentlyContinue
    Uninstall-SgtSessionHelper
    Disable-SgtNetworkTripwire
}

# Sprint 6 step 4 measurements (M1-M3). Each It writes one MEASURE line with made-up values and asserts nothing about the
# measured value, so the same file measures any version of the module. Invoke-SendGrid and Invoke-SendGridPagedList are mocked
# and only record the namespace they were given.
Describe 'Sprint 6 step 4 measurements' {
    BeforeEach {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
        }
        Mock -CommandName Invoke-SendGrid -ModuleName SendGridTools -MockWith {
            $null = $global:SgtM64Namespace.Add([string]$Namespace)
            [pscustomobject]@{ id = 'sgt-1'; api_key_id = 'sgt-1'; name = 'sgt-name' }
        }
        Mock -CommandName Invoke-SendGridPagedList -ModuleName SendGridTools -MockWith {
            $null = $global:SgtM64Namespace.Add([string]$InvokeSplat.Namespace)
            [pscustomobject]@{ id = 'sgt-1'; api_key_id = 'sgt-1'; name = 'sgt-name' }
        }
        Mock -CommandName Confirm-SendGridContinue -ModuleName SendGridTools -MockWith { $true }
    }

    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
        }
    }

    It 'M1: <Command> with the id a/b?c#d' -ForEach $script:M1Case {
        $Result = Invoke-SgtM64Command -Command $Command -Params $Params
        $Text = $Result.Namespace -join ' | '
        if ($Result.ErrorId) { $Text += ' ; error {0}: {1}' -f $Result.ErrorId, $Result.Message }
        Write-Host ('MEASURE M1 [{0}] {1}: {2}' -f $script:Shell, $Command, $Text)
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }

    It 'M2: <Command> <CaseName>' -ForEach $script:M2Case {
        $Result = Invoke-SgtM64Command -Command $Command -Params $Params
        if ($Result.Refusal) {
            $Text = 'refused at binding: {0}' -f $Result.Refusal
        }
        else {
            $Parts = foreach ($Namespace in $Result.Namespace) {
                if ($Namespace.Contains('?')) { $Namespace.Substring($Namespace.IndexOf('?') + 1) } else { '(no query)' }
            }
            $Text = if (@($Parts).Count -gt 0) { @($Parts) -join ' | ' } else { '(no call)' }
            if ($Result.ErrorId) { $Text += ' ; error {0}: {1}' -f $Result.ErrorId, $Result.Message }
        }
        Write-Host ('MEASURE M2 [{0}] {1} {2}: {3}' -f $script:Shell, $Command, $CaseName, $Text)
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }

    It 'M3: Get-SGEmailActivity <Operator>' -ForEach $script:M3Case {
        $Splat = $Params.Clone()
        $Splat['Value'] = $script:FilterValue
        $Result = Invoke-SgtM64Command -Command 'Get-SGEmailActivity' -Params $Splat
        if ($Result.Refusal) {
            $Text = 'refused at binding: {0}' -f $Result.Refusal
        }
        else {
            $Parts = foreach ($Namespace in $Result.Namespace) {
                if ($Namespace.Contains('?')) { $Namespace.Substring($Namespace.IndexOf('?') + 1) } else { '(no query)' }
            }
            $Text = if (@($Parts).Count -gt 0) { @($Parts) -join ' | ' } else { '(no call)' }
            if ($Result.ErrorId) { $Text += ' ; error {0}: {1}' -f $Result.ErrorId, $Result.Message }
        }
        Write-Host ('MEASURE M3 [{0}] {1}: {2}' -f $script:Shell, $Operator, $Text)
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
