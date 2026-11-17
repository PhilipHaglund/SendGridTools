BeforeDiscovery {
    $projectPath = "$($PSScriptRoot)\..\.." | Convert-Path

    <#
        If the QA tests are run outside of the build script (e.g with Invoke-Pester)
        the parent scope has not set the variable $ProjectName.
    #>
    if (-not $ProjectName)
    {
        # Assuming project folder name is project name.
        $ProjectName = Get-SamplerProjectName -BuildRoot $projectPath
    }

    $script:moduleName = $ProjectName

    $sourcePath = (
        Get-ChildItem -Path $projectPath\*\*.psd1 |
            Where-Object -FilterScript {
                ($_.Directory.Name -match 'source|src' -or $_.Directory.Name -eq $_.BaseName) `
                    -and $(
                    try
                    {
                        Test-ModuleManifest -Path $_.FullName -ErrorAction Stop
                    }
                    catch
                    {
                        $false
                    }
                )
            }
    ).Directory.FullName

    Remove-Module -Name $script:moduleName -Force -ErrorAction SilentlyContinue

    $mut = Get-Module -Name $script:moduleName -ListAvailable |
        Select-Object -First 1 |
            Import-Module -Force -ErrorAction Stop -PassThru

    # Exported functions only: unit test and help requirements apply to the public surface.
    $exportedTestCases = @(
        foreach ($functionName in ($mut.ExportedFunctions.Keys | Sort-Object))
        {
            @{ Name = $functionName }
        }
    )

    # Unit test ratchet (A13): public functions that still lack a <Name>.Tests.ps1. The list may only shrink.
    $baselineLines = [System.IO.File]::ReadAllLines((Join-Path -Path $PSScriptRoot -ChildPath 'UnitTestBaseline.txt'))
    $baselineTestCases = @(
        foreach ($baselineName in $baselineLines)
        {
            @{ Name = $baselineName; IsExported = ($exportedTestCases.Name -contains $baselineName) }
        }
    )

    # Script Analyzer covers exported and private functions.
    $allModuleFunctions = & $mut { Get-Command -Module $args[0] -CommandType Function } $script:moduleName
    $allTestCases = @(
        foreach ($function in ($allModuleFunctions | Sort-Object -Property Name))
        {
            @{ Name = $function.Name }
        }
    )

    # One flat list of parameter cases, so a function without parameters never yields an empty -ForEach.
    $parameterTestCases = @(
        foreach ($testCase in $exportedTestCases)
        {
            $functionFile = Get-ChildItem -Path $sourcePath -Recurse -Include "$($testCase.Name).ps1"
            $abstractSyntaxTree = [System.Management.Automation.Language.Parser]::ParseInput(
                (Get-Content -Raw -Path $functionFile.FullName), [ref] $null, [ref] $null)
            $parsedFunction = $abstractSyntaxTree.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
                Where-Object -FilterScript { $_.Name -eq $testCase.Name }

            foreach ($parameter in $parsedFunction.Body.ParamBlock.Parameters.Name.VariablePath.ForEach({ $_.ToString() }))
            {
                @{ Name = $testCase.Name; Parameter = $parameter }
            }
        }
    )

    if (Get-Command -Name Invoke-ScriptAnalyzer -ErrorAction SilentlyContinue)
    {
        $scriptAnalyzerRules = Get-ScriptAnalyzerRule
    }
    else
    {
        if ($ErrorActionPreference -ne 'Stop')
        {
            Write-Warning -Message 'ScriptAnalyzer not found!'
        }
        else
        {
            throw 'ScriptAnalyzer not found!'
        }
    }
}

BeforeAll {
    # Convert-Path required for PS7 or Join-Path fails
    $projectPath = "$($PSScriptRoot)\..\.." | Convert-Path

    if (-not $ProjectName)
    {
        $ProjectName = Get-SamplerProjectName -BuildRoot $projectPath
    }

    $script:moduleName = $ProjectName

    $sourcePath = (
        Get-ChildItem -Path $projectPath\*\*.psd1 |
            Where-Object -FilterScript {
                ($_.Directory.Name -match 'source|src' -or $_.Directory.Name -eq $_.BaseName) `
                    -and $(
                    try
                    {
                        Test-ModuleManifest -Path $_.FullName -ErrorAction Stop
                    }
                    catch
                    {
                        $false
                    }
                )
            }
    ).Directory.FullName
}

Describe 'Changelog Management' -Tag 'Changelog' {
    It 'Changelog has been updated' -Skip:(
        !([bool](Get-Command git -EA SilentlyContinue) -and
            [bool](&(Get-Process -Id $PID).Path -NoProfile -Command 'git rev-parse --is-inside-work-tree 2>$null'))
    ) {
        # Get the list of changed files compared with master
        $HeadCommit = &git rev-parse HEAD
        $MasterCommit = &git rev-parse origin/main
        $filesChanged = &git @('diff', "$MasterCommit...$HeadCommit", '--name-only')

        if ($HeadCommit -ne $MasterCommit)
        {
            # if we're not testing same commit (i.e. master..master)
            $filesChanged.Where{ (Split-Path $_ -Leaf) -match '^changelog' } | Should -Not -BeNullOrEmpty
        }
    }

    It 'Changelog format compliant with keepachangelog format' -Skip:(![bool](Get-Command git -EA SilentlyContinue)) {
        { Get-ChangelogData (Join-Path $projectPath 'CHANGELOG.md') -ErrorAction Stop } | Should -Not -Throw
    }
}

