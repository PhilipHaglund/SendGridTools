# SendGridTools: notes for coding agents

PowerShell module wrapping the SendGrid v3 Web API. Sessions start with `Connect-SendGrid`. The module has 61 exported functions in `source/Public`, helpers in `source/Private` and classes in `source/Classes`. Sampler and ModuleBuilder build it into `output/SendGridTools/<version>`.

## Build and test

Works in PowerShell 7 and Windows PowerShell 5.1.

```powershell
./build.ps1 -ResolveDependency -Tasks noop   # resolve build modules
./build.ps1 -Tasks build
./build.ps1 -Tasks test
```

- Dependencies resolve with PSResourceGet into `output/RequiredModules` at exact versions pinned in `RequiredModules.psd1`. Nothing is installed globally and PSGallery trust is left untouched when the PSResourceGet bootstrap succeeds; on a failed download Resolve-Dependency.ps1 falls back to the legacy PowerShellGet path, which can install the NuGet provider for the current user and trust PSGallery.
- Use the Pester in `output/RequiredModules` (Pester 5), never a globally installed Pester.
- Tests live in `tests/QA/module.tests.ps1`: changelog guard, module import, unit-test ratchet, PSScriptAnalyzer per function, comment-based help per exported function.
- `tests/QA/module.tests.ps1` also holds the version cap: the built version must be at least 0.4.8 and below 1.0.0.
- `tests/Workflow` tests the workflow scripts in `.github/scripts` and the steps of the workflow's publish path. They need PowerShell 7 and are skipped in Windows PowerShell 5.1.
- Changelog guard: on a branch, the root `CHANGELOG.md` must change since the merge base with `origin/main`. It is skipped with a reason on main.
- Unit-test ratchet: `tests/QA/UnitTestBaseline.txt` lists exported functions that have no `<Name>.Tests.ps1`. The list may only shrink. A new public function needs a test.
- Coverage: `CodeCoverageThreshold` in `build.yaml` equals the measured coverage, floored to a whole number (9 today: 9.47% in both pwsh and Windows PowerShell 5.1). It may only be raised, as tests arrive.
- PSScriptAnalyzer: fix findings in the code. Suppress only with `SuppressMessageAttribute` and a justification, and only when the repair would change the public surface or behaviour.
- Help: every exported function needs SYNOPSIS, a DESCRIPTION over 40 characters, an example, and every parameter described in more than 25 characters.

## Must not change

- Public surface: no function, parameter or output type is removed or renamed without a decision and a `CHANGELOG.md` line.
- No real e-mail addresses, domains, subuser names, API keys or key ids in code, tests, documents or logs. Use placeholders such as `<address>`.
- No calls to `api.sendgrid.com` from tests. HTTP is mocked. Do not read or print an API key, and do not open SecretStore.

## Version tokens

Only these commit-text tokens move the version, as GitVersion reads them from commit messages: `+semver: breaking|major`, `+semver: feature|minor`, `+semver: fix|patch`, `+semver: none|skip`, and a conventional-commit subject with `!` before the colon (a major step). Ordinary words ("add", "prefix", "fix" and so on) no longer do. Version tags and the branch configuration (`feature/` and `hotfix/` increments) still set the base and the default increment.

- GitVersion reads every reachable commit message, and a squash merge copies the PR title and text into main. So never quote a token or write a breaking-form subject in commit texts, PR titles or PR texts. Name it in words. File content is never read.
- `next-version: 0.4.8` in `GitVersion.yml` lifts the first preview above the already released 0.4.7. The version cap `[0.4.8, 1.0.0)` in `tests/QA/module.tests.ps1` fails the build if the version leaves that range.
- A minor bump has no cap, so the rule above is the control: a token that slips into a commit text bumps the version.

## Publishing

The workflow `.github/workflows/build-and-test.yml`, in its `publish` job, is the only supported publish path.

