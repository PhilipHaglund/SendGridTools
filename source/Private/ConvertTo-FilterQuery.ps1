function ConvertTo-FilterQuery {
    [CmdletBinding()]
    param (
        [Parameter(
            Mandatory,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName
        )]
        [string]$Filter
    )

    $OperatorFormatStructure = @{
        'EQ'          = ('(Property{0})' -f ([uri]::EscapeDataString('=Value')))
        'NE'          = ('(Property{0})' -f ([uri]::EscapeDataString('!=Value')))
        'GT'          = ('(Property{0})' -f ([uri]::EscapeDataString('>Value')))
        'LT'          = ('(Property{0})' -f ([uri]::EscapeDataString('<Value')))
        'IN'          = ('(Property+IN+({0}))' -f ([uri]::EscapeDataString('Value'))) # Array = ("Value1", "Value2")
        'NotIn'       = ('(Property+NOT+IN ({0}))' -f ([uri]::EscapeDataString('Value'))) # Array = ("Value1", "Value2")
        'Like'        = ('(Property+LIKE+{0})' -f ([uri]::EscapeDataString('%Value%'))) #'(Property LIKE "%Value%")'
        'NotLike'     = ('(Property+NOT+LIKE+{0})' -f ([uri]::EscapeDataString('%Value%'))) #'(Property NOT LIKE "%Value%")'
        'Contains'    = ('(Contains(Property{0}))' -f ([uri]::EscapeDataString(',Value'))) #'(Contains(Property,"Value"))'
        'NotContains' = ('(Not Contains(Property{0}))' -f ([uri]::EscapeDataString(',Value'))) #'(Not Contains(Property,"Value"))'
        'IsEmpty'     = '(Property+IS+NULL)'
        'IsNotEmpty'  = '(Property+IS+NOT NULL)'
        'Between'     = '(Property+BETWEEN+TIMESTAMP+Value1+AND+TIMESTAMP+Value2)' # (last_event_time BETWEEN TIMESTAMP "2024-06-30T00:00:00.000Z" AND TIMESTAMP "2024-07-02T23:59:59.999Z")
        'OR'          = '+OR+'
        'AND'         = '+AND+'
    }
    $Properties = @{
        'MessageId'             = 'msg_id'
        'FromEmail'             = 'from_email'
        'Subject'               = 'subject'
        'ToEmail'               = 'to_email'
        'Status'                = 'status'
        'TemplateId'            = 'template_id'
        'MarketingCampaignName' = 'marketing_campaign_name'
        'MarketingCampaignId'   = 'marketing_campaign_id'
        'ApiKeyId'              = 'api_key_id'
        'ApiKeyName'            = 'api_key_id'
        'Events'                = 'events'
        'Categories'            = 'categories'
        'UniqueArgs'            = 'unique_args'
        'OutboundIp'            = 'outbound_ip'
        'LastEventTime'         = 'last_event_time'
        'Clicks'                = 'clicks'
        'AsmGroupId'            = 'asm_group_id'
        'AsmGroupName'          = 'asm_group_id'
        'Teammate'              = 'teammate'
        'Date'                  = 'last_event_time'
        'timestamp'             = 'last_event_time'
    }
    # Regular expression to match the conditions and logical operators
    $MultiSeparateRegex = '(-AND|-OR)'
    $Regex = '^(?<Property>\w+)\s*(?<operator>-eq|-ne|-gt|-lt|-in|-notin|-like|-notlike|-contains|-notcontains|isempty|-isnotempty|-between)\s*(?<Value>.*?)$'

    # Match the logical operators
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

    # Create a loop for the number of matches using the separator list
    [System.Text.StringBuilder]$QueryString = [System.Text.StringBuilder]::new()
    for ($i = 0; $i -le $LogicalOperatorsInOrder.Count; $i++) {
        $DateTime = $false
        $RegMatches = [regex]::Matches(($Filters[$i].Trim()), $Regex, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $Match = $RegMatches[0]
        $Property = $Match.Groups[1].Value.Trim()
        $Operator = $Match.Groups[2].Value.Trim()
        $Value = $Match.Groups[3].Value.Trim()

        # Define the properties that require the -Between operator
        $PropertiesRequiringBetween = @('LastEventTime', 'Date', 'Timestamp', 'last_event_time')

        # Check if the current property requires the -Between operator
        if ($PropertiesRequiringBetween -contains $Property) {
            if ($Operator -ne '-between') {
                throw "The property $Property requires the use of the -Between operator."
            }
            elseif ($Operator -eq '-between') {
                $MultipleValues = foreach ($MValue in ($Value -split ',')) {
                    $ModifiedValue = $MValue.Trim() -replace '^''|"|''|"$'
                    $ParsedDate = [DateTime]::Parse($ModifiedValue, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal)
                    '"{0:yyyy-MM-ddTHH:mm:ss.fffZ}"' -f [DateTime]::Parse($ParsedDate)
                }
                if ($MultipleValues.Count -ne 2) {
                    throw 'The -Between operator requires two values separated by a comma.'
                }
                $Value = $MultipleValues -join ','
                $DateTime = $true
            }
        }
        elseif ($Operator -eq '-between') {
            # If the operator is -Between, ensure it's used with a correct property
            if ($PropertiesRequiringBetween -notcontains $Property) {
                throw "The -Between operator can only be used with the following properties: $($PropertiesRequiringBetween -join ', ')."
            }
            elseif ($PropertiesRequiringBetween -contains $Property) {
                $MultipleValues = foreach ($MValue in ($Value -split ',')) {
                    $ModifiedValue = $MValue.Trim() -replace '^''|"|''|"$'
                    $ParsedDate = [DateTime]::Parse($ModifiedValue, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal)
                    '"{0:yyyy-MM-ddTHH:mm:ss.fffZ}"' -f [DateTime]::Parse($ParsedDate)
                }
                if ($MultipleValues.Count -ne 2) {
                    throw 'The -Between operator requires two values separated by a comma.'
                }
                $Value = $MultipleValues -join ','
                $DateTime = $true
            }
        }
        if ($Properties.Keys -notcontains $Property) {
            if ($Properties.Values -notcontains $Property) {
                throw ('Invalid property: {0}. Valid properties are: {1}' -f $Property, ($Properties.Keys -join ', '))
            }
        }
        else {
            $Property = $Properties[$Property]
            if ($null -eq $OperatorFormatStructure[$Operator.Replace('-', '')]) {
                throw ('Invalid operator: {0}. Valid operators are: {1}' -f $Operator, ($OperatorFormatStructure.Keys -join ', '))
            }
        }
        if ($Operator -eq '-in' -or $Operator -eq '-notin') {
            $MultipleValues = foreach ($MValue in ($Value -split ',')) {
                $ModifiedValue = $MValue.Trim() -replace '^''|"|''|"$'
                "`"$ModifiedValue`""
            }
            $Value = $MultipleValues -join ','
        }
        elseif ($DateTime -eq $false -or $null -eq $DateTime) {
            $ModifiedValue = $Value.Trim() -replace '^''|"|''|"$'
            $Value = "`"$ModifiedValue`""
        }

        if ($DateTime -eq $true) {
            Write-Verbose -Message "DateTime: $Value"
            $EncodedValue1 = [uri]::EscapeDataString($Value.Split(',')[0])
            $EncodedValue2 = [uri]::EscapeDataString($Value.Split(',')[1])
            $null = $QueryString.Append(($OperatorFormatStructure[$Operator.Replace('-', '')] -replace 'Property', $Property -replace 'Value1', $EncodedValue1 -replace 'Value2', $EncodedValue2))
        }
        else {
            $EncodedValue = [uri]::EscapeDataString($Value)
            $null = $QueryString.Append(($OperatorFormatStructure[$Operator.Replace('-', '')] -replace 'Property', $Property -replace 'Value', $EncodedValue))
        }

        Write-Verbose "Property: $Property, Operator: $Operator, Value: $EncodedValue$EncodedValue1$EncodedValue2"
        if ($i -lt $LogicalOperatorsInOrder.Count) {
            $null = $QueryString.Append($OperatorFormatStructure[$($LogicalOperatorsInOrder[$i]).Replace('-', '')])
            Write-Verbose "Logical Operator: $($LogicalOperatorsInOrder[$i])"
        }
    }
    $QueryString.ToString()
}