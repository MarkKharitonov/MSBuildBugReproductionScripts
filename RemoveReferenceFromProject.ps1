param([Parameter(Mandatory)]$SolutionName)

function ParseSourceProject($SourceProjectPath, $BuildOrder)
{
    $SourceProjectPath = (Get-Item $SourceProjectPath).FullName
    $xml = [xml](Get-Content $SourceProjectPath)
    $nsmgr = [Xml.XmlNamespaceManager]::New($xml.NameTable)
    $nsmgr.AddNamespace('a', "http://schemas.microsoft.com/developer/msbuild/2003")

    $DllReferences = $xml.Project.ItemGroup.Reference | Where-Object { 
        $_.HintPath -and $_.HintPath -notmatch '(packages|Dependencies)' 
    } | ForEach-Object {
        $ProjectPath = [io.Path]::GetFullPath([io.Path]::Combine("$SourceProjectPath\..", "$($_.HintPath -replace '\$\(Configuration\)','Debug')\.."))
        $ProjectPath = $ProjectPath -replace '\\Debug', '' -replace '\\bin', ''
        $ProjectPath = (Get-Item "$ProjectPath\*.csproj").FullName
        [PSCustomObject]@{
            Element     = 'Reference'
            RawValue    = $_.Include
            ProjectPath = $ProjectPath
        }
    }

    $ProjectReferences = $xml.Project.ItemGroup.ProjectReference | Where-Object { $_ } | ForEach-Object {
        $ProjectPath = [io.Path]::GetFullPath([io.Path]::Combine("$SourceProjectPath\..", $_.Include))
        [PSCustomObject]@{
            Element     = 'ProjectReference'
            RawValue    = $_.Include
            ProjectPath = $ProjectPath
        }
    }

    @{
        Path             = $SourceProjectPath
        Name             = [io.path]::GetFileNameWithoutExtension($SourceProjectPath)
        Xml              = $xml
        XmlNsMgr         = $nsmgr
        ProjectsToRemove = $DllReferences, $ProjectReferences | ForEach-Object { $_ } | ForEach-Object {
            $ProjectName = [io.path]::GetFileNameWithoutExtension($_.ProjectPath)
            $_ | Add-Member @{
                ProjectName = $ProjectName
                Index       = $BuildOrder.IndexOf($ProjectName)
            }
            $_
        } | Sort-Object -Descending Index | Where-Object { $_.ProjectName -ne 'DfVersioning' }
    }
}

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

function DoRemoveReference($SourceProject, $ProjectToRemove)
{
    $RawValue = $ProjectToRemove.RawValue
    $Element = $ProjectToRemove.Element
    $node = $SourceProject.Xml.SelectNodes("/a:Project/a:ItemGroup/a:$Element[@Include='$RawValue']", $SourceProject.XmlNsMgr)
    if (!$node)
    {
        throw "Failed to locate the reference XML node for $RawValue"
    }
    if ($node.Count -gt 1)
    {
        throw "Found more than one reference XML node for $RawValue"
    }
    $null = $node[0].ParentNode.RemoveChild($node[0])
    $SourceProject.Xml.Save($SourceProject.Path)
}

function RemoveFailingFilesFromProject($ProjectXml, $nsmgr, $ProjectPath, $SourceFiles)
{
    $FilesToRemove = (Get-Content c:\temp\errors.txt) -replace '\(.+', '' | Sort-Object -Unique
    $FilesToRemove = $FilesToRemove | ForEach-Object {
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
        if ($SourceFiles[$FullPath])
        {
            --$SourceFiles[$FullPath]
            if (!$SourceFiles[$FullPath])
            {
                $SourceFiles.Remove($FullPath)
            }
        }
        $FullPath
    }

    if ($FilesToRemove)
    {
        $ProjectXml.Save($ProjectPath)

        Push-Location "$ProjectPath\.."
        Remove-Item $($FilesToRemove | Where-Object { !$SourceFiles[$_] })
        Pop-Location
        $true
    }
}

function RemoveReference($SourceProject, $ProjectToRemove, $Solutions, $SolutionMap, $SourceFiles)
{
    $ProjectName = $ProjectToRemove.ProjectName
    Write-Host -ForegroundColor Green "Remove $ProjectName from $($SourceProject.Name)"

    DoRemoveReference $SourceProject $ProjectToRemove

    $Start = $false
    $Solutions | ForEach-Object {
        $SolutionName = $_
        $Solution = $SolutionMap[$SolutionName]

        $Solution.BuildOrder | Where-Object {
            if ($Start)
            {
                $true
            }
            elseif ($_ -eq $SourceProject.Name)
            {
                $Start = $true
                $true
            }
        } | ForEach-Object {
            $BuildProjectName = $_
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

            if ($BuildProjectPath -eq $SourceProject.Path)
            {
                $xml = $SourceProject.Xml
            }
            else
            {
                $xml = [xml](Get-Content $BuildProjectPath)                
            }

            $i = 0
            do
            {
                ++$i
                Write-Host -NoNewline "$BuildProjectName $i                                         `r"
                $null = msbuild ".\$SolutionName.sln" /t:$BuildTarget /noconlog /nologo /fl1 "/flp1:logfile=c:\temp\errors.txt;errorsonly" /fl2 "/flp2:logfile=c:\temp\warnings.txt;warningsonly"
                Get-Content c:\temp\warnings.txt
                $Cont = RemoveFailingFilesFromProject $xml $SourceProject.XmlNsMgr $BuildProjectPath $SourceFiles
            } while ($Cont)
        }
    }
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

$Projects = $SolutionMap[$SolutionName].BuildOrder | ForEach-Object { $_ }
[Array]::Reverse($Projects)

$SourceFiles = & "$PSScriptRoot\MapSharedSourceCode.ps1" $SolutionName

$Projects | ForEach-Object {
    $SourceProjectName = $_
    $SourceProjectPath = $SolutionMap[$SolutionName].Projects | Where-Object { [io.path]::GetFileNameWithoutExtension($_) -eq $SourceProjectName }

    $SourceProject = ParseSourceProject $SourceProjectPath $SolutionMap[$SolutionName].BuildOrder
    if (!$SourceProject.ProjectsToRemove)
    {
        return 'Done'
    }

    $SourceProject.ProjectsToRemove | ForEach-Object {

        $ProjectName = $_.ProjectName

        InitialBuild
        pskill msbuild

        if ($SourceFiles.Shared.Count)
        {
            $SharedBackup = [hashtable]::New($SourceFiles.Shared)
        }
        else
        {
            $SharedBackup = $SourceFiles.Shared
        }
        RemoveReference $SourceProject $_ $SourceFiles.Solutions $SolutionMap $SourceFiles.Shared
 
        try
        {
            & "$PSScriptRoot\ReproduceBug" @{ } { } { 
                "Removed $ProjectName from $($SourceProject.Name)" 
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