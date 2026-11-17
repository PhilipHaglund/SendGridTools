# Changelog for SendGridTools

The format is based on and uses the types of changes according to [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- 

### Changed

- The build now resolves its dependencies locally into `output/RequiredModules` at pinned versions, and the quality tests run on Pester 5.
- Made it Windows PowerShell 5.1 compatible by using ArgumentCompleter instead of using " : System.Management.Automation.IValidateSetValuesGenerator"
- The module is built and tested on Linux, Windows and macOS in PowerShell 7 and in Windows PowerShell 5.1, and published to the PowerShell Gallery from GitHub Actions: every merge to main publishes a preview, and a full release comes only from a version tag.



### Deprecated

- 

### Removed

- The Azure Pipelines definition is removed.

### Fixed

- 

### Security

- 

