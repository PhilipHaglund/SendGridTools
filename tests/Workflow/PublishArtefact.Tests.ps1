# The workflow scripts carry '#Requires -Version 7.2', so they run on pwsh 7 only. This file must
# still PARSE in Windows PowerShell 5.1, where the build's Pester discovers it, so the whole
# Describe is skipped there instead of failing.
BeforeDiscovery {
    $script:OnDesktop = $PSVersionTable.PSEdition -eq 'Desktop'
    if ($script:OnDesktop) { Write-Warning 'tests/Workflow skipped: the workflow scripts run on pwsh 7 only (#Requires -Version 7.2).' }
}

BeforeAll {
    $script:ProjectPath = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath (Join-Path -Path '..' -ChildPath '..'))).Path
    $script:ScriptPath = Join-Path -Path $script:ProjectPath -ChildPath (Join-Path -Path '.github' -ChildPath (Join-Path -Path 'scripts' -ChildPath 'PublishArtefact.ps1'))

    # Commit ids made of one repeated digit: shaped like git's, naming nothing.
    $script:Sha = '1111111111111111111111111111111111111111'
    $script:OtherSha = '2222222222222222222222222222222222222222'

    function New-ArtefactRoot {
        <#
        .SYNOPSIS
        Builds a fixture artefact root under $TestDrive: <root>/SendGridTools/0.4.8 with three files.
        #>
        param([string]$Name, [string]$Prerelease = 'preview0001')
        $Root = Join-Path -Path $TestDrive -ChildPath $Name
        $Folder = Join-Path -Path $Root -ChildPath (Join-Path -Path 'SendGridTools' -ChildPath '0.4.8')
        $null = New-Item -Path (Join-Path -Path $Folder -ChildPath 'en-US') -ItemType Directory -Force
        if ($Prerelease) {
            $Manifest = "@{ ModuleVersion = '0.4.8'; PrivateData = @{ PSData = @{ Prerelease = '$Prerelease' } } }"
        }
        else {
            $Manifest = "@{ ModuleVersion = '0.4.8' }"
        }
        [System.IO.File]::WriteAllText((Join-Path -Path $Folder -ChildPath 'SendGridTools.psd1'), $Manifest)
        [System.IO.File]::WriteAllText((Join-Path -Path $Folder -ChildPath 'SendGridTools.psm1'), '# fixture module')
        [System.IO.File]::WriteAllText((Join-Path -Path $Folder -ChildPath (Join-Path -Path 'en-US' -ChildPath 'about_SendGridTools.help.txt')), 'fixture help')
        [PSCustomObject]@{ Root = $Root; Folder = $Folder }
    }

    function New-RecordedArtefact {
        <#
        .SYNOPSIS
        Builds a fixture artefact root and records it, so a test can then tamper with it.
        #>
        param([string]$Name)
        $Artefact = New-ArtefactRoot -Name $Name
        $null = & $script:ScriptPath -Record -Path $Artefact.Root -Sha $script:Sha -ModuleVersion '0.4.8-preview0001' 6>$null
        $Artefact
    }

    function Get-VerifyRefusal {
        <#
        .SYNOPSIS
        Returns the message -Verify refused with, or RETURNED when it did not refuse.
        #>
        param([string]$Root, [string]$Sha = $script:Sha)
        try { $null = & $script:ScriptPath -Verify -Path $Root -Sha $Sha 6>$null; 'RETURNED' } catch { $_.Exception.Message }
    }
}

