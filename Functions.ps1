Set-Location c:\dayforce\exp
pskill msbuild
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

function GetProjectPath($SolutionName, $ProjectName)
{
    $ProjectPath = $SolutionMap[$SolutionName].Projects | Where-Object { 
        [io.path]::GetFileNameWithoutExtension($_) -eq $ProjectName
    }
    if (!$ProjectPath)
    {
        throw "The project $ProjectName is not found in the solution $SolutionName"
    }
    $ProjectPath
}

function BackupSharedSourceFiles($Shared)
{
    if ($Shared.Count)
    {
        $Shared = [hashtable]::New($Shared)
    }
    $Shared
}

function InitialBuild()
{
    Write-Host -NoNewline -ForegroundColor Green "Building ... "
    msbuild DataSvc.sln /err /v:q /m /nologo '/nowarn:CS2008;CS8021'
    if ($LASTEXITCODE)
    {
        throw "Failed"
    }
    msbuild Main.sln /err /v:q /m /nologo '/nowarn:CS2008;CS8021'
    if ($LASTEXITCODE)
    {
        throw "Failed"
    }
    Write-Host -ForegroundColor Green "done."
}

function RemoveFilesFromProject($ProjectXml, $ProjectPath, $SharedSourceFiles, $FilesToRemove, [switch]$MayNotExist)
{
    $nsmgr = [Xml.XmlNamespaceManager]::New($ProjectXml.NameTable)
    $nsmgr.AddNamespace('a', "http://schemas.microsoft.com/developer/msbuild/2003")

    $FilesToRemove = $FilesToRemove | Where-Object { $_ } | ForEach-Object {
        Push-Location "$ProjectPath\.."
        try
        {
            if (!(Test-Path $_) -and $MayNotExist)
            {
                return
            }
            $CompileInclude = Resolve-Path $_ -Relative
            $FullPath = (Get-Item $CompileInclude).FullName
        }
        finally
        {
            Pop-Location
        }
        if ($CompileInclude.StartsWith('.\'))
        {
            $CompileInclude = $CompileInclude.Substring(2)
        }

        $node = $ProjectXml.SelectNodes("/a:Project/a:ItemGroup/a:Compile[@Include='$CompileInclude']", $nsmgr)
        if (!$node -or !$node[0])
        {
            if ($MayNotExist)
            {
                return
            }
            throw "Failed to locate the compile XML node for $CompileInclude in $ProjectPath"
        }
        elseif ($node.Count -gt 1)
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
        try
        {
            Remove-Item $($FilesToRemove | Where-Object { !$SharedSourceFiles[$_] })
        }
        finally
        {
            Pop-Location
        }
        $true
    }
}

function RemoveFailingFilesFromProject($ProjectXml, $ProjectPath, $SharedSourceFiles)
{
    $FilesToRemove = (Get-Content c:\temp\errors.txt) -replace '\(.+', '' | Sort-Object -Unique

    RemoveFilesFromProject $ProjectXml $ProjectPath $SharedSourceFiles $FilesToRemove
}

function AdjustProject($SolutionName, $Solution, $BuildProjectName, $SharedSourceFiles, $SourceProject)
{
    $BuildTarget = $BuildProjectName.Replace('.', '_')

    if ($SourceProject.Name -eq $BuildProjectName)
    {
        $BuildProjectPath = $SourceProject.Path
        $xml = $SourceProject.Xml
    }
    else
    {
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
    }

    $i = 0
    do
    {
        ++$i
        Write-Host -NoNewline "$BuildProjectName $i                                         `r"
        $null = msbuild ".\$SolutionName.sln" /t:$BuildTarget /noconlog /nologo '/nowarn:CS2008;CS8021' /fl1 "/flp1:logfile=c:\temp\errors.txt;errorsonly" /fl2 "/flp2:logfile=c:\temp\warnings.txt;warningsonly"
        Get-Content c:\temp\warnings.txt
        $Cont = RemoveFailingFilesFromProject $xml $BuildProjectPath $SharedSourceFiles
    } while ($Cont)
}

function ParseProject($SolutionName, $ProjectName)
{
    $ProjectPath = GetProjectPath $SolutionName $ProjectName
    $xml = [xml](Get-Content $ProjectPath)

    $DllReferences = $xml.Project.ItemGroup.Reference | Where-Object { 
        $_.HintPath -and $_.HintPath -notmatch '(packages|Dependencies)' 
    } | ForEach-Object {
        $RefProjectPath = [io.Path]::GetFullPath([io.Path]::Combine("$ProjectPath\..", "$($_.HintPath -replace '\$\(Configuration\)','Debug')\.."))
        $RefProjectPath = $RefProjectPath -replace '\\Debug', '' -replace '\\bin', ''
        $RefProjectPath = (Get-Item "$RefProjectPath\*.csproj").FullName
        [PSCustomObject]@{
            Element     = 'Reference'
            RawValue    = $_.Include
            ProjectPath = $RefProjectPath
        }
    }

    $ProjectReferences = $xml.Project.ItemGroup.ProjectReference | Where-Object { $_ } | ForEach-Object {
        $RefProjectPath = [io.Path]::GetFullPath([io.Path]::Combine("$ProjectPath\..", $_.Include))
        [PSCustomObject]@{
            Element     = 'ProjectReference'
            RawValue    = $_.Include
            ProjectPath = $RefProjectPath
        }
    }

    $BuildOrder = $SolutionMap[$SolutionName].BuildOrder
    
    @{
        Name             = $ProjectName
        Path             = $ProjectPath
        Xml              = $xml
        ProjectsToRemove = $DllReferences, $ProjectReferences | ForEach-Object { $_ } | ForEach-Object {
            $ProjectName = [io.path]::GetFileNameWithoutExtension($_.ProjectPath)
            $_ | Add-Member @{
                ProjectName = $ProjectName
                Index       = $BuildOrder.IndexOf($ProjectName)
            }
            $_
        } | Sort-Object -Descending Index
    }
}
