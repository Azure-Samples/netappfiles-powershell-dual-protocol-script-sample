# Copyright(c) Microsoft and contributors. All rights reserved
#
# This source code is licensed under the MIT license found in the LICENSE file in the root directory of the source tree

<#
.SYNOPSIS
    This script creates Azure Netapp files dual-protocol volume
.DESCRIPTION
    Authenticates with Azure and select the targeted subscription first, then created ANF account, capacity pool and dual-protocol Volume
.PARAMETER ResourceGroupName
    Name of the Azure Resource Group where the ANF will be created
.PARAMETER Location
    Azure Location (e.g 'WestUS', 'EastUS')
.PARAMETER NetAppAccountName
    Name of the Azure NetApp Files Account
.PARAMETER NetAppPoolName
    Name of the Azure NetApp Files Capacity Pool
.PARAMETER ServiceLevel
    Service Level - Ultra, Premium or Standard
.PARAMETER NetAppPoolSize
    Size of the Azure NetApp Files Capacity Pool in Bytes. Range between 4398046511104 and 549755813888000
.PARAMETER NetAppVolumeName
    Name of the Azure NetApp Files Volume
.PARAMETER NetAppVolumeSize
    Size of the Azure NetApp Files volume in Bytes. Range between 107374182400 and 109951162777600
.PARAMETER SubnetId
    The Delegated subnet Id within the VNET
.PARAMETER DomainJoinUsername
    Domain Username
.PARAMETER DomainJoinPassword
    Domain Password
.PARAMETER DNSList
    Comma-seperated DNS list
.PARAMETER ADFQDN
    Active Directory FQDN
.PARAMETER SmbServerNamePrefix
    SMB Server name prefix
.PARAMETER ServerRootCACertificatePath
    Server Root CA certificate
.PARAMETER CleanupResources
    If the script should clean up the resources, $false by default
.EXAMPLE
    PS C:\\> CreateANFVolume.ps1
#>
param
(
    # Name of the Azure Resource Group
    [string]$ResourceGroupName = 'My-rg',

    #Azure location 
    [string]$Location = 'WestUS',

    #Azure NetApp Files account name
    [string]$NetAppAccountName = 'anfaccount',

    #Azure NetApp Files capacity pool name    
    [string]$NetAppPoolName = 'pool1',

    # Service Level can be {Ultra, Premium or Standard}
    [ValidateSet("Ultra","Premium","Standard")]
    [string]$ServiceLevel = 'Standard',

    #Azure NetApp Files capacity pool size
    [ValidateRange(4398046511104,549755813888000)]
    [long]$NetAppPoolSize = 4398046511104,

    #Azure NetApp Files volume name
    [string]$NetAppVolumeName = 'vol1',

    #Azure NetApp Files volume size
    [ValidateRange(107374182400,109951162777600)]
    [long]$NetAppVolumeSize=107374182400,

    #Subnet Id 
    [string]$SubnetId = 'Subnet ID',
    
    #Domain Join Username    
    [string]$DomainJoinUsername = 'User',

    #Domain Join Password
    [string]$DomainJoinPassword = 'Admin',

    #DNS List
    [string]$DNSList = '10.0.2.4,10.0.2.5',

    #Active Directory FQDN
    [string]$ADFQDN = 'testdomain.local',

    #SMB Server Name Prefix
    [string]$SmbServerNamePrefix = 'pmcdns',

    #Root certificate path
    [string]$ServerRootCACertificatePath = 'CA Cert Path',

    #Clean Up resources
    [bool]$CleanupResources = $false
)

$ErrorActionPreference="Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

#Functions

# Wait for Azure NetApp Files resource to be in sucessfull provision status
Function WaitForANFResource
{
    Param 
    (
        [ValidateSet("NetAppAccount","CapacityPool","Volume")]
        [string]$ResourceType,
        [string]$ResourceId, 
        [int]$IntervalInSec = 10,
        [int]$retries = 60
    )

    for($i = 0; $i -le $retries; $i++)
    {
        Start-Sleep -s $IntervalInSec
        try
        {
            if($ResourceType -eq "NetAppAccount")
            {
                $Account = Get-AzNetAppFilesAccount -ResourceId $ResourceId
                if($Account.ProvisioningState -eq "Succeeded")
                {
                    break
                }

            }
            elseif($ResourceType -eq "CapacityPool")
            {
                $Pool = Get-AzNetAppFilesPool -ResourceId $ResourceId
                if($Pool.ProvisioningState -eq "Succeeded")
                {
                    break
                }
            }
            elseif($ResourceType -eq "Volume")
            {
                $Volume = Get-AzNetAppFilesVolume -ResourceId $ResourceId
                if($Volume.ProvisioningState -eq "Succeeded")
                {
                    break                    
                }
            }            
        }
        catch
        {
            continue
        }
    }    
}

