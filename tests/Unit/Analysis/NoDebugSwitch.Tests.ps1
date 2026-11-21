BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Support/NetworkTripwire.ps1')
    # Import once per run: in Windows PowerShell 5.1 a class stays bound to the first loaded module instance.
    if (-not (Get-Module -Name SendGridTools)) {
        Get-Module -Name SendGridTools -ListAvailable | Select-Object -First 1 | Import-Module -ErrorAction Stop
    }
    Enable-SgtNetworkTripwire
    Assert-SgtNetworkTripwireActive

    $script:TestsRoot = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../..')).Path

    function script:Find-SgtDebugParameter {
        # The CommandParameterAst nodes that bind to Debug (any case): -Debug, its alias -db and the prefixes -deb and -debu.
        param($Ast)
        $Ast.FindAll({
                param($Node)
                $Node -is [System.Management.Automation.Language.CommandParameterAst] -and $Node.ParameterName -match '^(db|deb|debu|debug)$'
            }, $true)
    }
}

AfterAll {
    Disable-SgtNetworkTripwire
}

# A command called with -Debug can wait on a console for an answer. D170: no test does that.
Describe 'No test passes the Debug switch' {
    It 'Finds the switch in a script that passes it (self-check)' {
        $Parsed = [System.Management.Automation.Language.Parser]::ParseInput('Get-Item -Path x -DEBUG', [ref]$null, [ref]$null)
        @(Find-SgtDebugParameter -Ast $Parsed).Count | Should -Be 1
    }

    It 'Finds the alias and the prefixes that bind to Debug (self-check)' -ForEach @(
        @{ Script = 'Get-Item -Path x -db' }
        @{ Script = 'Get-Item -Path x -Deb' }
        @{ Script = 'Get-Item -Path x -debu' }
    ) {
        $Parsed = [System.Management.Automation.Language.Parser]::ParseInput($Script, [ref]$null, [ref]$null)
        @(Find-SgtDebugParameter -Ast $Parsed).Count | Should -Be 1
    }

    It 'Does not find the switch in a script that only names a debug channel (self-check)' -ForEach @(
        @{ Script = 'Write-Debug -Message x' }
        @{ Script = 'New-Thing -Description x' }
    ) {
        $Parsed = [System.Management.Automation.Language.Parser]::ParseInput($Script, [ref]$null, [ref]$null)
        @(Find-SgtDebugParameter -Ast $Parsed).Count | Should -Be 0
    }

    It 'Finds no -Debug parameter in any script under tests' {
        $Files = @(Get-ChildItem -LiteralPath $script:TestsRoot -Filter '*.ps1' -Recurse -File)
        $Files.Count | Should -BeGreaterThan 0
        $Found = foreach ($File in $Files) {
            $Errors = $null
            $Ast = [System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$null, [ref]$Errors)
            foreach ($Node in @(Find-SgtDebugParameter -Ast $Ast)) {
                '{0}:{1}' -f $File.FullName.Substring($script:TestsRoot.Length + 1), $Node.Extent.StartLineNumber
            }
        }
        @($Found) | Should -BeNullOrEmpty
    }
}

Describe 'Network tripwire' {
    It 'Made no unmocked network call' {
        Assert-SgtNetworkTripwireActive
        Get-SgtUnmockedNetworkCall | Should -BeNullOrEmpty
    }
}
