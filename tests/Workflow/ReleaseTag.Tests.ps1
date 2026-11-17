# The workflow scripts carry '#Requires -Version 7.2', so they run on pwsh 7 only. This file must
# still PARSE in Windows PowerShell 5.1, where the build's Pester discovers it, so the whole
# Describe is skipped there instead of failing.
BeforeDiscovery {
    $script:OnDesktop = $PSVersionTable.PSEdition -eq 'Desktop'
    if ($script:OnDesktop) { Write-Warning 'tests/Workflow skipped: the workflow scripts run on pwsh 7 only (#Requires -Version 7.2).' }
}

BeforeAll {
    $script:ProjectPath = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath (Join-Path -Path '..' -ChildPath '..'))).Path
    $script:ScriptPath = Join-Path -Path $script:ProjectPath -ChildPath (Join-Path -Path '.github' -ChildPath (Join-Path -Path 'scripts' -ChildPath 'ReleaseTag.ps1'))

    # =====================================================================================
    # THE TAG STEP'S DECISION.
    #
    # .github/scripts/ReleaseTag.ps1 is pure: it reads the facts the tag step gathered and answers
    # Create or Skip, or throws. These tests run it with made-up facts -- no gh, no git, no network.
    # The publish job runs only after a merge, so this file is the only place a pull request sees
    # that code at all.
    # =====================================================================================

    # Commit ids made of one repeated digit: shaped like git's, naming nothing.
    $script:Sha = '1111111111111111111111111111111111111111'
    $script:OtherSha = '2222222222222222222222222222222222222222'
    $script:TagObject = '3333333333333333333333333333333333333333'

    function Invoke-ReleaseTag {
        <#
        .SYNOPSIS
        Runs ReleaseTag.ps1 with a main run's facts, changed by -Change.
        #>
        param([hashtable]$Change = @{})
        $Arguments = @{
            Version            = '0.4.8-preview0002'
            Sha                = $script:Sha
            Ref                = 'refs/heads/main'
            PublishedByThisJob = 'true'
            ReleaseExists      = $false
            RemoteTag          = @()
            Prerelease         = 'preview0002'
        }
        foreach ($Key in $Change.Keys) { $Arguments[$Key] = $Change[$Key] }
        & $script:ScriptPath @Arguments
    }

    function Get-ReleaseTagRefusal {
        <#
        .SYNOPSIS
        Returns the message ReleaseTag.ps1 refused with, or RETURNED when it did not refuse.
        #>
        param([hashtable]$Change = @{})
        try { $null = Invoke-ReleaseTag -Change $Change; 'RETURNED' } catch { $_.Exception.Message }
    }
}

