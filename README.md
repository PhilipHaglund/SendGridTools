# SendGridTools

Manage SendGrid using PowerShell

[![Build and test](https://github.com/PhilipHaglund/SendGridTools/actions/workflows/build-and-test.yml/badge.svg?branch=main)](https://github.com/PhilipHaglund/SendGridTools/actions/workflows/build-and-test.yml)

## Table of Contents

- [Introduction](#introduction)
- [Installation](#installation)
- [Usage](#usage)
- [Cmdlets](#cmdlets)
- [Examples](#examples)
- [Contributing](#contributing)
- [License](#license)

## Introduction

SendGridTools is a PowerShell module designed to help you manage SendGrid using its API. This module provides a set of functions and wrappers to interact with SendGrid, making it easier to automate email-related tasks.

## Installation

### Prerequisites

- Windows PowerShell 5.1 or PowerShell 7
- SendGrid API Key

### Installing from PowerShell Gallery

You can install the SendGridTools module directly from the PowerShell Gallery:

```PowerShell
Install-PSResource -Name SendGridTools
```

Or with PowerShellGet:

```PowerShell
Install-Module -Name SendGridTools -Scope CurrentUser
```

Preview versions are published to the gallery as prereleases:

```PowerShell
Install-PSResource -Name SendGridTools -Prerelease
```

### Installing from Source

Clone the repository, resolve the build dependencies, build and test the module:

```PowerShell
git clone https://github.com/PhilipHaglund/SendGridTools.git
Set-Location SendGridTools
./build.ps1 -ResolveDependency -Tasks noop   # resolve build modules
./build.ps1 -Tasks build
./build.ps1 -Tasks test
```

The build writes the module to a versioned output directory. Import the built module from there:

```PowerShell
Import-Module ./output/SendGridTools/<version>/SendGridTools.psd1
```

### Usage
Importing the Module
To use the SendGridTools module, you need to import it into your PowerShell session:
```PowerShell
Import-Module SendGridTools
```
### Authenticating with SendGrid
Before using the cmdlets, you need to authenticate with SendGrid using your API key
```PowerShell
Connect-SendGrid
Enter your ApiKey
Password for user apikey:
```

A new session uses SendGrid's global host by default, and an existing session is refreshed on its own host. For an account on the EU host, use `-Region EU`, or give another https base URI with `-BaseUri` (`/v3` is added when missing). Naming another host than the current session starts a new session and asks for the key unless `-Credential` is given; if that connection fails, no session is left.
```PowerShell
Connect-SendGrid -Region EU
Connect-SendGrid -BaseUri 'https://api.eu.sendgrid.com'
```

To sign in without a prompt, for example from a vault or an environment variable, give the key as a secure string with `-ApiKey` (it cannot be combined with `-Credential`); in a host that cannot prompt, `Connect-SendGrid` without `-Credential` or `-ApiKey` fails with an error that names both.
```PowerShell
$ApiKey = ConvertTo-SecureString -String $env:<variable> -AsPlainText -Force
Connect-SendGrid -ApiKey $ApiKey
```

*The session lifetime when connecting is **1 hour** and will be renewed with each cmdlet run.*


## Cmdlets
Currently contains **63** functions.

For a full list of cmdlets, use the following command:

```PowerShell
Get-Command -Module SendGridTools
```

## Examples
### Sending an Email
```PowerShell
Send-SGMailMessage -To '<address>' -From '<address>' -Subject 'Test Email' -Body 'This is a test email.'
```
### Retrieving Authenticated Domains
```PowerShell
Get-SGAuthenticatedDomain
```
### Retrieving Email Activity
*Requires the SendGrid [30 Days Additional Email Activity History Addon](https://sendgrid.com/en-us/solutions/add-ons/30-days-additional-email-activity-history)*
```PowerShell
Get-SGEmailActivity -Property ToEmail -Like -Value '<address>' -Verbose
```
```PowerShell
Get-SGEmailActivity -Filter "fromemail -contains '<domain>'"
```
```PowerShell
Get-SGEmailActivity -SendGridFilter "from_email%3D%22<address>%22"
```
*`-SendGridFilter` is sent as given, so the query must already be URL encoded.*
### Removing an Email from the Global Suppression List
```PowerShell
Remove-SGGlobalSuppression -EmailAddress '<address>'
```


## Contributing
We welcome contributions to the SendGridTools module. If you would like to contribute, please follow these steps:

1. Fork the repository.
2. Create a new branch for your feature or bugfix.
3. Make your changes and commit them with clear and concise messages.
4. Push your changes to your fork.
5. Create a pull request to the main repository.
6. Please ensure that your code follows the existing coding style and includes appropriate tests.

## License
This project is licensed under the MIT License. See the LICENSE file for more details.

## Acknowledgements
Thank you to all those who contributed to this module by writing code, sharing opinions, and providing feedback.

## Troubleshooting
If you encounter any issues, please check the GitHub repository for known issues and new releases. You can also open a new issue if you need further assistance.

## See Also
- [SendGrid v3 API documentation](https://docs.sendgrid.com/api-reference)
- [PowerShell documentation](https://learn.microsoft.com/powershell/)

Keywords: SendGrid, PowerShell, Email, API, Automation
