param(
    [Parameter(Mandatory)][ValidateScript({Test-Path $_ -PathType Leaf})]$Solution,
    [Parameter(Mandatory)]$ProjectName
)

$SolutionLines = Get-Content $Solution
$ProjectRecord = $SolutionLines | Select-String "`"$ProjectName`","
if (!$ProjectRecord)
{
    return 'NotFound'
}
if (!($ProjectRecord -match '.+{([0-9A-Fa-f-]+)}"$'))
{
    throw "Failed to parse $ProjectRecord"
}
$ProjectGuid = $Matches[1]
$DeleteEndProject = $false
$NewSolutionLines = $SolutionLines | Where-Object {
    if ($DeleteEndProject)
    {
        $DeleteEndProject = $false
        if ($_ -ne 'EndProject')
        {
            throw "Failed to parse $Solution - unexpected token '$_'"
        }
        return
    }
    
    if ($ProjectRecord -and ($_ -eq $ProjectRecord))
    {
        $DeleteEndProject = $true
        $ProjectRecord = $null
        return
    }

    if ($_ -match $ProjectGuid)
    {
        if ($ProjectRecord)
        {
            throw "Failed to parse $Solution - encountered the project guid $ProjectGuid before the project record"
        }
        return
    }

    $true
}

Set-Content $Solution $NewSolutionLines
return 'OK'