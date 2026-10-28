Function Get-WinClatInstanceScript {

    <#

    .SYNOPSIS
        Returns the self-contained script block that Get-WinClatInstance runs on each target.

    .DESCRIPTION
        The script block takes one positional argument, an array of InterfaceAlias patterns (empty for all adapters), and follows the execution order in DESIGN.md, section 4.4:
          1. Feature check: 'clat' in the 'netsh interface ?' sub-context list. If absent, returns one object with Status NotSupported on Windows Server or FeatureNotAvailable on a client (Get-WinClatFeatureFailure).
          2. Elevation check on the current token. If not elevated, returns one ElevationRequired object.
          3. Enumerates up adapters with Get-NetAdapter, drops adapters without IPv6 (ms_tcpip6) bound, filters by InterfaceAlias (wildcards supported), and runs 'netsh interface clat show instance interface=<ifIndex>' for each (section 4.7). If the IPv6 bindings cannot be read, no adapters are dropped and the reason is written to the verbose stream.
          4. Classifies a non-zero exit code for an adapter with Get-WinClatNetshFailure. Other adapters are still reported.

        For an enabled instance, TriggerSource comes from the newest event 1106 for the adapter's LUID in the IPxlatCfg event log (Get-WinClatTriggerSource), and Mode is Manual when TriggerSource is Manual and Automatic otherwise. Windows keeps a manually enabled instance running when autoenable is enabled again, so autoenable alone does not show it. When the instance is disabled or no event is found, Mode is derived from the active autoenable value read with 'show global' in the same session: Automatic when enabled, Manual when disabled, $null when it cannot be read (section 6).

        When no up adapter with IPv6 enabled matches, returns one Success object with no interface data and a message, and no error (section 7.2).

        Get-WinClatInstance and the unit tests both use this function, so the tests exercise the script block that is sent remotely.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.ScriptBlock.

    .EXAMPLE
        & (Get-WinClatInstanceScript) @('Wi-Fi')

        Returns the WinCLAT state of the Wi-Fi adapter on the local computer.

    .LINK
        https://learn.microsoft.com/powershell/module/netadapter/get-netadapter

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
        'ConvertTo-WinClatTimeSpan'
        'ConvertTo-WinClatInstance'
        'Get-WinClatNetshFailure'
        'Get-WinClatTriggerSource'
        'Test-WinClatElevation'
        'Get-WinClatFeatureFailure'
        'Test-WinClatFeature'

    )

    $Body = {

        Param ($InterfaceAlias)

        # Flatten, so the patterns work however the array arrives (Invoke-Command, a local runspace, or a direct call).
        $InterfaceAlias = @($InterfaceAlias | ForEach-Object -Process { $_ } | Where-Object -FilterScript { $_ })
        $Help = @(netsh.exe interface '?')

        If (-not (Test-WinClatFeature -InputObject $Help)) {

            # NotSupported on Windows Server, FeatureNotAvailable on a client that has not received the feature.
            $Missing = Get-WinClatFeatureFailure

            $Failure = @{

                ComputerName   = $env:COMPUTERNAME
                Status         = $Missing.Status
                CollectedAtUtc = (Get-Date).ToUniversalTime()
                Message        = $Missing.Message

            }

            ConvertTo-WinClatInstance @Failure
            Return

        }

        If (-not (Test-WinClatElevation)) {

            $Failure = @{

                ComputerName   = $env:COMPUTERNAME
                Status         = 'ElevationRequired'
                CollectedAtUtc = (Get-Date).ToUniversalTime()
                Message        = 'Reading WinCLAT instance state requires an elevated session. Run PowerShell as administrator, or connect with an account that is a local administrator on the target. Get-WinClatConfiguration does not require elevation.'

            }

            ConvertTo-WinClatInstance @Failure
            Return

        }

        $Adapters = @(Get-NetAdapter | Where-Object -FilterScript { $_.Status -eq 'Up' } | Sort-Object -Property ifIndex)

        # An adapter without IPv6 bound, such as a physical NIC attached to a Hyper-V switch, can never run CLAT.
        Try {

            $IPv6Bound = @(Get-NetAdapterBinding -ComponentID 'ms_tcpip6' -ErrorAction Stop | Where-Object -FilterScript { $_.Enabled } | ForEach-Object -Process { $_.Name })
            $Adapters = @($Adapters | Where-Object -FilterScript { $IPv6Bound -contains $_.Name })

        }

        Catch {

            Write-Verbose -Message "IPv6 bindings could not be read, so no adapters were excluded: $($_.Exception.Message)"

        }

        If ($InterfaceAlias.Count -gt 0) {

            $Adapters = @($Adapters | Where-Object -FilterScript {

                    $Alias = $_.Name
                    @($InterfaceAlias | Where-Object -FilterScript { $Alias -like $_ }).Count -gt 0

                })

        }

        If ($Adapters.Count -eq 0) {

            $Message = 'No up network adapter with IPv6 enabled was found.'

            If ($InterfaceAlias.Count -gt 0) {

                $Message = "No up network adapter with IPv6 enabled matches InterfaceAlias '$($InterfaceAlias -join "', '")'."

            }

            ConvertTo-WinClatInstance -ComputerName $env:COMPUTERNAME -Status 'Success' -CollectedAtUtc (Get-Date).ToUniversalTime() -Message $Message
            Return

        }

        # Mode falls back to the active autoenable value; netsh does not report how an instance was enabled.
        $Mode = $null
        $GlobalOutput = @(netsh.exe interface clat show global)

        If ($LASTEXITCODE -eq 0) {

            $GlobalSettings = @(ConvertFrom-WinClatNetshOutput -InputObject $GlobalOutput)[0]

            If ($GlobalSettings -and $GlobalSettings.PSObject.Properties['AutoEnable'] -and $GlobalSettings.AutoEnable -is [bool]) {

                $Mode = 'Manual'

                If ($GlobalSettings.AutoEnable) {

                    $Mode = 'Automatic'

                }

            }

        }

        # Read only when an enabled instance is found, so computers without active CLAT do not query the log.
        $TriggerSources = $null

        ForEach ($Adapter in $Adapters) {

            $Output = @(netsh.exe interface clat show instance "interface=$($Adapter.ifIndex)")
            $ExitCode = $LASTEXITCODE

            $Result = @{

                ComputerName   = $env:COMPUTERNAME
                InterfaceAlias = $Adapter.Name
                InterfaceIndex = $Adapter.ifIndex
                Mode           = $Mode
                CollectedAtUtc = (Get-Date).ToUniversalTime()

            }

            If ($ExitCode -ne 0) {

                $Classified = Get-WinClatNetshFailure -InputObject $Output -ExitCode $ExitCode
                ConvertTo-WinClatInstance @Result -Status $Classified.Status -Message $Classified.Message
                Continue

            }

            $Settings = @(ConvertFrom-WinClatNetshOutput -InputObject $Output)[0]

            If (-not $Settings) {

                ConvertTo-WinClatInstance @Result -Status 'Failed' -Message "netsh.exe returned no instance data: $((@($Output) -join ' ').Trim())"
                Continue

            }

            # Windows keeps a manually enabled instance when autoenable is enabled again, so the event decides when it exists.
            If ($Settings.Enabled -eq $true -and $Adapter.NetLuid) {

                If ($null -eq $TriggerSources) {

                    $TriggerSources = Get-WinClatTriggerSource

                }

                $Trigger = $TriggerSources[[string]$Adapter.NetLuid]

                If ($Trigger) {

                    $Result['TriggerSource'] = $Trigger
                    $Result['Mode'] = 'Automatic'

                    If ($Trigger -eq 'Manual') {

                        $Result['Mode'] = 'Manual'

                    }

                }

            }

            ConvertTo-WinClatInstance @Result -Status 'Success' -Settings $Settings

        }

    }

    Get-WinClatRemoteScript -HelperName $HelperName -ScriptBlock $Body

}
