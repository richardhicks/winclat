Function Get-WinClatSetConfigurationScript {

    <#

    .SYNOPSIS
        Returns the self-contained script block that Set-WinClatConfiguration runs on each confirmed target.

    .DESCRIPTION
        The script block takes one positional argument, a hashtable of requested settings (Permit, Pref64FromDns, Pref64FromRA, AutoEnable) mapped to [bool] values, and returns one WinClat.SetResult row per requested setting (DESIGN.md, section 7.3):
          1. Feature check, then elevation check (section 4.4). Either failure returns one row per setting with that status and changes nothing.
          2. Reads 'show global store=both' to record the effective values before the change.
          3. Runs one 'netsh interface clat set global' with every requested setting. Output lines are written to the verbose stream. A non-zero exit code is classified with Get-WinClatNetshFailure.
          4. Re-reads 'show global store=both' and the policy registry key, because netsh returns exit code 0 even when Group Policy prevents the change from taking effect.
          5. For each setting: Success when the effective value matches the request; PolicyOverride when it does not and Group Policy controls the setting; Failed when it does not and no policy applies.
          6. When Permit was disabled and the change took effect, reads the instances of the up adapters with IPv6 bound. Any still translating was enabled manually, so the Permit row's message names them and says how to stop them, or says that CLAT stopped on every automatically enabled interface. When the instances cannot be read, the message is the general note that a running manual instance keeps translating.

        The prefix discovery validation and the confirmation prompt happen on the calling computer before this script runs.

        Set-WinClatConfiguration and the unit tests both use this function, so the tests exercise the script block that is sent remotely.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.ScriptBlock.

    .EXAMPLE
        & (Get-WinClatSetConfigurationScript) @{ Permit = $true }

        Enables permit on the local computer and returns one WinClat.SetResult row.

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
        'ConvertTo-WinClatTimeSpan'
        'ConvertTo-WinClatSetResult'
        'Get-WinClatNetshFailure'
        'Get-WinClatPolicyControlled'
        'Test-WinClatElevation'
        'Get-WinClatFeatureFailure'
        'Test-WinClatFeature'

    )

    $Body = {

        Param ($Requested)

        $Order = @('Permit', 'Pref64FromDns', 'Pref64FromRA', 'AutoEnable')
        $Names = @($Order | Where-Object -FilterScript { $Requested.ContainsKey($_) })

        # One row per requested setting when nothing could be changed.
        $FailAll = {

            Param ($Status, $Message)

            ForEach ($Name in $Names) {

                ConvertTo-WinClatSetResult -ComputerName $env:COMPUTERNAME -Status $Status -Setting $Name -RequestedValue ([bool]$Requested[$Name]) -Message $Message

            }

        }

        $ReadGlobal = {

            $Output = @(netsh.exe interface clat show global 'store=both')

            If ($LASTEXITCODE -eq 0) {

                @(ConvertFrom-WinClatNetshOutput -InputObject $Output)

            }

        }

        If (-not (Test-WinClatFeature -InputObject @(netsh.exe interface '?'))) {

            $Missing = Get-WinClatFeatureFailure
            & $FailAll $Missing.Status $Missing.Message
            Return

        }

        If (-not (Test-WinClatElevation)) {

            & $FailAll 'ElevationRequired' 'Changing the WinCLAT configuration requires an elevated session. Run PowerShell as administrator, or connect with an account that is a local administrator on the target.'
            Return

        }

        $Before = @(@(& $ReadGlobal) | Where-Object -FilterScript { $_.Store -eq 'Active' })[0]

        # Always an array: splatting a single string passes it to netsh one character at a time.
        $Arguments = @(ForEach ($Name in $Names) {

                $Value = 'disabled'

                If ($Requested[$Name]) {

                    $Value = 'enabled'

                }

                "$($Name.ToLowerInvariant())=$Value"

            })

        $Output = @(netsh.exe interface clat set global @Arguments)
        $ExitCode = $LASTEXITCODE

        ForEach ($Line in $Output) {

            If ("$Line".Trim()) {

                Write-Verbose -Message "$($env:COMPUTERNAME): $("$Line".Trim())"

            }

        }

        If ($ExitCode -ne 0) {

            $Classified = Get-WinClatNetshFailure -InputObject $Output -ExitCode $ExitCode
            & $FailAll $Classified.Status $Classified.Message
            Return

        }

        # Never trust netsh success alone: re-read both stores (section 9).
        $After = @(& $ReadGlobal)
        $Active = @($After | Where-Object -FilterScript { $_.Store -eq 'Active' })[0]
        $Persistent = @($After | Where-Object -FilterScript { $_.Store -eq 'Persistent' })[0]

        If (-not $Active -or -not $Persistent) {

            & $FailAll 'Failed' 'netsh.exe reported success, but the configuration could not be read back to verify the change.'
            Return

        }

        $Controlled = @((Get-WinClatPolicyControlled) -split ',\s*' | Where-Object -FilterScript { $_ })

        # Values in messages use the words of the rows and parameters (DESIGN.md, section 6).
        $Word = {

            Param ($Value)

            If ($Value -eq $true) {

                'Enabled'

            }

            ElseIf ($Value -eq $false) {

                'Disabled'

            }

            Else {

                'unknown'

            }

        }

        # After Permit is disabled, any instance still translating was enabled manually. Reads the up adapters with IPv6
        # bound (section 4.7); when they cannot all be read, falls back to the general note.
        $InstanceNote = {

            Param ($AutoEnable)

            $General = 'A manually enabled instance that is already running keeps translating; stop it with Set-WinClatInstance -State Disabled.'
            $Running = @()

            Try {

                $Bound = @(Get-NetAdapterBinding -ComponentID 'ms_tcpip6' -ErrorAction Stop | Where-Object -FilterScript { $_.Enabled } | ForEach-Object -Process { $_.Name })
                $Adapters = @(Get-NetAdapter -ErrorAction Stop | Where-Object -FilterScript { $_.Status -eq 'Up' -and $Bound -contains $_.Name } | Sort-Object -Property ifIndex)

            }

            Catch {

                Write-Verbose -Message "$($env:COMPUTERNAME): The network adapters could not be read, so running instances were not checked: $($_.Exception.Message)"
                Return $General

            }

            ForEach ($Adapter in $Adapters) {

                $Lines = @(netsh.exe interface clat show instance "interface=$($Adapter.ifIndex)")

                If ($LASTEXITCODE -ne 0) {

                    Write-Verbose -Message "$($env:COMPUTERNAME): The instance on $($Adapter.Name) could not be read, so running instances were not checked."
                    Return $General

                }

                $Instance = @(ConvertFrom-WinClatNetshOutput -InputObject $Lines)[0]

                If ($Instance -and $Instance.Enabled -eq $true -and $Instance.IsTranslating -eq $true) {

                    $Running += $Adapter.Name

                }

            }

            If ($Running.Count -eq 0) {

                Return 'CLAT stopped on every interface where it was automatically enabled.'

            }

            $Stop = 'Set-WinClatInstance -State Disabled'

            If ($AutoEnable -eq $true) {

                $Stop = 'Set-WinClatConfiguration -AutoEnable Disabled and then Set-WinClatInstance -State Disabled'

            }

            "A manually enabled instance is still translating on $($Running -join ', '); stop it with $Stop."

        }

        ForEach ($Name in $Names) {

            $RequestedValue = [bool]$Requested[$Name]
            $EffectiveValue = $Active.$Name
            $PersistentValue = $Persistent.$Name
            $PolicyControlled = $Controlled -contains $Name
            $Changed = $null

            If ($Before -and $null -ne $Before.$Name) {

                $Changed = $EffectiveValue -ne $Before.$Name

            }

            $Status = 'Success'
            $Message = $null

            If ($EffectiveValue -eq $RequestedValue) {

                If ($PolicyControlled) {

                    $Message = "Group Policy controls $Name. The local value was written, and the policy currently sets the same value."

                }

            }

            ElseIf ($PolicyControlled) {

                $Status = 'PolicyOverride'
                $Message = "Group Policy controls $Name. The local value was written (persistent: $(& $Word $PersistentValue)), but the effective value is $(& $Word $EffectiveValue). The local value takes effect only if the policy is removed."

            }

            Else {

                $Status = 'Failed'
                $Message = "netsh.exe reported success, but after the change the effective value is $(& $Word $EffectiveValue) and the persistent value is $(& $Word $PersistentValue)."

            }

            # Disabling Permit stops automatically enabled instances but not a running manual one (section 10), so say which
            # happened instead of a caveat that may not apply (decided October 27, 2026; section 7.3).
            If ($Name -eq 'Permit' -and $Status -eq 'Success' -and $EffectiveValue -eq $false -and $Changed -eq $true) {

                $Note = & $InstanceNote $Active.AutoEnable
                $Message = (@($Message, $Note) | Where-Object -FilterScript { $_ }) -join ' '

            }

            $Row = @{

                ComputerName          = $env:COMPUTERNAME
                Status                = $Status
                Setting               = $Name
                RequestedValue        = $RequestedValue
                PersistentValue       = $PersistentValue
                EffectiveValue        = $EffectiveValue
                PolicyControlled      = $PolicyControlled
                EffectiveValueChanged = $Changed
                Message               = $Message

            }

            ConvertTo-WinClatSetResult @Row

        }

    }

    Get-WinClatRemoteScript -HelperName $HelperName -ScriptBlock $Body

}
