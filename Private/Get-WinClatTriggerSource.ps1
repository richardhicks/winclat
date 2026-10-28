Function Get-WinClatTriggerSource {

    <#

    .SYNOPSIS
        Returns how each currently enabled CLAT instance was enabled, from the IPxlatCfg event log.

    .DESCRIPTION
        netsh does not report how an instance was enabled, but Windows logs it. Event 1106 (464xlat Enabled) in the Microsoft-Windows-IPxlatCfg/Operational log carries a numeric TriggerSource (property 0) and the InterfaceLuid (property 1), and event 1107 (464xlat Disabled) carries the InterfaceLuid in property 1 (DESIGN.md, section 10).

        The newest 1106 or 1107 event for each interface decides. When it is 1106, the interface's TriggerSource is returned; when it is 1107, the interface is left out. The numeric code is read from the event data, not the message text, so the result does not depend on the display language.

        Returns a hashtable keyed by the interface LUID as a decimal string, the same form as [string](Get-NetAdapter).NetLuid, with values 'Pref64 RA' (1), 'No IPv4' (3), 'Manual' (5), or 'Unknown (<code>)' for codes not yet observed. The hashtable is empty when the log has no matching events or cannot be read; the reason is written to the verbose stream.

        This function must also be available in the remote session. See DESIGN.md, section 4.3.

    .PARAMETER MaxEvents
        The number of the newest 1106 and 1107 events to read. Interfaces whose newest event is older are left out, and their Mode falls back to the autoenable value. The default is 500.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Collections.Hashtable.

    .EXAMPLE
        (Get-WinClatTriggerSource)[[string](Get-NetAdapter -Name 'Ethernet').NetLuid]

        Returns 'Manual' when CLAT on the Ethernet adapter was last enabled with 'netsh interface clat set instance state=enabled'.

    .LINK
        https://learn.microsoft.com/powershell/module/microsoft.powershell.diagnostics/get-winevent

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
    [OutputType([hashtable])]

    Param (

        [ValidateRange(1, 100000)]
        [int]$MaxEvents = 500

    )

    $Labels = @{ 1 = 'Pref64 RA'; 3 = 'No IPv4'; 5 = 'Manual' }
    $Result = @{}

    $Query = @{

        FilterHashtable = @{ LogName = 'Microsoft-Windows-IPxlatCfg/Operational'; Id = 1106, 1107 }
        MaxEvents       = $MaxEvents
        ErrorAction     = 'Stop'

    }

    Try {

        $Records = @(Get-WinEvent @Query)

    }

    Catch {

        If ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*') {

            Write-Verbose -Message "The IPxlatCfg event log could not be read, so Mode is derived from the AutoEnable value: $($_.Exception.Message)"

        }

        Return $Result

    }

    # Get-WinEvent returns the newest events first, so the first event seen for an interface is its newest.
    $Seen = @{}

    ForEach ($Record in $Records) {

        $Properties = @($Record.Properties)

        If ($Properties.Count -lt 2 -or $null -eq $Properties[1].Value) {

            Continue

        }

        $Luid = [string]$Properties[1].Value

        If ($Seen.ContainsKey($Luid)) {

            Continue

        }

        $Seen[$Luid] = $true

        If ($Record.Id -ne 1106) {

            Continue

        }

        $Code = [int]$Properties[0].Value
        $Label = "Unknown ($Code)"

        If ($Labels.ContainsKey($Code)) {

            $Label = $Labels[$Code]

        }

        $Result[$Luid] = $Label

    }

    $Result

}
