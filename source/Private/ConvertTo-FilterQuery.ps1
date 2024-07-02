function ConvertTo-FilterQuery {
    [CmdletBinding()]
    param (
        [ValidatePattern("(.+?)\s(-eq|-ne|-gt|-lt|-in|-notin|-like|-notlike|-contains|-notcontains|isempty|-isnotempty)\s(['""])((?:[^'""']+?['""]?(?:\s*,\s*['""]?[^'""']*['""]?)*)+)['""]")]
        [string]$Filter
    )

    $OperatorFormatStructure = @{
            'EQ'          = ('(Property{0})' -f ([uri]::EscapeDataString('="Value"')))
            'NE'          = ('(Property{0})' -f ([uri]::EscapeDataString('!="Value"')))
            'GT'          = ('(Property{0})' -f ([uri]::EscapeDataString('>Value"')))
            'LT'          = ('(Property{0})' -f ([uri]::EscapeDataString('<Value"')))
            'IN'          = ('(Property IN ({0}))' -f ([uri]::EscapeDataString('"Value"'))) # Array = ("Value1", "Value2")
            'NotIn'       = ('(Property NOT IN ({0}))' -f ([uri]::EscapeDataString('"Value"'))) # Array = ("Value1", "Value2")
            'Like'        = ('(Property LIKE {0})' -f ([uri]::EscapeDataString('"%Value%"'))) #'(Property LIKE "%Value%")'
            'NotLike'     = ('(Property NOT LIKE {0})' -f ([uri]::EscapeDataString('"%Value%"'))) #'(Property NOT LIKE "%Value%")'
            'Contains'    = ('(Contains(Property{0}))' -f ([uri]::EscapeDataString(',"Value"'))) #'(Contains(Property,"Value"))'
            'NotContains' = ('(Not Contains(Property{0}))' -f ([uri]::EscapeDataString(',"Value"'))) #'(Not Contains(Property,"Value"))'
            'IsEmpty'     = '(Property IS NULL)'
            'IsNotEmpty'  = '(Property IS NOT NULL)'
            'OR'          = ' OR '
            'AND'         = ' AND '
        }
    # Regular expression to match the conditions and logical operators
    $MultiSeparateRegex = '(-AND|-OR)'
    $Regex = '(?<Property>\w+)\s*(?<operator>-eq|-ne|-gt|-lt|-in|-notin|-like|-notlike|-contains|-notcontains|isempty|-isnotempty|-between)\s*(?<Value>.*?)'
    <#OLD 
    $Regex = "(.+?)\s(-eq|-ne|-gt|-lt|-in|-notin|-like|-notlike|-contains|-notcontains|isempty|-isnotempty)\s['`"](.+?)['`"]"
    $Regex = "(.+?)\s(-eq|-ne|-gt|-lt|-in|-notin|-like|-notlike|-contains|-notcontains|isempty|-isnotempty)\s(['`"]?)(.+?)(?:\3|(\d+))?"
    $Regex = "(.+?)\s(-eq|-ne|-gt|-lt|-in|-notin|-like|-notlike|-contains|-notcontains|isempty|-isnotempty)\s((['`"]).*?\4 | (\d+))(, \s*((['`"]).*?\8|(\d+)))*"
    $Regex = "(.+?)\s(-eq|-ne|-gt|-lt|-in|-notin|-like|-notlike|-contains|-notcontains|isempty|-isnotempty)\s'((?:[^']+?'(?:\s*,\s*'?[^']*'?)*)+)'" # Match multiple values
    $Regex = "(.+?)\s(-eq|-ne|-gt|-lt|-in|-notin|-like|-notlike|-contains|-notcontains|isempty|-isnotempty)\s(['""])((?:[^'""']+?['""]?(?:\s*,\s*['""]?[^'""']*['""]?)*)+)['""]" # Match multiple values enclosed in either single or double quotes
    $Regex = "(.+?)\s(-eq|-ne|-gt|-lt|-in|-notin|-like|-notlike|-contains|-notcontains|isempty|-isnotempty)\s(?:(['""])?((?:NULL|[^,'""\s]+)(?:\s*,\s*(?:['""])?[^,'""\s]+(?:['""])?)*))\3?)"
    $Regex = "(.+?)\s(-eq|-ne|-gt|-lt|-in|-notin|-like|-notlike|-contains|-notcontains|isempty|-isnotempty)\s(?:(['""])?((?:NULL|[^,'""\s]+)(?:\s*,\s*(?:['""])?[^,'""\s]+)*(?:['""])?))\3?"
    #>
    $MatchesSeparator = [regex]::Matches($Filter, $MultiSeparateRegex, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    # Initialize an list to hold the operators in order
    $LogicalOperatorsInOrder = [System.Collections.Generic.List[string]]::new()

    # Process each match to extract the operators
    foreach ($Match in $MatchesSeparator) {
        $LogicalOperatorsInOrder.Add($Match.Value)
    }
    # Filter out the logical operators and remove double whitespaces
    $FilterWithOutSeparator = $Filter -replace $MultiSeparateRegex, '_SPLITTING_' #-replace '\s+', ' '
    $Filters = $FilterWithOutSeparator -split '_SPLITTING_'

    $RegMatches = [regex]::Matches($FilterWithOutSeparator, $Regex, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($null -eq $RegMatches) {
        throw "Invalid filter format. Please use the format 'Property -Operator 'Value''"
    }
    $RegMatches.Groups  

    # Create a loop for the number of matches using the separator list
    [System.Text.StringBuilder]$QueryString = [System.Text.StringBuilder]::new()
    for ($i = 0; $i -le $LogicalOperatorsInOrder.Count; $i++) {
        $RegMatches = [regex]::Matches($Filters[$i], $Regex, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $Match = $RegMatches[$i]
        $Property = $Match.Groups[1].Value.Trim()
        $Operator = $Match.Groups[2].Value.Trim()
        $Value = $Match.Groups[3].Value.Trim()

        #$RegexEscape = '[\=]|[\!]|[\>]|[\<]|[\"]|[\'']|[\%]|[\@]'
        #$NewValue = [regex]::Matches($Value, $RegexEscape) | ForEach-Object {
        #    $Value -replace $_.Value, [uri]::EscapeDataString($_.Value)
        #}
        #if ($null -eq $NewValue) {
            $NewValue = [uri]::EscapeDataString($Value)
        #}

        $null = $QueryString.Append(($OperatorFormatStructure[$Operator.Replace('-', '')] -replace 'Property', $Property -replace 'Value', $NewValue))

        Write-Verbose "Property: $Property, Operator: $Operator, Value: $NewValue"
        if ($i -lt $LogicalOperatorsInOrder.Count) {
            $null = $QueryString.Append($OperatorFormatStructure[$($LogicalOperatorsInOrder[$i]).Replace('-', '')])
            Write-Verbose "Logical Operator: $($LogicalOperatorsInOrder[$i])"
        }
        #Transform the filter to query using $OperatorFormatStructure
    }
    $QueryString.ToString()
    # Split the filter into its components
    <#if ($Filter -match "(.+)\s(-eq|-ne|-gt|-lt|-like|-notlike|-contains|-notcontains|isempty|-isnotempty)\s\'(.+)\'") {
        $Property = $matches[1]
        $Operator = $matches[2] 
        $Value = $matches[3]
        # Map PowerShell operators to API query operators
        $Operators = @{
            'EQ'          = '='
            'NE'          = '!='
            'GT'          = '>'
            'LT'          = '<'
            'IN'          = 'IN'
            'NotIn'       = 'NOT IN'
            'Like'        = 'LIKE'
            'NotLike'     = 'NOT LIKE'
            'Contains'    = 'Contains'
            'NotContains' = 'Not Contains'
            'IsEmpty'     = 'IS NULL'
            'IsNotEmpty'  = 'IS NOT NULL'
            'OR'          = 'OR'
            'AND'         = 'AND'
        }
        $URLConvertOperators = @{
            'EQ' = '='
            'NE' = '!='
            'GT' = '>'
            'LT' = '<'
        }
        $OperatorFormatStructure = @{
            'EQ'          = '(Property="Value")'
            'NE'          = '(Property!="Value")'
            'GT'          = '(Property>Value)'
            'LT'          = '(Property<Value)'
            'IN'          = '(Property IN ("Value"))' # Array = ("Value1", "Value2")
            'NotIn'       = '(Property NOT IN ("Value"))' # Array = ("Value1", "Value2")
            'Like'        = '(Property LIKE "%Value%"'
            'NotLike'     = '(Property NOT LIKE "%Value%"'
            'Contains'    = '(Contains(Property,"Value"))'
            'NotContains' = '(Not Contains(Property,"Value"))'
            'IsEmpty'     = '(Property IS NULL)'
            'IsNotEmpty'  = '(Property IS NOT NULL)'
            'OR'          = ' OR '
            'AND'         = ' AND '
        }

        # Construct the query string
        [System.Text.StringBuilder]$QueryString = [System.Text.StringBuilder]::new()
        $APIProperty = $Property -replace ' ', '_'
        $operator = $Operator.ToUpper()
        if ($Operator -eq '-eq' -or $Operator -eq '-ne' -or $Operator -eq '-gt' -or $Operator -eq '-lt') {
            $QueryString.Append("($APIProperty" + $URLConvertOperators[$operator] + [uri]::EscapeDataString("`"$Value`")"))
        }
        else {
            $QueryString.Append("($APIProperty" + $OperatorFormatStructure[$operator] + [uri]::EscapeDataString("`"$Value`")"))
        }        
        
    }
    else {
        throw "Invalid filter format. Please use the format 'Property -Operator 'Value''"
    }#>

}

<#
$Filter = "toemail -eq 'name@example.com' -and toemail -eq 'kalle@example.com' -or toemail -eq 'john@example.com'"

# Regular expression to match the conditions and logical operators
$MultiSeparateRegex = '(-AND|-OR)'
$Regex = "(.+?)\s(-eq|-ne|-gt|-lt|-like|-notlike|-contains|-notcontains|isempty|-isnotempty)\s'(.+?)'"

$MatchesSeparator = [regex]::Matches($Filter, $MultiSeparateRegex, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
# Initialize an list to hold the operators in order
$OperatorsInOrder = [System.Collections.Generic.List[string]]::new()

# Process each match to extract the operators
foreach ($Match in $MatchesSeparator) {
    $OperatorsInOrder.Add($Match.Value)
}
# Filter out the logical operators and remove double whitespaces
$FilterWithOutSeparator = $Filter -replace $MultiSeparateRegex -replace '\s+', ' '
$RegMatches = [regex]::Matches($FilterWithOutSeparator, $Regex)

# Create a loop for the number of matches using the separator list
for ($i = 0; $i -lt $OperatorsInOrder.Count; $i++) {
    $Match = $RegMatches[$i]
    $Property = $Match.Groups[1].Value.Trim()
    $Operator = $Match.Groups[2].Value.Trim()
    $Value = $Match.Groups[3].Value.Trim()

    # Output for demonstration
    $OperatorFormatStructure[$Operator.Replace('-','')] -replace 'Property', $Property -replace 'Value', $Value
    Write-Verbose "Property: $Property, Operator: $Operator, Value: $Value"
    if ($i -lt $OperatorsInOrder.Count) {
        $OperatorFormatStructure[$($OperatorsInOrder[$i]).Replace('-', '')]
        Write-Verbose "Logical Operator: $($OperatorsInOrder[$i])"
    }

    
    #Transform the filter to query using $OperatorFormatStructure
}
# Process each match
foreach ($match in $matches) {
    $property = $match.Groups[1].Value
    $operator = $match.Groups[2].Value
    $value = $match.Groups[3].Value

    # Output for demonstration
    Write-Output "Property: $property, Operator: $operator, Value: $value"
}

# To handle logical operators separately, you might need to split the string by conditions and then analyze each part.

$Filter = "toemail -eq 'name@example.com' -and toemail -eq 'kalle@example.com' -or toemail -eq 'john@example.com'"

# Regular expression to match -AND and -OR logical operators
$MultiSeparateRegex = '(\-AND|\-OR)'

# Find all matches
$Filter -match $MultiSeparateRegex
$matches = [regex]::Matches($Filter, $MultiSeparateRegex, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

# Initialize an array to hold the operators in order
$operatorsInOrder = @()

# Process each match to extract the operators
foreach ($match in $matches) {
    $operatorsInOrder += $match.Value
}

# Output the operators in order
$operatorsInOrder
#>