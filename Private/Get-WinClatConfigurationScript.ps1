Function Get-WinClatConfigurationScript {

    <#

    .SYNOPSIS
        Returns the self-contained script block that Get-WinClatConfiguration runs on each target.

    .DESCRIPTION
        The script block takes one positional argument, the netsh store name ('active', 'persistent', or 'both'), and follows the execution order in DESIGN.md, section 4.4:
          1. Feature check: 'clat' in the 'netsh interface ?' sub-context list. If absent, returns NotSupported on Windows Server or FeatureNotAvailable on a client (Get-WinClatFeatureFailure), with the OS build.
          2. No elevation check; 'show global' does not require elevation (section 3.3).
          3. Runs 'netsh interface clat show global store=<store>'.
          4. Classifies a non-zero exit code with Get-WinClatNetshFailure.

        On success it returns one WinClat.Configuration object per store, with PolicyControlled from the policy registry key (section 9), OSBuild, and a UTC CollectedAtUtc.

        Get-WinClatConfiguration and the unit tests both use this function, so the tests exercise the script block that is sent remotely.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.ScriptBlock.

    .EXAMPLE
        & (Get-WinClatConfigurationScript) 'both'

        Returns the active and persistent configuration of the local computer.

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
        'ConvertTo-WinClatConfiguration'
        'Get-WinClatNetshFailure'
        'Get-WinClatOSBuild'
        'Get-WinClatPolicyControlled'
        'Get-WinClatFeatureFailure'
        'Test-WinClatFeature'

    )

    $Body = {

        Param ($Store)

        $OSBuild = Get-WinClatOSBuild
        $Help = @(netsh.exe interface '?')

        If (-not (Test-WinClatFeature -InputObject $Help)) {

            # NotSupported on Windows Server, FeatureNotAvailable on a client that has not received the feature.
            $Missing = Get-WinClatFeatureFailure -OSBuild $OSBuild

            $Failure = @{

                ComputerName   = $env:COMPUTERNAME
                Status         = $Missing.Status
                OSBuild        = $OSBuild
                CollectedAtUtc = (Get-Date).ToUniversalTime()
                Message        = $Missing.Message

            }

            ConvertTo-WinClatConfiguration @Failure
            Return

        }

        $Output = @(netsh.exe interface clat show global "store=$Store")
        $ExitCode = $LASTEXITCODE
        $CollectedAtUtc = (Get-Date).ToUniversalTime()

        If ($ExitCode -ne 0) {

            $Classified = Get-WinClatNetshFailure -InputObject $Output -ExitCode $ExitCode

            $Failure = @{

                ComputerName   = $env:COMPUTERNAME
                Status         = $Classified.Status
                OSBuild        = $OSBuild
                CollectedAtUtc = $CollectedAtUtc
                Message        = $Classified.Message

            }

            ConvertTo-WinClatConfiguration @Failure
            Return

        }

        $Settings = @(ConvertFrom-WinClatNetshOutput -InputObject $Output)

        If ($Settings.Count -eq 0) {

            $Failure = @{

                ComputerName   = $env:COMPUTERNAME
                Status         = 'Failed'
                OSBuild        = $OSBuild
                CollectedAtUtc = $CollectedAtUtc
                Message        = "netsh.exe returned no configuration data: $((@($Output) -join ' ').Trim())"

            }

            ConvertTo-WinClatConfiguration @Failure
            Return

        }

        $PolicyControlled = Get-WinClatPolicyControlled

        ForEach ($Item in $Settings) {

            $Result = @{

                ComputerName     = $env:COMPUTERNAME
                Status           = 'Success'
                Settings         = $Item
                PolicyControlled = $PolicyControlled
                OSBuild          = $OSBuild
                CollectedAtUtc   = $CollectedAtUtc

            }

            ConvertTo-WinClatConfiguration @Result

        }

    }

    Get-WinClatRemoteScript -HelperName $HelperName -ScriptBlock $Body

}
