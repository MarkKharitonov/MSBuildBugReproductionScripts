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
    
        Write-Host -ForegroundColor Green "Attempting to remove all the functions from $ProjectName in $SolutionName"
        
        $ProjectPath = GetProjectPath $SolutionName $ProjectName
        $FilesToNullify = $(Get-FilesInDotNetProject $ProjectPath)
        $j = 0
        $FilesToNullify | ForEach-Object {
            ++$j
            $FileToNullify = $_

            Write-Host -NoNewline -ForegroundColor Green "[$j/$($FilesToNullify.Count)] $FileToNullify                                                 `r"

            $funcs = & $CodeTool 'get-functions' -i $FileToNullify --all
            if ($funcs -eq '{}')
            {
                return
            }

            Write-Host -ForegroundColor Green "[$j/$($FilesToNullify.Count)] Removing functions in $FileToNullify from $ProjectName ..."

            ($funcs | ConvertFrom-Json).PSObject.Properties | ForEach-Object {
                $ClassCount = $_.Value.PSObject.Properties.Count
                $k = 0
                
                $_.Value.PSObject.Properties | ForEach-Object {
                    $ClassName = $_.Name
                    ++$k

                    $FuncCount = $_.Value.Count
                    $n = 0

                    $_.Value | Sort-Object @{
                        Expression = {
                            $_ -replace 'set:', '____'
                        }
                    } | ForEach-Object {
                        $FuncName = $_
                        ++$n

                        Write-Host -ForegroundColor Green "[$n/$FuncCount/$k/$ClassCount/$j/$($FilesToNullify.Count)] Removing $ClassName.$FuncName in $FileToNullify from $ProjectName ..."
                        $count = & $CodeTool 'remove-function' -i $FileToNullify -c $ClassName -f $FuncName
                        if ($count -ne 1)
                        {
                            throw "Failed to locate the function $ClassName.$FuncName in $FileToNullify from $ProjectName"
                        }

                        try
                        {
                            $SolutionMap.Keys | ForEach-Object {
                                $CurSolutionName = $_
                                $CurSolution = $SolutionMap[$CurSolutionName]

                                $CurSolution.BuildOrder | ForEach-Object {
                                    $CurProjectName = $_

                                    AdjustProject2 $CurSolutionName $CurSolution $CurProjectName
                                }
                            }

                            & "$PSScriptRoot\ReproduceBug" @{ } { } { 
                                "Removed function $ClassName.$FuncName in $FileToNullify from $ProjectName in $SolutionName" 
                            } -NoReset
                        }
                        catch
                        {
                            Write-Host -ForegroundColor Red $_.Exception.Message
                            git reset --hard HEAD
                            if ($LASTEXITCODE)
                            {
                                throw "git reset --hard HEAD returned exit code $LastExitCode"
                            }
                        }
                    }
                }
            }
        }
    }
    $ProjectName = $null
}
Write-Host ""