# SendGridTools

Manage SendGrid using PowerShell

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

- PowerShell 6.0 or higher
- SendGrid API Key

### Installing from PowerShell Gallery

You can install the SendGridTools module directly from the PowerShell Gallery:

```PowerShell
Install-Module -Name SendGridTools -Scope CurrentUser
```
### Installing from Source
Clone the repository and import the module:
```PowerShell
git clone https://github.com/yourusername/SendGridTools.git
Import-Module ./SendGridTools/SendGridTools.psd1
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

*The session lifetime when connecting is **1 hour** and will be renewed with each cmdlet run.*


## Cmdlets

Here are some of the key cmdlets provided by the SendGridTools module:

- [`Get-SGAuthenticatedDomain`](command:_github.copilot.openSymbolFromReferences?%5B%22Get-SGAuthenticatedDomain%22%2C%5B%7B%22uri%22%3A%7B%22%24mid%22%3A1%2C%22fsPath%22%3A%22c%3A%5C%5CGit%5C%5CSendGridTools%5C%5Cbuild.ps1%22%2C%22_sep%22%3A1%2C%22external%22%3A%22file%3A%2F%2F%2Fc%253A%2FGit%2FSendGridTools%2Fbuild.ps1%22%2C%22path%22%3A%22%2Fc%3A%2FGit%2FSendGridTools%2Fbuild.ps1%22%2C%22scheme%22%3A%22file%22%7D%2C%22pos%22%3A%7B%22line%22%3A423%2C%22character%22%3A32%7D%7D%5D%5D "Go to definition"): Retrieves authenticated domains.
- `Send-SGMailMessage`: Sends a new email.
- [`Get-SGEmailStatistics`](command:_github.copilot.openSymbolFromReferences?%5B%22Get-SGEmailStatistics%22%2C%5B%7B%22uri%22%3A%7B%22%24mid%22%3A1%2C%22fsPath%22%3A%22c%3A%5C%5CGit%5C%5CSendGridTools%5C%5Cbuild.ps1%22%2C%22_sep%22%3A1%2C%22external%22%3A%22file%3A%2F%2F%2Fc%253A%2FGit%2FSendGridTools%2Fbuild.ps1%22%2C%22path%22%3A%22%2Fc%3A%2FGit%2FSendGridTools%2Fbuild.ps1%22%2C%22scheme%22%3A%22file%22%7D%2C%22pos%22%3A%7B%22line%22%3A423%2C%22character%22%3A32%7D%7D%5D%5D "Go to definition"): Retrieves email statistics.
- [`New-SGAuthenticatedDomain`](command:_github.copilot.openSymbolFromReferences?%5B%22Get-SGSuppressionList%22%2C%5B%7B%22uri%22%3A%7B%22%24mid%22%3A1%2C%22fsPath%22%3A%22c%3A%5C%5CGit%5C%5CSendGridTools%5C%5Cbuild.ps1%22%2C%22_sep%22%3A1%2C%22external%22%3A%22file%3A%2F%2F%2Fc%253A%2FGit%2FSendGridTools%2Fbuild.ps1%22%2C%22path%22%3A%22%2Fc%3A%2FGit%2FSendGridTools%2Fbuild.ps1%22%2C%22scheme%22%3A%22file%22%7D%2C%22pos%22%3A%7B%22line%22%3A423%2C%22character%22%3A32%7D%7D%5D%5D "Go to definition"): Retrieves the suppression list.
- `Remove-SGSuppression`: Removes an email from the suppression list.

For a full list of cmdlets, use the following command:

```PowerShell
Get-Command -Module SendGridTools
```

## Examples
### Sending an Email
```PowerShell
Send-SGMailMessage -To 'recipient@example.com' -From 'sender@example.com' -Subject 'Test Email' -Body 'This is a test email.'
```
### Retrieving Authenticated Domains
```PowerShell
Get-SGAuthenticatedDomain
```
### Retrieving Email Activity
```PowerShell
Get-SGEmailActivity -Property ToEmail -Like 'recipient@example.com' -Verbose
```
```PowerShell
Get-SGEmailActivity -Filter "fromemail -contains @example.com"
```
```PowerShell
Get-SGEmailActivity -SendGridFilter "to_email%3D%22example%40example.com%22"
```
### Removing an Email from the Suppression List
```PowerShell
Remove-SGSuppression -Email 'user@example.com'
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
SendGrid API Documentation
PowerShell Documentation
Keywords
SendGrid, PowerShell, Email, API, Automation