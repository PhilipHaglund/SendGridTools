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
}

AfterAll {
    Uninstall-SgtSessionHelper
    Disable-SgtNetworkTripwire
}

# Every run goes through the counting host: a regression to an unbound Invoke-SendGrid call must throw there, never wait on a console.
Describe 'Get-SGTeammate sends the username in the path (D63)' {
    It 'Sends one request to <Expected> for <Name>' -ForEach @(
        @{ Name = 'a b+c'; Expected = '/v3/teammates/a%20b%2Bc' }
        @{ Name = 'placeholder-name'; Expected = '/v3/teammates/placeholder-name' }
    ) {
        $Script = @"
try { `$null = Get-SGTeammate -Username '$Name' } catch { 'threw {0}' -f `$_.Exception.GetType().FullName }
foreach (`$Call in `$global:SgtNetworkCall) { 'path {0}' -f ([uri]`$Call.Uri).AbsolutePath }
"@
        $Run = Invoke-SgtInCountingHost -Script $Script -AnswerJson '{"username":"placeholder-name"}'

        @($Run.Output | Where-Object { $_ -like 'threw *' }).Count | Should -Be 0
        $Run.NetworkCallCount | Should -Be 1
        @($Run.Output | Where-Object { $_ -like 'path *' }) | Should -Be @("path $Expected")
        $Run.UnmockedCall | Should -BeNullOrEmpty
    }

    It 'Sends one request to /v3/teammates without -Username' {
        $Script = @'
try { $null = Get-SGTeammate } catch { 'threw {0}' -f $_.Exception.GetType().FullName }
foreach ($Call in $global:SgtNetworkCall) { 'path {0}' -f ([uri]$Call.Uri).AbsolutePath }
'@
        $Run = Invoke-SgtInCountingHost -Script $Script -AnswerJson '{"result":[]}'

        @($Run.Output | Where-Object { $_ -like 'threw *' }).Count | Should -Be 0
        $Run.NetworkCallCount | Should -Be 1
        @($Run.Output | Where-Object { $_ -like 'path *' }) | Should -Be @('path /v3/teammates')
        $Run.UnmockedCall | Should -BeNullOrEmpty
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
