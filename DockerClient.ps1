﻿#Requires -Version 4.0

if (Test-Path "$PSScriptRoot\DockerClient") {
    Remove-Item -Recurse "$PSScriptRoot\DockerClient"
}


Configuration DockerClient
{

<#
.Synopsis
   Generate a configuration for Docker installation on Ubuntu
.DESCRIPTION
   This configuration ensures that the required components for Docker
   are installed on a specified node. A specified image can also be installed.
.PARAMETER Hostname
   The node on which the Docker configuration should be enacted. Use the built-in
   ConfigurationData parameter rather than the Hostname parameter if this configuration
   should be enacted upon more than one node.
.PARAMETER Image
   Docker image(s) to pull or remove. Pass a string or string array to this parameter
   to pull or or more images. Pass a hashtable or hashtable array to this parameter with
   the following properties to remove one or more images:

      - Name -> Name of image to remove
      - Remove -> Use $true to set image for removal

.PARAMETER Container
   Docker container(s) to run. This parameter requires one or more hashtables with the
   desired options for the container. Valid properties for the hashtable are:

      - Name -> Name to assign container
      - Image -> Image container will use
      - Port -> Port mapping
      - Link -> Name of container to link to
      - Command -> Command to execute in container
      - Remove -> Boolean to indicate whether or not container should be removed

   When using this paramter, your hashtable must define at least the Name and Image properties, unless
   the Remove property is chosen in which case on the Name property needs to be defined. Use of this
   parameter does not require the use of the Image parameter unless you wish to configure a combination
   of containers and images.
.EXAMPLE
   . .\DockerClient.ps1
   DockerClient -Hostname mgmt01.contoso.com

   Generates a .mof for configuring Docker components on mgmt01.contoso.com.
.EXAMPLE
   . .\DockerClient.ps1
   DockerClient -Hostname mgmt01.contoso.com -Image node

   Generates a .mof for configuring Docker components on mgmt01.contoso.com. The
   "node" image will also pulled from the Docker Hub repository.
.EXAMPLE
   . .\DockerClient.ps1
   DockerClient -Hostname mgmt01.contoso.com -Image node -Container @{Name="Hello World";Port=8080;Command='echo "Hello world"'}

   Generates a .mof for configuring Docker components on mgmt01.contoso.com. The
   "node" image will be pulled from the Docker Hub repository if it doesn't already exist.
   A container by the name "Hello World" with the command 'echo "Hello World"' will also be created.
.NOTES
   Ensure that both the OMI and DSC Linux Resource Provider source have been compiled
   and installed on the specified node. Instructions for doing so can be found here:
   https://github.com/MSFTOSSMgmt/WPSDSCLinux.

   Author: Andrew Weiss | Microsoft
           andrew.weiss@microsoft.com
#>

    param
    (
        [Parameter(Position=1)]
        [string]$Hostname,
        [Parameter(Position=2)]
        $Image,
        [Parameter(Position=3)]
        [hashtable[]]$Container
    )

    if (!$PSBoundParameters['Hostname']) {
        if (!$PSBoundParameters['ConfigurationData']) {
            throw "Hostname and/or ConfigurationData must be specified"
        }
    }
    
    # Force user to define name for container so it can be referenced later
    if ($Container) {
        $Container | % {
            if (!$_['Name']) {
                throw "Name property must be defined in the Container hashtable parameter"
            }

            if (!$_['Image']) {
                if (!$_['Remove']) {
                    throw "Image property must be defined in the Container hashtable parameter"
                }
            }
        }
    }


    $OFS = [Environment]::Newline
    
    $installationScripts = Get-ChildItem -Recurse -File -Path "scripts\installation" | % { $_.FullName }
    $installationScripts | % {
        $fileName = [System.IO.Path]::GetFileNameWithoutExtension($_)
        Set-Variable -Name $fileName -Value (Get-Content $_)
    }

    $bashString = "#!/bin/bash`r`n"

    Import-DscResource -Module nx
    
    function getImageBlock {
        param (
            $dockerImage,
            $isRemovable
        )
        
        $imageVarName = $dockerImage.Replace('-', "").Replace(':', "").Replace('/', "")

        if ($isRemovable) {
            if ($dockerImage.Contains(':')) {
                Set-Variable -Scope Script  -Name "get$imageVarName" -Value ($bashString + '[[ $(docker images | grep "' + $dockerImage.Split(':')[0] + '" | awk ''{ print $2 }'') == "' + $dockerImage.Split(':')[1] + '" ]] && exit 1 || exit 0')
                Set-Variable -Scope Script -Name "test$imageVarName" -Value ($bashString + '[[ $(docker images | grep "' + $dockerImage.Split(':')[0] + '" | awk ''{ print $2 }'') == "' + $dockerImage.Split(':')[1] + '" ]] && exit 1 || exit 0')
            } else {
                Set-Variable -Scope Script -Name "get$imageVarName" -Value ($bashString + '[[ $(docker images | grep -c "' + $dockerImage + '") -gt 0 ]] && exit 1 || exit 0')
                Set-Variable -Scope Script -Name "test$imageVarName" -Value ($bashString + '[[ $(docker images | grep -c "' + $dockerImage + '") -gt 0 ]] && exit 1 || exit 0')
            }

            Set-Variable -Scope Script -Name "set$imageVarName" -Value ($bashString + 'docker rmi -f ' + $dockerImage)

$imageBlock = @"
nxScript $imageVarName
{
    GetScript = `$get$imageVarName
    SetScript = `$set$imageVarName
    TestScript = `$test$imageVarName
    DependsOn = "[nxService]DockerService"
}


"@

        } else {
            if ($dockerImage.Contains(':')) {
                Set-Variable -Scope Script  -Name "get$imageVarName" -Value ($bashString + '[[ $(docker images | grep "' + $dockerImage.Split(':')[0] + '" | awk ''{ print $2 }'') == "' + $dockerImage.Split(':')[1] + '" ]] && exit 0 || exit 1')
                Set-Variable -Scope Script -Name "test$imageVarName" -Value ($bashString + '[[ $(docker images | grep "' + $dockerImage.Split(':')[0] + '" | awk ''{ print $2 }'') == "' + $dockerImage.Split(':')[1] + '" ]] && exit 0 || exit 1')
            } else {
                Set-Variable -Scope Script -Name "get$imageVarName" -Value ($bashString + '[[ $(docker images | grep -c "' + $dockerImage + '") -gt 0 ]] && exit 0 || exit 1')
                Set-Variable -Scope Script -Name "test$imageVarName" -Value ($bashString + '[[ $(docker images | grep -c "' + $dockerImage + '") -gt 0 ]] && exit 0 || exit 1')
            }
            Set-Variable -Scope Script -Name "set$imageVarName" -Value ($bashString + 'docker pull ' + $dockerImage + '; exit 0')

$imageBlock = @"
nxScript $imageVarName
{
    GetScript = `$get$imageVarName
    SetScript = `$set$imageVarName
    TestScript = `$test$imageVarName
    DependsOn = @("[nxService]DockerService", "[nxScript]DockerInstallation")
}


"@

        }

        return $imageBlock
    }

    function getContainerBlock {
        param
        (
            $containerName,
            $containerImage,
            $containerPort,
            $containerEnv,
            $containerLink,
            $containerCommand,
            $isRemovable
        )

        if ($isRemovable) {
            Set-Variable -Scope Script -Name "get$containerName" -Value ($bashString + '[[ $(docker ps -a | grep -c "' + $containerName + '") -ge 1 ]] && exit 1 || exit 0')
            Set-Variable -Scope Script -Name "test$containerName" -Value ($bashString + '[[ $(docker ps -a | grep -c "' + $containerName + '") -ge 1 ]] && exit 1 || exit 0')
            Set-Variable -Scope Script -Name "set$containerName" -Value ($bashString + 'docker rm -v -f ' + $containerName)

$containerBlock = @"
nxScript $containerName
{
    GetScript = `$get$containerName
    SetScript = `$set$containerName
    TestScript = `$test$containerName
    DependsOn = "[nxService]DockerService"
}


"@

        } else {
            Set-Variable -Scope Script -Name "get$containerName" -Value ($bashString + '[[ $(docker ps -a | grep -c "' + $containerName + '") -ge 1 ]] && exit 0 || exit 1')
            Set-Variable -Scope Script -Name "test$containerName" -Value ($bashString + '[[ $(docker ps -a | grep -c "' + $containerName + '") -ge 1 ]] && exit 0 || exit 1')

            Set-Variable -Scope Script -Name "set$containerName" -Value ($bashString + '[[ $(docker run -d --name="' + $containerName + '"')
            if ($containerPort) {
                $existing = (Get-Variable -Name "set$containerName").Value
                $existing += ' -p ' + $containerPort
                Set-Variable -Scope Script -Name "set$containerName" -Value $existing
            }

            if ($containerEnv) {
                foreach ($env in $containerEnv) {
                    $existing = (Get-Variable -Name "set$containerName").Value
                    $existing += " -e `"$env`""
                    Set-Variable -Scope Script -Name "set$containerName" -Value $existing
                }
            }
        
            if ($containerLink) {
                $existing = (Get-Variable -Name "set$containerName").Value
                $existing += ' --link ' + $containerLink + ':' + $containerLink
                Set-Variable -Scope Script -Name "set$containerName" -Value $existing
            }
      
            $existing = (Get-Variable -Name "set$containerName").Value
            $existing += ' ' + $containerImage
            Set-Variable -Scope Script -Name "set$containerName" -Value $existing

            if ($containerCommand) {
                $existing = (Get-Variable -Name "set$container").Value
                $existing += ' ' + $containerCommand
                Set-Variable -Scope Script -Name "set$containerName" -Value $existing
            }

            $existing = (Get-Variable -Name "set$containerName").Value
            $existing += ' ) ]] && exit 0 || exit 1'
            Set-Variable -Scope Script -Name "set$containerName" -Value $existing

            $imageVarName = $containerImage.Replace('-', "").Replace(':', "").Replace('/', "")

            if ($requiredImage -notcontains $containerImage) {
                if ($Image -notcontains $containerImage) {
                    $script:imageBlocks += getImageBlock -dockerImage $containerImage
                }

                $requiredImage += $containerImage
            }

$containerBlock = @"
nxScript $containerName
{
    GetScript = `$get$containerName
    SetScript = `$set$containerName
    TestScript = `$test$containerName
    DependsOn = `"[nxScript]$imageVarName`"
}


"@

        }

        return $containerBlock
    }

    [string[]]$script:imageBlocks = @()
    [string[]]$containerBlocks = @()

    # Dynamically create nxScript resource blocks for Docker images
    if ($Image) {
        foreach ($dockerImage in $Image) {
            if ($dockerImage.GetType().Name -eq "Hashtable") {
                $imageName = $dockerImage['Name']
                $isRemovable = $dockerImage['Remove']                       
                $script:imageBlocks += getImageBlock -dockerImage $imageName -isRemovable $isRemovable
            } elseif ($dockerImage.GetType().Name -eq "String") {
                $script:imageBlocks += getImageBlock -dockerImage $dockerImage
            }
        }
    }

    if ($Container) {
        $requiredImage = @()
        foreach ($dockerContainer in $Container) {
            $containerName = $dockerContainer['Name']
            $containerImage = $dockerContainer['Image']
            $containerPort = $dockerContainer['Port']
            $containerEnv = $dockerContainer['Env']
            $containerLink = $dockerContainer['Link']
            $containerCommand = $dockerContainer['Command']
            $isRemovable = $dockerContainer['Remove']

            $containerBlocks += getContainerBlock -containerName $containerName -containerImage $containerImage -containerPort $containerPort -containerEnv $containerEnv -containerLink -$containerLink -isRemovable $isRemovable
        }
    }
       
    if ($PSBoundParameters['Container']) {
        
$dockerConfig = @'
nxScript DockerInstallation
{
    GetScript = "$getDockerClient"
    SetScript = "$setDockerClient"
    TestScript = "$testDockerClient"
}

nxService DockerService
{
    Name = "docker.io"
    Controller = "init"
    Enabled = $true
    State = "Running"
    DependsOn = "[nxScript]DockerInstallation"
}


'@                

        $script:imageBlocks | % { $dockerConfig += $_ }
        $containerBlocks | % { $dockerConfig += $_ }
        $dockerConfig = [scriptblock]::Create($dockerConfig)
    } elseif ($PSBoundParameters['Image']) {

$dockerConfig = @'
nxScript DockerInstallation
{
    GetScript = "$getDockerClient"
    SetScript = "$setDockerClient"
    TestScript = "$testDockerClient"
}

nxService DockerService
{
    Name = "docker.io"
    Controller = "init"
    Enabled = $true
    State = "Running"
    DependsOn = "[nxScript]DockerInstallation"
}


'@   

        $script:imageBlocks | % { $dockerConfig += $_ }
        $dockerConfig = [scriptblock]::Create($dockerConfig)
    } else {

$dockerConfig = @'
nxScript DockerInstallation
{
    GetScript = "$getDockerClient"
    SetScript = "$setDockerClient"
    TestScript = "$testDockerClient"
}

nxService DockerService
{
    Name = "docker.io"
    Controller = "init"
    Enabled = $true
    State = "Running"
    DependsOn = "[nxScript]DockerInstallation"
}
'@

        $dockerConfig = [scriptblock]::Create($dockerConfig)
    }

    Node $AllNodes.Where{$_.Role -eq "Docker Host"}.Nodename
    {
        if ($AllNodes.Where{$_.Role -eq "Docker Host"}.Nodename -eq "$Hostname") {
            throw "Duplicate node detected in configuration data and Hostname parameter"
        }

        $dockerConfig.Invoke()
    }

    Node $Hostname
    {
        $dockerConfig.Invoke()
    }
}