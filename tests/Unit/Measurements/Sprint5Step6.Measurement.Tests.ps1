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

    # Runs one Send-SGMailMessage in module scope with made-up addresses and returns the request count, the parsed body
    # and the error. Kept as text and re-created inside the module, so [SGASM] resolves in module scope.
    $script:SendText = {
        param($Cred, $Case)
        $script:Session = New-SgtTestSession -Credential $Cred -AgeHours 0
        Reset-SgtNetworkStub
        Set-SgtNetworkStub -Response ([pscustomobject]@{ placeholder = 'accepted' })
        $Params = @{
            From    = 'sender@example.com'
            To      = 'one@example.com'
            Subject = 'placeholder subject'
            Body    = 'placeholder body'
        }
        switch ($Case) {
            'BatchId' { $Params['BatchId'] = 'sgt-made-up-batch' }
            'SGASM new(1)' { $Params['Unsubscribe'] = [SGASM]::new(1) }
            'SGASM new(7) with GroupsToDisplay 7, 8 as property' {
                $Asm = [SGASM]::new(7)
                $Asm.GroupsToDisplay = 7, 8
                $Params['Unsubscribe'] = $Asm
            }
            'SGASM new()' { $Params['Unsubscribe'] = [SGASM]::new() }
            'Categories one name of 11 characters' { $Params['Categories'] = 'c' * 11 }
            'Categories one name of 256 characters' { $Params['Categories'] = 'c' * 256 }
            'Categories ten names' { $Params['Categories'] = @(1..10 | ForEach-Object { 'sgt-c{0:d2}' -f $_ }) }
            'Categories eleven names' { $Params['Categories'] = @(1..11 | ForEach-Object { 'sgt-c{0:d2}' -f $_ }) }
            default { }
        }
        $Caught = $null
        try { $null = Send-SGMailMessage @Params -Confirm:$false -ErrorAction Stop } catch { $Caught = $_ }
        $Calls = @(Get-SgtNetworkCall | ForEach-Object { $_ })
        [pscustomobject]@{
            Count  = $Calls.Count
            Sent   = if ($Calls.Count) { $Calls[0].Body | ConvertFrom-Json } else { $null }
            Caught = $Caught
        }
    }.ToString()

    function script:Get-SgtM6Text {
        param($Run)
        $Sent = $Run.Sent
        $Keys = if ($Sent) { @($Sent.PSObject.Properties.Name | Sort-Object) -join ', ' } else { 'none' }
        $HasBatch = [bool]($Sent -and $Sent.PSObject.Properties['batch_id'])
        $BatchMatches = $HasBatch -and ($Sent.batch_id -ceq 'sgt-made-up-batch')
        $HasAsm = [bool]($Sent -and $Sent.PSObject.Properties['asm'])
        $AsmKeys = if ($HasAsm) { @($Sent.asm.PSObject.Properties.Name | Sort-Object) -join ', ' } else { 'none' }
        $GroupId = if ($HasAsm -and $Sent.asm.PSObject.Properties['group_id']) { "$($Sent.asm.group_id)" } else { 'none' }
        $Display = if ($HasAsm -and $Sent.asm.PSObject.Properties['groups_to_display']) { @($Sent.asm.groups_to_display).Count } else { 0 }
        $CategoryCount = if ($Sent -and $Sent.PSObject.Properties['categories']) { @($Sent.categories).Count } else { 0 }
        $ErrorText = if ($null -eq $Run.Caught) { 'threw False' } else {
            'threw True; error type {0}; at binding {1}' -f $Run.Caught.Exception.GetType().FullName, ($Run.Caught.Exception -is [System.Management.Automation.ParameterBindingException])
        }
        'requests {0}; body keys {1}; batch_id {2}; batch_id is the value {3}; asm {4}; asm keys {5}; group_id {6}; groups_to_display {7}; categories {8}; {9}' -f
        $Run.Count, $Keys, $HasBatch, $BatchMatches, $HasAsm, $AsmKeys, $GroupId, $Display, $CategoryCount, $ErrorText
    }
}

AfterAll {
    Uninstall-SgtSessionHelper
    Disable-SgtNetworkTripwire
}

# Sprint 5 step 6 measurements (M1-M3). Each It writes one MEASURE line with command names, counts, body keys, made-up
# values, error types and True/False only, and asserts nothing about the measured value, so the same file measures any
# version of the module. Invoke-RestMethod is answered by the tripwire's stub, which logs the body.
Describe 'Sprint 5 step 6 measurements' {
    AfterEach {
        InModuleScope SendGridTools {
            $script:Session = $null
            Reset-SgtNetworkStub
        }
    }

    It '<Id>: Send-SGMailMessage with <Case>' -ForEach @(
        @{ Id = 'M1'; Case = 'BatchId' }
        @{ Id = 'M1'; Case = 'SGASM new(1)' }
        @{ Id = 'M1'; Case = 'SGASM new(7) with GroupsToDisplay 7, 8 as property' }
        @{ Id = 'M1'; Case = 'SGASM new()' }
        @{ Id = 'M2'; Case = 'Categories one name of 11 characters' }
        @{ Id = 'M2'; Case = 'Categories one name of 256 characters' }
        @{ Id = 'M2'; Case = 'Categories ten names' }
        @{ Id = 'M2'; Case = 'Categories eleven names' }
        @{ Id = 'M3'; Case = 'none of the parameters' }
    ) {
        $Run = InModuleScope SendGridTools -Parameters @{ Cred = $script:Cred; Case = $Case; Send = $script:SendText } {
            & ([scriptblock]::Create($Send)) $Cred $Case
        }
        $Text = Get-SgtM6Text -Run $Run
        Write-Host ('MEASURE {0} [{1} {2}] Send-SGMailMessage {3}: {4}' -f $Id, $PSVersionTable.PSEdition, $PSVersionTable.PSVersion, $Case, $Text)
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
