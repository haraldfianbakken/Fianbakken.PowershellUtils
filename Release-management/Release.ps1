# Powershell release script for bumping package.json and bower.json
# Builds a web project (simple) task using npm, bower and gulp . 
# Pushes the correct tags to git.
# Then assembles a package and uploads the web-package to artifactory with the right version
# Harald S. Fianbakken <harald.fianbakken@gmail.com>

param(
    [Parameter(Mandatory=$true,ParameterSetname='default')]
    [ValidateSet("major","minor","patch")]
     $releaseType,
    [Parameter(Mandatory=$true,ParameterSetname='default')]
     $workingDirectory,
     [Parameter(ParameterSetname='default')]
     [switch]$dry,
     [Parameter(ParameterSetname='default')]
     [switch]$skipBuild,
     [Parameter(ParameterSetname='help')]
     [switch]$help);
Set-StrictMode -Version latest

$scriptFile=$MyInvocation.MyCommand.Name;
$artifactoryBowerUri = "https://foo-bar.com/bower";
$deploymentCredentials = @{
        "Username"="__INSERT_USERNAME_ARTIFACTORY__";
        "Password" = "__INSERT_PASSWORD_HERE";
};

# This will make Write-tar mess up the path if your username has an alias in it (e.g. domain~1user1)
$tempFolder = Join-path $env:TEMP "bower-release";
# If you have issues with write-tar (packaging your web-app), use this instead 
# $tempFolder = Join-path "C:\temp\" "bower-release";

if($workingDirectory){
    Write-Verbose "Working folder $workingDirectory";
    ïf(Test-Path $workingDirectory){
        Push-Location $workingDirectory;
    } else {
        Write-Error "$workingDirectory does not exist";
        throw "$workingDirectory does not exist!";
    }
}
Write-verbose "Assemblying folder $tempFolder";

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
    
    return $fileJson;
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

function Clean-WebProject(){    
    Clean-BowerAndNodeModules;

    if((Get-Command rimraf)){
        Write-Verbose "Cleaning WebProject Dist folder";
        rimraf .\dist                 
    } else {
        Write-Verbose "Cleaning WebProject Dist folder";
        Remove-Item -Force .\dist -Recurse
        Write-Verbose "Cleaning bower components";
        Remove-Item -Force .\bower_components -Recurse
        Write-Verbose "Cleaning node modules";
        Remove-Item -Force .\node_modules -Recurse
    }
}

function Clean-BowerAndNodeModules(){
   if((Get-Command rimraf)){        
        Write-Verbose "Cleaning bower components";
        rimraf .\bower_components 
        Write-Verbose "Cleaning node modules";
        rimraf .\node_modules 
    } else {        
        Write-Verbose "Cleaning bower components";
        rm -Force .\bower_components -Recurse
        Write-Verbose "Cleaning node modules";
        rm -Force .\node_modules -Recurse
    }
}


