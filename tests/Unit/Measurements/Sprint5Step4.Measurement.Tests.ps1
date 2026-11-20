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

    # Every command the measured paths can reach is answered in module scope and counted in $global:SgtM4Call.
    # Values are made up. -Fail makes the three lookups throw, as they do without a connection.
    function script:Set-SgtM4Mock {
        param([switch]$Fail)
        $global:SgtM4Call = [System.Collections.Generic.List[object]]::new()
        $global:SgtM4Fail = [bool]$Fail
        Mock -CommandName Get-SGApiKey -ModuleName SendGridTools -MockWith {
            $null = $global:SgtM4Call.Add(@{ Name = 'Get-SGApiKey' })
            if ($global:SgtM4Fail) { throw 'sgt-measure: lookup failed' }
            [pscustomobject]@{ ApiKeyId = 'sgt-key-id-1'; Name = 'sgt-key-name-1' }
            [pscustomobject]@{ ApiKeyId = 'sgt-key-id-2'; Name = 'sgt-key-name-2' }
        }
        Mock -CommandName Get-SGSuppressionGroup -ModuleName SendGridTools -MockWith {
            $null = $global:SgtM4Call.Add(@{ Name = 'Get-SGSuppressionGroup' })
            if ($global:SgtM4Fail) { throw 'sgt-measure: lookup failed' }
            [pscustomobject]@{ Id = 101; Name = 'sgt-group-name-1' }
            [pscustomobject]@{ Id = 102; Name = 'sgt-group-name-2' }
        }
        Mock -CommandName Get-SGTeammate -ModuleName SendGridTools -MockWith {
            $null = $global:SgtM4Call.Add(@{ Name = 'Get-SGTeammate' })
            if ($global:SgtM4Fail) { throw 'sgt-measure: lookup failed' }
            [pscustomobject]@{ Username = 'sgt-teammate-1' }
            [pscustomobject]@{ Username = 'sgt-teammate-2' }
        }
        Mock -CommandName Invoke-SendGrid -ModuleName SendGridTools -MockWith {
            $null = $global:SgtM4Call.Add(@{ Name = 'Invoke-SendGrid'; Namespace = "$Namespace" })
            [pscustomobject]@{ MsgId = 'sgt-test-message-id' }
        }
    }

    function script:Get-SgtM4Count {
        $Names = @($global:SgtM4Call | ForEach-Object { $_.Name })
        'Get-SGApiKey {0}, Get-SGSuppressionGroup {1}, Get-SGTeammate {2}, Invoke-SendGrid {3}' -f @($Names | Where-Object { $_ -eq 'Get-SGApiKey' }).Count,
            @($Names | Where-Object { $_ -eq 'Get-SGSuppressionGroup' }).Count, @($Names | Where-Object { $_ -eq 'Get-SGTeammate' }).Count,
            @($Names | Where-Object { $_ -eq 'Invoke-SendGrid' }).Count
    }

    function script:Get-SgtM4Query {
        $Sent = @($global:SgtM4Call | Where-Object { $_.Name -eq 'Invoke-SendGrid' })
        if ($Sent.Count -eq 0) { return 'none' }
        $Namespace = $Sent[0].Namespace
        if ($Namespace -match '[?&]query=(.*)$') { $Matches[1] } else { $Namespace }
    }

    function script:Get-SgtM4Error {
        param($Caught)
        if ($null -eq $Caught) { return 'threw False' }
        'threw True; error type {0}; error id {1}; binding error {2}' -f $Caught.Exception.GetType().FullName, $Caught.FullyQualifiedErrorId,
            ($Caught.Exception -is [System.Management.Automation.ParameterBindingException])
    }
}

AfterAll {
    Remove-Variable -Name SgtM4Call, SgtM4Fail -Scope Global -ErrorAction SilentlyContinue
    Uninstall-SgtSessionHelper
    Disable-SgtNetworkTripwire
}

