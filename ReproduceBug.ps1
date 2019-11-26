param(
    [Parameter(Mandatory)][hashtable]$ctx,
    [Parameter(Mandatory)][ScriptBlock]$ReduceAction,
    [Parameter(Mandatory)][ScriptBlock]$FormatCommitMessage,
    [Switch]$NoReset)

Write-Host -ForegroundColor Green "  [$(Get-Date -Format 'HH:mm:ss')] Cleanup"
pskill -nobanner msbuild
pskill -nobanner node
pskill -nobanner cmd

$TryCount = 3
do
{
    --$TryCount
    git clean -qdfx
} while ($TryCount -and $LastExitCode)
if ($LastExitCode)
{
    throw "git clean -qdfx returned exit code $LastExitCode"
}

if (!$NoReset)
{
    $TryCount = 3
    do
    {
        --$TryCount
        git reset --hard HEAD
    } while ($TryCount -and $LastExitCode)
    if ($LastExitCode)
    {
        throw "git reset --hard HEAD returned exit code $LastExitCode"
    }
}

& $ReduceAction
if ($ctx.Skip)
{
    $ctx.Skip = $null
    return
}

Write-Host -ForegroundColor Green "  [$(Get-Date -Format 'HH:mm:ss')] DataSvc"
msbuild DataSvc.sln /v:q /m /nologo
if ($LastExitCode)
{
    if ($NoReset)
    {
        throw "Failed to build DataSvc"
    }
    return
}

$Time = get-date -Format 'yyyy-MM-dd_HH-mm-ss'
Write-Host -ForegroundColor Green "  [$(Get-Date -Format 'HH:mm:ss')] Main 1"
msbuild /err Main.sln /v:q /m /nologo "/bl:c:\temp\exp\exp-Main-${Time}_1.binlog"
if ($LastExitCode)
{
    if ($NoReset)
    {
        throw "Failed to build Main (1)"
    }
    return
}

pskill -nobanner msbuild
pskill -nobanner node
pskill -nobanner cmd
Write-Host -ForegroundColor Green "  [$(Get-Date -Format 'HH:mm:ss')] Main 2"
msbuild /err Main.sln /v:q /m /nologo "/bl:c:\temp\exp\exp-Main-${Time}_2.binlog"
if ($LastExitCode)
{
    if ($NoReset)
    {
        throw "Failed to build Main (2)"
    }
    return
}

$a = & $MSBuildBinaryLogAnalyzer default -i "c:\temp\exp\exp-Main-${Time}_2.binlog" --i2 "c:\temp\exp\exp-Main-${Time}_1.binlog" --json | ConvertFrom-Json
if (!$a.Triggers.Diff.FirstBuild)
{
    if ($NoReset)
    {
        throw "No repro"
    }
    return
}

Write-Host -ForegroundColor Green "  [$(Get-Date -Format 'HH:mm:ss')] Commit"
git add .
git commit -m "$(& $FormatCommitMessage) ($Time)"