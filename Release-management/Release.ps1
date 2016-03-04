# Powershell release script for bumping package.json and bower.json
# Building a web project (simple) task. 
# Then pushing the correct tags to git. 
# Harald S. Fianbakken <harald.fianbakken@gmail.com>
param(
    [Parameter(Mandatory=$true,ParameterSetname='default')]
    [ValidateSet("major","minor","patch")]
     $releaseType,
     [Parameter(ParameterSetname='default')]
     [switch]$dry,
     [Parameter(ParameterSetname='help')]
     [switch]$help);
Set-StrictMode -Version latest
$scriptFile=$MyInvocation.MyCommand.Name;

function Bump-Version($file, $releaseType, [switch]$dry){
    if(-not (Test-Path $file)){
        Write-Error "Invalid file";
        throw "File $file does not exist or cannot be opened";
    }
    
    $fileJson = (Get-Content $file -raw|ConvertFrom-Json);
    $versions = $fileJson.version -split '\.';    
    
    while($versions.length -lt 3){
        $versions += 0;    
    }
    switch ($releaseType) {
        "major" {
            $versions[0]=[int]::Parse($versions[0])+1;
            $versions[1] = 0;
            $versions[2] = 0;
        }
        "minor" {
            $versions[1]=[int]::Parse($versions[1])+1;
            $versions[2] = 0;
        }
        "patch" {
            $versions[2]=[int]::Parse($versions[2])+1;
        }
        default {
            Write-Error "Invalid releaseType $releaseType";
            throw "Invalid releasetype $releaseType";
        }        
    }

    $fileJson.version = $versions -join '.';
    if($dry -and $dry.IsPresent){
        Write-Debug "Dry run - not bumping version "
    } else {
        Write-Verbose "Bumping version in file $file";
        $fileJson|ConvertTo-Json|Set-Content -Path $file;    
    }
    
    return $fileJson.version;
}


function Invoke-safe($cmd){    
    Write-Verbose "Invoking command $cmd";
    Invoke-Expression $cmd;    
    if(-not $?){
        Write-Error ("Error {0} when executing $cmd" -f $?, $cmd);        
        exit $LASTEXITCODE;
    }
}

function Print-Usage(){
    Write-Host ("Help: {0} -ReleaseType [major|minor|patch] [-help] [-dry] [-Verbose] [-Debug]" -f $scriptFile)    
    Write-Host "If -try is specified, will not update anything";
}

if($help -and $help.IsPresent){
    Print-Usage;
    exit 0;
}

function Build-WebProject (){    
    Write-Verbose "Building web project";
    Invoke-safe -cmd "npm install"
    Invoke-safe -cmd "bower install"
    Invoke-safe -cmd "gulp"
}

function Commit-Changes($version,[switch]$dry){
    Write-Verbose "Committing changes to git for new version $version";
    $dryCmd = "";
    if($dry -and $dry.IsPresent){
        $dryCmd = "--dry-run";
    }
    Invoke-safe -cmd "git commit -a $drycmd -m 'Release v$version'"
    if($dry -and $dry.IsPresent){
        Write-debug  "Script finished; dry run complete!";
    } else {
        Write-debug "Script updating and releasing $version"
        Invoke-safe -cmd "git tag -a v$version -m '$version'"
        Invoke-safe -cmd "git push"
        Invoke-safe -cmd "git push --tags"
    }
}

$packageVersion = Bump-Version -file ".\package.json" -releaseType $releaseType -dry $dry;
$bowerVersion = Bump-Version -file ".\bower.json" -releaseType $releaseType -dry $dry;
Build-WebProject;

Commit-Changes -version $bowerVersion -dry $dry;