function Build-WebProject([Parameter(Mandatory=$true)]$projectName, [Parameter(Mandatory=$true)]$version,[switch]$packageOnly){    
 
    if(-not $packageOnly -or -not $packageOnly.IsPresent){
        Clean-WebProject;
        Write-Verbose "Building web project";
        Invoke-safe -cmd "npm install" | Out-Null
        Invoke-safe -cmd "bower install" | Out-Null
        Invoke-safe -cmd "gulp" | Out-Null
    }
    # Clean if existing
    if(Test-Path $tempFolder){
        Remove-Item $tempFolder -Force -Recurse | Out-Null;
        New-Item -ItemType Directory -Path $tempFolder -Force|Out-Null ;
    } else {
       New-Item -ItemType Directory -Path $tempFolder -Force |Out-Null;
    }
    
    Copy-item * $tempFolder -Exclude @("bower_Components", "node_modules", ".git", ".idea") -Force -Recurse|Out-Null ;
    
    if($?){
        Write-Verbose "Packaging webproject for deployment";        
        $destination = (Join-Path "dist" "$($projectname)-v$($version).tar");
        $destinationZip = "$($destination).gz";
        if(-not (Test-Path (Split-Path $destination))){
            New-Item -ItemType Directory -Force (Split-Path $destination) | Out-Null;
        }

        $Source = $tempFolder;
        Write-Verbose "Creating zip from $source to $destination";        
        
        if(Test-Path $destination){
            Write-Verbose "Removing file $destination";
            Remove-Item -Force $destination;
        }

        if((Get-Command Write-Tar)){            
            Write-Verbose "Using PSCX Zip method!";
            Get-ChildItem -Recurse -Path $tempfolder -Exclude @(".git", ".idea")| write-tar -outputpath $destination -EntryPathRoot $tempFolder|out-null;
            Get-ChildItem $destination|write-gzip -OutputPath $destinationZip -EntryPathRoot "dist\" -Level 9 |out-null;            
            $item = $destinationZip;
            if($?){
                return (Get-ChildItem $item);
            }   
        } elseif((Get-Command Compress-Archive)){
            Write-verbose "Using PowerShell5 zip method";
            Compress-Archive -Path $Source -CompressionLevel NoCompression -DestinationPath $destination;

            Write-Warning -Message "This file cannot be used with bower unless it has installed support for standard zip compression";
            Write-Warning "You might want to consider packing your $Source manually then running Deploy (e.g. 7zip)"; 
            if($?){
                $item = Move-Item $destination $destinationZip -PassThru;
                return $item; 
            } else {
                Write-Error "Unable to create ZIP $destination";
                throw "Unable to create ZIP $destination";
            }            
        } 
        else {
            Write-Error "Unable to find compression method - Consider installing pscx? Install-module PSCX";
            throw "Cannot create zip/tar.gz of $Source";
        }
        

    } else {
        Write-Error "Build failed with $LASTEXITCODE";
        throw "Build failed";
    }
}

function Deploy-BowerPackage-To-Artifactory(
[Parameter(Mandatory=$true)]$deploycredentials,
[Parameter(Mandatory=$true)]$package,
[Parameter(Mandatory=$true)]$artifactname,
[Parameter(Mandatory=$true)]$file
){    
    $url = "$($artifactoryBowerUri)/$($package)/$($artifactname)"
    $cred = [pscredential]::new($deploycredentials.Username, ($deploycredentials.Password | ConvertTo-SecureString -AsPlainText -Force));
    Write-Verbose "Deploying $package with artifactname $artifactname - using file $file to $url";
    Invoke-WebRequest -Credential $cred -Method PUT -Uri $url -InFile $file.Fullname -ContentType "multipart/form-data";
}

function Remove-BowerPackage-From-Artifactory(
[Parameter(Mandatory=$true)]$deploycredentials,
[Parameter(Mandatory=$true)]$package,
[Parameter(Mandatory=$true)]$artifactname
){    
    $url = "$($artifactoryBowerUri)/$($package)/$($artifactname)"
    $cred = [pscredential]::new($deploycredentials.Username, ($deploycredentials.Password | ConvertTo-SecureString -AsPlainText -Force));
    Write-Verbose "Removing $package with artifactname $artifactname - Using url $url";
    Invoke-WebRequest -Credential $cred -Method DELETE -Uri $url;
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
        Write-debug "Script updating and releasing $version";
        Invoke-safe -cmd "git tag -a v$version -m '$version'";
        Invoke-safe -cmd "git push";
        Invoke-safe -cmd "git push --tags";
    }
}

if($dry -and $dry.IsPresent){
    $package = Bump-Version -file ".\package.json" -releaseType $releaseType -dry $dry;
    $bower = Bump-Version -file ".\bower.json" -releaseType $releaseType -dry $dry;
} else {
    $package = Bump-Version -file ".\package.json" -releaseType $releaseType;
    $bower = Bump-Version -file ".\bower.json" -releaseType $releaseType;
}

if($dry -and $dry.IsPresent){
    Write-Verbose "Running with -dry, skipping build";
} elseif($skipBuild -and $skipBuild.IsPresent){
   Write-Verbose "Skipping build";
}
 else {
    $deployment = Build-WebProject -projectName $bower.name -version $bower.version;    
    if($?){
        $artifactName = $bower.name;        
        Deploy-BowerPackage-To-Artifactory -deploycredentials $deploymentCredentials -package $bower.name -artifactname $deployment.Name -file $deployment;
    }
}

if($dry -and $dry.IsPresent){
    Commit-Changes -version $bower.version -dry $dry;
} else {
    Commit-Changes -version $bower.version;
}

if($workingDirectory){
    Pop-Location;
}