# Sprint 5 step 4 measurements (M1-M3). Each It writes one MEASURE line with command names, counts, made-up values,
# error types and True/False only, and asserts nothing about the measured value, so the same file measures any version
# of the module. Get-SGApiKey, Get-SGSuppressionGroup, Get-SGTeammate and Invoke-SendGrid are mocked in module scope.
Describe 'Sprint 5 step 4 measurements' {
    BeforeEach {
        InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred } {
            $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
        }
    }
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It 'M1: calls when -Value binds for <Property> (Get-Command -ArgumentList)' -ForEach @(
        foreach ($Property in 'ApiKeyId', 'ApiKeyName', 'AsmGroupId', 'AsmGroupName', 'Teammate') { @{ Property = $Property } }
    ) {
        Set-SgtM4Mock
        $Caught = $null
        $Parameter = $null
        try { $Parameter = (Get-Command -Name Get-SGEmailActivity -ArgumentList $Property -ErrorAction Stop).Parameters['Value'] } catch { $Caught = $_ }
        $HasSet = $null -ne $Parameter -and @($Parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).Count -gt 0
        $HasCompleter = $null -ne $Parameter -and @($Parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ArgumentCompleterAttribute] }).Count -gt 0
        $Result = '{0}; Value bound {1}; ValidateSet {2}; completer {3}; {4}' -f (Get-SgtM4Count), ($null -ne $Parameter), $HasSet, $HasCompleter, (Get-SgtM4Error $Caught)
        Write-Host ('MEASURE M1 [{0} {1}] binding {2}: {3}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Property, $Result)
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
        $Result | Should -Not -BeNullOrEmpty
    }

    It 'M1: binding for <Property> when the lookup fails, as without a connection' -ForEach @(
        foreach ($Property in 'ApiKeyId', 'ApiKeyName', 'AsmGroupId', 'AsmGroupName', 'Teammate') { @{ Property = $Property } }
    ) {
        Set-SgtM4Mock -Fail
        $Caught = $null
        $Parameter = $null
        try { $Parameter = (Get-Command -Name Get-SGEmailActivity -ArgumentList $Property -ErrorAction Stop).Parameters['Value'] } catch { $Caught = $_ }
        $Result = '{0}; Value bound {1}; {2}' -f (Get-SgtM4Count), ($null -ne $Parameter), (Get-SgtM4Error $Caught)
        Write-Host ('MEASURE M1 [{0} {1}] binding with a failing lookup {2}: {3}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Property, $Result)
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
        $Result | Should -Not -BeNullOrEmpty
    }

    It 'M1: calls in a run for <Property> -EQ -Value <Value>' -ForEach @(
        @{ Property = 'ApiKeyId'; Value = 'sgt-key-id-1' }
        @{ Property = 'ApiKeyName'; Value = 'sgt-key-name-1' }
        @{ Property = 'AsmGroupId'; Value = '101' }
        @{ Property = 'AsmGroupName'; Value = 'sgt-group-name-1' }
        @{ Property = 'Teammate'; Value = 'sgt-teammate-1' }
    ) {
        Set-SgtM4Mock
        $Caught = $null
        try { $null = Get-SGEmailActivity -Property $Property -EQ -Value $Value -ErrorAction Stop } catch { $Caught = $_ }
        $Result = '{0}; query {1}; {2}' -f (Get-SgtM4Count), (Get-SgtM4Query), (Get-SgtM4Error $Caught)
        Write-Host ('MEASURE M1 [{0} {1}] run {2}: {3}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Property, $Result)
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
        $Result | Should -Not -BeNullOrEmpty
    }

    It 'M1: a run for <Property> -EQ -Value <Value> when the lookup fails, as without a connection' -ForEach @(
        @{ Property = 'ApiKeyId'; Value = 'sgt-key-id-1' }
        @{ Property = 'ApiKeyName'; Value = 'sgt-key-name-1' }
        @{ Property = 'AsmGroupId'; Value = '101' }
        @{ Property = 'AsmGroupName'; Value = 'sgt-group-name-1' }
        @{ Property = 'Teammate'; Value = 'sgt-teammate-1' }
    ) {
        Set-SgtM4Mock -Fail
        $Caught = $null
        try { $null = Get-SGEmailActivity -Property $Property -EQ -Value $Value -ErrorAction Stop } catch { $Caught = $_ }
        $Result = '{0}; query {1}; {2}' -f (Get-SgtM4Count), (Get-SgtM4Query), (Get-SgtM4Error $Caught)
        Write-Host ('MEASURE M1 [{0} {1}] run with a failing lookup {2}: {3}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Property, $Result)
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
        $Result | Should -Not -BeNullOrEmpty
    }

    It 'M2: the query for <Property> with <Case>' -ForEach @(
        @{ Property = 'ApiKeyName'; Case = 'one name'; Value = @('sgt-key-name-1') }
        @{ Property = 'ApiKeyName'; Case = 'two names'; Value = @('sgt-key-name-1', 'sgt-key-name-2') }
        @{ Property = 'ApiKeyName'; Case = 'a name that does not exist'; Value = @('sgt-key-name-missing') }
        @{ Property = 'AsmGroupName'; Case = 'one name'; Value = @('sgt-group-name-1') }
        @{ Property = 'AsmGroupName'; Case = 'two names'; Value = @('sgt-group-name-1', 'sgt-group-name-2') }
        @{ Property = 'AsmGroupName'; Case = 'a name that does not exist'; Value = @('sgt-group-name-missing') }
    ) {
        Set-SgtM4Mock
        $Caught = $null
        try { $null = Get-SGEmailActivity -Property $Property -EQ -Value $Value -ErrorAction Stop } catch { $Caught = $_ }
        $Message = if ($Caught) { $Caught.Exception.Message -replace '\s+', ' ' } else { 'none' }
        $Result = '{0}; query {1}; {2}; message {3}' -f (Get-SgtM4Count), (Get-SgtM4Query), (Get-SgtM4Error $Caught), $Message
        Write-Host ('MEASURE M2 [{0} {1}] {2} with {3}: {4}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Property, $Case, $Result)
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
        $Result | Should -Not -BeNullOrEmpty
    }

    It 'M3: TemplateName with <Operator>' -ForEach @(
        @{ Operator = 'EQ' }
        @{ Operator = 'Contains' }
        @{ Operator = 'NotContains' }
        @{ Operator = 'NE (extra)' }
    ) {
        Set-SgtM4Mock
        $Switch = ($Operator -split ' ')[0]
        $Params = @{ Property = 'TemplateName'; Value = 'sgt-template-name'; ErrorAction = 'Stop' }
        $Params[$Switch] = [switch]::new($true)
        $Caught = $null
        try { $null = Get-SGEmailActivity @Params } catch { $Caught = $_ }
        $Message = if ($Caught) { $Caught.Exception.Message -replace '\s+', ' ' } else { 'none' }
        $Result = '{0}; query {1}; {2}; message {3}' -f (Get-SgtM4Count), (Get-SgtM4Query), (Get-SgtM4Error $Caught), $Message
        Write-Host ('MEASURE M3 [{0} {1}] TemplateName -{2}: {3}' -f $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Operator, $Result)
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
        $Result | Should -Not -BeNullOrEmpty
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
