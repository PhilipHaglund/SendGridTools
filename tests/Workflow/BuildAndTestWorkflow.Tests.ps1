# The workflow's publish path is read and executed here. The workflow scripts carry
# '#Requires -Version 7.2', so they run on pwsh 7 only. This file must still PARSE in Windows
# PowerShell 5.1, where the build's Pester discovers it, so the whole Describe is skipped there
# instead of failing.
BeforeDiscovery {
    $script:OnDesktop = $PSVersionTable.PSEdition -eq 'Desktop'
    if ($script:OnDesktop) { Write-Warning 'tests/Workflow skipped: the workflow scripts run on pwsh 7 only (#Requires -Version 7.2).' }
}

BeforeAll {
    $script:ProjectPath = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath (Join-Path -Path '..' -ChildPath '..'))).Path
    $script:WorkflowPath = Join-Path -Path $script:ProjectPath -ChildPath (Join-Path -Path '.github' -ChildPath (Join-Path -Path 'workflows' -ChildPath 'build-and-test.yml'))
    . (Join-Path -Path $PSScriptRoot -ChildPath 'WorkflowText.ps1')

    # =====================================================================================
    # THE WORKFLOW FILE, READ AS TEXT, AND ITS REFUSAL STEP, RUN.
    #
    # There is no YAML parser among the build's modules, so the static tests read lines. The
    # refusal step's run: text is executed against a fake gh: nothing leaves the process.
    # =====================================================================================

    $script:Sha = '1111111111111111111111111111111111111111'

    function Get-JobText {
        <#
        .SYNOPSIS
        Returns the lines of one top-level job, from its '  <Job>:' line to the next job or the end.
        #>
        param([string]$Text, [string]$Job)
        $Lines = $Text -split '\r?\n'
        $Collected = [System.Collections.Generic.List[string]]::new()
        $Inside = $false
        foreach ($Line in $Lines) {
            if ($Line -match '^  [A-Za-z][\w-]*:\s*$') {
                $Inside = $Line -ceq ('  {0}:' -f $Job)
            }
            elseif ($Line -match '^\S') {
                $Inside = $false
            }
            if ($Inside) { $Collected.Add($Line) }
        }
        $Collected -join "`n"
    }

    function Get-CodeLine {
        <#
        .SYNOPSIS
        Returns the lines of the text that are not comment lines.
        #>
        param([string]$Text)
        @($Text -split '\r?\n' | Where-Object { $_ -notmatch '^\s*#' })
    }

    function Get-GalleryTokenFinding {
        <#
        .SYNOPSIS
        Returns one text per breach of the rule that only the publish step gets the gallery key.
        .DESCRIPTION
        The rule: every line that is not a comment and names GALLERYAPITOKEN lies in the job
        publish, inside the one step that maps the secret to an environment variable under that
        step's env:, and exactly one step does so. The text is read line by line, tracking the
        top-level key, the job (a two-space key under jobs:) and the step (a line that starts
        with six spaces and a dash; a four-space key of the job ends it). The secret is matched
        without regard to case, since GitHub expressions are. Each finding names the line number
        and the reason. Nothing is returned when the text keeps the rule. A line inside a block
        scalar (a key whose value is | or >, with an optional - or +) is content, not a comment,
        even when it starts with #, since GitHub expands an expression in it; such a line is read
        like any code line. A block holds every following line that is blank or indented deeper
        than its key (for "- key: |" the key stands after the dash).
        #>
        param([string]$Text)
        $Lines = $Text -split '\r?\n'
        $Findings = [System.Collections.Generic.List[string]]::new()
        $Mappings = [System.Collections.Generic.List[object]]::new()
        $Names = [System.Collections.Generic.List[object]]::new()
        $TopKey = ''
        $Job = ''
        $StepLine = 0
        $StepName = ''
        $BlockIndent = -1
        for ($Index = 0; $Index -lt $Lines.Count; $Index++) {
            $Line = $Lines[$Index]
            $InBlock = $false
            if ($BlockIndent -ge 0) {
                if ($Line -match '^\s*$') { continue }
                if (($Line.Length - $Line.TrimStart().Length) -gt $BlockIndent) { $InBlock = $true }
                else { $BlockIndent = -1 }
            }
            if (-not $InBlock -and ($Line -match '^\s*$' -or $Line -match '^\s*#')) { continue }
            if ($InBlock) {
                # Content of a block scalar: not a comment and not a key, so no structure is read from it.
            }
            elseif ($Line -match '^(\S[^:]*):') {
                $TopKey = $Matches[1]
                $Job = ''
                $StepLine = 0
                $StepName = ''
            }
            elseif ($TopKey -eq 'jobs' -and $Line -match '^  ([A-Za-z][\w-]*):\s*$') {
                $Job = $Matches[1]
                $StepLine = 0
                $StepName = ''
            }
            elseif ($Line -match '^      - ') {
                $StepLine = $Index + 1
                $StepName = if ($Line -match '^      - name:\s*(.+?)\s*$') { $Matches[1] } else { '' }
            }
            elseif ($Line -match '^    \S') {
                $StepLine = 0
                $StepName = ''
            }
            if (-not $InBlock -and $Line -match '^(\s*)(- )?[A-Za-z_][\w-]*:\s*[|>][-+]?\s*$') {
                $BlockIndent = $Matches[1].Length + $(if ($Matches[2]) { 2 } else { 0 })
            }
            if ($Line -notmatch 'GALLERYAPITOKEN') { continue }
            $Number = $Index + 1
            $Entry = [PSCustomObject]@{ Number = $Number; Job = $Job; StepLine = $StepLine; StepName = $StepName }
            $Names.Add($Entry)
            if ($Job -ne 'publish') {
                $Findings.Add(('line {0}: names GALLERYAPITOKEN outside the job publish (job: {1})' -f $Number, $(if ($Job) { $Job } else { 'none' })))
            }
            if ($Line -match "secrets\s*(\.\s*GALLERYAPITOKEN\b|\[\s*['""]GALLERYAPITOKEN['""]\s*\])") {
                $Mappings.Add($Entry)
                $Indent = $Line.Length - $Line.TrimStart().Length
                $Parent = $null
                for ($Back = $Index - 1; $Back -ge 0; $Back--) {
                    $Earlier = $Lines[$Back]
                    if ($Earlier -match '^\s*$' -or $Earlier -match '^\s*#') { continue }
                    if (($Earlier.Length - $Earlier.TrimStart().Length) -lt $Indent) { $Parent = $Earlier; break }
                }
                $IsEnvEntry = $Line -match '^\s+[A-Za-z_][A-Za-z0-9_]*:\s*\$\{\{\s*secrets\.GALLERYAPITOKEN\s*\}\}\s*$'
                if (-not $IsEnvEntry -or $null -eq $Parent -or $Parent -notmatch '^\s+env:\s*$' -or $StepLine -eq 0) {
                    $Findings.Add(('line {0}: maps GALLERYAPITOKEN other than as an entry under the env: of a step' -f $Number))
                }
            }
        }
        if ($Mappings.Count -ne 1) {
            $Findings.Add(('file: {0} lines map GALLERYAPITOKEN, exactly one is allowed' -f $Mappings.Count))
        }
        else {
            foreach ($Entry in $Names) {
                if ($Entry.StepLine -ne $Mappings[0].StepLine) {
                    $Findings.Add(('line {0}: names GALLERYAPITOKEN in a step other than the one that maps it (the step at line {1})' -f $Entry.Number, $Mappings[0].StepLine))
                }
            }
        }
        $Findings.ToArray()
    }

    function Invoke-RefusalStep {
        <#
        .SYNOPSIS
        Runs the refusal step's run: text against a fake gh and reports what happened.
        .DESCRIPTION
        The fake is a function, which PowerShell resolves before an executable of the same name; it
        records each call as one line and answers the compare call with -GhStatus and -GhExit the
        way gh would. Nothing leaves the process: no gh, no network. GH_TOKEN is the fake
        NOT-A-REAL-TOKEN. An alias outranks a function, so before the step runs gh is resolved with
        Get-Command, and the harness throws, running nothing, when it does not resolve to the fake
        function. The environment variables the step reads are set for the call and put back after.
        Returns Thrown (the message of the terminating error, or $null) and Calls.
        #>
        param(
            [hashtable]$Environment = @{},
            [string]$GhStatus = 'identical',
            [int]$GhExit = 0
        )
        $Variables = @{
            PublishVersion    = '0.4.8-preview0001'
            PublishPrerelease = 'preview0001'
            GITHUB_SHA        = $script:Sha
            GITHUB_REF        = 'refs/heads/main'
            GITHUB_REF_NAME   = 'main'
            GITHUB_REPOSITORY = 'owner/repository'
            GH_TOKEN          = 'NOT-A-REAL-TOKEN'
        }
        foreach ($Key in $Environment.Keys) { $Variables[$Key] = $Environment[$Key] }
        $Saved = @{}
        foreach ($Key in $Variables.Keys) { $Saved[$Key] = [System.Environment]::GetEnvironmentVariable($Key) }
        $SavedExitCode = $global:LASTEXITCODE
        $Calls = [System.Collections.Generic.List[string]]::new()

        function gh {
            $Calls.Add('gh ' + ($args -join ' '))
            $global:LASTEXITCODE = $GhExit
            $GhStatus
        }

        $Resolved = Get-Command -Name 'gh' -ErrorAction Ignore | Select-Object -First 1
        if (($Resolved -isnot [System.Management.Automation.FunctionInfo]) -or -not $Resolved.ScriptBlock.ToString().Contains('$Calls.Add(')) {
            $Found = if ($Resolved) { '{0} {1}' -f $Resolved.CommandType, $Resolved.Name } else { 'nothing' }
            throw ('Invoke-RefusalStep: gh resolves to {0}, not to the fake function, so the step would reach the real tool; nothing was run.' -f $Found)
        }

        $Thrown = $null
        Push-Location -LiteralPath $script:ProjectPath
        try {
            foreach ($Key in $Variables.Keys) { [System.Environment]::SetEnvironmentVariable($Key, $Variables[$Key]) }
            & ([scriptblock]::Create($script:RefusalRun)) 6>$null
        }
        catch { $Thrown = $_.Exception.Message }
        finally {
            Pop-Location
            foreach ($Key in $Saved.Keys) { [System.Environment]::SetEnvironmentVariable($Key, $Saved[$Key]) }
            $global:LASTEXITCODE = $SavedExitCode
        }
        [PSCustomObject]@{ Thrown = $Thrown; Calls = $Calls }
    }
}

