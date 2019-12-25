param($SolutionName, $ProjectName)

. "$PSScriptRoot\Functions.ps1"

if ($SolutionName)
{
    $Solutions = $SolutionName
}
else
{
    $Solutions = $SolutionMap.Keys
}

$InitBuild = $true

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
    
        Write-Host -ForegroundColor Green "Attempting to nullify all the source files from $ProjectName in $SolutionName"

        if ($InitBuild)
        {
            pskill msbuild
            InitialBuild
            $InitBuild = $false
        }
        
        $ProjectPath = GetProjectPath $SolutionName $ProjectName
        $FilesToNullify = $(Get-FilesInDotNetProject $ProjectPath)
        $j = 0
        $FilesToNullify | ForEach-Object {
            ++$j
            $FileToNullify = $_

            Write-Host -NoNewline -ForegroundColor Green "[$j/$($FilesToNullify.Count)] $FileToNullify                                                 `r"

            $count = & $CodeTool 'nullify-file' -i $FileToNullify
            if ($count -eq 0)
            {
                return
            }

            Write-Host -ForegroundColor Green "[$j/$($FilesToNullify.Count)] Nullified $FileToNullify from $ProjectName ..."

            $SolutionMap.Keys | ForEach-Object {
                $CurSolutionName = $_
                $CurSolution = $SolutionMap[$CurSolutionName]

                $CurSolution.BuildOrder | ForEach-Object {
                    $CurProjectName = $_

                    AdjustProject2 $CurSolutionName $CurSolution $CurProjectName
                }
            }

            try
            {
                & "$PSScriptRoot\ReproduceBug" @{ } { } { 
                    "Nullified $FileToNullify from $ProjectName in $SolutionName" 
                } -NoReset
            }
            catch
            {
                $InitBuild = $true
                Write-Host -ForegroundColor Red $_.Exception.Message
                git reset --hard HEAD
                if ($LASTEXITCODE)
                {
                    throw "git reset --hard HEAD returned exit code $LastExitCode"
                }
            }
        }
    }
    $ProjectName = $null
}
Write-Host ""