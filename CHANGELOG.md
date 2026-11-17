# Changelog for SendGridTools

The format is based on and uses the types of changes according to [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- The build now resolves its dependencies locally into `output/RequiredModules` at pinned versions, and the quality tests run on Pester 5.
- The module is built and tested on Linux, Windows and macOS in PowerShell 7 and in Windows PowerShell 5.1, and published to the PowerShell Gallery from GitHub Actions: every merge to main publishes a preview, and a full release comes only from a version tag.
- The changelog now lists every released version.
- The README states the real requirements (Windows PowerShell 5.1 or PowerShell 7) and the install and build steps.
- `about_SendGridTools` now has real content.
- The transport (the internal session class and `Invoke-SendGrid`) now has unit tests with mocked HTTP; the code coverage threshold is raised from 0 to 9, and the tests check that the API key never appears in errors, verbose, debug or output.
- The build now imports only the four Sampler task files that build and test use, so the publish and tag tasks are no longer defined and the `pack` workflow alias is gone.
- A quality test now checks that the number of exported functions equals the number of files in `source/Public`.
- `New-SGSubuser` now has unit tests with mocked HTTP in both shells, and the exposure tests check that request body values never appear in verbose, debug, errors or output.
- `New-SGAuthenticatedDomain`, `New-SGBrandedDomainLink`, `New-SGCombinedDomain`, `Set-SGAuthenticatedDomain` and the alert, suppression and forward spam commands fixed below now have unit tests with mocked HTTP, and the code coverage threshold is raised from 9 to 21.

### Removed

- The Azure Pipelines definition is removed.

### Fixed

- The module now imports in a new Windows PowerShell 5.1 session. The four `InvokeQuery` methods of the internal session class named a type that 5.1 has not loaded when the module is parsed; a quality test now imports the built module in a new PowerShell 7 process and, on Windows, a new Windows PowerShell process.
- Help for `New-SGAuthenticatedDomain`, `New-SGBrandedDomainLink` and `New-SGCombinedDomain` no longer documents a `-Force` parameter they do not have, and help for `Get-SGBounce`, `Get-SGBlock`, `Get-SGGlobalSuppression`, `Get-SGInvalidEmail` and `Get-SGSpamReport` no longer states a 500-item limit.
- Help for `Connect-SendGrid` now gives the real session lifetime of one hour (it said 12 hours), and the first `New-SGBrandedDomainLink` example names the link it asks for.
- `New-SGSubuser` now works in Windows PowerShell 5.1; it turned the password into plain text with a parameter that 5.1 does not have.
- `New-SGSubuser` returns only the created subuser; it also wrote its internal request to the output.
- `New-SGAuthenticatedDomain`, `New-SGBrandedDomainLink` and `New-SGCombinedDomain` now send the subdomain given with `-SendGridSubdomain` and send none when none is given; the first two failed or sent an empty subdomain, and `New-SGCombinedDomain` dropped it.
- `Set-SGAuthenticatedDomain` now updates each domain it is given with `-UniqueId` or from the pipeline; it made no change before.
- `Remove-SGAlert`, `Remove-SGSuppressionGroup`, `Set-SGSuppressionGroup` and `Remove-SGGlobalSuppression` now act on each id or address given, also from the pipeline, and `Set-SGSuppressionGroup` sends only the values given.
- An expired session now raises an error that names `Connect-SendGrid -Force`; it returned a text as if it were data.
- `New-SGSubuser` now sends the values of each piped object.

### Security

- Verbose output names the keys and value types of a request body but no longer its values, so a subuser password no longer shows with `-Verbose`.
- `New-SGSubuser` no longer writes its internal request, with the password in plain text, to the output.
- `Set-SGForwardSpamSetting` no longer writes its request, with the forwarding addresses, to the output.

## [0.4.7] - 2025-11-08

### Changed

- Published to the PowerShell Gallery without a version tag, from commit `33c9a1f`. Its release notes on the Gallery are those of 0.4.6.

### Fixed

- `New-SGCombinedDomain` now passes `-OnBehalfOf` on when it creates the branded link.
- `Send-SGMailMessage` reads attachment content from the attachment stream instead of a file path, so attachments built from streams are sent.
- The module manifest carries the `PSEdition_Desktop` tag, so the module is found as Windows PowerShell compatible on the Gallery.

## [0.4.6] - 2024-08-15

### Changed

- Made it Windows PowerShell 5.1 compatible by using ArgumentCompleter instead of using " : System.Management.Automation.IValidateSetValuesGenerator"
- `New-SGApiKey`: the `-Scopes` parameter was renamed `-Scope` (no alias), with tab completion of valid scopes.
- `Connect-SendGrid` no longer passes `-Title` to the credential prompt.

## [0.4.5] - 2024-08-15

### Fixed

- `Remove-SGBlock`, `Remove-SGBounce`, `Remove-SGInvalidEmail` and `Remove-SGSpamReport` now use the e-mail address of a piped object.
- `-OnBehalfOf` now also works with piped input on the `Remove-` commands for blocks, bounces, global suppressions, invalid e-mails and spam reports.
- `Get-SGAlert` no longer limits `-OnBehalfOf` to one parameter set.
- `Get-SGEmailActivity` no longer writes the bound parameters to the output.

## [0.4.4] - 2024-08-12

### Fixed

- Results from the API that use a `results` property are now handled.
- The `lastat` time stamp is converted to a date.

## [0.4.3] - 2024-08-12

### Added

- Eight commands now take piped objects through a new `-InputObject` parameter: `Confirm-SGBrandedDomainLink`, `Remove-SGApiKey`, `Remove-SGBounce`, `Remove-SGBrandedDomainLink`, `Remove-SGSuppressionGroup`, `Set-SGApiKey`, `Set-SGBrandedDomainLink` and `Set-SGSuppressionGroup`.

### Fixed

- `Confirm-SGBrandedDomainLink` and `Remove-SGBrandedDomainLink` take several ids, and `Get-SGBrandedDomainLink` now finds a link by `-DomainName`.
- `New-SGCombinedDomain` accepts a custom DKIM selector of one to three characters.

## [0.4.2] - 2024-08-12

### Changed

- Module manifest: added the project, license and icon links and release notes. No change to commands.

## [0.4.1] - 2024-08-12

### Added

- 44 new commands, bringing the module to 61: alerts, blocks, bounces, invalid e-mails, spam reports, global suppressions, suppression groups, subusers, teammates, IP addresses, mail settings (address allow list, bounce purge, forward bounce, forward spam), designs, e-mail activity, `Set-SGAuthenticatedDomain`, `Set-SGBrandedDomainLink`, `New-SGCombinedDomain` and `Invoke-SGCommand`.
- `-ShowDNS` on `Get-SGAuthenticatedDomain` and `Get-SGBrandedDomainLink`; `-Default` on `New-SGAuthenticatedDomain` and `New-SGBrandedDomainLink`; `-IPAddress` on `New-SGAuthenticatedDomain`; `-InputObject` on `Confirm-SGAuthenticatedDomain` and `Remove-SGAuthenticatedDomain`.

### Changed

- `Remove-SGBrandedDomainLink` is now exported. 0.3.0 listed it as `Remove-SMSGBrandedDomainLink`, which could not be run.
- Breaking for 0.3.0 scripts: `New-SGAuthenticatedDomain -Subdomain` is now `-SendGridSubdomain` and `New-SGBrandedDomainLink -Subdomain` is now `-SendGridSubDomain` (no alias on either). `New-SGAuthenticatedDomain -SubUser` is now `-Username`; the alias `SubUser` is kept.
- Breaking for 0.3.0 scripts: `Remove-SGApiKey -ApiKeyId` and `Set-SGApiKey -ApiKeyID` are now `-UniqueId`, with the alias `Id` only, so the old name no longer works.
- `Get-SGAuthenticatedDomain -UniqueId` is now `-Id`; the alias `UniqueId` is kept.

### Removed

- Breaking for 0.3.0 scripts: `-Force` is removed from `New-SGAuthenticatedDomain` and `New-SGBrandedDomainLink`.

## [0.3.0] - 2024-01-25

### Added

- First release: connect to SendGrid, manage API keys, authenticated domains and branded links, and send mail with `Send-SGMailMessage`.

[Unreleased]: https://github.com/PhilipHaglund/SendGridTools/compare/33c9a1ff5221e3612aa8357f7ecedfccfd5cc59f...HEAD
[0.4.7]: https://github.com/PhilipHaglund/SendGridTools/commit/33c9a1ff5221e3612aa8357f7ecedfccfd5cc59f
[0.4.6]: https://github.com/PhilipHaglund/SendGridTools/compare/0.4.5...0.4.6
[0.4.5]: https://github.com/PhilipHaglund/SendGridTools/compare/0.4.4...0.4.5
[0.4.4]: https://github.com/PhilipHaglund/SendGridTools/compare/0.4.3...0.4.4
[0.4.3]: https://github.com/PhilipHaglund/SendGridTools/compare/0.4.2...0.4.3
[0.4.2]: https://github.com/PhilipHaglund/SendGridTools/compare/0.4.1...0.4.2
[0.4.1]: https://github.com/PhilipHaglund/SendGridTools/compare/v0.3.0...0.4.1
[0.3.0]: https://github.com/PhilipHaglund/SendGridTools/tree/v0.3.0
