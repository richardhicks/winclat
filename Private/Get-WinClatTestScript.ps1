Function Get-WinClatTestScript {

    <#

    .SYNOPSIS
        Returns the self-contained script block that Test-WinClat runs on each target.

    .DESCRIPTION
        The script block takes three positional arguments: an array of InterfaceAlias patterns (empty for all adapters), the IPv4 target for the functional test (empty to skip it), and the TCP port (0 for ICMP). It returns one WinClat.TestResult row per check (DESIGN.md, section 8):
          1. Feature present. When the feature is missing, every other check returns Skipped. On Windows Server the check is Info, not Fail, and every row has Status NotSupported, because Microsoft delivers WinCLAT to client editions only.
          2. Global checks from 'show global store=both' (section 8.2): CLAT permitted (when Permit is disabled: Fail only when an interface is IPv6-only and could use CLAT, Info otherwise or without elevation, and a Warning when an instance is still translating, which needs elevation to see), Prefix discovery valid, Policy override, and Policy controlled (Info, only when policy applies). If the global configuration cannot be read, one 'Global configuration' row with Status Failed is returned instead.
          3. Elevation. When the session is not elevated, the seven interface checks return one Skipped row each with no interface.
          4. Interface checks for each up adapter with IPv6 bound, filtered by InterfaceAlias (section 8.3): SLAAC address, IPv6 default route, Native IPv4, Instance active, CLAT address, and Prefix consistency.
          5. Mode sanity, once per computer, considering every up adapter with IPv6 bound.
          6. Functional test, when an IPv4 target is supplied and an interface is translating (section 8.4).

        Test-WinClat and the unit tests both use this function, so the tests exercise the script block that is sent remotely.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.ScriptBlock.

    .EXAMPLE
        & (Get-WinClatTestScript) @() '192.0.2.10' 443

        Runs every check on the local computer, followed by a TCP functional test to 192.0.2.10 port 443.

    .LINK
        https://learn.microsoft.com/windows-server/administration/windows-commands/netsh

    .NOTES
        Version:        1.0.0
        Creation Date:  October 28, 2026
        Last Updated:   October 28, 2026
        Author:         Richard Hicks
        Organization:   Richard M. Hicks Consulting, Inc.
        Contact:        rich@richardhicks.com
        Website:        https://www.richardhicks.com/

    #>

    [CmdletBinding()]
    [OutputType([scriptblock])]

    Param ()

    $HelperName = @(

        'ConvertFrom-WinClatNetshOutput'
        'ConvertTo-WinClatIPv6Prefix'
        'ConvertTo-WinClatTimeSpan'
        'ConvertTo-WinClatTestResult'
        'Get-WinClatDns64Address'
        'Get-WinClatNetshFailure'
        'Get-WinClatOSBuild'
        'Get-WinClatPolicyControlled'
        'Test-WinClatElevation'
        'Get-WinClatFeatureFailure'
        'Test-WinClatFeature'
        'Test-WinClatIcmp'
        'Test-WinClatPrefixMatch'
        'Test-WinClatTcp'

    )

    $Body = {

        Param ($InterfaceAlias, $IPv4Target, $IPv4Port)

        # Flatten, so the patterns work however the array arrives (Invoke-Command, a local runspace, or a direct call).
        $InterfaceAlias = @($InterfaceAlias | ForEach-Object -Process { $_ } | Where-Object -FilterScript { $_ })
        $InterfaceCheckNames = @('SLAAC address', 'IPv6 default route', 'Native IPv4', 'Instance active', 'CLAT address', 'Prefix consistency', 'Mode sanity')

        # The computer-level status of every row; NotSupported on Windows Server (DESIGN.md, section 8.6).
        $RowStatus = 'Success'

        $Emit = {

            Param ($Alias, $Check, $Result, $Detail, $Remediation)

            $Row = @{

                ComputerName   = $env:COMPUTERNAME
                Status         = $RowStatus
                InterfaceAlias = $Alias
                Check          = $Check
                Result         = $Result
                Detail         = $Detail
                Remediation    = $Remediation
                CollectedAtUtc = (Get-Date).ToUniversalTime()

            }

            ConvertTo-WinClatTestResult @Row

        }

        $SkipChecks = {

            Param ([string[]]$Check, $Reason)

            ForEach ($Name in $Check) {

                & $Emit $null $Name 'Skipped' $Reason $null

            }

        }

        $SkipFunctional = {

            Param ($Reason)

            If ($IPv4Target) {

                & $Emit $null 'Functional test' 'Skipped' $Reason $null

            }

        }

        # 1. Feature present.
        $OSBuild = Get-WinClatOSBuild
        $Help = @(netsh.exe interface '?')

        If (-not (Test-WinClatFeature -InputObject $Help)) {

            $Missing = Get-WinClatFeatureFailure -OSBuild $OSBuild

            # Windows Server never receives WinCLAT, so it is not applicable rather than failed. Every row carries the
            # same detail, and NotSupported is not counted in the summary warning (DESIGN.md, section 4.6).
            If ($Missing.Status -eq 'NotSupported') {

                $RowStatus = 'NotSupported'
                & $Emit $null 'Feature present' 'Info' $Missing.Message $null
                & $SkipChecks @('CLAT permitted', 'Prefix discovery valid', 'Policy override') $Missing.Message
                & $SkipChecks $InterfaceCheckNames $Missing.Message
                & $SkipFunctional $Missing.Message
                Return

            }

            $Reason = 'The WinCLAT feature is not present.'
            & $Emit $null 'Feature present' 'Fail' "The clat netsh context is not present on OS build $OSBuild." 'WinCLAT is generally available on Windows 11 version 25H2 build 26200.9550 and later. Install the latest cumulative update.'
            & $SkipChecks @('CLAT permitted', 'Prefix discovery valid', 'Policy override') $Reason
            & $SkipChecks $InterfaceCheckNames $Reason
            & $SkipFunctional $Reason
            Return

        }

        & $Emit $null 'Feature present' 'Pass' "The clat netsh context is present on OS build $OSBuild." $null

        # 2. Global checks.
        $GlobalOutput = @(netsh.exe interface clat show global 'store=both')
        $ExitCode = $LASTEXITCODE
        $Stores = @()

        If ($ExitCode -eq 0) {

            $Stores = @(ConvertFrom-WinClatNetshOutput -InputObject $GlobalOutput)

        }

        $Active = @($Stores | Where-Object -FilterScript { $_.Store -eq 'Active' })[0]
        $Persistent = @($Stores | Where-Object -FilterScript { $_.Store -eq 'Persistent' })[0]

        If (-not $Active) {

            $Status = 'Failed'
            $Message = "netsh.exe returned no active global configuration: $((@($GlobalOutput) -join ' ').Trim())"

            If ($ExitCode -ne 0) {

                $Classified = Get-WinClatNetshFailure -InputObject $GlobalOutput -ExitCode $ExitCode
                $Status = $Classified.Status
                $Message = $Classified.Message

            }

            $Row = @{

                ComputerName   = $env:COMPUTERNAME
                Status         = $Status
                Check          = 'Global configuration'
                Result         = 'Fail'
                Detail         = $Message
                CollectedAtUtc = (Get-Date).ToUniversalTime()

            }

            ConvertTo-WinClatTestResult @Row
            Return

        }

        $PolicyControlled = Get-WinClatPolicyControlled
        $Controlled = @($PolicyControlled -split ',\s*' | Where-Object -FilterScript { $_ })

        # Remediation for a global setting: point at the policy when Group Policy controls it.
        $SettingRemedy = {

            Param ($Setting, $Command)

            If ($Controlled -contains $Setting) {

                "Group Policy controls $Setting. Change the WinCLAT policy under Computer Configuration > Administrative Templates > Network > TCPIP Settings > IPv6 Transition Technologies."

            }

            Else {

                $Command

            }

        }

        # Elevation decides whether instances can be read, for CLAT permitted and for the interface checks.
        $Elevated = Test-WinClatElevation
        $Candidates = @()

        # Instances read so far, by interface index, so no instance is read twice.
        $InstanceState = @{}

        If ($Elevated) {

            # Up adapters with IPv6 bound (section 4.7).
            $Candidates = @(Get-NetAdapter | Where-Object -FilterScript { $_.Status -eq 'Up' } | Sort-Object -Property ifIndex)

            Try {

                $IPv6Bound = @(Get-NetAdapterBinding -ComponentID 'ms_tcpip6' -ErrorAction Stop | Where-Object -FilterScript { $_.Enabled } | ForEach-Object -Process { $_.Name })
                $Candidates = @($Candidates | Where-Object -FilterScript { $IPv6Bound -contains $_.Name })

            }

            Catch {

                Write-Verbose -Message "IPv6 bindings could not be read, so no adapters were excluded: $($_.Exception.Message)"

            }

        }

        # Addresses and routes of each candidate, read once for CLAT permitted and the interface checks. An interface could
        # use CLAT when it is IPv6-only: a SLAAC address, an IPv6 default route, and no native IPv4.
        $Facts = @{}
        $Eligible = @()

        ForEach ($Adapter in $Candidates) {

            $Index = $Adapter.ifIndex
            $IPv6Assigned = @(Get-NetIPAddress -InterfaceIndex $Index -AddressFamily IPv6 -ErrorAction SilentlyContinue | Where-Object -FilterScript { $_ })

            $Fact = @{

                IPv6Assigned = $IPv6Assigned
                Slaac        = @($IPv6Assigned | Where-Object -FilterScript { $_.PrefixOrigin -eq 'RouterAdvertisement' -and $_.IPAddress -notlike 'fe80:*' })
                Route        = @(Get-NetRoute -InterfaceIndex $Index -DestinationPrefix '::/0' -ErrorAction SilentlyContinue | Where-Object -FilterScript { $_ })
                NativeIPv4   = @(Get-NetIPAddress -InterfaceIndex $Index -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object -FilterScript { $_.IPAddress -notlike '169.254.*' -and $_.IPAddress -notmatch '^192\.0\.0\.[0-7]$' } | ForEach-Object -Process { $_.IPAddress })

            }

            $Facts[[string]$Index] = $Fact

            If ($Fact.Slaac.Count -gt 0 -and $Fact.Route.Count -gt 0 -and $Fact.NativeIPv4.Count -eq 0) {

                $Eligible += $Adapter.Name

            }

        }

        $Permitted = $Active.Permit -eq $true

        If ($Permitted) {

            & $Emit $null 'CLAT permitted' 'Pass' 'Permit is enabled in the active store.' $null

        }

        Else {

            # Disabling permit stops automatic instances but not a running manual one (section 10), so look for one before
            # reporting. Any instance still translating is therefore a manual one.
            $Running = @()

            ForEach ($Adapter in $Candidates) {

                $Key = [string]$Adapter.ifIndex
                $Output = @(netsh.exe interface clat show instance "interface=$Key")

                If ($LASTEXITCODE -eq 0) {

                    $InstanceState[$Key] = @(ConvertFrom-WinClatNetshOutput -InputObject $Output)[0]

                    If ($InstanceState[$Key] -and $InstanceState[$Key].Enabled -eq $true -and $InstanceState[$Key].IsTranslating -eq $true) {

                        $Running += $Adapter.Name

                    }

                }

            }

            If ($Running.Count -gt 0) {

                $Stop = 'Set-WinClatInstance -State Disabled'

                If ($Active.AutoEnable -eq $true) {

                    $Stop = 'Set-WinClatConfiguration -AutoEnable Disabled and then Set-WinClatInstance -State Disabled'

                }

                $Keep = 'run Set-WinClatConfiguration -Permit Enabled.'

                If ($Controlled -contains 'Permit') {

                    $Keep = "Permit must be enabled. $(& $SettingRemedy 'Permit' $null)"

                }

                & $Emit $null 'CLAT permitted' 'Warning' "Permit is disabled in the active store, but a manually enabled instance is still translating on $($Running -join ', '). Disabling Permit stops automatically enabled instances but not manually enabled ones, and no instance can be enabled while Permit is disabled." "To stop CLAT, run $Stop. To keep it, $Keep"

            }

            # Fail only where CLAT could be used, so an untouched default configuration on a dual-stack network is not a
            # failure (section 8.2).
            ElseIf ($Eligible.Count -gt 0) {

                & $Emit $null 'CLAT permitted' 'Fail' "Permit is disabled in the active store, so CLAT does not activate on non-cellular interfaces. IPv6-only interfaces that could use CLAT: $($Eligible -join ', ')." (& $SettingRemedy 'Permit' 'Set-WinClatConfiguration -Permit Enabled')

            }

            ElseIf ($Elevated) {

                & $Emit $null 'CLAT permitted' 'Info' 'Permit is disabled in the active store (the Windows default), so CLAT does not activate on non-cellular interfaces. No interface is IPv6-only, so CLAT would not be used here now.' (& $SettingRemedy 'Permit' 'To use CLAT on IPv6-only networks, run Set-WinClatConfiguration -Permit Enabled.')

            }

            Else {

                & $Emit $null 'CLAT permitted' 'Info' 'Permit is disabled in the active store (the Windows default), so CLAT does not activate on non-cellular interfaces. Whether an interface could use CLAT is not known without an elevated session.' (& $SettingRemedy 'Permit' 'Run Test-WinClat elevated to check the interfaces. To use CLAT on IPv6-only networks, run Set-WinClatConfiguration -Permit Enabled.')

            }

        }

        $Methods = @()

        If ($Active.Pref64FromRA -eq $true) {

            $Methods += 'Pref64FromRA'

        }

        If ($Active.Pref64FromDns -eq $true) {

            $Methods += 'Pref64FromDns'

        }

        $DiscoveryValid = $Methods.Count -gt 0

        If ($DiscoveryValid) {

            & $Emit $null 'Prefix discovery valid' 'Pass' "Prefix discovery is enabled: $($Methods -join ', ')." $null

        }

        Else {

            & $Emit $null 'Prefix discovery valid' 'Fail' 'Pref64FromRA and Pref64FromDns are both disabled in the active store, so CLAT never activates.' (& $SettingRemedy 'Pref64FromRA' 'Set-WinClatConfiguration -Pref64FromRA Enabled')

        }

        If ($Persistent) {

            $Differences = @(ForEach ($Name in @('Permit', 'Pref64FromDns', 'Pref64FromRA', 'AutoEnable')) {

                    If ("$($Active.$Name)" -ne "$($Persistent.$Name)") {

                        "${Name}: active $($Active.$Name), persistent $($Persistent.$Name)"

                    }

                })

            If ($Differences.Count -gt 0) {

                & $Emit $null 'Policy override' 'Warning' "The active and persistent stores differ: $($Differences -join '; ')." 'Group Policy overrides the local configuration. Change the policy, or align the local settings with Set-WinClatConfiguration.'

            }

            Else {

                & $Emit $null 'Policy override' 'Pass' 'The active and persistent stores match.' $null

            }

        }

        Else {

            & $Emit $null 'Policy override' 'Info' 'The persistent store was not returned, so the stores could not be compared.' $null

        }

        If ($PolicyControlled) {

            & $Emit $null 'Policy controlled' 'Info' "Group Policy controls: $PolicyControlled." $null

        }

        # 3. Elevation.
        If (-not $Elevated) {

            $Reason = 'Interface checks require an elevated session. Run PowerShell as administrator, or connect with an account that is a local administrator on the target.'
            & $SkipChecks $InterfaceCheckNames $Reason
            & $SkipFunctional $Reason
            Return

        }

        # 4. Interface checks on the up adapters with IPv6 bound, read above.
        $Selected = $Candidates

        If ($InterfaceAlias.Count -gt 0) {

            $Selected = @($Candidates | Where-Object -FilterScript {

                    $Alias = $_.Name
                    @($InterfaceAlias | Where-Object -FilterScript { $Alias -like $_ }).Count -gt 0

                })

        }

        If ($Selected.Count -eq 0) {

            $Message = 'No up network adapter with IPv6 enabled was found.'

            If ($InterfaceAlias.Count -gt 0) {

                $Message = "No up network adapter with IPv6 enabled matches InterfaceAlias '$($InterfaceAlias -join "', '")'."

            }

            & $SkipChecks @($InterfaceCheckNames | Where-Object -FilterScript { $_ -ne 'Mode sanity' }) $Message

        }

        $Translating = New-Object -TypeName 'System.Collections.Generic.List[string]'
        $NotConnected = 'Not connected to an IPv6 network; CLAT is not expected to activate.'

        ForEach ($Adapter in $Selected) {

            $Alias = $Adapter.Name
            $Index = $Adapter.ifIndex
            $IsActive = $false

            $Fact = $Facts[[string]$Index]
            $IPv6Assigned = $Fact.IPv6Assigned
            $Slaac = $Fact.Slaac
            $Route = $Fact.Route
            $NativeIPv4 = $Fact.NativeIPv4
            $Connected = $Slaac.Count -gt 0 -or $Route.Count -gt 0

            If ($Slaac.Count -gt 0) {

                & $Emit $Alias 'SLAAC address' 'Pass' "SLAAC address $($Slaac[0].IPAddress) ($($Slaac.Count) in total)." $null

            }

            ElseIf (-not $Connected) {

                & $Emit $Alias 'SLAAC address' 'Info' $NotConnected $null

            }

            # On a dual-stack interface CLAT is not expected to activate, so missing IPv6 prerequisites are Info, not Fail
            # (section 8.3).
            ElseIf ($NativeIPv4.Count -gt 0) {

                & $Emit $Alias 'SLAAC address' 'Info' 'An IPv6 default route is present but there is no SLAAC address, which WinCLAT requires (DHCPv6-only addressing is not supported). This does not matter on this dual-stack interface, but CLAT would not work if the network became IPv6-only.' 'To use CLAT on this network when it is IPv6-only, enable SLAAC: router advertisements must include an on-link prefix with the autonomous (A) flag set.'

            }

            Else {

                & $Emit $Alias 'SLAAC address' 'Fail' 'An IPv6 default route is present but there is no SLAAC address. DHCPv6-only addressing is not supported by WinCLAT.' 'Enable SLAAC on this network: router advertisements must include an on-link prefix with the autonomous (A) flag set.'

            }

            If ($Route.Count -gt 0) {

                & $Emit $Alias 'IPv6 default route' 'Pass' "IPv6 default route via $($Route[0].NextHop)." $null

            }

            ElseIf (-not $Connected) {

                & $Emit $Alias 'IPv6 default route' 'Info' $NotConnected $null

            }

            ElseIf ($NativeIPv4.Count -gt 0) {

                & $Emit $Alias 'IPv6 default route' 'Info' 'A SLAAC address is present but there is no IPv6 default route (::/0). This does not matter on this dual-stack interface, but CLAT would not work if the network became IPv6-only.' 'To use CLAT on this network when it is IPv6-only, confirm that the router sends router advertisements with a non-zero router lifetime.'

            }

            Else {

                & $Emit $Alias 'IPv6 default route' 'Fail' 'A SLAAC address is present but there is no IPv6 default route (::/0).' 'Confirm that the router sends router advertisements with a non-zero router lifetime.'

            }

            If ($NativeIPv4.Count -eq 0) {

                & $Emit $Alias 'Native IPv4' 'Pass' 'No native IPv4 address.' $null

            }

            Else {

                & $Emit $Alias 'Native IPv4' 'Info' "Dual-stack interface with native IPv4 $($NativeIPv4 -join ', '). CLAT is not expected to activate." $null

            }

            $Key = [string]$Index
            $ExitCode = 0
            $Instance = $null

            If (-not $InstanceState.ContainsKey($Key)) {

                $Output = @(netsh.exe interface clat show instance "interface=$Index")
                $ExitCode = $LASTEXITCODE

                If ($ExitCode -eq 0) {

                    $InstanceState[$Key] = @(ConvertFrom-WinClatNetshOutput -InputObject $Output)[0]

                }

            }

            If ($ExitCode -ne 0) {

                $Classified = Get-WinClatNetshFailure -InputObject $Output -ExitCode $ExitCode
                & $Emit $Alias 'Instance active' 'Fail' $Classified.Message $null

            }

            Else {

                $Instance = $InstanceState[$Key]
                # Each translating interface takes the next address in 192.0.0.0/29: 192.0.0.1, then 192.0.0.2 on a second
                # interface (CLIENT6, October 27, 2026; section 10). 192.0.0.0 is the gateway.
                $IsActive = [bool]($Instance -and $Instance.Enabled -eq $true -and $Instance.IsTranslating -eq $true -and $Instance.RemotePrefix -and $Instance.IPv4Address -match '^192\.0\.0\.[1-7]$')

                If ($IsActive) {

                    $Translating.Add($Alias)
                    & $Emit $Alias 'Instance active' 'Pass' "Translating with remote prefix $($Instance.RemotePrefix) and IPv4 address $($Instance.IPv4Address)." $null

                }

                Else {

                    $State = 'netsh.exe returned no instance data.'

                    If ($Instance) {

                        $RemotePrefix = $Instance.RemotePrefix

                        If (-not $RemotePrefix) {

                            $RemotePrefix = 'none'

                        }

                        $State = "Instance enabled: $($Instance.Enabled), translating: $($Instance.IsTranslating), remote prefix: $RemotePrefix."

                    }

                    $Reasons = @()

                    If (-not $Permitted) {

                        $Reasons += 'CLAT is not permitted'

                    }

                    If (-not $DiscoveryValid) {

                        $Reasons += 'prefix discovery is disabled'

                    }

                    If (-not $Connected) {

                        $Reasons += 'the interface is not connected to an IPv6 network'

                    }

                    ElseIf ($Slaac.Count -eq 0) {

                        $Reasons += 'the interface has no SLAAC address'

                    }

                    ElseIf ($Route.Count -eq 0) {

                        $Reasons += 'the interface has no IPv6 default route'

                    }

                    If ($NativeIPv4.Count -gt 0) {

                        $Reasons += 'the interface has native IPv4'

                    }

                    # An enabled instance without a remote prefix is waiting for a NAT64 prefix that discovery has not found.
                    If ($Reasons.Count -eq 0 -and $Instance -and $Instance.Enabled -eq $true -and -not $Instance.RemotePrefix) {

                        $Remedy = 'Neither the router advertisements (the PREF64 option) nor the DNS servers (DNS64 for ipv4only.arpa) provide a NAT64 prefix on this network. Confirm that the network has a NAT64 gateway and advertises its prefix.'

                        If ($Methods -notcontains 'Pref64FromDns') {

                            $Remedy = 'If the DNS servers of this network perform DNS64, run Set-WinClatConfiguration -Pref64FromDns Enabled. Otherwise the network must advertise the PREF64 option in router advertisements.'

                            If ($Controlled -contains 'Pref64FromDns') {

                                $Remedy = & $SettingRemedy 'Pref64FromDns' $null

                            }

                        }

                        ElseIf ($Methods -notcontains 'Pref64FromRA') {

                            $Remedy = 'If this network advertises the PREF64 option in router advertisements, run Set-WinClatConfiguration -Pref64FromRA Enabled. Otherwise its DNS servers must perform DNS64 for ipv4only.arpa.'

                            If ($Controlled -contains 'Pref64FromRA') {

                                $Remedy = & $SettingRemedy 'Pref64FromRA' $null

                            }

                        }

                        & $Emit $Alias 'Instance active' 'Fail' "CLAT is enabled but no NAT64 prefix was discovered, so it cannot translate. Prefix discovery is enabled for: $($Methods -join ', '). $State" $Remedy

                    }

                    ElseIf ($Reasons.Count -eq 0) {

                        & $Emit $Alias 'Instance active' 'Fail' "CLAT is not translating although the prerequisites are met. $State" 'Confirm that the network advertises a NAT64 prefix (the PREF64 router advertisement option, or DNS64 for ipv4only.arpa), then review Get-WinClatInstance.'

                    }

                    Else {

                        # Reads as a sentence: "A", "A and B", or "A, B, and C".
                        $Because = $Reasons[0]

                        If ($Reasons.Count -eq 2) {

                            $Because = "$($Reasons[0]) and $($Reasons[1])"

                        }

                        ElseIf ($Reasons.Count -gt 2) {

                            $Because = "$($Reasons[0..($Reasons.Count - 2)] -join ', '), and $($Reasons[-1])"

                        }

                        & $Emit $Alias 'Instance active' 'Info' "Not translating, which is expected because $Because. $State" $null

                    }

                }

            }

            # CLAT address: after a network change CLAT keeps its address on the previous prefix, which breaks IPv4, while
            # show instance already reports values for the new network (section 10). The address netsh reports must be
            # assigned to the adapter and on the /64 of a current SLAAC address.
            If (-not $IsActive) {

                & $Emit $Alias 'CLAT address' 'Skipped' 'CLAT is not active on this interface.' $null

            }

            ElseIf (-not $Instance.IPv6Address) {

                & $Emit $Alias 'CLAT address' 'Info' 'netsh.exe reported no CLAT IPv6 address, so it was not compared with the adapter prefixes.' $null

            }

            Else {

                $Current = @($Slaac | ForEach-Object -Process { ConvertTo-WinClatIPv6Prefix -Address $_.IPAddress } | Where-Object -FilterScript { $_ } | Sort-Object -Unique)
                $ClatPrefix = ConvertTo-WinClatIPv6Prefix -Address $Instance.IPv6Address
                # Compared as /128 prefixes, so differences in how netsh and Get-NetIPAddress format the address do not matter.
                $ClatHost = ConvertTo-WinClatIPv6Prefix -Address $Instance.IPv6Address -PrefixLength 128
                $IsAssigned = @($IPv6Assigned | Where-Object -FilterScript { (ConvertTo-WinClatIPv6Prefix -Address $_.IPAddress -PrefixLength 128) -eq $ClatHost }).Count -gt 0
                $CurrentText = 'none'

                If ($Current.Count -gt 0) {

                    $CurrentText = $Current -join ', '

                }

                If ($IsAssigned -and $Current -contains $ClatPrefix) {

                    & $Emit $Alias 'CLAT address' 'Pass' "The CLAT IPv6 address $($Instance.IPv6Address) is assigned and on the current prefix $ClatPrefix." $null

                }

                Else {

                    $Detail = "netsh.exe reports the CLAT IPv6 address $($Instance.IPv6Address), which is not on a current prefix of the adapter ($CurrentText)."

                    If (-not $IsAssigned) {

                        $Detail = "netsh.exe reports the CLAT IPv6 address $($Instance.IPv6Address), but it is not assigned to the adapter."

                    }

                    # A manually configured address off the current prefixes is most likely the address CLAT kept. A static
                    # address on a current prefix is not named.
                    $Stale = @($IPv6Assigned | Where-Object -FilterScript { $_.PrefixOrigin -eq 'Manual' -and (ConvertTo-WinClatIPv6Prefix -Address $_.IPAddress -PrefixLength 128) -ne $ClatHost -and $Current -notcontains (ConvertTo-WinClatIPv6Prefix -Address $_.IPAddress) } | ForEach-Object -Process { $_.IPAddress })

                    If ($Stale.Count -gt 0) {

                        $Detail += " The adapter carries $($Stale -join ', '), which is not on its current prefix ($CurrentText)."

                    }

                    $Detail += ' The network changed after CLAT started, and CLAT kept its address on the previous prefix, so IPv4 traffic through CLAT fails. Microsoft has acknowledged this as a known issue.'
                    & $Emit $Alias 'CLAT address' 'Fail' $Detail "Restart the network adapter: Restart-NetAdapter -Name '$Alias'. CLAT then takes an address on the current prefix."

                }

            }

            If (-not $IsActive) {

                & $Emit $Alias 'Prefix consistency' 'Skipped' 'CLAT is not active on this interface.' $null

            }

            ElseIf ($Instance.RemotePrefix -notmatch '/96$') {

                & $Emit $Alias 'Prefix consistency' 'Info' "The remote prefix $($Instance.RemotePrefix) is not a /96, so it is not compared with DNS64." $null

            }

            Else {

                $Synthesized = @(Get-WinClatDns64Address -InterfaceIndex $Index)

                If ($Synthesized.Count -eq 0) {

                    & $Emit $Alias 'Prefix consistency' 'Info' 'No AAAA record was returned for ipv4only.arpa, so DNS64 is not in use or not reachable and the prefix was not compared.' $null

                }

                ElseIf (@($Synthesized | Where-Object -FilterScript { Test-WinClatPrefixMatch -Prefix $Instance.RemotePrefix -Address $_ }).Count -gt 0) {

                    & $Emit $Alias 'Prefix consistency' 'Pass' "The DNS64 prefix matches the remote prefix $($Instance.RemotePrefix)." $null

                }

                Else {

                    & $Emit $Alias 'Prefix consistency' 'Warning' "The PREF64 router advertisement and DNS64 disagree: the remote prefix is $($Instance.RemotePrefix), and DNS64 returned $($Synthesized -join ', ')." 'Configure the same NAT64 prefix in the PREF64 router advertisement option and on the DNS64 server.'

                }

            }

        }

        # 5. Mode sanity, once per computer.
        If ($Active.AutoEnable -eq $true) {

            & $Emit $null 'Mode sanity' 'Pass' 'AutoEnable is enabled, so CLAT activates automatically on eligible interfaces.' $null

        }

        ElseIf ($Active.AutoEnable -eq $false) {

            # Every up adapter with IPv6 bound counts, including those excluded by InterfaceAlias.
            $Manual = @()

            ForEach ($Adapter in $Candidates) {

                $Key = [string]$Adapter.ifIndex

                If (-not $InstanceState.ContainsKey($Key)) {

                    $Output = @(netsh.exe interface clat show instance "interface=$Key")

                    If ($LASTEXITCODE -eq 0) {

                        $InstanceState[$Key] = @(ConvertFrom-WinClatNetshOutput -InputObject $Output)[0]

                    }

                }

                If ($InstanceState[$Key] -and $InstanceState[$Key].Enabled -eq $true) {

                    $Manual += $Adapter.Name

                }

            }

            If ($Manual.Count -gt 0) {

                & $Emit $null 'Mode sanity' 'Pass' "AutoEnable is disabled, and an instance is manually enabled on $($Manual -join ', ')." $null

            }

            Else {

                & $Emit $null 'Mode sanity' 'Fail' 'AutoEnable is disabled and no instance is manually enabled, so CLAT never activates.' 'Set-WinClatConfiguration -AutoEnable Enabled'

            }

        }

        Else {

            & $Emit $null 'Mode sanity' 'Info' 'The active AutoEnable value could not be read.' $null

        }

        # 6. Functional test.
        If ($IPv4Target) {

            If ($Translating.Count -eq 0) {

                & $Emit $null 'Functional test' 'Skipped' 'CLAT not active on any tested interface.' $null

            }

            Else {

                If ([int]$IPv4Port -gt 0) {

                    $Test = Test-WinClatTcp -Target $IPv4Target -Port $IPv4Port

                }

                Else {

                    $Test = Test-WinClatIcmp -Target $IPv4Target

                }

                # CLAT's IPv4 default route has route metric 256, so Windows prefers any native IPv4 route (section 8.4). The
                # route Windows chooses for the target decides whether the test went through CLAT at all.
                $Source = $null

                Try {

                    $Source = @(Find-NetRoute -RemoteIPAddress $IPv4Target -ErrorAction Stop | Where-Object -FilterScript { $_.PSObject.Properties['IPAddress'] -and $_.IPAddress })[0]

                }

                Catch {

                    Write-Verbose -Message "The route to $IPv4Target could not be found, so the functional test does not report which interface it used: $($_.Exception.Message)"

                }

                $Alias = $Translating[0]
                $Result = $Test.Result
                $Detail = $Test.Detail
                $Remedy = $null

                If ($Source) {

                    $Alias = $Source.InterfaceAlias
                    $Address = [string]$Source.IPAddress

                    If ($Address -match '^192\.0\.0\.[0-7]$') {

                        $Detail = "$Detail Sent through CLAT on $Alias ($Address)."

                    }

                    Else {

                        # Not a CLAT result, whatever the outcome, so it is Info (decided October 27, 2026).
                        $Result = 'Info'
                        $Detail = "$Detail It was sent through native IPv4 on $Alias ($Address), not through CLAT, so CLAT was not tested."
                        $Remedy = 'Windows prefers a native IPv4 route over the CLAT route, so the functional test reaches CLAT only when no native IPv4 route is preferred for the target, for example when the interface with native IPv4 is disconnected.'

                    }

                }

                If ($Result -eq 'Warning') {

                    $Remedy = 'Confirm that the target responds and is not filtered, or choose a target known to respond, ideally your own infrastructure.'

                }

                ElseIf ($Result -eq 'Fail') {

                    $Remedy = 'Review the IPv4 default route through the CLAT interface and confirm that the NAT64 gateway is reachable.'

                }

                & $Emit $Alias 'Functional test' $Result $Detail $Remedy

            }

        }

    }

    Get-WinClatRemoteScript -HelperName $HelperName -ScriptBlock $Body

}
