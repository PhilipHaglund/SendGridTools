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

### Removed

- The Azure Pipelines definition is removed.

### Fixed

- Help no longer documents a `-Force` parameter on the domain commands, nor a 500-item limit that the commands do not enforce.

## [0.4.7] - 2025-11-08

### Changed

- Published to the PowerShell Gallery without a version tag, from commit `33c9a1f`. Its release notes on the Gallery are those of 0.4.6.

### Fixed

- `New-SGCombinedDomain` now passes `-OnBehalfOf` on when it creates the branded link.
- `Send-SGMailMessage` reads attachment content from the attachment stream instead of a file path, so attachments built from streams are sent.
- Module manifest: corrected the version and added the `PSEdition_Desktop` tag.

## [0.4.6] - 2024-08-15

### Changed

- Made it Windows PowerShell 5.1 compatible by using ArgumentCompleter instead of using " : System.Management.Automation.IValidateSetValuesGenerator"
- `New-SGApiKey`: the `-Scopes` parameter is now `-Scope`, with tab completion of valid scopes.
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

### Fixed

- The `-InputObject` parameter was missing on eight commands and is restored: `Confirm-SGBrandedDomainLink`, `Remove-SGApiKey`, `Remove-SGBounce`, `Remove-SGBrandedDomainLink`, `Remove-SGSuppressionGroup`, `Set-SGApiKey`, `Set-SGBrandedDomainLink` and `Set-SGSuppressionGroup`.
- `Confirm-SGBrandedDomainLink`, `Get-SGBrandedDomainLink` and `Remove-SGBrandedDomainLink` take several ids, and `Get-SGBrandedDomainLink` finds a link by `-DomainName`.
- `New-SGCombinedDomain` accepts a custom DKIM selector of one to three characters.

## [0.4.2] - 2024-08-12

### Changed

- Module manifest: added the project, license and icon links and release notes. No change to commands.

## [0.4.1] - 2024-08-12

### Added

- 44 new commands, bringing the module to 61: alerts, blocks, bounces, invalid e-mails, spam reports, global suppressions, suppression groups, subusers, teammates, IP addresses, mail settings (address allow list, bounce purge, forward bounce, forward spam), designs, e-mail activity, `Set-SGAuthenticatedDomain`, `Set-SGBrandedDomainLink`, `New-SGCombinedDomain` and `Invoke-SGCommand`.

### Changed

- `Remove-SMSGBrandedDomainLink` is renamed `Remove-SGBrandedDomainLink`.

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
