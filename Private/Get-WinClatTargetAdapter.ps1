Function Get-WinClatTargetAdapter {

    <#

    .SYNOPSIS
        Finds the adapter that Set-WinClatInstance should change and checks that it can run CLAT.

    .DESCRIPTION
        Looks up one adapter with Get-NetAdapter, by exact name (case-insensitive, no wildcards) or by interface index (DESIGN.md, section 7.4). Returns an object with InterfaceAlias, InterfaceIndex, InterfaceLuid (the adapter NetLuid, used to match IPxlatCfg events), and Problem. Problem is $null when the adapter can be changed, and otherwise explains why it was refused:
          - No adapter has that name or index.
          - The adapter is not up.
          - IPv6 (ms_tcpip6) is not bound to the adapter, so CLAT can never run on it.

        If the IPv6 binding cannot be read, the adapter is not refused for that reason.

        This function must also be available in the remote session. See DESIGN.md, section 4.3.

    .PARAMETER InterfaceAlias
        The exact adapter name. Leave empty to look up by index.

    .PARAMETER InterfaceIndex
        The interface index, used when InterfaceAlias is empty.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSCustomObject with InterfaceAlias, InterfaceIndex, InterfaceLuid, and Problem properties.

    .EXAMPLE
        Get-WinClatTargetAdapter -InterfaceAlias 'Internal'

        Returns InterfaceAlias 'Internal', its interface index, and Problem $null when the adapter is up with IPv6 bound.

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
    [OutputType([PSCustomObject])]

    Param (

        [AllowNull()]
        [AllowEmptyString()]
        [string]$InterfaceAlias,

        [int]$InterfaceIndex

    )

    $Adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object -FilterScript { $_ })

    If ($InterfaceAlias) {

        $Match = @($Adapters | Where-Object -FilterScript { $_.Name -eq $InterfaceAlias })
        $NotFound = "No network adapter named '$InterfaceAlias' was found."
        $Result = [PSCustomObject]@{ InterfaceAlias = $InterfaceAlias; InterfaceIndex = $null; InterfaceLuid = $null; Problem = $null }

    }

    Else {

        $Match = @($Adapters | Where-Object -FilterScript { $_.ifIndex -eq $InterfaceIndex })
        $NotFound = "No network adapter with interface index $InterfaceIndex was found."
        $Result = [PSCustomObject]@{ InterfaceAlias = $null; InterfaceIndex = $InterfaceIndex; InterfaceLuid = $null; Problem = $null }

    }

    If ($Match.Count -eq 0) {

        $Result.Problem = $NotFound
        Return $Result

    }

    $Adapter = $Match[0]
    $Result.InterfaceAlias = $Adapter.Name
    $Result.InterfaceIndex = $Adapter.ifIndex
    $Result.InterfaceLuid = $Adapter.NetLuid

    If ($Adapter.Status -ne 'Up') {

        $Result.Problem = "The adapter is not up (status: $($Adapter.Status)), so its CLAT state was not changed."
        Return $Result

    }

    Try {

        $Binding = @(Get-NetAdapterBinding -Name $Adapter.Name -ComponentID 'ms_tcpip6' -ErrorAction Stop)[0]

        If ($Binding -and -not $Binding.Enabled) {

            $Result.Problem = 'IPv6 is not bound to the adapter, so CLAT can never run on it. Its CLAT state was not changed.'

        }

    }

    Catch {

        Write-Verbose -Message "The IPv6 binding of '$($Adapter.Name)' could not be read, so it was not checked: $($_.Exception.Message)"

    }

    $Result

}
