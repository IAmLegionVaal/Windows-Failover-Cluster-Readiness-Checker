[CmdletBinding()]
param(
    [string]$ClusterName,
    [switch]$RestartClusterService,
    [string]$ResourceName,
    [ValidateSet('Online','Offline','Restart')]
    [string]$ResourceAction,
    [string]$GroupName,
    [string]$MoveToNode,
    [string]$NodeName,
    [ValidateSet('Suspend','Resume')]
    [string]$NodeAction,
    [switch]$Drain,
    [switch]$DryRun,
    [switch]$Yes,
    [string]$OutputPath = (Join-Path $env:ProgramData 'FailoverClusterRepair')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Failures = 0
$script:VerificationFailures = 0
$script:Actions = 0

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if ($env:OS -ne 'Windows_NT') { Write-Error 'This tool requires Windows Server.'; exit 3 }
if (-not ($RestartClusterService -or $ResourceAction -or ($GroupName -and $MoveToNode) -or $NodeAction)) { Write-Error 'Choose at least one repair action.'; exit 2 }
if ($ResourceAction -and [string]::IsNullOrWhiteSpace($ResourceName)) { Write-Error '-ResourceName is required with -ResourceAction.'; exit 2 }
if (($GroupName -and -not $MoveToNode) -or ($MoveToNode -and -not $GroupName)) { Write-Error '-GroupName and -MoveToNode must be supplied together.'; exit 2 }
if ($NodeAction -and [string]::IsNullOrWhiteSpace($NodeName)) { Write-Error '-NodeName is required with -NodeAction.'; exit 2 }
if ($Drain -and $NodeAction -ne 'Suspend') { Write-Error '-Drain is valid only with -NodeAction Suspend.'; exit 2 }
if (-not $DryRun -and -not (Test-Administrator)) { Write-Error 'Run from an elevated PowerShell session.'; exit 4 }
Import-Module FailoverClusters -ErrorAction Stop

$clusterArgs = @{}
if ($ClusterName) { $clusterArgs.Cluster = $ClusterName }
Get-Cluster @clusterArgs -ErrorAction Stop | Out-Null
if ($ResourceName) { Get-ClusterResource @clusterArgs -Name $ResourceName -ErrorAction Stop | Out-Null }
if ($GroupName) { Get-ClusterGroup @clusterArgs -Name $GroupName -ErrorAction Stop | Out-Null; Get-ClusterNode @clusterArgs -Name $MoveToNode -ErrorAction Stop | Out-Null }
if ($NodeName) { Get-ClusterNode @clusterArgs -Name $NodeName -ErrorAction Stop | Out-Null }

$runPath = Join-Path $OutputPath (Get-Date -Format 'yyyyMMdd_HHmmss')
$backupPath = Join-Path $runPath 'backup'
New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
$logPath = Join-Path $runPath 'repair.log'
$beforePath = Join-Path $runPath 'before.json'
$afterPath = Join-Path $runPath 'after.json'

function Write-Log([string]$Message) { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message" | Tee-Object -FilePath $logPath -Append }
function Invoke-RepairAction([string]$Description,[scriptblock]$Script) {
    $script:Actions++
    Write-Log "ACTION: $Description"
    if ($DryRun) { Write-Log "DRY-RUN: $Description"; return }
    try {
        $result = & $Script 2>&1
        if ($null -ne $result) { $result | Out-String | Add-Content $logPath }
        Write-Log "SUCCESS: $Description"
    } catch {
        $script:Failures++
        Write-Log "FAILED: $Description - $($_.Exception.Message)"
    }
}
function Get-RepairState {
    [pscustomobject]@{
        Collected = Get-Date
        Cluster = Get-Cluster @clusterArgs | Select-Object Name,Domain,QuorumType
        LocalClusterService = Get-Service ClusSvc -ErrorAction SilentlyContinue | Select-Object Name,Status,StartType
        Nodes = @(Get-ClusterNode @clusterArgs | Select-Object Name,State,NodeWeight,DynamicWeight)
        Groups = @(Get-ClusterGroup @clusterArgs | Select-Object Name,State,OwnerNode,IsCoreGroup)
        Resources = @(Get-ClusterResource @clusterArgs | Select-Object Name,State,OwnerGroup,OwnerNode,ResourceType)
        Networks = @(Get-ClusterNetwork @clusterArgs | Select-Object Name,State,Role,Address,AddressMask)
    }
}

$before = Get-RepairState
$before | ConvertTo-Json -Depth 8 | Set-Content $beforePath -Encoding UTF8
$before | Export-Clixml (Join-Path $backupPath 'cluster-state.xml')

if (-not $DryRun -and -not $Yes) {
    if ((Read-Host 'Apply the selected failover-cluster repairs? Type YES') -cne 'YES') { Write-Log 'Repair cancelled.'; exit 10 }
}

if ($RestartClusterService) {
    Invoke-RepairAction 'Restarting the local Cluster Service' { Restart-Service ClusSvc -Force; (Get-Service ClusSvc).WaitForStatus('Running',[TimeSpan]::FromSeconds(60)) }
}
if ($ResourceAction) {
    switch ($ResourceAction) {
        'Online'  { Invoke-RepairAction "Bringing cluster resource '$ResourceName' online" { Start-ClusterResource @clusterArgs -Name $ResourceName | Out-Null } }
        'Offline' { Invoke-RepairAction "Taking cluster resource '$ResourceName' offline" { Stop-ClusterResource @clusterArgs -Name $ResourceName | Out-Null } }
        'Restart' {
            Invoke-RepairAction "Restarting cluster resource '$ResourceName'" {
                Stop-ClusterResource @clusterArgs -Name $ResourceName | Out-Null
                Start-ClusterResource @clusterArgs -Name $ResourceName | Out-Null
            }
        }
    }
}
if ($GroupName -and $MoveToNode) {
    Invoke-RepairAction "Moving cluster group '$GroupName' to '$MoveToNode'" { Move-ClusterGroup @clusterArgs -Name $GroupName -Node $MoveToNode | Out-Null }
}
if ($NodeAction) {
    if ($NodeAction -eq 'Suspend') {
        Invoke-RepairAction "Suspending cluster node '$NodeName'$(if ($Drain) { ' with drain' })" { Suspend-ClusterNode @clusterArgs -Name $NodeName -Drain:$Drain | Out-Null }
    } else {
        Invoke-RepairAction "Resuming cluster node '$NodeName'" { Resume-ClusterNode @clusterArgs -Name $NodeName | Out-Null }
    }
}

if (-not $DryRun) { Start-Sleep -Seconds 3 }
Get-RepairState | ConvertTo-Json -Depth 8 | Set-Content $afterPath -Encoding UTF8
if ($RestartClusterService -and (Get-Service ClusSvc).Status -ne 'Running') { $script:VerificationFailures++; Write-Log 'VERIFY FAILED: ClusSvc is not running.' }
if ($ResourceAction) {
    $resourceState = (Get-ClusterResource @clusterArgs -Name $ResourceName).State.ToString()
    $expected = if ($ResourceAction -eq 'Offline') { 'Offline' } else { 'Online' }
    if ($resourceState -ne $expected) { $script:VerificationFailures++; Write-Log "VERIFY FAILED: resource state is $resourceState, expected $expected." }
}
if ($GroupName -and $MoveToNode) {
    $owner = (Get-ClusterGroup @clusterArgs -Name $GroupName).OwnerNode.Name
    if ($owner -ne $MoveToNode) { $script:VerificationFailures++; Write-Log "VERIFY FAILED: group owner is $owner." }
}
if ($NodeAction) {
    $nodeState = (Get-ClusterNode @clusterArgs -Name $NodeName).State.ToString()
    $expectedNode = if ($NodeAction -eq 'Suspend') { 'Paused' } else { 'Up' }
    if ($nodeState -ne $expectedNode) { $script:VerificationFailures++; Write-Log "VERIFY FAILED: node state is $nodeState, expected $expectedNode." }
}

if ($script:Failures -gt 0) { exit 20 }
if ($script:VerificationFailures -gt 0) { exit 30 }
Write-Log "Repair completed. Actions: $script:Actions"
exit 0
