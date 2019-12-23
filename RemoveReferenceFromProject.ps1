param([Parameter(Mandatory)]$SolutionName)

. "$PSScriptRoot\Functions.ps1"

function DoRemoveReference($CurProject, $ProjectToRemove)
{
    $nsmgr = [Xml.XmlNamespaceManager]::New($CurProject.Xml.NameTable)
    $nsmgr.AddNamespace('a', "http://schemas.microsoft.com/developer/msbuild/2003")

    $RawValue = $ProjectToRemove.RawValue
    $Element = $ProjectToRemove.Element
    $node = $CurProject.Xml.SelectNodes("/a:Project/a:ItemGroup/a:$Element[@Include='$RawValue']", $nsmgr)
    if (!$node)
    {
        throw "Failed to locate the reference XML node for $RawValue"
    }
    if ($node.Count -gt 1)
    {
        throw "Found more than one reference XML node for $RawValue"
    }
    $null = $node[0].ParentNode.RemoveChild($node[0])
    $CurProject.Xml.Save($CurProject.Path)
}

function RemoveReference($CurProject, $ProjectToRemove, $SourceFiles)
{
    $ProjectName = $ProjectToRemove.ProjectName
    Write-Host -ForegroundColor Green "Remove $ProjectName from $($CurProject.Name)"

    DoRemoveReference $CurProject $ProjectToRemove

    $Start = $false
    $SourceFiles.Solutions | ForEach-Object {
        $SolutionName = $_
        $Solution = $SolutionMap[$SolutionName]

        $Solution.BuildOrder | Where-Object {
            if ($Start)
            {
                $true
            }
            elseif ($_ -eq $CurProject.Name)
            {
                $Start = $true
                $true
            }
        } | ForEach-Object {
            AdjustProject $SolutionName $Solution $_ $SourceFiles.Shared $CurProject
        }
    }
}

$Projects = $SolutionMap[$SolutionName].BuildOrder | ForEach-Object { $_ }
[Array]::Reverse($Projects)

$SourceFiles = & "$PSScriptRoot\MapSharedSourceCode.ps1" DataSvc

$Projects | ForEach-Object {
    $CurProject = ParseProject $SolutionName $_
    if (!$CurProject.ProjectsToRemove)
    {
        return 'Done'
    }

    $CurProject.ProjectsToRemove | ForEach-Object {
        $ProjectName = $_.ProjectName

        pskill msbuild
        InitialBuild

        $SharedBackup = BackupSharedSourceFiles $SourceFiles.Shared
        RemoveReference $CurProject $_ $SourceFiles
 
        try
        {
            & "$PSScriptRoot\ReproduceBug" @{ } { } { 
                "Removed $ProjectName from $($CurProject.Name)" 
            } -NoReset
        }
        catch
        {
            $SourceFiles.Shared = $SharedBackup
            git reset --hard HEAD
            if ($LASTEXITCODE)
            {
                throw "git reset --hard HEAD returned exit code $LastExitCode"
            }
        }
    }
}