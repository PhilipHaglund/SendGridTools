BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/NetworkTripwire.ps1')
    # Import once per run: in Windows PowerShell 5.1 a class stays bound to the first loaded module instance.
    if (-not (Get-Module -Name SendGridTools)) {
        Get-Module -Name SendGridTools -ListAvailable | Select-Object -First 1 | Import-Module -ErrorAction Stop
    }
    Enable-SgtNetworkTripwire
    Assert-SgtNetworkTripwireActive

    # D146: a child process in the same shell builds [SGASM]::new(5, @(1, 2)) and prints only the type name,
    # GroupId and GroupsToDisplay. The child scripts make no network call and run no command from the module.
    $script:ManifestPath = (Get-Module -Name SendGridTools -ListAvailable | Select-Object -First 1).Path
    $script:Shell = (Get-Process -Id $PID).Path

    function script:Invoke-SgtChildScript {
        param(
            [Parameter(Mandatory)] [string] $Name,
            [Parameter(Mandatory)] [string[]] $Lines
        )
        $ScriptPath = Join-Path -Path $TestDrive -ChildPath $Name
        Set-Content -LiteralPath $ScriptPath -Value $Lines -Encoding UTF8
        # A stderr line from the child under 2>&1 must not become a terminating error under a parent with Stop.
        $ErrorActionPreference = 'Continue'
        $Output = @(& $script:Shell -NoProfile -NonInteractive -File $ScriptPath 2>&1 | ForEach-Object -Process { "$_" })
        [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Output   = ($Output -join "`n")
        }
    }

    if ($script:ManifestPath) {
        $Quoted = $script:ManifestPath.Replace("'", "''")
        $script:CaseA = Invoke-SgtChildScript -Name 'using-module.ps1' -Lines @(
            "using module '$Quoted'"
            "`$ErrorActionPreference = 'Stop'"
            '$Asm = [SGASM]::new(5, @(1, 2))'
            "'TYPE=' + `$Asm.GetType().FullName"
            "'GROUPID=' + `$Asm.GroupId"
            "'GROUPS=' + (`$Asm.GroupsToDisplay -join ',')"
        )
        $script:CaseB = Invoke-SgtChildScript -Name 'import-module.ps1' -Lines @(
            "`$ErrorActionPreference = 'Stop'"
            "Import-Module -Name '$Quoted' -ErrorAction Stop"
            'try {'
            '    $Asm = [SGASM]::new(5, @(1, 2))'
            "    'TYPE=' + `$Asm.GetType().FullName"
            "    'GROUPID=' + `$Asm.GroupId"
            "    'GROUPS=' + (`$Asm.GroupsToDisplay -join ',')"
            '} catch {'
            "    'ERROR=' + `$_.Exception.Message"
            '}'
        )
    }
}

AfterAll {
    Disable-SgtNetworkTripwire
}

Describe 'SGASM reachability from outside the module' {
    It 'Finds the built manifest and the shell' {
        $script:ManifestPath | Should -Not -BeNullOrEmpty -Because 'the built module must resolve from PSModulePath; run ./build.ps1 -Tasks build first'
        $script:Shell | Should -Not -BeNullOrEmpty
    }

    It 'using module reaches [SGASM] in a new process and keeps GroupsToDisplay' {
        $Because = "child exit code $($script:CaseA.ExitCode), output: $($script:CaseA.Output)"
        $script:CaseA.ExitCode | Should -Be 0 -Because $Because
        $script:CaseA.Output | Should -Match '(?m)^TYPE=SGASM\s*$' -Because $Because
        $script:CaseA.Output | Should -Match '(?m)^GROUPID=5\s*$' -Because $Because
        $script:CaseA.Output | Should -Match '(?m)^GROUPS=1,2\s*$' -Because $Because
    }

    It 'Import-Module alone does not make [SGASM] reachable in a new process' {
        $Because = "child exit code $($script:CaseB.ExitCode), output: $($script:CaseB.Output)"
        $script:CaseB.Output | Should -Not -Match '(?m)^TYPE=' -Because $Because
        $script:CaseB.Output | Should -Match 'Unable to find type' -Because $Because
        $script:CaseB.Output | Should -Match 'SGASM' -Because $Because
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
