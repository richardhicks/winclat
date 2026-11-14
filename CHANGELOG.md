# Changelog

All notable changes to the WinCLAT module are recorded in this file. Versions follow [Semantic Versioning](https://semver.org/): a patch release fixes behavior without changing output, a minor release adds features or changes how results are reported, and a major release removes or renames commands, parameters, or properties.

## [1.2.0] - November 13, 2026

### Changed

- `Get-WinClatInstance`: while CLAT has nothing to translate, Windows keeps the IP Translation Configuration Service (`IPxlatCfgSvc`) stopped, and netsh cannot read the instance ("The RPC server is unavailable."). The adapter is now returned with `Status` `Success`, empty instance properties, and a `Message` saying there is no active CLAT instance. Previously it was `Failed`, which counted the computer in the multi-computer warning. A disabled service is still `Failed`, and the `Message` now says the service is disabled.
- `Test-WinClat`: in the same situation, Instance active is judged like any interface that is not translating: `Info` when CLAT is not expected to run (for example, `Permit` disabled or native IPv4 present), and `Fail` only when the prerequisites are met. Previously it was always `Fail` with only the netsh message, so a default dual-stack client reported `Overall` `Fail`.
- `Test-WinClat`: the SLAAC address check names a stable address instead of a temporary (privacy) address when the interface has both. The count and the result are unchanged.

### Upgrade notes

- Scripts that find problem computers with `Get-WinClatInstance | Where-Object -FilterScript { $_.Status -ne 'Success' }` no longer return adapters where CLAT is simply idle. To list those adapters, filter on `Status -eq 'Success'` and an empty `Enabled`.

## [1.1.0] - November 12, 2026

### Changed

- `Test-WinClat`: `Overall` separates CLAT that is active from CLAT that could start. `Pass` now means CLAT is translating and no check failed or warned. When CLAT is not translating and no check failed or warned, `Overall` is `Ready` if CLAT would start automatically on an IPv6-only network (CLAT permitted, Prefix discovery valid, and Mode sanity all passed), and `Inactive` if it would not. Previously all of these reported `Pass`.
- `Test-WinClat`: without elevation, `Overall` is `Incomplete` instead of `Pass`, because whether CLAT is active is not known. The single-computer view shows it as `Incomplete (requires elevation)`; the value stays `Incomplete` for filtering and `Export-Csv`. `Fail` and `Warning` still take precedence.
- `Test-WinClat`: the Policy override check is `Info` instead of `Warning` when Group Policy controls every setting that differs between the active and persistent stores. A difference on a setting that policy does not control is still a `Warning`.

### Added

- `Test-WinClat`: the summary has a `Note` property that explains `Ready`, `Inactive`, and `Incomplete`, and for `Inactive` names the checks that did not pass. It is shown in the single-computer view, `Format-List`, and `Export-Csv`, but not in the multi-computer table.

### Upgrade notes

- Scripts that filter on `Overall -eq 'Pass'` or `Overall -ne 'Pass'` return different computers than in 1.0. To find computers that need attention, filter on `Overall -in 'Fail', 'Warning', 'Incomplete'`. Filters on `Warning` and `Fail` are unchanged.
- `Export-Csv` output of the summary has a new `Note` column at the end.

## [1.0.1] - November 4, 2026

### Fixed

- `Get-WinClatInstance`: `TriggerSource` reports `DHCP Option 108` (event 1106 trigger source code 2) for an instance that Windows enabled after honoring DHCPv4 option 108 on an IPv6-mostly network. It was previously reported as `Unknown (2)`. `Mode` for these instances is `Automatic`, as before.

## [1.0.0] - October 28, 2026

Initial release.

### Added

- `Get-WinClatConfiguration`: global configuration (active, persistent, or both stores) and the settings Group Policy controls.
- `Get-WinClatInstance`: per-interface CLAT state, including how each instance was started (`Mode`, `TriggerSource`).
- `Test-WinClat`: global and per-interface health checks with remediation, and an optional ICMP or TCP functional test through CLAT.
- `Set-WinClatConfiguration`: changes `Permit`, `Pref64FromDns`, `Pref64FromRA`, and `AutoEnable`, and re-reads the result to detect Group Policy overrides.
- `Set-WinClatInstance`: manually enables or disables CLAT on one interface.
- `Export-WinClatConfiguration` and `Import-WinClatConfiguration`: save and restore the global configuration. Import parses the file strictly and never runs it.
- `Reset-WinClatConfiguration`: returns the global configuration to the Windows defaults.

[1.2.0]: https://github.com/richardhicks/WinCLAT/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/richardhicks/WinCLAT/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/richardhicks/WinCLAT/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/richardhicks/WinCLAT/releases/tag/v1.0.0
