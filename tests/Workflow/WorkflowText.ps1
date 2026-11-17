# Helper for the workflow tests; dot-source it from a BeforeAll. It holds function definitions
# only, so dot-sourcing it runs nothing. It is not named *.Tests.ps1, so Pester never runs it.

function Get-WorkflowStepRun {
    <#
    .SYNOPSIS
    Returns the run: block of the named workflow step, dedented, or $null.
    .DESCRIPTION
    The step starts at its '- name: <StepName>' line; its run: | block is every following line
    indented at least as far as the block's first line. Reads text only -- there is no YAML
    parser among the build's modules.
    #>
    param([string]$Text, [string]$StepName)
    $Lines = $Text -split '\r?\n'
    $Start = -1
    $Indent = ''
    for ($Index = 0; $Index -lt $Lines.Count; $Index++) {
        if ($Lines[$Index] -match ('^(\s*)- name: ' + [regex]::Escape($StepName) + '\s*$')) {
            $Start = $Index
            $Indent = $Matches[1]
            break
        }
    }
    if ($Start -lt 0) { return $null }
    $Run = -1
    for ($Index = $Start + 1; $Index -lt $Lines.Count; $Index++) {
        $Line = $Lines[$Index]
        if ($Line.StartsWith($Indent + '- name: ') -or $Line -match '^\S') { break }
        if ($Line -match '^\s+run: \|\s*$') { $Run = $Index; break }
    }
    if ($Run -lt 0) { return $null }
    $Body = [System.Collections.Generic.List[string]]::new()
    $BodyIndent = -1
    for ($Index = $Run + 1; $Index -lt $Lines.Count; $Index++) {
        $Line = $Lines[$Index]
        if ($Line.Trim().Length -eq 0) { $Body.Add(''); continue }
        $Lead = $Line.Length - $Line.TrimStart().Length
        if ($BodyIndent -lt 0) { $BodyIndent = $Lead }
        if ($Lead -lt $BodyIndent) { break }
        $Body.Add($Line.Substring($BodyIndent))
    }
    ($Body -join "`n").TrimEnd()
}
