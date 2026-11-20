# Changelog for SendGridTools

The format is based on and uses the types of changes according to [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `New-SGAuthenticatedDomain`, `New-SGBrandedDomainLink` and `New-SGApiKey` have a `-Force` switch. With `-Force` the question before `-Default` replaces the current default, or before a key with full access is created, is not asked, so a script without a console can do it. `-Force` does not change `-WhatIf` or `-Confirm`. Without `-Force` the commands ask as before.
- `Send-SGMailMessage` has a `-SandboxMode` switch. With it the message is sent to SendGrid in sandbox mode: SendGrid validates the request and answers without delivering the message. With `-SandboxMode` the target that `-WhatIf` and `-Confirm` name ends with ` in sandbox mode`. Without `-SandboxMode` the request and the target are unchanged.

### Fixed

- `Get-SGBlock`, `Get-SGBounce`, `Get-SGGlobalSuppression`, `Get-SGInvalidEmail` and `Get-SGSpamReport` with `-EmailAddress` now encode the address in the query, so an address with `+`, `#` or `&` asks for that address. Before, the address was sent as given: SendGrid read `+` as a space, and `#` or `&` cut or split the query. Without `-EmailAddress` the query is unchanged.
- `Disable-SGSubuser`, `Enable-SGSubuser`, `Remove-SGSubuser` and `Get-SGTeammate -Username` encode the username in the request path; a name without special characters gives the same path as before. `Get-SGTeammate -Username` now sends its request; before, it called the module's request function without its parameters, so in a console PowerShell asked for those parameters, and otherwise the command failed; no request for the username was sent. `Remove-SGSubuser` names the username in its question and in `-WhatIf`; before, the target was the word `Subuser`. The help for `-Username` in the three subuser commands says the username of the Subuser with the right verb; before, it said the ID (and "to enable" in `Disable-SGSubuser`).
- `Remove-SGBlock`, `Remove-SGBounce`, `Remove-SGInvalidEmail` and `Remove-SGSpamReport` stop with "InputObject has no Email property; pass an email address or an object with an Email property." for an object in the pipeline without a non-empty `Email`, and send nothing for it. Before, an object without `Email` sent a removal to the list's path without an address, and an object with an empty `Email` failed with a conversion error. Any other input that is not a text or such an object now gives "Failed to convert InputObject to an email address." instead of "Failed to convert InputObject to Id.". A text and an object with `Email` work as before.
- `Get-SGDesign` sends `-PageSize` as a plain number, encodes `-PageToken`, and sends `summary=true` for `-Summary` and `summary=false` for `-Summary:$false`. Before, `-PageSize` was sent with an extra `)`, which SendGrid refused, the token was sent as given, `-Summary` was sent as `True`, and `-Summary:$false` sent nothing, so all fields were never asked for. Without `-Summary` no value is sent, as before.
- `New-SGApiKey -FullAccessKey` honours `-WhatIf` and `-Confirm`: with `-WhatIf` it writes one line for the key, asks nothing and creates nothing; with `-Confirm` it asks for the key and then the question about full access. Before, the question about full access was asked also under `-WhatIf`, and `-Confirm` gave no question of its own. Without these switches it asks once, as before.
- `Get-SGEmailActivity` no longer calls SendGrid when PowerShell binds `-Value` for `-Property ApiKeyId`, `ApiKeyName`, `AsmGroupId`, `AsmGroupName` and `Teammate`, also in `Get-Command`, `Get-Help` and Tab. `-Value` is an ordinary list of texts and Tab completes the account's values. Names are turned into ids when the command runs, so two names give both ids, and an unknown name stops with "No API key named '`<name>`'." or "No unsubscribe group named '`<name>`'.". Before, a value outside the account's list failed at binding, binding failed without a connection, and two names gave no id, so an empty value was sent.
- `Get-SGEmailActivity -Property TemplateName` stops with "SendGrid cannot filter email activity by template name; use -Property TemplateId." and sends nothing. Before, a query without a field name was sent.
- `Get-SGSubuser -Username` now looks the username up with SendGrid's documented `username` filter on the list of Subusers and encodes it, so a name with `+`, `/`, `#`, `?`, `&` or a space asks for that name. Only a Subuser whose username equals the value, without regard to case, is given out; measured live, SendGrid's filter also returned a Subuser whose username only starts with the value. A name that does not exist gives no output and no error. Before, the name was put in the request path as given, a path that SendGrid does not document for reading (it answered for an existing name); a `#` dropped the rest of the name and `-Limit` and `-Offset`, and a name that does not exist stopped with "Subuser not found". The help for `-Username` in `Get-SGSubuser` and `New-SGSubuser` says the username; before, it said the ID. Without `-Username` the request is unchanged.
- `Send-SGMailMessage` now sends `-BatchId` as `batch_id` and `-Unsubscribe` as `asm` (`group_id`, and `groups_to_display` when it has groups), and stops with "Unsubscribe needs a GroupId greater than 0." before any request for a `GroupId` of 0 or less. Before, both parameters were accepted and left out of the request without an error. Without them the request is unchanged.
- `Send-SGMailMessage -Categories` takes 1 to 10 names of 1 to 255 characters each; an empty list is refused at binding. Before, each name could be at most 10 characters, the number of names was not limited, so SendGrid refused more than 10 names, and an empty list was accepted and left out of the request.
- `Get-SGSubuser` refuses an empty `-Username` at binding, also from the pipeline, and sends no request for it; `-Limit` takes 1 or more and `-Offset` 0 or more, and `-Offset 0` is sent. With `-Username`, `-Limit` and `-Offset` are not sent, and one warning per run says that they apply only without `-Username`. Before, an empty `-Username` was skipped without an error, so every Subuser was given out, also to a command further on in the pipeline; `-Limit 0` and `-Offset 0` were skipped, a negative value was sent as given, and `-Limit` and `-Offset` were sent with `-Username`, so SendGrid's longer names that start with the value could hide the equal name. Without these parameters the request is unchanged.
- `Get-SGSubuser -Username` names the username in `-WhatIf` and `-Confirm` as `Subuser '<name>'`, and the help says that the list includes disabled Subusers. Before, the target was `Subusers` also with `-Username`, and the help said that disabled Subusers are not listed. Without `-Username` the target is `Subusers`, as before.

## [0.5.2] - 2026-11-19

### Fixed

- `New-SGBrandedDomainLink -Default:$false` no longer asks for a default link and does not set one; before, the switch counted when it was given at all, also with `$false`. The question now goes through the same helper as in `New-SGAuthenticatedDomain`. With the switch set, or without it, the request is as before.
- `New-SGAuthenticatedDomain` no longer calls SendGrid when PowerShell binds its parameters. `-IPAddress` is an ordinary parameter with the same name and type; Tab completes the addresses of the account, and SendGrid decides whether an address belongs to the account. Before, a value outside the account's list failed at binding. `Get-Command -Syntax`, `Get-Help` and `New-SGCombinedDomain` no longer need a session for it. A third positional argument still binds to `-Username`.
- `Confirm-SGAuthenticatedDomain`, `Confirm-SGBrandedDomainLink`, `Remove-SGApiKey`, `Remove-SGAuthenticatedDomain`, `Remove-SGBrandedDomainLink`, `Set-SGApiKey`, `Set-SGAuthenticatedDomain` and `Set-SGBrandedDomainLink` accept an id as a 64-bit integer from the pipeline, as `Get-SGAuthenticatedDomain` gives it in PowerShell 7. Before, the command failed with "Failed to convert InputObject to Id.". Other ids work as before.
- `New-SGAuthenticatedDomain`, `New-SGBrandedDomainLink`, `Confirm-SGAuthenticatedDomain`, `Confirm-SGBrandedDomainLink`, `Remove-SGAuthenticatedDomain` and `Remove-SGBrandedDomainLink` write their own informational notes (which subdomain is used, that a domain is already validated, and the reminder to remove DNS records) only with `-Verbose` or when `$VerbosePreference` asks for it. Before, these notes were shown without it.
- A failed request is passed on inside the module as the error record it was raised with, instead of as a new error that held only the message text. The record keeps where the error was raised and, for an error raised while the answer is read (for example an error body that is not JSON), its type and inner exception. An HTTP error is still turned into a text by the session, as before, and the error message a command shows is the same.
- An answer with several entries in `errors` now raises one error whose text is their `message` texts in order, separated by `; `; an entry without a message is left out. Before, the texts were joined with a space. With one entry the text is as before.
- `Add-SGGlobalSuppression`, `Remove-SGBlock`, `Remove-SGBounce`, `Remove-SGInvalidEmail` and `Remove-SGSpamReport` show the reason in their error message when a request fails. Before, the message repeated the email address where the reason should be.
- `Get-SGEmailActivity -Verbose` no longer writes the filter values or the date values in its filter notes. They name the property, the operator and the logical operator of each condition. The two notes about the request itself ("Starting process" and "Successfully invoked") name the request path without its query, for every command, so they no longer hold the filter values either. The query that is sent is unchanged, and `-WhatIf` shows the request with its query as before.
- `Connect-SendGrid` writes "Connection to SendGrid established." and its two refresh notes, and a request with an empty answer writes "Successfully invoked", only with `-Verbose` or when `$VerbosePreference` asks for it. Before, these lines were shown without it. The texts are unchanged.
- A command called with `-Confirm`, or with `$ConfirmPreference` set to `Low` or `Medium`, is no longer asked again by the request it sends or for each property name of the answer. Before, the request asked a second time and every property name of the answer was a question of its own.
- `Set-SGApiKey -Verbose` names the key in "Updating key"; before, the name was empty.
- `Remove-SGGlobalSuppression` encodes the email address in the request path, so an address with `+`, `#`, `?` or `/` removes that address. Before, such a character could change what was requested. `-WhatIf` and the error message show the address as given.
- A request with an empty answer writes "Successfully invoked" once with `-Verbose`. Before, it was written once for every empty object in the answer and once more at the end.
- A time that SendGrid sends as Unix seconds is a `DateTime` in both PowerShell 7 and Windows PowerShell 5.1. It holds for a whole number in a property whose name contains `valid`, `created`, `updated` or `lastat`, and now also for a name that ends in `_at`, such as `assigned_at` (`AssignedAt` from `Get-SGIPAddress`). Before, Windows PowerShell 5.1 returned every such value as a number, and PowerShell 7 returned a value whose name only ends in `_at` as a number. A list of such numbers is a list of dates in the same order; before, PowerShell 7 returned only the first one, as a single date. A Boolean, a decimal number, a text and an empty value are as before.
- `Get-SGEmailActivity -Property TemplateId` and `-Property TemplateName` no longer fail when PowerShell binds their parameters. `-Value` is an ordinary list of texts for them, and SendGrid decides whether the value exists. Before, binding called a command that the module does not have. The filter for `TemplateName` still has no field name.
- `Get-SGEmailActivity -Filter` with `-Between` sends the same dates under every culture. Before, a culture that writes the day before the month, such as en-GB or tr-TR, swapped day and month or failed. Under en-US the query is unchanged.
- A `date` field in an answer is read the same under every culture, for every command. Before, a culture with another calendar, such as th-TH, gave another year. Under en-US the dates are unchanged.
- Property names in the output are the same under every culture, for every command. Before, the Turkish culture gave `id`, `ip` and `is_enabled` a dotted capital I and no value. Under en-US the names are unchanged.
- The build's dependency resolution (`Resolve-Dependency.ps1`) stops with an error that names `Microsoft.PowerShell.PSResourceGet` and the cause when PSResourceGet cannot be downloaded, unpacked or imported. Before, a failed download wrote a warning and went on with the legacy PowerShellGet path, which could install the NuGet package provider for the current user and mark `PSGallery` as trusted for the run, and a failed unpack or import wrote errors and went on as if PSResourceGet were in place. When the PSResourceGet bootstrap succeeds the resolution is as before.
- `Confirm-SGAuthenticatedDomain`, `Confirm-SGBrandedDomainLink`, `Remove-SGApiKey`, `Remove-SGAuthenticatedDomain`, `Remove-SGBrandedDomainLink`, `Set-SGApiKey` and `Set-SGAuthenticatedDomainToSubUser` ask once with `-Confirm`, for the object they change. Before, the read of that object through `Get-SGApiKey`, `Get-SGAuthenticatedDomain` or `Get-SGBrandedDomainLink` asked as well. With `-WhatIf` they read the object and write one line for it; before, the read was skipped and wrote a line of its own, so the command's line lacked the name, for example in `Remove-SGApiKey`. `Confirm-SGAuthenticatedDomain`, `Confirm-SGBrandedDomainLink`, `Remove-SGAuthenticatedDomain` and `Remove-SGBrandedDomainLink` also return the object they read under `-WhatIf`, as they do without it. The three `Get-SG*` commands are unchanged.
- `Remove-SGBlock`, `Remove-SGBounce`, `Remove-SGInvalidEmail` and `Remove-SGSpamReport` encode the email address in the request path, as `Remove-SGGlobalSuppression` does, so an address with `+`, `#`, `?` or `/` removes that address. Before, such a character could change what was requested. `-WhatIf` and the error message show the address as given. `Remove-SGBlock` says block in its `-WhatIf` and `-Confirm` text and in its error messages; before, it said bounce.
- A time value becomes a `DateTime` only when it is a whole number within the 32-bit range, and a list of them a list of dates only when every element is; any other value is returned as SendGrid sends it. Before, a whole number outside that range under a name that contains `valid`, `created`, `updated` or `lastat` made the command fail. `Get-SGIPAddress -IncludeRegion` returns `AddedAt` and `UpdatedAt` as dates by the same rule, as `Get-SGIPAddress` does without the switch; before, they were Unix seconds.

## [0.5.1] - 2026-11-19

### Fixed

- A property whose value is an empty list is kept in the output, with the empty list as its value, instead of being dropped; for example `Get-SGIPAddress` now returns `Pools` for an IP address in no pool. A response whose only properties are empty lists now returns an object instead of the verbose line "Successfully invoked". An empty `errors` list still raises no error.
- `Connect-SendGrid -Credential` or `-ApiKey` on an existing session on the same host now uses the given key: it replaces the session's key, is verified against SendGrid and starts the one-hour lifetime again, and the host and region are kept. Before, the given key was ignored and the old key was refreshed. If the new key fails, no session is left. Without a given key a refresh is as before.
- `New-SGAuthenticatedDomain -DisableAutomaticSecurity:$false` and `-Default:$false` behave as if the switch were not given: SendGrid manages security and no default domain is asked for or set. Before, the switch counted when it was given at all, also with `$false`. With the switch set, or without it, the request is as before.
- `New-SGCombinedDomain -CustomDkimSelector` accepts exactly three letters or digits, as `New-SGAuthenticatedDomain` does. A shorter selector fails before any request; before, the authenticated domain failed while the branded link was still created.
- `Set-SGAddressWhitelistSetting`, `Set-SGBouncePurgeSetting`, `Set-SGForwardBounceSetting` and `Set-SGForwardSpamSetting` accept `-WhatIf` and `-Confirm`. They do not ask by default, and without the switches the request and output are as before.
- `Set-SGApiKey -Scopes` accepts a scope again (it failed at binding in both PowerShell 7 and Windows PowerShell 5.1), and `Get-Command -Syntax Set-SGApiKey` no longer fails in PowerShell 7. The scope names complete with Tab, as in `New-SGApiKey`, and SendGrid decides whether a scope is valid.
- The build's dependency resolution (`Resolve-Dependency.ps1`) now saves each build module through a function that tries `Save-PSResource` up to three times. Between attempts it writes a warning with the module name, the error type and the attempt number, and waits 5 seconds. After the third failure it fails with the last error, unchanged. A save that succeeds on the first attempt behaves as before. Before, one sporadic error from PSResourceGet during the save failed the whole job, and a re-run passed.

### Security

- Every request to SendGrid no longer follows an HTTP redirect, so the API key is never sent to the host a redirect points at. In PowerShell 7 every 3xx answer, and in Windows PowerShell 5.1 a 301 or 302 answer, raises an error that names only that host (`SendGrid answered with a redirect to <host>; the request was refused so that the API key is not sent there.`). In Windows PowerShell 5.1 another 3xx answer (300, 303, 304, 305, 307 or 308) is not followed either, but comes back as an empty answer instead of an error, because that version reports no status code. Without a redirect, requests, responses and error messages are as before.
- The publish job's step "Refuse a version the triggering ref does not call for" now refuses a stable tag on an older main commit (GitHub compares the commit to main as `behind`). A tag run publishes only when the tag points at main's tip. The run fails with `REFUSING TO PUBLISH.` before the Gallery key is used, and the tag is left where it is. Before, the step let such a tag through, and only the changelog guard stopped the run.

## [0.5.0] - 2026-11-18

### Added

- `Connect-SendGrid -Region Global|EU` connects to SendGrid's EU host `api.eu.sendgrid.com` (issue #3), and `-BaseUri` to a given https base URI with `/v3` added when missing; a new session without them uses the global host, as before, and an existing session is refreshed on its own host. `-Region` or `-BaseUri` naming another host than the current session starts a new session (it asks for the key when `-Credential` is not given); if that connection fails, no session is left.
- `Get-SGSubuser -IncludeRegion` adds the region of each subuser as `Region`, and `-Region All|Global|EU` returns only the subusers in that region (issue #4). Both apply to the list only; with `-Username` they send nothing extra and warn, because SendGrid does not report the region of a single subuser. `Get-SGIPAddress -IncludeRegion` reads the IP Address Management API (`/v3/send_ips/ips`), which has other properties than `/v3/ips`, among them `Region`, and reads every page of it. Without the new parameters both commands send the same request and return the same output as before.
- `Get-SGEnforcedTls` reads the Enforced TLS settings of the account, or of a subuser with `-OnBehalfOf`, as `RequireTls`, `RequireValidCert` and `Version`, and `Set-SGEnforcedTls` changes them and sends only the settings given (issue #4). `Set-SGEnforcedTls` asks for confirmation, because the setting applies to all mail from the account: with `-RequireTls`, a recipient that does not support TLS does not get the mail.
- `Connect-SendGrid -ApiKey` takes the API key as a secure string, so a key from a vault or an environment variable needs no `PSCredential` (issue #4); it cannot be combined with `-Credential`. In a host that cannot prompt (a console host started with `-NonInteractive`, a Windows service, a scheduled task without a signed-in user, or a runspace without a user interface), `Connect-SendGrid` without `-Credential` or `-ApiKey` fails with an error that names both instead of asking for the key, and leaves an existing session as it was. An interactive host asks for the key as before. `-NonInteractive` counts only in the console host: a host with its own user interface (for example Visual Studio Code) asks for the key as before, and a remote session leaves the prompt to the client. On Linux and macOS only `-NonInteractive` is recognised (there .NET reports every process as user interactive), so start a cron or systemd job with `pwsh -NonInteractive` or pass `-ApiKey`.

### Fixed

- `Get-SGAuthenticatedDomain` and `Get-SGApiKey` return every authenticated domain and API key: they read the list page by page instead of taking only what one request returned, and `-DomainName` offers every domain. With no authenticated domains, `Get-SGAuthenticatedDomain` returns nothing instead of failing. The API key choices in `Get-SGEmailActivity` now include every key too.
- `Invoke-SGCommand` accepts a full URL on the session's host, global or EU, and refuses a URL to another host so the API key is never sent there; before, it recognised only the global host and removed `/v3/` anywhere in the path.

## [0.4.8] - 2026-11-18

### Fixed

- The module imports in a new Windows PowerShell 5.1 session; the internal session class named a type that 5.1 had not loaded when the module is parsed. `New-SGSubuser` now also works in 5.1; it used a parameter that 5.1 does not have.
- `New-SGAuthenticatedDomain` sends the addresses given with `-IPAddress` (it sent an empty value) and asks for a custom SPF only when `-CustomSPF` is set, and `New-SGCombinedDomain` no longer asks for one when only `-DisableAutomaticSecurity` is given.
- `New-SGAuthenticatedDomain`, `New-SGBrandedDomainLink` and `New-SGCombinedDomain` send the subdomain given with `-SendGridSubdomain` and none when none is given; before, they failed, sent an empty subdomain or dropped it.
- `Set-SGAuthenticatedDomain`, `Remove-SGAlert`, `Remove-SGSuppressionGroup`, `Set-SGSuppressionGroup`, `Remove-SGGlobalSuppression` and `New-SGSubuser` act on each id, address or object given, also from the pipeline. `Set-SGAuthenticatedDomain` made no change before, and `Set-SGSuppressionGroup` sends only the values given.
- An expired session raises an error that names `Connect-SendGrid -Force`; it returned a text as if it were data.
- Help: `Connect-SendGrid` gives the real session lifetime of one hour (it said 12 hours); `New-SGAuthenticatedDomain`, `New-SGBrandedDomainLink` and `New-SGCombinedDomain` no longer document a `-Force` parameter they do not have; `Get-SGBounce`, `Get-SGBlock`, `Get-SGGlobalSuppression`, `Get-SGInvalidEmail` and `Get-SGSpamReport` no longer state a 500-item limit; the first `New-SGBrandedDomainLink` example names the link it asks for.

### Security

- Verbose output names the keys and value types of a request body but not its values, so a subuser password no longer shows with `-Verbose`.
- `New-SGSubuser` returns only the created subuser and no longer writes its internal request, with the password in plain text, to the output. `Set-SGForwardSpamSetting` no longer writes its request, with the forwarding addresses, to the output.

### Changed

- The module is built and tested on Linux, Windows and macOS in PowerShell 7 and in Windows PowerShell 5.1, and published to the PowerShell Gallery from GitHub Actions: every merge to main publishes a preview, and a full release comes only from a version tag.
- The build resolves its dependencies locally into `output/RequiredModules` at pinned versions, runs the tests on Pester 5, and imports only the four Sampler task files that build and test use, so the publish and tag tasks and the `pack` workflow alias are gone.
- The build accepts a version tag on the tip of main: the changelog check now looks at the commit, not at the branch name, which on a tag run is named after the tag. A version tag on an older main commit still fails the check.
- Unit tests with mocked HTTP cover the transport and the commands whose requests or output are fixed above, in both shells, and check that the API key and request body values never appear in output, errors, verbose or debug. Quality tests import the built module in a new PowerShell 7 process and, on Windows, a new Windows PowerShell process, and check that the exported functions match the files in `source/Public`. The code coverage threshold is raised from 0 to 21.
- The README states the real requirements (Windows PowerShell 5.1 or PowerShell 7) and the install and build steps, `about_SendGridTools` has real content, and the changelog lists every released version.

### Removed

- The Azure Pipelines definition is removed.

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

[Unreleased]: https://github.com/PhilipHaglund/SendGridTools/compare/v0.5.2...HEAD
[0.5.2]: https://github.com/PhilipHaglund/SendGridTools/compare/v0.5.1...v0.5.2
[0.5.1]: https://github.com/PhilipHaglund/SendGridTools/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/PhilipHaglund/SendGridTools/compare/v0.4.8...v0.5.0
[0.4.8]: https://github.com/PhilipHaglund/SendGridTools/compare/33c9a1ff5221e3612aa8357f7ecedfccfd5cc59f...v0.4.8
[0.4.7]: https://github.com/PhilipHaglund/SendGridTools/commit/33c9a1ff5221e3612aa8357f7ecedfccfd5cc59f
[0.4.6]: https://github.com/PhilipHaglund/SendGridTools/compare/0.4.5...0.4.6
[0.4.5]: https://github.com/PhilipHaglund/SendGridTools/compare/0.4.4...0.4.5
[0.4.4]: https://github.com/PhilipHaglund/SendGridTools/compare/0.4.3...0.4.4
[0.4.3]: https://github.com/PhilipHaglund/SendGridTools/compare/0.4.2...0.4.3
[0.4.2]: https://github.com/PhilipHaglund/SendGridTools/compare/0.4.1...0.4.2
[0.4.1]: https://github.com/PhilipHaglund/SendGridTools/compare/v0.3.0...0.4.1
[0.3.0]: https://github.com/PhilipHaglund/SendGridTools/tree/v0.3.0
