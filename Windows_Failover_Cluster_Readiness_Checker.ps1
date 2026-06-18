#requires -Version 5.1
<#
.SYNOPSIS
    Windows Failover Cluster Readiness Checker.
.DESCRIPTION
    Read-only cluster readiness context reporter for infrastructure support.
#>
[CmdletBinding()]
param([string]$OutputPath)
$RunStamp=Get-Date -Format 'yyyyMMdd_HHmmss'
if([string]::IsNullOrWhiteSpace($OutputPath)){$OutputPath=Join-Path ([Environment]::GetFolderPath('Desktop')) 'Cluster_Readiness_Reports'}
New-Item -Path $OutputPath -ItemType Directory -Force|Out-Null
function New-Row{param($Area,$Name,$Status,$Value,$Notes)[PSCustomObject]@{Area=$Area;Name=$Name;Status=$Status;Value=$Value;Notes=$Notes}}
$rows=@()
$module=Get-Module -ListAvailable FailoverClusters|Select-Object -First 1
$rows+=New-Row 'Module' 'FailoverClusters' ($(if($module){'OK'}else{'Info'})) ($(if($module){$module.Version}else{'Not installed'})) 'Required for live cluster checks.'
$svc=Get-Service ClusSvc -ErrorAction SilentlyContinue
$rows+=New-Row 'Service' 'Cluster Service' 'Info' ($(if($svc){"Status=$($svc.Status); StartType=$($svc.StartType)"}else{'Not found'})) 'Service exists on cluster-capable systems.'
$net=Get-NetAdapter -ErrorAction SilentlyContinue|Where-Object Status -eq 'Up'|Select-Object Name,LinkSpeed,InterfaceDescription
$net|Export-Csv (Join-Path $OutputPath "network_adapters_$RunStamp.csv") -NoTypeInformation -Encoding UTF8
$disks=Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"|Select-Object DeviceID,VolumeName,FileSystem,Size,FreeSpace
$disks|Export-Csv (Join-Path $OutputPath "local_volumes_$RunStamp.csv") -NoTypeInformation -Encoding UTF8
$template='Validate OS patch level','Validate DNS records','Validate time sync','Validate network paths','Validate storage presentation','Validate backups','Validate monitoring','Validate maintenance window'|ForEach-Object{[PSCustomObject]@{Check=$_;Status='Not assessed';Notes=''}}
$template|Export-Csv (Join-Path $OutputPath "cluster_readiness_template_$RunStamp.csv") -NoTypeInformation -Encoding UTF8
$rows|Export-Csv (Join-Path $OutputPath "cluster_readiness_$RunStamp.csv") -NoTypeInformation -Encoding UTF8
$html="<h1>Cluster Readiness - $env:COMPUTERNAME</h1><p>Generated $(Get-Date)</p><h2>Checks</h2>$($rows|ConvertTo-Html -Fragment)<h2>Template</h2>$($template|ConvertTo-Html -Fragment)"
$html|ConvertTo-Html -Title 'Cluster Readiness'|Set-Content (Join-Path $OutputPath "cluster_readiness_$RunStamp.html") -Encoding UTF8
$rows|Format-Table -AutoSize
Write-Host "Reports saved to: $OutputPath" -ForegroundColor Green
Start-Process explorer.exe -ArgumentList "`"$OutputPath`"" -ErrorAction SilentlyContinue