# Skipped on Windows PowerShell 5.1: the script under test requires PowerShell 7.2.
Describe 'PublishArtefact.ps1' -Skip:$script:OnDesktop {
    Context 'When it records a build' {
        It 'records the commit, both versions and one SHA-256 per file' {
            $Artefact = New-ArtefactRoot -Name 'record'
            $null = & $script:ScriptPath -Record -Path $Artefact.Root -Sha $script:Sha -ModuleVersion '0.4.8-preview0001' 6>$null
            $Meta = Get-Content -LiteralPath (Join-Path -Path $Artefact.Root -ChildPath 'publish-meta.json') -Raw | ConvertFrom-Json
            $Meta.Sha | Should -BeExactly $script:Sha
            $Meta.ModuleVersion | Should -BeExactly '0.4.8-preview0001'
            $Meta.ComposedVersion | Should -BeExactly '0.4.8-preview0001'
            $Meta.ManifestPrerelease | Should -BeExactly 'preview0001'
            @($Meta.Files).Count | Should -Be 3
            @($Meta.Files.Path) | Should -Contain 'en-US/about_SendGridTools.help.txt'
            foreach ($File in $Meta.Files) {
                $File.Path | Should -Not -Match '\\'
                $File.Sha256 | Should -Match '^[0-9A-F]{64}$'
            }
        }

        It 'refuses to record when GitVersion''s numeric part differs from the manifest' {
            $Artefact = New-ArtefactRoot -Name 'mismatch'
            { & $script:ScriptPath -Record -Path $Artefact.Root -Sha $script:Sha -ModuleVersion '0.4.9-preview0001' 6>$null } | Should -Throw '*0.4.9*0.4.8*'
        }

        It 'composes a version without a label when the manifest has no prerelease' {
            $Artefact = New-ArtefactRoot -Name 'stable' -Prerelease ''
            $null = & $script:ScriptPath -Record -Path $Artefact.Root -Sha $script:Sha -ModuleVersion '0.4.8' 6>$null
            $Meta = Get-Content -LiteralPath (Join-Path -Path $Artefact.Root -ChildPath 'publish-meta.json') -Raw | ConvertFrom-Json
            $Meta.ComposedVersion | Should -BeExactly '0.4.8'
        }
    }

    Context 'When it verifies an artefact' {
        It 'verifies an untouched artefact and returns the version folder' {
            $Artefact = New-RecordedArtefact -Name 'verify-ok'
            $Result = & $script:ScriptPath -Verify -Path $Artefact.Root -Sha $script:Sha 6>$null
            $Result | Should -BeLike '*SendGridTools?0.4.8'
        }

        It 'refuses a changed file' {
            $Artefact = New-RecordedArtefact -Name 'verify-changed'
            [System.IO.File]::WriteAllText((Join-Path -Path $Artefact.Folder -ChildPath 'SendGridTools.psm1'), '# tampered')
            Get-VerifyRefusal -Root $Artefact.Root | Should -BeLike '*SHA-256 of 1*'
        }

        It 'refuses an added file' {
            $Artefact = New-RecordedArtefact -Name 'verify-added'
            [System.IO.File]::WriteAllText((Join-Path -Path $Artefact.Folder -ChildPath 'extra.ps1'), '# extra')
            Get-VerifyRefusal -Root $Artefact.Root | Should -BeLike '*never recorded*'
        }

        It 'refuses a removed file' {
            $Artefact = New-RecordedArtefact -Name 'verify-removed'
            Remove-Item -LiteralPath (Join-Path -Path $Artefact.Folder -ChildPath 'SendGridTools.psm1')
            Get-VerifyRefusal -Root $Artefact.Root | Should -BeLike '*missing 1*'
        }

        It 'refuses another commit' {
            $Artefact = New-RecordedArtefact -Name 'verify-sha'
            Get-VerifyRefusal -Root $Artefact.Root -Sha $script:OtherSha | Should -BeLike '*different commit*'
        }

        It 'refuses two version folders' {
            $Artefact = New-RecordedArtefact -Name 'verify-two'
            $null = New-Item -Path (Join-Path -Path $Artefact.Root -ChildPath (Join-Path -Path 'SendGridTools' -ChildPath '0.4.9')) -ItemType Directory
            Get-VerifyRefusal -Root $Artefact.Root | Should -BeLike '*exactly one version folder*'
        }

        It 'refuses an artefact with no publish-meta.json' {
            $Artefact = New-ArtefactRoot -Name 'verify-nometa'
            Get-VerifyRefusal -Root $Artefact.Root | Should -BeLike '*No publish-meta.json*'
        }
    }

    Context 'When PSScriptAnalyzer reads it' {
        It 'reports nothing' {
            $Findings = @(Invoke-ScriptAnalyzer -Path $script:ScriptPath)
            $Findings.Count | Should -Be 0 -Because (($Findings | ForEach-Object { '{0}:{1} {2}' -f $_.RuleName, $_.Line, $_.Message }) -join '; ')
        }
    }
}
