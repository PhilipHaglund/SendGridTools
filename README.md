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
git clone https://github.com/PhilipHaglund/SendGridTools.git
build.ps1 -Tasks build
Import-Module SendGridTools/output/SendGridTools.psd1
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
*Requires the SendGrid [30 Days Additional Email Activity History Addon](https://sendgrid.com/en-us/solutions/add-ons/30-days-additional-email-activity-history)*
```PowerShell
Get-SGEmailActivity -Property ToEmail -Like 'recipient@example.com' -Verbose
```
```PowerShell
Get-SGEmailActivity -Filter "fromemail -contains @example.com"
```
```PowerShell
Get-SGEmailActivity -SendGridFilter "from_email%3D%22sender%40example.com%22"
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