- A pull request must pass `ubuntu-latest`, `windows-latest`, `macos-latest`, `windows-powershell-5.1` and `package` (the repository owner makes them required). `publish` is skipped on a pull request.
- A merge to main publishes a preview `<next version>-previewNNNN` to the PowerShell Gallery (the first is `0.4.8-preview0001`). The publish job then creates the tag `v<version>` (hyphenated preview) and a GitHub prerelease. That tag is what moves the preview counter (GitVersion ContinuousDelivery).
- A stable version comes only from a `v<X.Y.Z>` tag on main's tip (a green main tip). A tag on an older main commit fails the changelog guard (`tests/QA/module.tests.ps1`, "Changelog has been updated") and publishes nothing. Only Philip approves it, with his explicit `RELEASE OK`. Only the bypass list of the `Stable Version` tag ruleset (repository admin role) can create, move or delete such a tag. The ruleset covers `refs/tags/v[0-9]*` and `refs/tags/[0-9]*`, except hyphenated tags. The workflow never creates, moves or deletes a stable tag. On a stable tag run the tag step creates that version's GitHub release (not a prerelease), which follows from Philip's tag.
- Never create a tag without `v` (`X.Y.Z`). It triggers nothing in the workflow, but GitVersion counts it as a base, and the release gate covers it like a `v` tag.
- The `publish` job runs only for a push to main or a `v` tag in `PhilipHaglund/SendGridTools`, in the environment `PSGallery`, with the secret `GALLERYAPITOKEN`. The repository owner sets the environment and the secret. Nothing in this repository reads or sets them.
- The step "Refuse a version the triggering ref does not call for" runs before the secret is used. It refuses a main build without a prerelease label, a tag build whose version is not exactly the tag's, a tag whose commit is not on main, and any other ref. Its tests are in `tests/Workflow/BuildAndTestWorkflow.Tests.ps1`.
- What is published is what was tested: `PublishArtefact.ps1 -Record` runs on the ubuntu leg, and `-Verify` runs in `package` and in `publish`. `package` rehearses into a temporary local repository and never publishes.
- `./build.ps1 -Tasks publish` is deliberately undefined. The Sampler and Sampler.GitHubTasks publish and tag tasks are no longer imported: `ModuleBuildTasks` in `build.yaml` lists only the four Sampler task files that build and test use (build, changelog, clean and Pester), so `Create_Release_Git_Tag`, `Push_Chocolatey_Package`, `Deploy_with_PSDeploy`, the gallery and GitHub release tasks and `package_module_nupkg` resolve as missing tasks. The comment in `build.yaml` names them all. Never add those task files back to `ModuleBuildTasks`, and never call any of them by name.
- If the tag step fails, repair it by hand. The refusal message from `.github/scripts/ReleaseTag.ps1` names the repair. A repair that touches a stable tag or a non-prerelease release needs Philip's explicit permission (release gate). A published version is permanent: the Gallery can unlist a version, not delete it.
- Never add `paths-ignore` to the workflow's triggers. A skipped run leaves the required checks pending.

## Release gate (verbatim, Swedish)

This block is binding and must stay verbatim. Do not translate, shorten or weaken it.

```text
Utan Philips uttryckliga tillstånd gör du aldrig, varken direkt eller indirekt:
- skapar, pushar, flyttar eller raderar en tagg vX.Y.Z utan prerelease-suffix;
- skapar en GitHub Release som inte är prerelease, eller gör om en prerelease till release;
- publicerar en version utan prerelease-suffix till PowerShell Gallery eller något annat register;
- ändrar GitVersion.yml, workflows, build.yaml, rulesets, tagskydd, bypass-listor, settings eller
  den här spärren i CLAUDE.md eller noterna, så att en merge eller ett jobb ger en stabil version
  eller så att spärren blir svagare;
- ber en kodare eller en annan session göra något av detta.
I SendGridTools gäller samma sak för en tagg X.Y.Z utan v och utan prerelease-suffix.
```
