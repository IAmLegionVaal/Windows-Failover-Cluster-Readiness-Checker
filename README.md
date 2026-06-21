# Windows Failover Cluster Readiness Checker

A PowerShell toolkit for Windows failover-cluster readiness review and guarded operational repair.

## Diagnostic script

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Windows_Failover_Cluster_Readiness_Checker.ps1
```

The diagnostic script reports clustering-module availability, service context and node, network and storage readiness evidence.

## Repair script

Preview a resource action:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Windows_Failover_Cluster_Repair_Toolkit.ps1 -ResourceName 'File Server' -ResourceAction Restart -DryRun
```

Examples:

```powershell
.\Windows_Failover_Cluster_Repair_Toolkit.ps1 -RestartClusterService
.\Windows_Failover_Cluster_Repair_Toolkit.ps1 -ResourceName 'IP Address 10.0.0.10' -ResourceAction Online
.\Windows_Failover_Cluster_Repair_Toolkit.ps1 -GroupName 'File Server Role' -MoveToNode NODE02
.\Windows_Failover_Cluster_Repair_Toolkit.ps1 -NodeName NODE01 -NodeAction Suspend -Drain
.\Windows_Failover_Cluster_Repair_Toolkit.ps1 -NodeName NODE01 -NodeAction Resume
```

Use `-ClusterName` when managing a cluster other than the default connected cluster.

## Repair behaviour

- Restarts the local Cluster Service only when requested.
- Brings one selected cluster resource online or offline, or restarts it.
- Moves one selected cluster group to one validated node.
- Suspends or resumes one selected node; `-Drain` is available only with suspend.
- Captures cluster, node, group, resource and network state before and after repair.
- Exports pre-change cluster state into the run backup directory.
- Supports `-DryRun`, confirmation prompts or `-Yes`, administrator checks, logs and verification.

## Safety and exit codes

Cluster actions can move or interrupt production workloads. The tool does not destroy clusters, evict nodes, remove resources or modify quorum configuration.

Exit codes: `0` success, `2` invalid arguments, `3` unsupported platform or missing feature, `4` elevation required, `10` cancelled, `20` action failure and `30` verification failure.

## Validation note

The repair script was committed and statically reviewed, but it was not runtime-tested on a Windows failover cluster.

## Author

Dewald Pretorius — L2 IT Support Engineer