# Wait for Azure NetApp Files resource to get deleted completely 
Function WaitForNoANFResource
{
    Param 
    (
        [ValidateSet("NetAppAccount","CapacityPool","Volume")]
        [string]$ResourceType,
        [string]$ResourceId, 
        [int]$IntervalInSec = 10,
        [int]$retries = 60
    )

    for($i = 0; $i -le $retries; $i++)
    {
        Start-Sleep -s $IntervalInSec
        try
        {
            if($ResourceType -eq "Volume")
            {
                Get-AzNetAppFilesVolume -ResourceId $ResourceId
            }
            elseif($ResourceType -eq "CapacityPool")
            {
                Get-AzNetAppFilesPool -ResourceId $ResourceId                
            }
            elseif($ResourceType -eq "NetAppAccount")
            {   
                Get-AzNetAppFilesAccount -ResourceId $ResourceId                              
            }
        }
        catch
        {
            break
        }
    }
}


# Authorizing and connecting to Azure
Write-Verbose -Message "Authorizing with Azure Account..." -Verbose
Add-AzAccount

#Get Certificate content and encode
$CertContent = Get-Content -Path $ServerRootCACertificatePath -Encoding Byte
$EncodedCertContent = [System.Convert]::ToBase64String($CertContent)

# Create Azure NetApp Files Account
Write-Verbose -Message "Creating Azure NetApp Files Account -> $NetAppAccountName" -Verbose
$ActiveDirectory = New-Object Microsoft.Azure.Commands.NetAppFiles.Models.PSNetAppFilesActiveDirectory
$ActiveDirectory.Dns = $DNSList
$ActiveDirectory.Username = $DomainJoinUsername
$ActiveDirectory.Password = $DomainJoinPassword
$ActiveDirectory.Domain = $ADFQDN
$ActiveDirectory.SmbServerName = $SmbServerNamePrefix
$ActiveDirectory.ServerRootCACertificate = $EncodedCertContent


$NewANFAccount = New-AzNetAppFilesAccount -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -Name $NetAppAccountName `
    -ActiveDirectory @($ActiveDirectory)

Write-Verbose -Message "Azure NetApp Files Account has been created successfully: $($NewANFAccount.Id)" -Verbose

# Create Azure NetApp Files Capacity Pool                                                                                                       
Write-Verbose -Message "Creating Azure NetApp Files Capacity Pool -> $NetAppPoolName" -Verbose                                         
$NewANFPool= New-AzNetAppFilesPool -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -AccountName $NetAppAccountName `
    -Name $NetAppPoolName `
    -PoolSize $NetAppPoolSize `
    -ServiceLevel $ServiceLevel

Write-Verbose -Message "Azure NetApp Files Capacity Pool has been created successfully: $($NewANFPool.Id)" -Verbose

#Create Azure NetApp Files NFS Volume
Write-Verbose -Message "Creating Azure NetApp Files - SMB Volume -> $NetAppVolumeName" -Verbose
$NewANFVolume = New-AzNetAppFilesVolume -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -AccountName $NetAppAccountName `
    -PoolName $NetAppPoolName `
    -Name $NetAppVolumeName `
    -UsageThreshold $NetAppVolumeSize `
    -SubnetId $SubnetId `
    -CreationToken $NetAppVolumeName `
    -ServiceLevel $ServiceLevel `
    -ProtocolType @("NFSv3","CIFS") `
    -SecurityStyle ntfs    

WaitForANFResource -ResourceType Volume -ResourceId $($NewANFVolume.Id)

Write-Verbose -Message "Azure NetApp Files Volume has been created successfully: $($NewANFVolume.Id)" -Verbose

Write-Verbose -Message "====> SMB Server FQDN: $($NewANFVolume.MountTargets[0].smbServerFQDN.ToString())" -Verbose

Write-Verbose -Message "Azure NetApp Files has been created successfully." -Verbose

if($CleanupResources)
{    
    Write-Verbose -Message "Cleaning up Azure NetApp Files resources..." -Verbose

    Write-Verbose -Message "Deleting Azure NetApp Files Volume $NetAppVolumeName" -Verbose
    Remove-AzNetAppFilesVolume -ResourceGroupName $ResourceGroupName `
        -AccountName $NetAppAccountName `
        -PoolName $NetAppPoolName `
        -Name $NetAppVolumeName

    WaitForNoANFResource -ResourceType Volume -ResourceId $($NewANFVolume.Id)
    
    Write-Verbose -Message "Deleting Azure NetApp Files Volume $NetAppPoolName" -Verbose
    Remove-AzNetAppFilesPool -ResourceGroupName $ResourceGroupName -AccountName $NetAppAccountName -PoolName $NetAppPoolName

    WaitForNoANFResource -ResourceType CapacityPool -ResourceId $($NewANFPool.Id)
   
    Write-Verbose -Message "Deleting Azure NetApp Files Volume $NetAppAccountName" -Verbose
    Remove-AzNetAppFilesAccount -ResourceGroupName $ResourceGroupName -Name $NetAppAccountName
   
    Write-Verbose -Message "All Azure NetApp Files resources have been deleted successfully." -Verbose       
}
