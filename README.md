# WinCLAT

[![PowerShell Gallery Version](https://img.shields.io/powershellgallery/v/WinCLAT?label=PowerShell%20Gallery)](https://www.powershellgallery.com/packages/WinCLAT)
[![PowerShell Gallery Downloads](https://img.shields.io/powershellgallery/dt/WinCLAT?label=Downloads)](https://www.powershellgallery.com/packages/WinCLAT)
[![License](https://img.shields.io/github/license/richardhicks/winclat?label=License)](https://github.com/richardhicks/winclat/blob/main/LICENSE)

PowerShell module for managing and reporting on Windows CLAT (WinCLAT) on Windows 11 clients, locally or remotely across many computers.

## What's New in 1.0

Version 1.0 is the initial release. Highlights include:

- **Fleet-wide reporting** - Every function runs locally or against many computers in parallel over WinRM, accepts computer names from a text file or `Get-ADComputer`, and returns one row for every computer, including computers that are offline, do not have the feature, or are not elevated. Unreachable computers are detected in about two seconds instead of waiting for a WinRM timeout.
- **Health checks with remediation** - `Test-WinClat` checks the global configuration and every IPv6-enabled interface, explains each warning and failure, and optionally proves the CLAT path end to end with an ICMP or TCP functional test.
- **Safe configuration changes** - `Set-WinClatConfiguration` refuses combinations that would stop CLAT from ever activating, re-reads every change because netsh reports success even when Group Policy overrides it, and asks for confirmation before any change that stops CLAT.
- **Baselines** - `Export-WinClatConfiguration` and `Import-WinClatConfiguration` save and restore the global configuration. Import parses each file strictly and never runs it. `Reset-WinClatConfiguration` returns computers to the Windows defaults.
- **Structured output** - Functions emit flat `PSCustomObject` results to the pipeline, so output can be filtered, sorted, and exported with `Export-Csv`.

## Description

Windows CLAT (WinCLAT) is the Windows customer-side translator (CLAT) of 464XLAT (RFC 6877). It translates IPv4 traffic from applications into IPv6, so applications that use IPv4 sockets or literal IPv4 addresses keep working on IPv6-only and IPv6-mostly networks that provide NAT64.

WinCLAT is a PowerShell module that wraps `netsh.exe interface clat` to configure, report on, and troubleshoot Windows CLAT. Every result carries a `Status` of `Success`, `Unreachable`, `FeatureNotAvailable`, `NotSupported`, `ElevationRequired`, `PolicyOverride`, or `Failed`, and a `Message` that explains anything other than `Success`. When some computers in a multi-computer run do not complete, one warning at the end gives the count.

## Installation

### PowerShell Gallery

```powershell
Install-Module -Name WinCLAT -Scope CurrentUser
```

Install the module on the computer you run the commands from. Target computers do not need it. On PowerShell 7.4 and later, `Install-PSResource -Name WinCLAT` can be used instead. Update to the latest version with `Update-Module -Name WinCLAT`.

### Manual Installation

For computers without access to the PowerShell Gallery:

1. On a computer with internet access, save the module with `Save-Module -Name WinCLAT -Path C:\Temp`.
2. Copy the `C:\Temp\WinCLAT` folder, including the version folder inside it, to a PowerShell module directory on the offline computer (e.g., `C:\Program Files\WindowsPowerShell\Modules\`).
3. Import the module:

```powershell
Import-Module -Name WinCLAT
```

## Functions

| Function | Description |
|---|---|
| [Get-WinClatConfiguration](#get-winclatconfiguration) | Return the global WinCLAT configuration |
| [Get-WinClatInstance](#get-winclatinstance) | Return the WinCLAT state of each network interface |
| [Test-WinClat](#test-winclat) | Diagnose WinCLAT readiness and operation |
| [Set-WinClatConfiguration](#set-winclatconfiguration) | Change the global WinCLAT configuration |
| [Set-WinClatInstance](#set-winclatinstance) | Manually enable or disable WinCLAT on an interface |
| [Export-WinClatConfiguration](#export-winclatconfiguration) | Save the WinCLAT configuration to a file |
| [Import-WinClatConfiguration](#import-winclatconfiguration) | Apply a WinCLAT configuration saved by Export-WinClatConfiguration |
| [Reset-WinClatConfiguration](#reset-winclatconfiguration) | Return the WinCLAT configuration to the Windows defaults |

The module also includes private helper functions used internally for parsing netsh output, remoting, and health checks. These are not exported.

## Usage

### Common Parameters

Every function accepts the following parameters for running against remote computers. They are not repeated in the parameter tables below.

| Parameter | Type | Required | Description |
|---|---|---|---|
| `-ComputerName` | String[] | No | One or more computers. Accepts pipeline input by value and by property name, including objects from `Get-ADComputer`. Blank lines and lines beginning with `#` are ignored, so `Get-Content` output can be piped directly. Aliases: `DNSHostName`, `CN`, `Name`. Default: the local computer |
| `-Credential` | PSCredential | No | Credentials for connecting to remote computers. Not used for the local computer |
| `-ThrottleLimit` | Int | No | Maximum number of concurrent remote connections (1 to 1024). Default: `32` |

---

### Get-WinClatConfiguration

Return the global WinCLAT configuration (`Permit`, `Pref64FromDns`, `Pref64FromRA`, and `AutoEnable`) from the active or persistent store. The output includes the settings that Group Policy controls and the OS build, which helps track which computers have received the feature.

#### Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `-Store` | String | No | Configuration store to return: `Active` (the effective configuration), `Persistent` (the local configuration, which Group Policy may override), or `Both`. Default: `Active` |

#### Examples

```powershell
# Return the active and persistent configuration of the local computer
Get-WinClatConfiguration -Store Both

# Return the configuration of every computer listed in a file
Get-Content -Path .\clients.txt | Get-WinClatConfiguration

# Export the configuration of every computer in an OU to a CSV file
Get-ADComputer -Filter * -SearchBase 'OU=Windows Clients,DC=corp,DC=example,DC=net' | Get-WinClatConfiguration | Export-Csv -Path .\winclat.csv -NoTypeInformation
```

---

### Get-WinClatInstance

Return the WinCLAT state of each up network adapter with IPv6 enabled, including whether it is translating, the NAT64 prefix and its remaining lifetime, the CLAT addresses, and whether the instance was enabled automatically or manually (`Mode` and `TriggerSource`, read from the `Microsoft-Windows-IPxlatCfg/Operational` event log).

> **Note:** Requires elevated (administrator) privileges on the target computer.

#### Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `-InterfaceAlias` | String[] | No | Limit results to adapters whose name matches any of these values. Wildcards are supported. Default: all up adapters with IPv6 enabled |

#### Examples

```powershell
# Return the WinCLAT state of every interface on the local computer
Get-WinClatInstance

# Return the WinCLAT state of the Wi-Fi adapter on a remote computer
Get-WinClatInstance -ComputerName CLIENT1 -InterfaceAlias 'Wi-Fi'

# Export every interface that is actively translating across many computers
Get-Content -Path .\clients.txt | Get-WinClatInstance | Where-Object -FilterScript { $_.IsTranslating } | Export-Csv -Path .\translating.csv -NoTypeInformation
```

---

### Test-WinClat

Diagnose WinCLAT readiness and operation. By default, returns one summary per computer with the overall result (`Pass`, `Warning`, `Fail`, or `NotApplicable`) and the checks that failed or warned. With `-Detailed`, returns one row per check with a `Detail` explaining what was found and a `Remediation` for each warning and failure.

Global checks (feature present, CLAT permitted, prefix discovery, Group Policy override) do not require elevation. Interface checks (SLAAC address, IPv6 default route, native IPv4, instance active, CLAT address, prefix consistency) require elevation and are skipped without it. When `-IPv4Target` is supplied and an interface is translating, a functional test sends up to three ICMP echo requests, or one TCP connection when `-IPv4Port` is also supplied, and reports which interface and source address the traffic used.

> **Note:** Use an IPv4 address, not a name, for `-IPv4Target`. A name can be reached through DNS64 and NAT64 without CLAT. Windows prefers a native IPv4 route over CLAT, so on a computer with native IPv4 on another interface the functional test reports Info instead of testing CLAT.

#### Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `-InterfaceAlias` | String[] | No | Limit interface checks to adapters whose name matches any of these values. Wildcards are supported |
| `-IPv4Target` | String | No | IPv4 address for the functional test. Choose a target known to respond. Alias: `Target` |
| `-IPv4Port` | Int | No | TCP port for the functional test (1 to 65535). When omitted, ICMP echo is used. Alias: `Port` |
| `-Detailed` | Switch | No | Return one result per check instead of one summary per computer |

#### Examples

```powershell
# Test the local computer
Test-WinClat

# Test the local computer, including a functional test, and show the remediation for each check
Test-WinClat -IPv4Target 1.1.1.1 -Detailed | Format-List -Property Check, InterfaceAlias, Result, Detail, Remediation

# Test the functional path with a TCP connection instead of ICMP
Test-WinClat -IPv4Target 192.0.2.10 -IPv4Port 443

# Test many computers and show only the failed and warning checks
Get-Content -Path .\clients.txt | Test-WinClat -Detailed | Where-Object -FilterScript { $_.Result -in 'Fail', 'Warning' }

# Save the names of unreachable computers to retry later
Get-Content -Path .\clients.txt | Test-WinClat | Where-Object -FilterScript { $_.Status -eq 'Unreachable' } | Select-Object -ExpandProperty ComputerName | Set-Content -Path .\retry.txt
```

---

### Set-WinClatConfiguration

Change the global WinCLAT configuration. Only the settings supplied are changed. The current configuration is read first, and a change that would leave both `Pref64FromRA` and `Pref64FromDns` disabled is refused because CLAT would never activate. netsh reports success even when Group Policy overrides a change, so the configuration is always read back, and a setting that policy keeps at a different value is reported with Status `PolicyOverride`. Supports `-WhatIf`; disabling `Permit` or `AutoEnable` requires confirmation by default.

> **Note:** Requires elevated (administrator) privileges on the target computer.

> **Note:** `Permit` is disabled by default in Windows, so CLAT does not activate on Wi-Fi or Ethernet until it is enabled. Disabling `Permit` or `AutoEnable` stops CLAT on every interface where it was automatically enabled. An instance enabled manually with `Set-WinClatInstance` keeps running.

#### Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `-Permit` | String | No | Whether CLAT is permitted on non-cellular interfaces: `Enabled` or `Disabled` |
| `-Pref64FromDns` | String | No | Whether to discover the NAT64 prefix using DNS (`ipv4only.arpa`): `Enabled` or `Disabled` |
| `-Pref64FromRA` | String | No | Whether to discover the NAT64 prefix from the PREF64 option in router advertisements: `Enabled` or `Disabled` |
| `-AutoEnable` | String | No | Whether CLAT enables automatically on eligible interfaces: `Enabled` or `Disabled` |

#### Examples

```powershell
# Permit CLAT on non-cellular interfaces on the local computer
Set-WinClatConfiguration -Permit Enabled

# Permit CLAT on many computers and keep a record of the results
Get-Content -Path .\clients.txt | Set-WinClatConfiguration -Permit Enabled | Export-Csv -Path .\winclat-changes.csv -NoTypeInformation

# Use only router advertisements for prefix discovery
Set-WinClatConfiguration -ComputerName CLIENT1 -Pref64FromDns Disabled

# Show what would change without making changes
Set-WinClatConfiguration -ComputerName CLIENT1 -AutoEnable Disabled -WhatIf
```

---

### Set-WinClatInstance

Manually enable or disable WinCLAT on one interface, selected by exact name or by interface index. netsh refuses manual changes while `AutoEnable` is enabled, so enabling an instance on a computer in automatic mode disables `AutoEnable` first, under one confirmation. Supports `-WhatIf`; every change requires confirmation by default.

> **Note:** Requires elevated (administrator) privileges on the target computer. `Permit` must be enabled before an instance can be enabled.

> **Warning:** Manual instance state is lost on reboot, while `AutoEnable` remains disabled. After a reboot, CLAT does not activate until `AutoEnable` is enabled again with `Set-WinClatConfiguration -AutoEnable Enabled`.

#### Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `-InterfaceAlias` | String | Yes* | Exact name of the adapter to change, for example `Ethernet`. Wildcards are not supported |
| `-InterfaceIndex` | Int | Yes* | Interface index of the adapter to change. Indexes differ between computers, so this is mainly useful for a single computer |
| `-State` | String | Yes | `Enabled` or `Disabled` |

\* Specify either `-InterfaceAlias` or `-InterfaceIndex`.

#### Examples

```powershell
# Manually enable CLAT on the Ethernet adapter of the local computer
Set-WinClatInstance -InterfaceAlias 'Ethernet' -State Enabled

# Return an interface from manual to automatic control
Set-WinClatConfiguration -AutoEnable Disabled
Set-WinClatInstance -InterfaceAlias 'Ethernet' -State Disabled
Set-WinClatConfiguration -AutoEnable Enabled

# List manually enabled instances across many computers
Get-Content -Path .\clients.txt | Get-WinClatInstance | Where-Object -FilterScript { $_.Enabled -and $_.Mode -eq 'Manual' }
```

---

### Export-WinClatConfiguration

Save the WinCLAT global configuration of one or more computers to files on the calling computer, one file per computer, named `WinCLAT-<ComputerName>-<yyyyMMdd-HHmmss>.txt`. Existing files are never overwritten, so repeated runs keep a history of baselines. Each file is the output of `netsh interface clat dump` and holds the persistent (local) values, not values set by Group Policy. Supports `-WhatIf`.

#### Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `-Path` | String | Yes | An existing folder on the calling computer where the files are written |

#### Examples

```powershell
# Save the configuration of the local computer
Export-WinClatConfiguration -Path C:\Exports

# Save the configuration of every computer listed in a file
Get-Content -Path .\clients.txt | Export-WinClatConfiguration -Path C:\Exports
```

---

### Import-WinClatConfiguration

Apply WinCLAT configuration files saved by `Export-WinClatConfiguration`. Files are never run: each one is parsed strictly, and a file that contains anything other than what netsh writes is refused before any computer is contacted. A file is applied to the local computer unless `-ComputerName` is supplied, and piped export results restore each computer from its own file. Only settings that differ from the file are written, with the same checks as `Set-WinClatConfiguration`. Supports `-WhatIf`; disabling `Permit` or `AutoEnable` requires confirmation by default.

> **Note:** Requires elevated (administrator) privileges on the target computer.

#### Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `-Path` | String[] | Yes | One or more files written by `Export-WinClatConfiguration`. Accepts pipeline input from `Get-ChildItem` and from `Export-WinClatConfiguration` results. Alias: `FullName` |

#### Examples

```powershell
# Apply a saved configuration to the local computer
Import-WinClatConfiguration -Path C:\Exports\WinCLAT-CLIENT1-20261028-120000.txt

# Apply one baseline file to many computers
Import-WinClatConfiguration -Path C:\Exports\WinCLAT-CLIENT1-20261028-120000.txt -ComputerName (Get-Content -Path .\clients.txt)

# Save every computer's configuration, then restore each computer from its own file
$Baseline = Get-Content -Path .\clients.txt | Export-WinClatConfiguration -Path C:\Exports
$Baseline | Import-WinClatConfiguration
```

---

### Reset-WinClatConfiguration

Return the WinCLAT global configuration to the Windows defaults without an export file. `Pref64FromDns`, `Pref64FromRA`, and `AutoEnable` are set to enabled. `Permit` is changed only when `-Permit` is supplied, so a plain reset never stops CLAT. Only settings that differ from the defaults are written. Manually enabled instances are not changed. Supports `-WhatIf`; `-Permit Disabled` requires confirmation by default.

> **Note:** Requires elevated (administrator) privileges on the target computer.

#### Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `-Permit` | String | No | Also set `Permit`: `Disabled` for a full reset to the current Windows defaults, or `Enabled` to permit CLAT. Default: `Permit` is not changed |

#### Examples

```powershell
# Reset the local computer to the Windows defaults, leaving Permit unchanged
Reset-WinClatConfiguration

# Reset many computers and permit CLAT
Get-Content -Path .\clients.txt | Reset-WinClatConfiguration -Permit Enabled

# Full reset to the Windows defaults, including Permit
Reset-WinClatConfiguration -ComputerName CLIENT1 -Permit Disabled
```

## Known Windows Issues

The following are Windows behaviors, not module defects. They were observed on builds 26200.9711 and 26300.9711.

- **Stale CLAT address after a network change** - CLAT keeps its IPv6 address on the previous network's prefix, and IPv4 traffic through CLAT fails. `Test-WinClat` reports the CLAT address check as Fail. Restarting the network adapter resolves it.
- **DNS registration of 192.0.0.1** - CLAT adds `192.0.0.1` to the interface without `SkipAsSource`, so the computer can register that address in DNS.
- **Translated ICMP errors** - ICMP errors that NAT64 returns for IPv4 destinations do not reach IPv4 applications, so `ping` to an unreachable IPv4 address times out instead of reporting that the destination is unreachable.

## Requirements

- Windows PowerShell 5.1 or PowerShell 7 on the computer running the commands.
- Windows 11 with WinCLAT on target computers. WinCLAT is generally available on Windows 11 version 25H2 build 26200.9550 and later. It is not available on Windows Server.
- WinRM enabled on remote target computers (TCP 5985), typically through Group Policy.
- Administrative privileges on the target computer for `Get-WinClatInstance`, the `Set-`, `Import-`, and `Reset-` functions, and the interface checks of `Test-WinClat`. `Get-WinClatConfiguration` and `Export-WinClatConfiguration` do not require elevation.
- English (en-US) netsh output on target computers.

## Author

**Richard M. Hicks** - [Richard M. Hicks Consulting, Inc.](https://www.richardhicks.com/)

- Website: [https://www.richardhicks.com/](https://www.richardhicks.com/)
- GitHub: [https://github.com/richardhicks/winclat](https://github.com/richardhicks/winclat)
- X: [@richardhicks](https://x.com/richardhicks)

## License

This project is licensed under the [MIT License](https://github.com/richardhicks/winclat/blob/main/LICENSE).

## Copyright

&copy; 2026 Richard M. Hicks Consulting, Inc.
