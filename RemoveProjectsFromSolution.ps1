param([Parameter(Mandatory)][ValidateScript({ Test-Path $_ -PathType Leaf })]$Solution)

$SolutionName = (Get-Item $Solution).BaseName
$ProjectsFilePath = "c:\Temp\exp\${SolutionName}_Projects.txt"
$ProjectNames = Get-Content $ProjectsFilePath
[Array]::Reverse($ProjectNames)

Set-Location "$Solution\.."
git reset --hard HEAD

$SharedSource = (& "$PSScriptRoot\MapSharedSourceCode.ps1" $SolutionName -All).Shared
$ctx = @{ }

$ProjectNames | ForEach-Object {
    $ProjectName = $_

    & "$PSScriptRoot\ReproduceBug" $ctx {
        Write-Host -ForegroundColor Green $ProjectName

        $res = & "$PSScriptRoot\RemoveProjectFromSolution.ps1" $Solution $ProjectName
        if ($res -eq 'NotFound')
        {
            $ctx.Skip = $true
        }
        else
        {
            $ProjectFile = (git diff -U0 -- $Solution | Select-String '^-Project') -replace '^.+"([^"]+\.csproj)",.+$', '$1'
            $ProjectDir = (Get-Item $ProjectFile).Directory.FullName + "\"
            $ProjectCompileFiles = Get-FilesInDotNetProject $ProjectFile
            $Shared = $ProjectCompileFiles | Where-Object {
                $SharedSource[$_] -gt 1
            } | ForEach-Object {
                --$SharedSource[$_]
                $_
            }
            $Shared2 = $SharedSource.Keys | Where-Object {
                $_.StartsWith($ProjectDir, 'OrdinalIgnoreCase') -and ($ProjectCompileFiles -notcontains $_)
            }

            if ($Shared -or $Shared2)
            {
                $AllFilesExceptShared = Get-ChildItem -r "$ProjectFile\.." -File | Where-Object {
                    ($Shared -notcontains $_.FullName) -and ($Shared2 -notcontains $_.FullName)
                }
                if ($AllFilesExceptShared)
                {
                    Remove-Item $AllFilesExceptShared.FullName
                }
            }
            else
            {
                Remove-Item -r "$ProjectFile\.."
            }
        }
    } { 
        Set-Content $ProjectsFilePath $((Get-Content $ProjectsFilePath) -ne $ProjectName)
        "Removed $ProjectName from $SolutionName" 
    } 
}