param([Parameter(Mandatory)]$SolutionName, [Switch]$All)

$Solutions = @($SolutionName)
if ($SolutionName -eq 'DataSvc')
{
    $Solutions = @('DataSvc', 'Main')
}

Write-Host -ForegroundColor Green -NoNewline "Building source file map ... "
$temp = @{ }
$Solutions | ForEach-Object {
    Get-ProjectsInSolution "$_.sln" | Get-FilesInDotNetProject | ForEach-Object {
        ++$temp[$_]
    }
}

if ($All)
{
    $SourceFiles = $temp
}
else
{
    $SourceFiles = @{ }
    $temp.GetEnumerator() | Where-Object {
        $_.Value -gt 1
    } | ForEach-Object {
        $SourceFiles[$_.Key] = $_.Value
    }
}
Write-Host -ForegroundColor Green "done."
@{
    Shared    = $SourceFiles
    Solutions = $Solutions
}