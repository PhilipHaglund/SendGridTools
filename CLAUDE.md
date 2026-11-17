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
- Changelog guard: on a branch, the root `CHANGELOG.md` must change since the merge base with `origin/main`. It is skipped with a reason on main.
- Unit-test ratchet: `tests/QA/UnitTestBaseline.txt` lists exported functions that have no `<Name>.Tests.ps1`. The list may only shrink. A new public function needs a test.
- Coverage: `CodeCoverageThreshold` in `build.yaml` equals the measured coverage (0 today, no unit tests yet). It may only be raised, as tests arrive.
- PSScriptAnalyzer: fix findings in the code. Suppress only with `SuppressMessageAttribute` and a justification, and only when the repair would change the public surface or behaviour.
- Help: every exported function needs SYNOPSIS, a DESCRIPTION over 40 characters, an example, and every parameter described in more than 25 characters.

## Must not change

- Public surface: no function, parameter or output type is removed or renamed without a decision and a `CHANGELOG.md` line.
- No real e-mail addresses, domains, subuser names, API keys or key ids in code, tests, documents or logs. Use placeholders such as `<address>`.
- No calls to `api.sendgrid.com` from tests. HTTP is mocked. Do not read or print an API key, and do not open SecretStore.

## Version tokens

The patterns in `GitVersion.yml` as they stand on main bump the version from commit texts. They match "breaking", "major", "add", "adds", "feature", "features", "minor", "fix" and "patch". "fix" and "patch" have no word boundary at all, so words that contain them ("prefix", "suffix") match; the other patterns have no leading boundary, so words that end in them match too. No such word may appear in commit texts, PR titles or PR texts until step 2 has replaced the patterns. Also keep "!" out of PR titles.

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
