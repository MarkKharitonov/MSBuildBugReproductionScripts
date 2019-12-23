param($SolutionName, $ProjectName)

. "$PSScriptRoot\Functions.ps1"

$SharedSourceFiles = & "$PSScriptRoot\MapSharedSourceCode.ps1" DataSvc
if ($SolutionName)
{
    $Solutions = $SolutionName
}
else
{
    $Solutions = $SharedSourceFiles.Solutions
}

$Solutions | ForEach-Object {
    $SolutionName = $_

    if ($ProjectName)
    {
        $Projects = $ProjectName
    }
    else
    {
        $Projects = $SolutionMap[$SolutionName].BuildOrder
    }
    $Projects | ForEach-Object {
        $ProjectName = $_
    
        if ($ProjectName -eq 'DfVersioning')
        {
            return
        }

        Write-Host -ForegroundColor Green "Attempting to remove all the source files from $ProjectName in $SolutionName"

        pskill msbuild
        InitialBuild

        $ProjectPath = GetProjectPath $SolutionName $ProjectName
        $FilesToRemove = $(Get-FilesInDotNetProject $ProjectPath)
        $j = 0
        $FilesToRemove | ForEach-Object {
            ++$j
            $FileToRemove = $_
            Write-Host -ForegroundColor Green "[$j/$($FilesToRemove.Count)] Attempting to delete $FileToRemove from $ProjectName ..."

            $ProjectXml = [xml](Get-Content $ProjectPath)
            $SharedBackup = BackupSharedSourceFiles $SharedSourceFiles.Shared
            $null = RemoveFilesFromProject $ProjectXml $ProjectPath $SharedSourceFiles.Shared $FileToRemove -MayNotExist

            $SourceProject = @{
                Name = $ProjectName
                Path = $ProjectPath
                Xml  = $ProjectXml
            }

            $SharedSourceFiles.Solutions | ForEach-Object {
                $CurSolutionName = $_
                $CurSolution = $SolutionMap[$CurSolutionName]

                $CurSolution.BuildOrder | ForEach-Object {
                    $CurProjectName = $_

                    AdjustProject $CurSolutionName $CurSolution $CurProjectName $SharedSourceFiles.Shared $SourceProject
                }
            }

            try
            {
                & "$PSScriptRoot\ReproduceBug" @{ } { } { 
                    "Removed $FileToRemove from $ProjectName in $SolutionName" 
                } -NoReset
            }
            catch
            {
                $SharedSourceFiles.Shared = $SharedBackup
                git reset --hard HEAD
                if ($LASTEXITCODE)
                {
                    throw "git reset --hard HEAD returned exit code $LastExitCode"
                }
            }
        }
    }
}