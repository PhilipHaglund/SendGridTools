<#
.SYNOPSIS
This function is used to interact with the SendGrid API.

.DESCRIPTION
Invoke-SendGrid is a custom function designed to interact with the SendGrid API. It requires an active SendGridSession, which should be established via the Connect-SendGrid cmdlet before calling this function.

.PARAMETER Method
The web request method to use (GET, POST, PUT, DELETE etc).

.PARAMETER Namespace
The endpoint of the SendGrid API to interact with.

.PARAMETER ContentBody
(Optional) A hashtable containing the request body to send with the request.

.EXAMPLE
Invoke-SendGrid -Method GET -Namespace "mail/send"

#>
function Invoke-SendGrid {
    [CmdletBinding(
        SupportsShouldProcess
    )]
    param (
        # The web request method.
        [Parameter(
            Mandatory,
            HelpMessage = 'The web request method.',
            Position = 0
        )]
        [ValidateNotNullOrEmpty()]
        [Microsoft.PowerShell.Commands.WebRequestMethod]$Method,

        # The endpoint to use.
        [Parameter(
            Mandatory,
            HelpMessage = 'The SendGrid endpoint to use.',
            Position = 1
        )]
        [ValidateNotNullOrEmpty()]
        [string]$Namespace,

        # The content body to send with the request.
        [Parameter(
            HelpMessage = 'The content body to send with the request.',
            Position = 2
        )]
        [ValidateNotNull()]
        [AllowEmptyCollection()]
        [hashtable]$ContentBody,

        # The username of the subuser to send the query on behalf of.
        [Parameter(
            HelpMessage = 'The username of the subuser to send the query on behalf of.',
            Position = 3
        )]
        [ValidateNotNullOrEmpty()]
        [string]$OnBehalfOf,

        # The calling cmdlet or function that invoked this function.
        [Parameter(
            HelpMessage = 'The calling cmdlet or function that invoked this function.',
            Position = 4
        )]
        [ValidateNotNullOrEmpty()]
        [string]$CallingCmdlet
    )
    begin {
        # Function to get unique properties of an object.
        function Get-UniqueProperties {
            param (
                [Parameter(
                    ValueFromPipeline
                )]
                [object[]]$InputObject
            )
            # Get the properties of each object in the input array.
            $Members = foreach ($Object in $InputObject) {
                $Object | Get-Member -MemberType NoteProperty
            }
            # Return the unique properties.
            if ($null -ne $Members) {
                ($Members | Sort-Object -Property Name -Unique).Name | ConvertTo-TitleCase
            }
        }
    }
    process {
        if ($PSCmdlet.ShouldProcess("$Method : $Namespace")) {
            Write-Verbose "Starting process with method: $Method and namespace: $Namespace"
            # Check if session is not a SendGridSession.
            if ($script:Session -isnot [SendGridSession]) {
                throw 'You must call the Connect-SendGrid cmdlet before calling any other cmdlets.'
            }
            try {
                # Invoke the query based on provided parameters.
                if ($PSBoundParameters.ContainsKey('ContentBody') -and $PSBoundParameters.ContainsKey('OnBehalfOf')) {
                    $Query = $script:Session.InvokeQuery($Method, $Namespace, $ContentBody, $OnBehalfOf)
                }
                elseif ($PSBoundParameters.ContainsKey('ContentBody')) {
                    $Query = $script:Session.InvokeQuery($Method, $Namespace, $ContentBody)
                }
                elseif ($PSBoundParameters.ContainsKey('OnBehalfOf')) {
                    $Query = $script:Session.InvokeQuery($Method, $Namespace, $OnBehalfOf)
                }
                else {
                    $Query = $script:Session.InvokeQuery($Method, $Namespace)
                }
            }
            catch {
                throw $_.Exception.Message
            }

            # Get unique properties.
            $Properties = Get-UniqueProperties -InputObject $Query
            
            # Handle PSObject array with a single or more than 'Result' property.
            if ($Query -is [System.Management.Automation.PSObject[]] -and $Properties.Count -eq 1) {
                switch ($Properties) {
                    'Result' {
                        $Query = $Query.result
                        break;
                    }
                    'Suppressions' {
                        $Query = $Query.suppressions
                        break;
                    }
                    Default {
                        break;
                    }
                }
                $Properties = Get-UniqueProperties -InputObject $Query
            }


            # Process each object in the query.
            foreach ($Object in $Query) {
                # Create a new custom object.
                [PSCustomObject]$PSObject = [PSCustomObject]::new()

                # Process each property in the properties array.
                foreach ($Property in $Properties) {
                    # Check for inline properties.
                    if ($Object.$Property -is [System.Management.Automation.PSCustomObject]) {
                        $InlineProperties = Get-UniqueProperties -InputObject $Object.$Property

                        # Process each inline property.
                        foreach ($InlineProperty in $InlineProperties) {
                            $PSObject | Add-Member -MemberType NoteProperty -Name (('{0}{1}' -f ($Property -replace '[\s_-]+'), $($InlineProperty -replace '[\s_-]+')) | ConvertTo-TitleCase) -Value $Object.$Property.$InlineProperty
                        }
                    }

                    # Switch based on the property type.
                    switch ($Object.$Property) {
                        { $_ -is [int64] -and $Property -match 'valid|created|updated' } {
                            $PSObject | Add-Member -MemberType NoteProperty -Name (($Property -replace '[\s_-]+') | ConvertTo-TitleCase) -Value ([UnixTime]::FromUnixTime($_))
                            break
                        }
                        { $_ -is [string] -and $Property -match '^date$'} {
                            $PSObject | Add-Member -MemberType NoteProperty -Name (($Property -replace '[\s_-]+') | ConvertTo-TitleCase) -Value ([datetime]::Parse($_))
                            break
                        }
                        Default {
                            $PSObject | Add-Member -MemberType NoteProperty -Name (($Property -replace '[\s_-]+') | ConvertTo-TitleCase) -Value $Object.$Property -Force
                            break
                        }
                    }
                }
                if ($PSObject | Get-Member -Name 'Errors' -MemberType 'NoteProperty') {
                    throw $PSObject.Errors.Message
                }
                else {
                    if (0 -eq @($PSObject.PSObject.Properties).Count) {
                        Write-Verbose -Message ('Successfully invoked "{0}" on "{1}".' -f $CallingCmdlet, $Namespace) -Verbose
                    }
                    else {
                        Write-Verbose -Message ('Successfully invoked "{0}" on "{1}".' -f $CallingCmdlet, $Namespace)
                        $PSObject
                    }
                }
            }
        }
    }
}