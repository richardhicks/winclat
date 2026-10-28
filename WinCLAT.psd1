@{

    # Script module associated with this manifest
    RootModule           = 'WinCLAT.psm1'

    # Version number of this module
    ModuleVersion        = '1.0.0'

    # Supported PSEditions
    CompatiblePSEditions = @('Desktop', 'Core')

    # ID used to uniquely identify this module. Never change this value.
    GUID                 = '5263ce1e-2593-4606-8245-daf99a70864e'

    # Author of this module
    Author               = 'Richard M. Hicks'

    # Company or vendor of this module
    CompanyName          = 'Richard M. Hicks Consulting, Inc.'

    # Copyright statement for this module
    Copyright            = '(c) 2026 Richard M. Hicks Consulting, Inc.'

    # Description of the functionality provided by this module
    Description          = 'Manage and report on Windows CLAT (WinCLAT) on Windows 11 clients, locally or remotely across many computers.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion    = '5.1'

    # Format files (.ps1xml) to be loaded when importing this module
    FormatsToProcess     = @('WinCLAT.Format.ps1xml')

    # Functions to export from this module
    FunctionsToExport    = @(

        'Get-WinClatConfiguration'
        'Get-WinClatInstance'
        'Set-WinClatConfiguration'
        'Set-WinClatInstance'
        'Export-WinClatConfiguration'
        'Import-WinClatConfiguration'
        'Reset-WinClatConfiguration'
        'Test-WinClat'

    )

    # Cmdlets, variables, and aliases to export from this module
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    # Private data to pass to the module specified in RootModule
    PrivateData          = @{

        PSData = @{

            # Tags applied to this module. These help with module discovery in online galleries.
            Tags         = @('CLAT', 'WinCLAT', '464XLAT', 'IPv6', 'NAT64', 'Networking', 'Windows11', 'Windows', 'PSEdition_Desktop', 'PSEdition_Core')

            # A URL to the license for this module.
            LicenseUri   = 'https://github.com/richardhicks/WinCLAT/blob/main/LICENSE'

            # A URL to the main website for this project.
            ProjectUri   = 'https://github.com/richardhicks/WinCLAT'

            # Release notes for this module
            ReleaseNotes = @'
1.0.0 (October 28, 2026)

Initial release.

Commands:
- Get-WinClatConfiguration: global configuration (active, persistent, or both stores) and the settings Group Policy controls.
- Get-WinClatInstance: per-interface CLAT state, including how each instance was started (Mode, TriggerSource).
- Test-WinClat: global and per-interface health checks with remediation, and an optional ICMP or TCP functional test through CLAT.
- Set-WinClatConfiguration: changes Permit, Pref64FromDns, Pref64FromRA, and AutoEnable (Enabled or Disabled), and re-reads the result to detect Group Policy overrides.
- Set-WinClatInstance: manually enables or disables CLAT on one interface.
- Export-WinClatConfiguration and Import-WinClatConfiguration: save and restore the global configuration. Import parses the file strictly and never runs it.
- Reset-WinClatConfiguration: returns the global configuration to the Windows defaults.

Every command runs locally or across many computers through WinRM, returns one row per computer (or per setting or interface) with a Status, including computers that are unreachable or do not have the feature, and produces flat objects that export cleanly with Export-Csv.

Requirements: Windows PowerShell 5.1 or PowerShell 7 on the calling computer. Target computers run Windows 11 with WinCLAT, which is generally available on version 25H2 build 26200.9550 and later, and have WinRM enabled for remote use. WinCLAT is not available on Windows Server.

Known Windows issues, reported by the module where they can be detected: CLAT keeps its IPv6 address on the previous prefix after a network change (Test-WinClat reports CLAT address Fail; restarting the network adapter fixes it), CLAT registers 192.0.0.1 in DNS, and ICMP errors translated by NAT64 do not reach IPv4 applications.
'@

        }

    }

}