Describe 'General module control' -Tags 'FunctionalQuality' {
    It 'Should import without errors' {
        { Import-Module -Name $script:moduleName -Force -ErrorAction Stop } | Should -Not -Throw
        Get-Module -Name $script:moduleName | Should -Not -BeNullOrEmpty
    }

    It 'Should remove without error' {
        { Remove-Module -Name $script:moduleName -ErrorAction Stop } | Should -Not -Throw
        Get-Module -Name $script:moduleName | Should -BeNullOrEmpty
    }
}

Describe 'Quality for module' -Tags 'TestQuality' {
    BeforeAll {
        $unitTestRoot = Join-Path -Path $projectPath -ChildPath 'tests'
        $baselineFile = Join-Path -Path $PSScriptRoot -ChildPath 'UnitTestBaseline.txt'
    }

    It 'Should have a unit test or a baseline entry for <Name>' -ForEach $exportedTestCases {
        $unitTestFile = Get-ChildItem -Path $unitTestRoot -Recurse -Filter "$Name.Tests.ps1"
        $baseline = [System.IO.File]::ReadAllLines($baselineFile)

        ($unitTestFile -or ($baseline -contains $Name)) |
            Should -BeTrue -Because "$Name has no $Name.Tests.ps1 under tests\. Write the unit test; do not add $Name to UnitTestBaseline.txt"
    }

    # An empty baseline gives no cases; Pester 5 fails on an empty -ForEach, so the It is only emitted when there are entries.
    if ($baselineTestCases.Count -gt 0)
    {
        It 'Should still need the baseline entry <Name>' -ForEach $baselineTestCases {
            $unitTestFile = Get-ChildItem -Path $unitTestRoot -Recurse -Filter "$Name.Tests.ps1"

            $IsExported | Should -BeTrue -Because "$Name is not an exported function any more. Remove it from UnitTestBaseline.txt"
            $unitTestFile | Should -BeNullOrEmpty -Because "$Name now has a unit test. Remove it from UnitTestBaseline.txt"
        }
    }

    It 'Should keep the baseline sorted and unique' {
        $baseline = [string[]][System.IO.File]::ReadAllLines($baselineFile)
        $sorted = [string[]] $baseline.Clone()
        [System.Array]::Sort($sorted, [System.StringComparer]::Ordinal)

        $blank = @($baseline | Where-Object -FilterScript { [string]::IsNullOrWhiteSpace($_) })
        $blank | Should -BeNullOrEmpty -Because 'the baseline must have one name per line and no blank lines'

        $duplicate = @($baseline | Group-Object | Where-Object -FilterScript { $_.Count -gt 1 }).Name
        $duplicate | Should -BeNullOrEmpty -Because 'each name may appear only once in UnitTestBaseline.txt'

        ($baseline -join "`n") | Should -BeExactly ($sorted -join "`n") -Because 'UnitTestBaseline.txt must be sorted ordinal'
    }

    It 'Should pass Script Analyzer for <Name>' -ForEach $allTestCases -Skip:(-not $scriptAnalyzerRules) {
        $functionFile = Get-ChildItem -Path $sourcePath -Recurse -Include "$Name.ps1"

        $pssaResult = (Invoke-ScriptAnalyzer -Path $functionFile.FullName)
        $report = $pssaResult | Format-Table -AutoSize | Out-String -Width 110
        $pssaResult | Should -BeNullOrEmpty -Because "some rule triggered.`r`n`r`n $report"
    }
}

Describe 'Help for module' -Tags 'helpQuality' {
    BeforeAll {
        # Parse a function file and return its help content; used by the checks below.
        function Get-FunctionHelpContent
        {
            param
            (
                [Parameter(Mandatory = $true)]
                [string]
                $FunctionName,

                [Parameter(Mandatory = $true)]
                [string]
                $SourcePath
            )

            $functionFile = Get-ChildItem -Path $SourcePath -Recurse -Include "$FunctionName.ps1"

            $abstractSyntaxTree = [System.Management.Automation.Language.Parser]::ParseInput(
                (Get-Content -Raw -Path $functionFile.FullName), [ref] $null, [ref] $null)

            $parsedFunction = $abstractSyntaxTree.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
                Where-Object -FilterScript { $_.Name -eq $FunctionName }

            $parsedFunction.GetHelpContent()
        }
    }

    It 'Should have .SYNOPSIS for <Name>' -ForEach $exportedTestCases {
        $functionHelp = Get-FunctionHelpContent -FunctionName $Name -SourcePath $sourcePath

        $functionHelp.Synopsis | Should -Not -BeNullOrEmpty
    }

    It 'Should have a .DESCRIPTION with length greater than 40 characters for <Name>' -ForEach $exportedTestCases {
        $functionHelp = Get-FunctionHelpContent -FunctionName $Name -SourcePath $sourcePath

        $functionHelp.Description.Length | Should -BeGreaterThan 40
    }

    It 'Should have at least one (1) example for <Name>' -ForEach $exportedTestCases {
        $functionHelp = Get-FunctionHelpContent -FunctionName $Name -SourcePath $sourcePath

        $functionHelp.Examples.Count | Should -BeGreaterThan 0
        $functionHelp.Examples[0] | Should -Match ([regex]::Escape($Name))
        $functionHelp.Examples[0].Length | Should -BeGreaterThan ($Name.Length + 10)
    }

    It 'Should have help for parameter <Parameter> of <Name>' -ForEach $parameterTestCases {
        $functionHelp = Get-FunctionHelpContent -FunctionName $Name -SourcePath $sourcePath

        $functionHelp.Parameters.($Parameter.ToUpper()) | Should -Not -BeNullOrEmpty -Because ('the parameter {0} must have a description' -f $Parameter)
        $functionHelp.Parameters.($Parameter.ToUpper()).Length | Should -BeGreaterThan 25 -Because ('the parameter {0} must have descriptive description' -f $Parameter)
    }
}
