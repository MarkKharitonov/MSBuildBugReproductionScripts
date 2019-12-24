param([switch]$NoBuild)
. "$PSScriptRoot\Functions.ps1"

$Files = @{
    "$pwd\NuGet.Config"                             = $true
    "$pwd\.nuget\nuget.targets"                     = $true
    "$pwd\Services\Platform\Common\FodyWeavers.xml" = $true
}
Get-Item .git* | ForEach-Object {
    $Files[$_.FullName] = $true
}
$SolutionMap.Keys | ForEach-Object {
    $SolutionName = $_

    (Get-Item "$SolutionName.sln", "before.$SolutionName.sln.targets").FullName
    $SolutionMap[$SolutionName].Projects | ForEach-Object {
        $ProjectPath = $_

        $xml = [xml](Get-Content $ProjectPath)
        $nsmgr = [Xml.XmlNamespaceManager]::New($xml.NameTable)
        $nsmgr.AddNamespace('a', "http://schemas.microsoft.com/developer/msbuild/2003")

        $xml.SelectNodes("/a:Project/a:ItemGroup/*[not(self::a:Compile|self::a:Reference|self::a:ProjectReference)][not(@Include='packages.config')]", $nsmgr) | Where-Object {
            $_
        } | ForEach-Object {
            $_.ParentNode.RemoveChild($_) > $null
        }
        $xml.Save($ProjectPath)
        Get-FilesInDotNetProject $ProjectPath
        Get-FilesInDotNetProject $ProjectPath None
        ($xml.Project.ItemGroup.Reference.HintPath | Select-String '\\Dependencies\\') -replace '.*(\\Dependencies)', "$pwd`$1"
        $ProjectPath
    }
} | ForEach-Object {
    $Files[$_] = $true
}
Remove-Item (Get-ChildItem -Recurse -File | Where-Object {
        !$Files[$_.FullName]
    }).FullName

$MinLength = $pwd.Path.Length + 1
$DirsWithFiles = @{ }
$Files.Keys | ForEach-Object {
    $Path = $_
    while ($Path.Length -gt $MinLength)
    {
        $Path = [io.path]::GetDirectoryName($Path)
        $DirsWithFiles[$Path] = $true
    }
}

Remove-Item -Recurse (Get-ChildItem -Recurse | Where-Object { 
        ($_.Attributes -eq 'Directory') -and !($DirsWithFiles[$_.FullName])
    }).FullName -ErrorAction SilentlyContinue

if (!$NoBuild)
{
    & "$PSScriptRoot\ReproduceBug.ps1" @{ } { } { 
        "Removed all the redundant files"
    } -NoReset
}