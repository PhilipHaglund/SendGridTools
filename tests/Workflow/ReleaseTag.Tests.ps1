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

    Context 'When PSScriptAnalyzer reads it' {
        It 'reports nothing' {
            $Findings = @(Invoke-ScriptAnalyzer -Path $script:ScriptPath)
            $Findings.Count | Should -Be 0 -Because (($Findings | ForEach-Object { '{0}:{1} {2}' -f $_.RuleName, $_.Line, $_.Message }) -join '; ')
        }
    }
}
