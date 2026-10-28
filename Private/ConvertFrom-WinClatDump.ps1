Function ConvertFrom-WinClatDump {

    <#

    .SYNOPSIS
        Strictly parses 'netsh interface clat dump' output or an export file into WinCLAT settings.

    .DESCRIPTION
        Accepts only the structure that 'netsh interface clat dump' writes (DESIGN.md, sections 7.5 and 7.7): blank lines, comment lines beginning with '#', one 'pushd interface clat', exactly one 'set global' line, and one 'popd' after it. The 'set global' line may only contain permit, pref64fromdns, pref64fromra, and autoenable, each once, with the value enabled or disabled.

        Returns an object with Settings, a hashtable of Permit, Pref64FromDns, Pref64FromRA, and AutoEnable to [bool] for the settings present, and Problem, $null when the input is valid and otherwise the reason it was refused. Settings is empty when Problem is set.

        The content is never run. Import-WinClatConfiguration applies the parsed values through the same code as Set-WinClatConfiguration, so a file that contains any other netsh command is refused instead of executed.

        This function must also be available in the remote session. See DESIGN.md, section 4.3.

    .PARAMETER InputObject
        The lines to parse.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSCustomObject with Settings and Problem properties.

    .EXAMPLE
        ConvertFrom-WinClatDump -InputObject (Get-Content -Path .\WinCLAT-CLIENT4-20261023-014419.txt)

        Returns Settings @{ Permit = $false; Pref64FromDns = $true; Pref64FromRA = $true; AutoEnable = $true } and Problem $null.

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
    [OutputType([PSCustomObject])]

    Param (

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [AllowNull()]
        [string[]]$InputObject

    )

    $Names = @{ 'permit' = 'Permit'; 'pref64fromdns' = 'Pref64FromDns'; 'pref64fromra' = 'Pref64FromRA'; 'autoenable' = 'AutoEnable' }
    $Settings = @{}
    $Problem = $null
    $State = 'Start'
    $Number = 0

    ForEach ($Line in @($InputObject)) {

        $Number++
        $Text = "$Line".Trim()

        If ($Text -eq '' -or $Text.StartsWith('#')) {

            Continue

        }

        If ($Text -match '^pushd\s+interface\s+clat$' -and $State -eq 'Start') {

            $State = 'Pushed'
            Continue

        }

        If ($Text -match '^set\s+global\s+(.+)$' -and $State -eq 'Pushed') {

            ForEach ($Token in @($Matches[1] -split '\s+')) {

                If ($Token -notmatch '^(\w+)=(enabled|disabled)$' -or -not $Names.ContainsKey($Matches[1].ToLowerInvariant())) {

                    $Problem = "line $Number sets '$Token', which is not a WinCLAT global setting with the value enabled or disabled."
                    Break

                }

                $Name = $Names[$Matches[1].ToLowerInvariant()]

                If ($Settings.ContainsKey($Name)) {

                    $Problem = "line $Number sets $($Name.ToLowerInvariant()) more than once."
                    Break

                }

                $Settings[$Name] = $Matches[2].ToLowerInvariant() -eq 'enabled'

            }

            If ($Problem) {

                Break

            }

            $State = 'Set'
            Continue

        }

        If ($Text -match '^popd$' -and $State -eq 'Set') {

            $State = 'Popped'
            Continue

        }

        $Problem = "line $Number is not part of a WinCLAT configuration script: '$Text'."
        Break

    }

    If (-not $Problem -and $State -ne 'Popped') {

        $Problem = "it does not contain 'pushd interface clat', one 'set global' line, and 'popd', in that order."

    }

    If ($Problem) {

        $Settings = @{}

    }

    [PSCustomObject]@{

        Settings = $Settings
        Problem  = $Problem

    }

}