# Skipped on Windows PowerShell 5.1: the script under test requires PowerShell 7.2.
Describe 'ReleaseTag.ps1' -Skip:$script:OnDesktop {
    Context 'When this job published the version' {
        It 'creates the tag and the release on GITHUB_SHA when neither exists' {
            $Decision = Invoke-ReleaseTag
            $Decision.Action | Should -BeExactly 'Create'
            $Decision.Tag | Should -BeExactly 'v0.4.8-preview0002'
            $Decision.Target | Should -BeExactly $script:Sha
        }

        It 'creates the release on a tag run whose annotated tag names GITHUB_SHA' {
            $Decision = Invoke-ReleaseTag -Change @{
                Version    = '0.5.0'
                Ref        = 'refs/tags/v0.5.0'
                Prerelease = ''
                RemoteTag  = @("$($script:TagObject)`trefs/tags/v0.5.0", "$($script:Sha)`trefs/tags/v0.5.0^{}")
            }
            $Decision.Action | Should -BeExactly 'Create'
            $Decision.Target | Should -BeExactly $script:Sha
        }

        It 'creates the release when a lightweight tag already names GITHUB_SHA' {
            $Decision = Invoke-ReleaseTag -Change @{ RemoteTag = @("$($script:Sha)`trefs/tags/v0.4.8-preview0002") }
            $Decision.Action | Should -BeExactly 'Create'
            $Decision.Target | Should -BeExactly $script:Sha
        }

        It 'skips when the release already exists on GITHUB_SHA' {
            $Decision = Invoke-ReleaseTag -Change @{ ReleaseExists = $true; RemoteTag = @("$($script:Sha)`trefs/tags/v0.4.8-preview0002") }
            $Decision.Action | Should -BeExactly 'Skip'
            $Decision.Target | Should -BeNullOrEmpty
        }

        It 'refuses when the release already exists on another commit' {
            $Message = Get-ReleaseTagRefusal -Change @{ ReleaseExists = $true; RemoteTag = @("$($script:OtherSha)`trefs/tags/v0.4.8-preview0002") }
            $Message | Should -BeLike 'REFUSING TO TAG.*'
            $Message | Should -BeLike "*$($script:OtherSha)*"
            $Message | Should -BeLike "*$($script:Sha)*"
        }

        It 'refuses when the tag already names another commit' {
            $Message = Get-ReleaseTagRefusal -Change @{ RemoteTag = @("$($script:OtherSha)`trefs/tags/v0.4.8-preview0002") }
            $Message | Should -BeLike 'REFUSING TO TAG.*'
            $Message | Should -BeLike "*already names $($script:OtherSha)*"
        }

        It 'refuses to create a stable tag on a tag run whose tag is gone' {
            $Message = Get-ReleaseTagRefusal -Change @{ Version = '0.5.0'; Ref = 'refs/tags/v0.5.0'; Prerelease = ''; RemoteTag = @() }
            $Message | Should -BeLike 'REFUSING TO TAG.*'
            $Message | Should -BeLike '*never creates*'
        }
    }

    Context 'When a run is not a tag run' {
        It 'refuses a stable version on a run that is not a tag run (<Case>)' -ForEach @(
            @{ Case = 'main, no label'; Change = @{ Version = '0.5.0'; Ref = 'refs/heads/main'; Prerelease = '' } }
            @{ Case = 'main, label and version disagree'; Change = @{ Version = '0.5.0'; Ref = 'refs/heads/main'; Prerelease = 'preview0001' } }
            @{ Case = 'another branch'; Change = @{ Version = '0.5.0'; Ref = 'refs/heads/chore/x'; Prerelease = '' } }
        ) {
            $Message = Get-ReleaseTagRefusal -Change $Change
            $Message | Should -BeLike 'REFUSING TO TAG.*'
            $Message | Should -BeLike "*$($Change.Ref)*"
            $Message | Should -BeLike '*0.5.0*'
            $Message | Should -BeLike '*never creates a stable tag*'
        }

        It 'refuses it even when the release already exists' {
            $Message = Get-ReleaseTagRefusal -Change @{ Version = '0.5.0'; Prerelease = ''; ReleaseExists = $true; RemoteTag = @("$($script:Sha)`trefs/tags/v0.5.0") }
            $Message | Should -BeLike 'REFUSING TO TAG.*'
            $Message | Should -BeLike '*never creates a stable tag*'
        }

        It 'refuses it even when this job did not publish' {
            $Message = Get-ReleaseTagRefusal -Change @{ Version = '0.5.0'; Prerelease = ''; PublishedByThisJob = '' }
            $Message | Should -BeLike 'REFUSING TO TAG.*'
            $Message | Should -BeLike '*never creates a stable tag*'
        }
    }

    Context 'When the publish step skipped' {
        It 'skips when the release already exists' {
            $Decision = Invoke-ReleaseTag -Change @{ PublishedByThisJob = ''; ReleaseExists = $true; RemoteTag = @("$($script:OtherSha)`trefs/tags/v0.4.8-preview0002") }
            $Decision.Action | Should -BeExactly 'Skip'
        }

        It 'refuses, naming the version, the Gallery and the hand repair, when the release is missing' {
            $Message = Get-ReleaseTagRefusal -Change @{ PublishedByThisJob = '' }
            $Message | Should -BeLike 'REFUSING TO TAG.*'
            $Message | Should -BeLike '*SendGridTools 0.4.8-preview0002 is already on the PowerShell Gallery*'
            $Message | Should -BeLike '*git tag v0.4.8-preview0002 *'
            $Message | Should -BeLike '*git push origin v0.4.8-preview0002*'
            $Message | Should -BeLike '*gh release create v0.4.8-preview0002 --verify-tag*--prerelease*'
            $Message | Should -BeLike "*$($script:Sha)*"
        }

        It 'points the hand repair at the log line written only after a successful upload' {
            $Message = Get-ReleaseTagRefusal -Change @{ PublishedByThisJob = '' }
            $Message | Should -BeLike '*logged ''Publishing SendGridTools 0.4.8-preview0002'' and, after the upload, ''Publish-PSResource returned without error''*'
        }

        It 'refuses on a tag run whose release is missing, naming the tag''s commit and the release command' {
            $Message = Get-ReleaseTagRefusal -Change @{
                PublishedByThisJob = ''
                Version            = '0.5.0'
                Ref                = 'refs/tags/v0.5.0'
                Prerelease         = ''
                RemoteTag          = @("$($script:TagObject)`trefs/tags/v0.5.0", "$($script:Sha)`trefs/tags/v0.5.0^{}")
            }
            $Message | Should -BeLike 'REFUSING TO TAG.*'
            $Message | Should -BeLike "*already exists, on $($script:Sha)*"
            $Message | Should -BeLike '*gh release create v0.5.0 --verify-tag*'
            $Message | Should -Not -BeLike '*--prerelease*'
        }

        It 'counts only the exact value true as published (<Value>)' -TestCases @(
            @{ Value = '' }
            @{ Value = 'false' }
            @{ Value = 'True' }
            @{ Value = '1' }
            @{ Value = ' true' }
        ) {
            param($Value)
            Get-ReleaseTagRefusal -Change @{ PublishedByThisJob = $Value } | Should -BeLike 'REFUSING TO TAG.*'
        }

        It 'counts a missing PublishedByThisJob as not published' {
            $Message = try {
                $null = & $script:ScriptPath -Version '0.4.8-preview0002' -Sha $script:Sha -Ref 'refs/heads/main' -ReleaseExists $false -RemoteTag @() -Prerelease 'preview0002'
                'RETURNED'
            } catch { $_.Exception.Message }
            $Message | Should -BeLike 'REFUSING TO TAG.*'
        }
    }

    Context 'When git ls-remote answered something else' {
        It 'refuses a line for another ref' {
            $Message = Get-ReleaseTagRefusal -Change @{ RemoteTag = @("$($script:Sha)`trefs/tags/v0.4.8-preview00021") }
            $Message | Should -BeLike '*cannot be read*'
            $Message | Should -BeLike '*a re-run cannot tag it: tag by hand*'
            $Message | Should -Not -BeLike '*before re-running*'
        }

        It 'refuses a line that is not a commit id and a ref' {
            Get-ReleaseTagRefusal -Change @{ RemoteTag = @('fatal: unable to access the remote') } | Should -BeLike '*cannot be read*'
        }

        It 'ignores blank lines' {
            (Invoke-ReleaseTag -Change @{ RemoteTag = @('', '   ') }).Action | Should -BeExactly 'Create'
        }
    }

    Context 'When its input is malformed' {
        It 'refuses a GITHUB_SHA that is not a full lower-case commit id' -TestCases @(
            @{ Value = 'abc123' }
            @{ Value = '1111111111111111111111111111111111111111'.ToUpper().Replace('1', 'A') }
        ) {
            param($Value)
            { Invoke-ReleaseTag -Change @{ Sha = $Value } } | Should -Throw
        }

        It 'refuses a version that is not a module version' {
            { Invoke-ReleaseTag -Change @{ Version = '0.4.8 preview' } } | Should -Throw
        }
    }

    Context 'When the workflow runs it' {
        BeforeAll {
            . (Join-Path -Path $PSScriptRoot -ChildPath 'WorkflowText.ps1')
            $script:WorkflowPath = Join-Path -Path $script:ProjectPath -ChildPath (Join-Path -Path '.github' -ChildPath (Join-Path -Path 'workflows' -ChildPath 'build-and-test.yml'))
            $script:WorkflowText = [System.IO.File]::ReadAllText($script:WorkflowPath)
            $script:PublishRun = Get-WorkflowStepRun -Text $script:WorkflowText -StepName 'Publish to the PowerShell Gallery'
            $script:TagRun = Get-WorkflowStepRun -Text $script:WorkflowText -StepName 'Tag the published commit and create the release'
        }

        It 'finds the publish step and the tag step' {
            $script:PublishRun | Should -Not -BeNullOrEmpty -Because 'a renamed step would hand every check below an empty text'
            $script:TagRun | Should -Not -BeNullOrEmpty -Because 'a renamed step would hand every check below an empty text'
        }

        It 'holds PowerShell that parses in both steps' {
            foreach ($Run in $script:PublishRun, $script:TagRun) {
                $Errors = $null
                $null = [System.Management.Automation.Language.Parser]::ParseInput($Run, [ref]$null, [ref]$Errors)
                @($Errors).Count | Should -Be 0 -Because ('the publish job runs only after a merge, so a syntax error here would first show after a publish: {0}' -f (@($Errors | ForEach-Object { $_.Message }) -join '; '))
            }
        }

        It 'writes PublishedByThisJob only after Publish-PSResource returns, and nowhere else' {
            [regex]::Matches($script:WorkflowText, 'PublishedByThisJob=').Count | Should -Be 1 -Because 'only the publish step may set the flag, once'
            # IndexOf answers -1 for text that is gone, which is "less than" everything: find each
            # anchor first, so that a renamed anchor fails here instead of passing the order checks.
            $Write = $script:PublishRun.IndexOf("'PublishedByThisJob=true'")
            $Upload = $script:PublishRun.IndexOf('Publish-PSResource -Path')
            $Skipped = $script:PublishRun.IndexOf('SKIPPING THE PUBLISH')
            $Write | Should -BeGreaterOrEqual 0
            $Upload | Should -BeGreaterOrEqual 0
            $Skipped | Should -BeGreaterOrEqual 0
            $Write | Should -BeGreaterThan $Upload
            $Upload | Should -BeGreaterThan $Skipped
        }

        It 'logs the line the hand repair names only after the upload' {
            $Upload = $script:PublishRun.IndexOf('Publish-PSResource -Path')
            $Logged = $script:PublishRun.IndexOf('Publish-PSResource returned without error')
            $Upload | Should -BeGreaterOrEqual 0
            $Logged | Should -BeGreaterThan $Upload
        }

        It 'hands the decision to ReleaseTag.ps1 with the job''s facts' {
            $script:TagRun | Should -Match '\./\.github/scripts/ReleaseTag\.ps1 '
            $script:TagRun | Should -Match '-Sha \$env:GITHUB_SHA'
            $script:TagRun | Should -Match '-Ref \$env:GITHUB_REF'
            $script:TagRun | Should -Match '-PublishedByThisJob \$env:PublishedByThisJob'
            $script:TagRun | Should -Match '-ReleaseExists \$ReleaseExists'
            $script:TagRun | Should -Match '-RemoteTag \$RemoteTag'
            $script:TagRun | Should -Match '-Prerelease \$env:PublishPrerelease'
        }

        It 'returns on Skip before it creates anything' {
            # Single-quoted patterns: in a double-quoted one a `$ would reach the regex as an anchor.
            $Skip = [regex]::Match($script:TagRun, 'if \(\$Decision\.Action -ceq ''Skip''\) \{ return \}')
            $Skip.Success | Should -BeTrue
            $Skip.Index | Should -BeLessThan $script:TagRun.IndexOf('gh @Arguments')
        }

        It 'asks ReleaseTag.ps1 for the decision before it creates the release, outside any try' {
            $Asked = $script:TagRun.IndexOf('./.github/scripts/ReleaseTag.ps1 ')
            $Created = $script:TagRun.IndexOf('gh @Arguments')
            $Asked | Should -BeGreaterOrEqual 0
            $Created | Should -BeGreaterThan $Asked

            $Errors = $null
            $Ast = [System.Management.Automation.Language.Parser]::ParseInput($script:TagRun, [ref]$null, [ref]$Errors)
            $Calls = @($Ast.FindAll({
                        param($Node)
                        $Node -is [System.Management.Automation.Language.CommandAst] -and $Node.GetCommandName() -ceq './.github/scripts/ReleaseTag.ps1'
                    }, $true))
            $Calls.Count | Should -Be 1
            $Wrapping = [System.Collections.Generic.List[string]]::new()
            $Parent = $Calls[0].Parent
            while ($null -ne $Parent) {
                if ($Parent -is [System.Management.Automation.Language.TryStatementAst]) { $Wrapping.Add($Parent.Extent.Text) }
                $Parent = $Parent.Parent
            }
            $Wrapping.Count | Should -Be 0 -Because 'a try around the call could swallow a refusal and let the step go on to create the release'
        }

        It 'tells a failed release creation to be repaired by hand, never to be re-run' {
            $script:TagRun | Should -Not -Match 're-running'
            $script:TagRun | Should -Match 'a re-run of this job cannot create the release: tag and release by hand'
        }

        It 'creates the release on the decision''s target, never on GITHUB_SHA directly' {
            $script:TagRun | Should -Match '''--target'', \$Decision\.Target'
            $script:TagRun | Should -Not -Match '''--target'', \$env:GITHUB_SHA'
        }
    }

    Context 'When the tag step runs against a fake gh and git' {
        BeforeAll {
            . (Join-Path -Path $PSScriptRoot -ChildPath 'WorkflowText.ps1')
            $script:WorkflowPath = Join-Path -Path $script:ProjectPath -ChildPath (Join-Path -Path '.github' -ChildPath (Join-Path -Path 'workflows' -ChildPath 'build-and-test.yml'))
            $script:TagRun = Get-WorkflowStepRun -Text ([System.IO.File]::ReadAllText($script:WorkflowPath)) -StepName 'Tag the published commit and create the release'
            # The step reads the built manifest's ReleaseNotes before it creates the release.
            $script:StepModulePath = Join-Path -Path $TestDrive -ChildPath 'ModulePath'
            $null = New-Item -Path $script:StepModulePath -ItemType Directory -Force
            Set-Content -LiteralPath (Join-Path -Path $script:StepModulePath -ChildPath 'SendGridTools.psd1') -Value "@{ PrivateData = @{ PSData = @{ ReleaseNotes = 'Notes of a manifest fixture, long enough to read.' } } }"

            function Invoke-TagStep {
                <#
                .SYNOPSIS
                Runs the tag step's run: text against a fake gh and a fake git, and reports what happened.
                .DESCRIPTION
                The fakes are functions, which PowerShell resolves before an executable of the same name; they
                record each call as one line and set $LASTEXITCODE the way the real tools would. Nothing leaves
                the process: no gh, no git, no network. The step runs from the project root, as a workflow
                step runs from the checkout, and the environment variables it reads are set for the call and
                put back afterwards. GH_TOKEN is set to the fake NOT-A-REAL-TOKEN, so a real gh that were ever
                reached would not be signed in as the user. An alias outranks a function, so before the step
                runs each of gh and git is resolved with Get-Command, and the harness throws, running nothing,
                when one does not resolve to its fake function. Returns Thrown (the message of the terminating
                error, or $null), Calls and Tokens (GH_TOKEN as each gh call saw it).
                #>
                param(
                    [hashtable]$Environment = @{},
                    [int]$GhViewExit = 1,
                    [int]$GitExit = 0,
                    [string[]]$GitOutput = @()
                )
                $Variables = @{
                    PublishVersion     = '0.4.8-preview0002'
                    GITHUB_SHA         = $script:Sha
                    GITHUB_REF         = 'refs/heads/main'
                    PublishedByThisJob = 'true'
                    PublishPrerelease  = 'preview0002'
                    ModulePath         = $script:StepModulePath
                    RUNNER_TEMP        = $script:StepModulePath
                    GH_TOKEN           = 'NOT-A-REAL-TOKEN'
                }
                foreach ($Key in $Environment.Keys) { $Variables[$Key] = $Environment[$Key] }
                $Saved = @{}
                foreach ($Key in $Variables.Keys) { $Saved[$Key] = [System.Environment]::GetEnvironmentVariable($Key) }
                $SavedExitCode = $global:LASTEXITCODE
                $Calls = [System.Collections.Generic.List[string]]::new()
                $Tokens = [System.Collections.Generic.List[string]]::new()

                function gh {
                    $Calls.Add('gh ' + ($args -join ' '))
                    $Tokens.Add($env:GH_TOKEN)
                    $global:LASTEXITCODE = if ($args[0] -ceq 'release' -and $args[1] -ceq 'view') { $GhViewExit } else { 0 }
                }

                function git {
                    $Calls.Add('git ' + ($args -join ' '))
                    $global:LASTEXITCODE = $GitExit
                    $GitOutput
                }

                foreach ($Tool in 'gh', 'git') {
                    $Resolved = Get-Command -Name $Tool -ErrorAction Ignore | Select-Object -First 1
                    if (($Resolved -isnot [System.Management.Automation.FunctionInfo]) -or -not $Resolved.ScriptBlock.ToString().Contains('$Calls.Add(')) {
                        $Found = if ($Resolved) { '{0} {1}' -f $Resolved.CommandType, $Resolved.Name } else { 'nothing' }
                        throw ('Invoke-TagStep: {0} resolves to {1}, not to the fake function, so the step would reach the real tool; nothing was run.' -f $Tool, $Found)
                    }
                }

                $Thrown = $null
                Push-Location -LiteralPath $script:ProjectPath
                try {
                    foreach ($Key in $Variables.Keys) { [System.Environment]::SetEnvironmentVariable($Key, $Variables[$Key]) }
                    & ([scriptblock]::Create($script:TagRun)) 6>$null
                }
                catch { $Thrown = $_.Exception.Message }
                finally {
                    Pop-Location
                    foreach ($Key in $Saved.Keys) { [System.Environment]::SetEnvironmentVariable($Key, $Saved[$Key]) }
                    $global:LASTEXITCODE = $SavedExitCode
                }
                [PSCustomObject]@{ Thrown = $Thrown; Calls = $Calls; Tokens = $Tokens }
            }
        }

        It 'creates the release on GITHUB_SHA, marked as a prerelease, when this job published' {
            $Run = Invoke-TagStep
            $Run.Thrown | Should -BeNullOrEmpty
            $Created = @($Run.Calls | Where-Object { $_ -like 'gh release create*' })
            $Created.Count | Should -Be 1
            $Created[0] | Should -BeLike "gh release create v0.4.8-preview0002 --target $($script:Sha) --title v0.4.8-preview0002 --notes-file *--prerelease"
            @($Run.Calls | Where-Object { $_ -eq 'git ls-remote origin refs/tags/v0.4.8-preview0002 refs/tags/v0.4.8-preview0002^{}' }).Count | Should -Be 1
        }

        It 'passes --verify-tag on a tag run, so gh never creates the stable tag' {
            $Run = Invoke-TagStep -Environment @{
                GITHUB_REF         = 'refs/tags/v0.5.0'
                PublishVersion     = '0.5.0'
                PublishPrerelease  = ''
                PublishedByThisJob = 'true'
            } -GitOutput @("$($script:TagObject)`trefs/tags/v0.5.0", "$($script:Sha)`trefs/tags/v0.5.0^{}")
            $Run.Thrown | Should -BeNullOrEmpty
            $Created = @($Run.Calls | Where-Object { $_ -like 'gh release create*' })
            $Created.Count | Should -Be 1
            $Created[0] | Should -BeLike '* --verify-tag*'
            $Created[0] | Should -Not -BeLike '*--prerelease*'
        }

        It 'does not pass --verify-tag on main, where the preview tag does not exist yet' {
            $Run = Invoke-TagStep
            $Run.Thrown | Should -BeNullOrEmpty
            $Created = @($Run.Calls | Where-Object { $_ -like 'gh release create*' })
            $Created.Count | Should -Be 1
            $Created[0] | Should -Not -BeLike '*--verify-tag*'
        }

        It 'stops before it asks for a decision when git ls-remote fails' {
            $Run = Invoke-TagStep -GitExit 128
            $Run.Thrown | Should -BeLike 'git ls-remote exited with 128*'
            $Run.Thrown | Should -BeLike '*a re-run cannot tag it: tag by hand*'
            @($Run.Calls | Where-Object { $_ -like 'gh release create*' }).Count | Should -Be 0
        }

        It 'creates nothing when the publish step skipped and the release is missing' {
            $Run = Invoke-TagStep -Environment @{ PublishedByThisJob = '' }
            $Run.Thrown | Should -BeLike 'REFUSING TO TAG.*'
            @($Run.Calls | Where-Object { $_ -like 'gh release create*' }).Count | Should -Be 0
        }

        It 'creates nothing when the release already exists' {
            $Run = Invoke-TagStep -Environment @{ PublishedByThisJob = '' } -GhViewExit 0
            $Run.Thrown | Should -BeNullOrEmpty
            @($Run.Calls | Where-Object { $_ -like 'gh release create*' }).Count | Should -Be 0
        }

        It 'runs the tag step with GH_TOKEN set to NOT-A-REAL-TOKEN' {
            $Run = Invoke-TagStep
            $Run.Thrown | Should -BeNullOrEmpty
            @($Run.Tokens).Count | Should -BeGreaterThan 0 -Because 'a step that never called gh would leave every token check below empty'
            foreach ($Token in $Run.Tokens) {
                $Token | Should -BeExactly 'NOT-A-REAL-TOKEN'
            }
        }

        # An alias outranks a function, so a profile alias named gh or git would run instead of the
        # fake. The shadow below only sets a global flag; it reaches no real tool.
        It 'refuses to run the tag step when <Tool> does not resolve to its fake' -ForEach @(@{ Tool = 'gh' }, @{ Tool = 'git' }) {
            $global:ShadowToolHit = $null
            try {
                function global:Invoke-ShadowTool { $global:ShadowToolHit = $true }
                Set-Alias -Name $Tool -Value Invoke-ShadowTool -Scope Global
                { Invoke-TagStep } | Should -Throw -ExpectedMessage "*$Tool*fake*"
                $global:ShadowToolHit | Should -BeNullOrEmpty
            } finally {
                Remove-Item -Path "Alias:$Tool" -ErrorAction SilentlyContinue
                Remove-Item -Path 'Function:Invoke-ShadowTool' -ErrorAction SilentlyContinue
                Remove-Variable -Name ShadowToolHit -Scope Global -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'When PSScriptAnalyzer reads it' {
        It 'reports nothing' {
            $Findings = @(Invoke-ScriptAnalyzer -Path $script:ScriptPath)
            $Findings.Count | Should -Be 0 -Because (($Findings | ForEach-Object { '{0}:{1} {2}' -f $_.RuleName, $_.Line, $_.Message }) -join '; ')
        }
    }
}
