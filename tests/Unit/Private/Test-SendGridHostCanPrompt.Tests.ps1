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
}

AfterAll {
    Uninstall-SgtSessionHelper
    Disable-SgtNetworkTripwire
}

Describe 'Test-SendGridHostCanPrompt' {
    It 'Returns $true for <Label>' -ForEach @(
        @{ Label = 'a bare pwsh'; Arguments = @('pwsh'); HostName = 'ConsoleHost'; Interactive = $true }
        @{ Label = '-NoProfile'; Arguments = @('pwsh', '-NoProfile'); HostName = 'ConsoleHost'; Interactive = $true }
        @{ Label = '-NonInteractive after -File'; Arguments = @('pwsh', '-NoProfile', '-File', 'x.ps1', '-NonInteractive'); HostName = 'ConsoleHost'; Interactive = $true }
        @{ Label = '-noni after -c'; Arguments = @('pwsh', '-c', 'Get-Date', '-noni'); HostName = 'ConsoleHost'; Interactive = $true }
        @{ Label = 'powershell.exe -NoLogo'; Arguments = @('powershell.exe', '-NoLogo'); HostName = 'ConsoleHost'; Interactive = $true }
        @{ Label = '-NonInteractive after -File with -ExecutionPolicy'; Arguments = @('powershell.exe', '-ExecutionPolicy', 'Bypass', '-File', 'x.ps1', '-NonInteractive'); HostName = 'ConsoleHost'; Interactive = $true }
        @{ Label = '-Interactive and -NoProfile'; Arguments = @('pwsh', '-Interactive', '-NoProfile'); HostName = 'ConsoleHost'; Interactive = $true }
        @{ Label = 'a remote session that is not user interactive'; Arguments = @('wsmprovhost.exe', '-Embedding'); HostName = 'ServerRemoteHost'; Interactive = $false }
        @{ Label = 'a remote session on a host started with -NonInteractive'; Arguments = @('pwsh', '-NonInteractive'); HostName = 'ServerRemoteHost'; Interactive = $true }
        @{ Label = 'the Visual Studio Code host'; Arguments = @('pwsh'); HostName = 'Visual Studio Code Host'; Interactive = $true }
        # PowerShell Editor Services starts with -NonInteractive, but its integrated console has its own user interface and prompts.
        @{ Label = 'the Visual Studio Code host started with -NonInteractive'; Arguments = @('pwsh', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', 'Start-EditorServices'); HostName = 'Visual Studio Code Host'; Interactive = $true }
        @{ Label = 'an unknown host started with -NonInteractive'; Arguments = @('pwsh', '-NoProfile', '-NonInteractive'); HostName = 'Some Other Host'; Interactive = $true }
    ) {
        InModuleScope SendGridTools -Parameters @{ Arguments = $Arguments; HostName = $HostName; Interactive = $Interactive } {
            Test-SendGridHostCanPrompt -CommandLineArgs $Arguments -UserInteractive $Interactive -HostName $HostName | Should -BeTrue
        }
    }

    It 'Returns $false for <Label>' -ForEach @(
        @{ Label = '-NonInteractive'; Arguments = @('pwsh', '-NonInteractive'); HostName = 'ConsoleHost'; Interactive = $true }
        @{ Label = '-noni'; Arguments = @('pwsh', '-noni'); HostName = 'ConsoleHost'; Interactive = $true }
        @{ Label = '-NONINTERACTIVE'; Arguments = @('pwsh', '-NONINTERACTIVE'); HostName = 'ConsoleHost'; Interactive = $true }
        @{ Label = '--noninteractive'; Arguments = @('pwsh', '--noninteractive'); HostName = 'ConsoleHost'; Interactive = $true }
        @{ Label = '/NonInteractive'; Arguments = @('powershell.exe', '/NonInteractive'); HostName = 'ConsoleHost'; Interactive = $true }
        @{ Label = '-NonInteractive before -File'; Arguments = @('pwsh', '-NoProfile', '-NonInteractive', '-File', 'x.ps1'); HostName = 'ConsoleHost'; Interactive = $true }
        @{ Label = '-NonInteractive after -ExecutionPolicy Bypass'; Arguments = @('powershell.exe', '-ExecutionPolicy', 'Bypass', '-NonInteractive', '-File', 'x.ps1'); HostName = 'ConsoleHost'; Interactive = $true }
        @{ Label = '-noni after -ep Bypass'; Arguments = @('pwsh', '-ep', 'Bypass', '-noni', '-File', 'x.ps1'); HostName = 'ConsoleHost'; Interactive = $true }
        @{ Label = '-NonInteractive after -WindowStyle Hidden'; Arguments = @('powershell.exe', '-WindowStyle', 'Hidden', '-NonInteractive', '-Command', 'Get-Date'); HostName = 'ConsoleHost'; Interactive = $true }
        @{ Label = '-NonInteractive after -wd'; Arguments = @('pwsh', '-wd', 'C:\work', '-NonInteractive'); HostName = 'ConsoleHost'; Interactive = $true }
        @{ Label = '-NonInteractive after -InputFormat and -OutputFormat'; Arguments = @('powershell.exe', '-InputFormat', 'Text', '-OutputFormat', 'Text', '-NonInteractive'); HostName = 'ConsoleHost'; Interactive = $true }
        @{ Label = 'a process that is not user interactive'; Arguments = @('pwsh'); HostName = 'ConsoleHost'; Interactive = $false }
        @{ Label = 'the Default Host'; Arguments = @('pwsh'); HostName = 'Default Host'; Interactive = $true }
        @{ Label = 'the console host started with -NonInteractive like the editor services'; Arguments = @('pwsh', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', 'Start-EditorServices'); HostName = 'ConsoleHost'; Interactive = $true }
        @{ Label = 'the Visual Studio Code host in a process that is not user interactive'; Arguments = @('pwsh'); HostName = 'Visual Studio Code Host'; Interactive = $false }
        @{ Label = 'the Default Host started with -NonInteractive'; Arguments = @('pwsh', '-NonInteractive'); HostName = 'Default Host'; Interactive = $true }
    ) {
        InModuleScope SendGridTools -Parameters @{ Arguments = $Arguments; HostName = $HostName; Interactive = $Interactive } {
            Test-SendGridHostCanPrompt -CommandLineArgs $Arguments -UserInteractive $Interactive -HostName $HostName | Should -BeFalse
        }
    }

    It 'Returns a bool with no arguments' {
        InModuleScope SendGridTools {
            { Test-SendGridHostCanPrompt } | Should -Not -Throw
            Test-SendGridHostCanPrompt | Should -BeOfType [bool]
        }
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
