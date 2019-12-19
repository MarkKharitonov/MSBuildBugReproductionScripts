function InitialBuild()
{
    Write-Host -NoNewline -ForegroundColor Green "Building ... "
    msbuild DataSvc.sln /v:q /m /nologo
    if ($LASTEXITCODE)
    {
        throw "Failed"
    }
    msbuild Main.sln /v:q /m /nologo
    if ($LASTEXITCODE)
    {
        throw "Failed"
    }
    Write-Host -ForegroundColor Green "done."
}

function RemoveFilesFromProject($ProjectXml, $ProjectPath, $SharedSourceFiles, $FilesToRemove)
{
    $nsmgr = [Xml.XmlNamespaceManager]::New($ProjectXml.NameTable)
    $nsmgr.AddNamespace('a', "http://schemas.microsoft.com/developer/msbuild/2003")

    $FilesToRemove = $FilesToRemove | Where-Object { $_ } | ForEach-Object {
        Push-Location "$ProjectPath\.."
        $CompileInclude = Resolve-Path $_ -Relative
        $FullPath = (Get-Item $CompileInclude).FullName
        Pop-Location
        if ($CompileInclude.StartsWith('.\'))
        {
            $CompileInclude = $CompileInclude.Substring(2)
        }

        $node = $ProjectXml.SelectNodes("/a:Project/a:ItemGroup/a:Compile[@Include='$CompileInclude']", $nsmgr)
        if (!$node -or !$node[0])
        {
            throw "Failed to locate the compile XML node for $CompileInclude in $ProjectPath"
        }
        if ($node.Count -gt 1)
        {
            throw "Found more than one compile XML node for $CompileInclude in $ProjectPath"
        }
        $null = $node[0].ParentNode.RemoveChild($node[0])
        if ($SharedSourceFiles[$FullPath])
        {
            --$SharedSourceFiles[$FullPath]
        }
        $FullPath
    }

    if ($FilesToRemove)
    {
        $ProjectXml.Save($ProjectPath)

        Push-Location "$ProjectPath\.."
        Remove-Item $($FilesToRemove | Where-Object { !$SharedSourceFiles[$_] })
        Pop-Location
        $true
    }
}

function RemoveFailingFilesFromProject($ProjectXml, $ProjectPath, $SharedSourceFiles)
{
    $FilesToRemove = (Get-Content c:\temp\errors.txt) -replace '\(.+', '' | Sort-Object -Unique

    RemoveFilesFromProject $ProjectXml $ProjectPath SharedSourceFiles $FilesToRemove
}

function AdjustProject($SolutionName, $Solution, $BuildProjectName, $SharedSourceFiles)
{
    $BuildTarget = $BuildProjectName.Replace('.', '_')
    $BuildProjectPath = $Solution.Projects | Where-Object { [io.path]::GetFileNameWithoutExtension($_) -eq $BuildProjectName }
    if (!$BuildProjectPath)
    {
        throw "Failed to locate the path to the project $BuildProjectName in $SolutionName.sln"
    }
    if ($BuildProjectPath -is [array])
    {
        throw "$BuildProjectName in $SolutionName.sln maps to more than one path - $BuildProjectPath"
    }

    $xml = [xml](Get-Content $BuildProjectPath)                

    $i = 0
    do
    {
        ++$i
        Write-Host -NoNewline "$BuildProjectName $i                                         `r"
        $null = msbuild ".\$SolutionName.sln" /t:$BuildTarget /noconlog /nologo /fl1 "/flp1:logfile=c:\temp\errors.txt;errorsonly" /fl2 "/flp2:logfile=c:\temp\warnings.txt;warningsonly"
        Get-Content c:\temp\warnings.txt
        $Cont = RemoveFailingFilesFromProject $xml $BuildProjectPath $SharedSourceFiles
    } while ($Cont)
}

Set-Location c:\dayforce\exp
git reset --hard HEAD

$SolutionMap = @{
    DataSvc = [PSCustomObject]@{
        Projects   = Get-ProjectsInSolution "DataSvc.sln"
        BuildOrder = Get-Content "C:\temp\exp\DataSvc_Projects.txt"
    }
    Main    = [PSCustomObject]@{
        Projects   = Get-ProjectsInSolution "Main.sln"
        BuildOrder = Get-Content "C:\temp\exp\Main_Projects.txt"
    }
}

$SharedSourceFiles = & "$PSScriptRoot\MapSharedSourceCode.ps1" DataSvc

$SharedSourceFiles.Solutions | ForEach-Object {
    $SolutionName = $_

    $SolutionMap[$SolutionName].BuildOrder | ForEach-Object {
        $ProjectName = $_
    
        if ($ProjectName -eq 'DfVersioning')
        {
            return
        }

        Write-Host -ForegroundColor Green "Attempting to remove all the source files from $ProjectName in $SolutionName"

        InitialBuild
        pskill msbuild

        if ($SharedSourceFiles.Shared.Count)
        {
            $SharedBackup = [hashtable]::New($SharedSourceFiles.Shared)
        }
        else
        {
            $SharedBackup = $SharedSourceFiles.Shared
        }

        $ProjectPath = $SolutionMap[$SolutionName].Projects | Where-Object { [io.path]::GetFileNameWithoutExtension($_) -eq $ProjectName }
        $FilesToRemove = Get-FilesInDotNetProject $ProjectPath
        $ProjectXml = [xml](Get-Content $ProjectPath)
        $null = RemoveFilesFromProject $ProjectXml $ProjectPath $SharedSourceFiles.Shared $FilesToRemove

        $SharedSourceFiles.Solutions | ForEach-Object {
            $CurSolutionName = $_
            $CurSolution = $SolutionMap[$CurSolutionName]

            $CurSolution.BuildOrder | ForEach-Object {
                $CurProjectName = $_

                AdjustProject $CurSolutionName $CurSolution $CurProjectName $SharedSourceFiles.Shared
            }
        }

        try
        {
            & "$PSScriptRoot\ReproduceBug" @{ } { } { 
                "Removed all the source files from $ProjectName in $SolutionName" 
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