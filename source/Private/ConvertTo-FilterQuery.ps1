function ConvertTo-FilterQuery {
    [CmdletBinding()]
    param (
        [string]$Filter
    )
    # Split the filter into its components
    if ($Filter -match "(.+)\s(-eq|-ne|-gt|-lt|-like|-notlike|-contains|-notcontains|isempty|-isnotempty)\s\'(.+)\'") {
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
    }
}


$Filter = "toemail -eq 'name@example.com' -and toemail -eq 'kalle@example.com' -or toemail -eq 'john@example.com'"

# Regular expression to match the conditions and logical operators
$MultiSeparateRegex = '(-AND|-OR)'
$Regex = "(.+?)\s(-eq|-ne|-gt|-lt|-like|-notlike|-contains|-notcontains|isempty|-isnotempty)\s'(.+?)'"

$MatchesSeprator = [regex]::Matches($Filter, $MultiSeparateRegex, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
# Initialize an list to hold the operators in order
$OperatorsInOrder = [System.Collections.Generic.List[string]]::new()

# Process each match to extract the operators
foreach ($Match in $MatchesSeprator) {
    $OperatorsInOrder.Add($Match.Value)
}
# Find all matches
$Matches = [regex]::Matches($Filter, $Regex)

# Create a loop for the number of matches using the separator list
for ($i = 0; $i -lt $OperatorsInOrder.Count; $i++) {
    $Match = $Matches[$i]
    $Property = $Match.Groups[1].Value
    $Operator = $Match.Groups[2].Value
    $Value = $Match.Groups[3].Value

    # Output for demonstration
    Write-Output "Property: $Property, Operator: $Operator, Value: $Value"
    if ($i -lt $OperatorsInOrder.Count) {
        Write-Output "Logical Operator: $($OperatorsInOrder[$i])"
    }
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