# Skipped on Windows PowerShell 5.1: the scripts the workflow calls require PowerShell 7.2.
Describe 'build-and-test.yml' -Skip:$script:OnDesktop {
    BeforeAll {
        $script:WorkflowText = [System.IO.File]::ReadAllText($script:WorkflowPath)
        $script:CodeLines = Get-CodeLine -Text $script:WorkflowText
        $script:RefusalRun = Get-WorkflowStepRun -Text $script:WorkflowText -StepName 'Refuse a version the triggering ref does not call for'
    }

    Context 'When its text is read' {
        It 'triggers on main, v tags without a hyphen, pull requests to main and workflow_dispatch, with no paths-ignore' {
            $script:CodeLines | Should -Contain '    branches: [main]'
            $script:CodeLines | Should -Contain "    tags: ['v*', '!v*-*']"
            $script:CodeLines | Should -Contain '  pull_request:'
            $script:CodeLines | Should -Contain '  workflow_dispatch:'
            @($script:CodeLines | Where-Object { $_ -match 'paths-ignore' }).Count | Should -Be 0
            $script:CodeLines | Should -Not -Contain '    branches: [master]'
        }

        It 'pins every action to a full commit SHA' {
            $Uses = @($script:CodeLines | Where-Object { $_ -match '^\s*(- )?uses:' })
            $Uses.Count | Should -BeGreaterThan 0
            foreach ($Line in $Uses) {
                $Line | Should -Match 'uses: \S+@[0-9a-f]{40}\b' -Because "an action must be pinned to a SHA: $Line"
            }
        }

        It 'grants contents: write only to publish' {
            $Writes = @($script:CodeLines | Where-Object { $_ -match '^\s+contents:\s*write\s*$' })
            $Writes.Count | Should -Be 1
            $PublishJob = Get-JobText -Text $script:WorkflowText -Job 'publish'
            @(Get-CodeLine -Text $PublishJob | Where-Object { $_ -match '^\s+contents:\s*write\s*$' }).Count | Should -Be 1
            $PublishStart = ($script:WorkflowText -split '\r?\n' | Select-String -Pattern '^  publish:' -CaseSensitive).LineNumber
            $WriteLine = ($script:WorkflowText -split '\r?\n' | Select-String -Pattern '^\s+contents:\s*write\s*$').LineNumber
            $WriteLine | Should -BeGreaterThan $PublishStart
        }

        It 'checks out full history in every test job' {
            $PackageStart = ($script:WorkflowText -split '\r?\n' | Select-String -Pattern '^  package:' -CaseSensitive).LineNumber
            $PackageStart | Should -BeGreaterThan 0
            $Depths = @($script:WorkflowText -split '\r?\n' | Select-String -Pattern '^\s+fetch-depth: 0\s*$')
            $Depths.Count | Should -Be 2
            foreach ($Depth in $Depths) { $Depth.LineNumber | Should -BeLessThan $PackageStart }
            foreach ($Job in 'build-and-test', 'windows-powershell') {
                @(Get-CodeLine -Text (Get-JobText -Text $script:WorkflowText -Job $Job) | Where-Object { $_ -match '^\s+fetch-depth: 0\s*$' }).Count | Should -Be 1 -Because "$Job needs the full history"
            }
        }

        It 'runs noop, build and test in pwsh and in Windows PowerShell 5.1' {
            $Matrix = Get-JobText -Text $script:WorkflowText -Job 'build-and-test'
            $Desktop = Get-JobText -Text $script:WorkflowText -Job 'windows-powershell'
            $Matrix | Should -Not -Match 'name: windows-powershell-5\.1'
            $Desktop | Should -Match 'name: windows-powershell-5\.1'
            $Desktop | Should -Match 'runs-on: windows-latest'
            $Desktop | Should -Match '\$PSVersionTable\.PSVersion'
            foreach ($Case in @(
                    @{ Text = $Matrix; Shell = 'pwsh'; Run = '\./build\.ps1 -ResolveDependency -Tasks noop\r?\n' }
                    @{ Text = $Desktop; Shell = 'powershell'; Run = '\|\r?\n\s+\$PSVersionTable\.PSVersion\r?\n\s+\./build\.ps1 -ResolveDependency -Tasks noop\r?\n' })) {
                $Noop = '- name: Resolve build dependencies\r?\n\s+shell: {0}\r?\n\s+run: {1}' -f $Case.Shell, $Case.Run
                $Build = '- name: Build\r?\n\s+shell: {0}\r?\n\s+run: \./build\.ps1 -Tasks build\r?\n' -f $Case.Shell
                $Test = '- name: Test\r?\n\s+shell: {0}\r?\n\s+run: \./build\.ps1 -Tasks test\r?\n' -f $Case.Shell
                $Case.Text | Should -Match $Noop
                $Case.Text | Should -Match $Build
                $Case.Text | Should -Match $Test
            }
            $Matrix | Should -Match "matrix:\r?\n\s+os: \[ubuntu-latest, windows-latest, macos-latest\]"
            $Matrix | Should -Match 'name: \$\{\{ matrix\.os \}\}'
        }

        It 'lets package wait for both test jobs' {
            (Get-JobText -Text $script:WorkflowText -Job 'package') | Should -Match 'needs: \[build-and-test, windows-powershell\]'
        }

        It 'publishes only from a push to main or a v tag in PhilipHaglund/SendGridTools, in the PSGallery environment' {
            $PublishJob = Get-JobText -Text $script:WorkflowText -Job 'publish'
            $PublishJob | Should -Match "github\.repository == 'PhilipHaglund/SendGridTools'"
            $PublishJob | Should -Match "&& github\.event_name == 'push'"
            $PublishJob | Should -Match "&& \(github\.ref == 'refs/heads/main' \|\| startsWith\(github\.ref, 'refs/tags/v'\)\)"
            $PublishJob | Should -Match "(?m)^    environment: 'PSGallery'\s*$"
            $PublishJob | Should -Match '(?m)^    needs: package\s*$'
        }

        It 'runs the refusal step before the publish step and before GALLERYAPITOKEN is mentioned in the job' {
            $PublishJob = Get-JobText -Text $script:WorkflowText -Job 'publish'
            # The job's own comments name the secret before any step; only the steps count.
            $Steps = $PublishJob.Substring($PublishJob.IndexOf("`n    steps:"))
            $Refuse = $Steps.IndexOf('- name: Refuse a version the triggering ref does not call for')
            $Publish = $Steps.IndexOf('- name: Publish to the PowerShell Gallery')
            $Secret = $Steps.IndexOf('GALLERYAPITOKEN')
            $Refuse | Should -BeGreaterOrEqual 0
            $Publish | Should -BeGreaterOrEqual 0
            $Secret | Should -BeGreaterOrEqual 0
            $Refuse | Should -BeLessThan $Publish
            $Refuse | Should -BeLessThan $Secret
        }

        It 'gives GALLERYAPITOKEN to one step only, the publish step, through its env' {
            Get-GalleryTokenFinding -Text $script:WorkflowText | Should -BeNullOrEmpty
            # A text that is empty or has the step renamed would find nothing too, so the one
            # mapping line is looked for in the publish step as well.
            $Mapping = '(?m)^\s+[A-Za-z_][A-Za-z0-9_]*:\s*\$\{\{\s*secrets\.GALLERYAPITOKEN\s*\}\}\s*$'
            [regex]::Matches((Get-CodeLine -Text $script:WorkflowText) -join "`n", $Mapping).Count | Should -Be 1
            $PublishJob = Get-JobText -Text $script:WorkflowText -Job 'publish'
            $Start = $PublishJob.IndexOf('- name: Publish to the PowerShell Gallery')
            $Start | Should -BeGreaterOrEqual 0
            $Rest = $PublishJob.Substring($Start + 1)
            $Next = $Rest.IndexOf("`n      - name:")
            $Step = if ($Next -ge 0) { $Rest.Substring(0, $Next) } else { $Rest }
            [regex]::Matches((Get-CodeLine -Text $Step) -join "`n", $Mapping).Count | Should -Be 1
        }

        It 'fails a copy of the file where <Case>' -ForEach @(
            @{
                Case = 'the refusal step also maps the secret'
                Old  = '          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}'
                New  = "          GH_TOKEN: `${{ secrets.GITHUB_TOKEN }}`n          GALLERY_API_TOKEN: `${{ secrets.GALLERYAPITOKEN }}"
            }
            @{
                Case = 'the job package gets it at job level'
                Old  = "  package:`n"
                New  = "  package:`n    env:`n      GALLERY_API_TOKEN: `${{ secrets.GALLERYAPITOKEN }}`n"
            }
            @{
                Case = 'a step of build-and-test gets it through its own env'
                Old  = "      - name: Build`n        shell: pwsh`n        run: ./build.ps1 -Tasks build"
                New  = "      - name: Build`n        shell: pwsh`n        env:`n          GALLERY_API_TOKEN: `${{ secrets.GALLERYAPITOKEN }}`n        run: ./build.ps1 -Tasks build"
            }
            @{
                Case  = 'the publish step interpolates it in lower case'
                After = '- name: Publish to the PowerShell Gallery'
                Old   = "          `$ModuleName = 'SendGridTools'"
                New   = "          `$ModuleName = 'SendGridTools'`n          Write-Host '`${{ secrets.galleryapitoken }}'"
            }
            @{
                Case = 'a # line in a run block of build-and-test names it'
                Old  = "        run: ./build.ps1 -Tasks build"
                New  = "        run: |`n          # `${{ secrets.GALLERYAPITOKEN }}`n          ./build.ps1 -Tasks build"
            }
            @{
                Case = 'the mapping is removed'
                Old  = 'GALLERY_API_TOKEN: ${{ secrets.GALLERYAPITOKEN }}'
                New  = "GALLERY_API_TOKEN: ''"
            }
        ) {
            $Original = $script:WorkflowText
            $Eol = if ($Original.Contains("`r`n")) { "`r`n" } else { "`n" }
            $Old = $Old -replace "`n", $Eol
            $New = $New -replace "`n", $Eol
            $From = 0
            if ($After) { $From = $Original.IndexOf($After) }
            $From | Should -BeGreaterOrEqual 0
            $At = $Original.IndexOf($Old, $From, [System.StringComparison]::Ordinal)
            $At | Should -BeGreaterOrEqual 0 -Because 'the text to change must exist in the real file'
            $Changed = $Original.Substring(0, $At) + $New + $Original.Substring($At + $Old.Length)
            $Copy = Join-Path -Path $TestDrive -ChildPath 'build-and-test.copy.yml'
            [System.IO.File]::WriteAllText($Copy, $Changed)
            $ReadBack = [System.IO.File]::ReadAllText($Copy)
            $ReadBack | Should -Not -BeExactly $Original
            @(Get-GalleryTokenFinding -Text $ReadBack).Count | Should -BeGreaterThan 0
        }

        It 'holds PowerShell that parses in the refusal step' {
            $script:RefusalRun | Should -Not -BeNullOrEmpty -Because 'a renamed step would hand every check below an empty text'
            $Errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseInput($script:RefusalRun, [ref]$null, [ref]$Errors)
            @($Errors).Count | Should -Be 0 -Because (@($Errors | ForEach-Object { $_.Message }) -join '; ')
        }

        It 'records and uploads the artefact from the ubuntu-latest leg only, under output/SendGridTools/' {
            $Matrix = Get-JobText -Text $script:WorkflowText -Job 'build-and-test'
            $Matrix | Should -Match 'name: module-ubuntu-latest'
            $Matrix | Should -Match '(?m)^\s+output/SendGridTools/\s*$'
            $Matrix | Should -Match '(?m)^\s+output/publish-meta\.json\s*$'
            (Get-JobText -Text $script:WorkflowText -Job 'windows-powershell') | Should -Not -Match 'PublishArtefact'
        }
    }

    Context 'When the refusal step runs against a fake gh' {
        It 'finds the refusal step' {
            $script:RefusalRun | Should -Not -BeNullOrEmpty
        }

        It 'refuses a main build without a prerelease label' {
            $Run = Invoke-RefusalStep -Environment @{ GITHUB_REF = 'refs/heads/main'; PublishVersion = '0.4.8'; PublishPrerelease = '' }
            $Run.Thrown | Should -BeLike 'REFUSING TO PUBLISH.*'
            $Run.Thrown | Should -BeLike '*full release comes from a v<X.Y.Z> tag*'
            @($Run.Calls).Count | Should -Be 0
        }

        It 'lets a main build with a prerelease label through' {
            $Run = Invoke-RefusalStep -Environment @{ GITHUB_REF = 'refs/heads/main'; PublishVersion = '0.4.8-preview0001'; PublishPrerelease = 'preview0001' }
            $Run.Thrown | Should -BeNullOrEmpty
            @($Run.Calls).Count | Should -Be 0
        }

        It 'refuses a tag whose version differs from the build (<Version>)' -ForEach @(
            @{ Version = '0.4.9'; Prerelease = '' }
            @{ Version = '0.4.8-preview0001'; Prerelease = 'preview0001' }
        ) {
            $Run = Invoke-RefusalStep -Environment @{ GITHUB_REF = 'refs/tags/v0.4.8'; GITHUB_REF_NAME = 'v0.4.8'; PublishVersion = $Version; PublishPrerelease = $Prerelease }
            $Run.Thrown | Should -BeLike 'REFUSING TO PUBLISH.*'
            @($Run.Calls).Count | Should -Be 0
        }

        It 'lets a tag through when the build equals it and the commit is on main (<Status>)' -ForEach @(
            @{ Status = 'identical' }
        ) {
            $Run = Invoke-RefusalStep -Environment @{ GITHUB_REF = 'refs/tags/v0.4.8'; GITHUB_REF_NAME = 'v0.4.8'; PublishVersion = '0.4.8'; PublishPrerelease = '' } -GhStatus $Status
            $Run.Thrown | Should -BeNullOrEmpty
            @($Run.Calls).Count | Should -Be 1
            $Run.Calls[0] | Should -BeLike "gh api repos/owner/repository/compare/main...$($script:Sha) --jq .status"
        }

        It 'refuses a tag on an older main commit, since main has moved on (<Status>)' -ForEach @(
            @{ Status = 'behind' }
            @{ Status = 'Behind' }
        ) {
            $Run = Invoke-RefusalStep -Environment @{ GITHUB_REF = 'refs/tags/v0.4.8'; GITHUB_REF_NAME = 'v0.4.8'; PublishVersion = '0.4.8'; PublishPrerelease = '' } -GhStatus $Status
            $Run.Thrown | Should -BeLike 'REFUSING TO PUBLISH.*'
            $Run.Thrown | Should -BeLike "*'$Status'*"
            $Run.Thrown | Should -BeLike "*NOTHING has been published.*The tag v0.4.8 is still there.*"
            if ($Status -ceq 'behind') {
                $Run.Thrown | Should -BeLike "*main's tip*"
                $Run.Thrown | Should -BeLike "*main has moved on*"
            }
            @($Run.Calls).Count | Should -Be 1
            $Run.Calls[0] | Should -BeLike "gh api repos/owner/repository/compare/main...$($script:Sha) --jq .status"
        }

        It 'refuses a tag whose commit is not on main (<Status>)' -ForEach @(
            @{ Status = 'ahead' }
            @{ Status = 'diverged' }
        ) {
            $Run = Invoke-RefusalStep -Environment @{ GITHUB_REF = 'refs/tags/v0.4.8'; GITHUB_REF_NAME = 'v0.4.8'; PublishVersion = '0.4.8'; PublishPrerelease = '' } -GhStatus $Status
            $Run.Thrown | Should -BeLike 'REFUSING TO PUBLISH.*'
            $Run.Thrown | Should -BeLike "*'$Status'*"
        }

        It 'refuses a tag when GitHub cannot compare it' {
            $Run = Invoke-RefusalStep -Environment @{ GITHUB_REF = 'refs/tags/v0.4.8'; GITHUB_REF_NAME = 'v0.4.8'; PublishVersion = '0.4.8'; PublishPrerelease = '' } -GhStatus 'HTTP 404' -GhExit 1
            $Run.Thrown | Should -BeLike 'REFUSING TO PUBLISH.*gh api exited with 1*'
        }

        It 'refuses any other ref' {
            $Run = Invoke-RefusalStep -Environment @{ GITHUB_REF = 'refs/heads/chore/x'; GITHUB_REF_NAME = 'chore/x' }
            $Run.Thrown | Should -BeLike 'REFUSING TO PUBLISH.*'
            @($Run.Calls).Count | Should -Be 0
        }

        It 'refuses to run the step when gh does not resolve to its fake' {
            $global:ShadowToolHit = $null
            try {
                function global:Invoke-ShadowTool { $global:ShadowToolHit = $true }
                Set-Alias -Name 'gh' -Value Invoke-ShadowTool -Scope Global
                { Invoke-RefusalStep } | Should -Throw -ExpectedMessage '*gh*fake*'
                $global:ShadowToolHit | Should -BeNullOrEmpty
            } finally {
                Remove-Item -Path 'Alias:gh' -ErrorAction SilentlyContinue
                Remove-Item -Path 'Function:Invoke-ShadowTool' -ErrorAction SilentlyContinue
                Remove-Variable -Name ShadowToolHit -Scope Global -ErrorAction SilentlyContinue
            }
        }
    }
}
