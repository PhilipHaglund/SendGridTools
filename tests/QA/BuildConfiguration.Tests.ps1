BeforeAll {
    $script:BuildYamlPath = Join-Path -Path (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..')).ProviderPath -ChildPath 'build.yaml'
}

Describe 'Build configuration' {
    It 'Should import only the build task files that build and test use' {
        $lines = Get-Content -LiteralPath $script:BuildYamlPath
        $block = [System.Collections.Generic.List[string]]::new()
        $inBlock = $false
        foreach ($line in $lines) {
            if (-not $inBlock) {
                if ($line -match '^ModuleBuildTasks:\s*(#.*)?$') { $inBlock = $true }
                continue
            }
            # The block ends at the next top-level key or comment line; blank lines are skipped.
            if ($line -match '^\S') { break }
            if ($line -match '^\s*(#.*)?$') { continue }
            $block.Add($line)
        }

        $block.Count | Should -BeGreaterThan 0

        $text = $block -join "`n"
        $text | Should -Not -Match '\*'

        # One module (Sampler) with an inline list of alias names.
        $modules = @($block | Where-Object { $_ -match '^\s{2}\S[^:]*:' })
        $modules.Count | Should -Be 1
        $modules[0] | Should -Match '^\s{2}Sampler:\s*\['

        $listText = ($modules[0] -replace '^[^\[]*\[', '' -replace '\]\s*(#.*)?$', '')
        $aliases = @($listText -split ',' | ForEach-Object { $_.Trim().Trim("'").Trim('"') })

        $expected = @(
            'Build-Module.ModuleBuilder.build.Sampler.ib.tasks'
            'Changelog.changelogmanagement.build.Sampler.ib.tasks'
            'Clean.ModuleBuilder.build.Sampler.ib.tasks'
            'Invoke-Pester.pester.build.Sampler.ib.tasks'
        )
        $aliases.Count | Should -Be $expected.Count
        @($aliases | Sort-Object) | Should -Be @($expected | Sort-Object)
    }
}
