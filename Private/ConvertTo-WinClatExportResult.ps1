Function ConvertTo-WinClatExportResult {

    <#

    .SYNOPSIS
        Builds a WinClat.ExportResult output object, or the WinClat.ExportData object that carries the dump back from the target.

    .DESCRIPTION
        Creates a WinClat.ExportResult object with the properties from DESIGN.md, section 6, in a fixed order, so success and failure rows have the same columns for Export-Csv.

        When Content is supplied, the object is a WinClat.ExportData object instead: the same properties plus Content, the dump text. It is internal to Export-WinClatConfiguration, which writes Content to a file on the calling computer and returns a WinClat.ExportResult without it (section 7.5).

        Used on the target to return the dump, and by Export-WinClatConfiguration to build results and Unreachable rows.

        This function must also be available in the remote session. See DESIGN.md, section 4.3.

    .PARAMETER ComputerName
        The computer name. Invoke-WinClatRemote replaces it with the name as supplied by the caller.

    .PARAMETER Status
        One of the status values in DESIGN.md, section 4.5.

    .PARAMETER Path
        The full path of the file written, or $null when no file was written.

    .PARAMETER Settings
        A hashtable with the Permit, Pref64FromDns, Pref64FromRA, and AutoEnable values parsed from the dump. Omit for failures.

    .PARAMETER PolicyControlled
        The settings that Group Policy controls, as from Get-WinClatPolicyControlled, or $null when unknown.

    .PARAMETER CollectedAtUtc
        The UTC time the dump was taken.

    .PARAMETER Message
        Detail for failures, or $null.

    .PARAMETER Content
        The dump text. When supplied, a WinClat.ExportData object is returned.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        WinClat.ExportResult, or WinClat.ExportData when Content is supplied.

    .EXAMPLE
        ConvertTo-WinClatExportResult -ComputerName 'CLIENT4' -Status 'Unreachable' -Message 'WinRM cannot complete the operation.' -CollectedAtUtc (Get-Date).ToUniversalTime()

        Returns a WinClat.ExportResult object with Status Unreachable and no file.

    .LINK
        https://learn.microsoft.com/powershell/scripting/learn/deep-dives/everything-about-pscustomobject

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
    [OutputType('WinClat.ExportResult', 'WinClat.ExportData')]

    Param (

        [AllowNull()]
        [AllowEmptyString()]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [string]$Status,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$Path,

        [hashtable]$Settings,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$PolicyControlled,

        [AllowNull()]
        [object]$CollectedAtUtc,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$Message,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$Content

    )

    $TypeName = 'WinClat.ExportResult'

    If ($PSBoundParameters.ContainsKey('Content')) {

        $TypeName = 'WinClat.ExportData'

    }

    # [string] parameters turn $null into ''; keep $null for values that were not supplied.
    $Result = [ordered]@{

        PSTypeName       = $TypeName
        ComputerName     = $ComputerName
        Status           = $Status
        Path             = $null
        Permit           = $null
        Pref64FromDns    = $null
        Pref64FromRA     = $null
        AutoEnable       = $null
        PolicyControlled = $null
        CollectedAtUtc   = $CollectedAtUtc
        Message          = $null

    }

    If ($Path) {

        $Result['Path'] = $Path

    }

    ForEach ($Name in @('Permit', 'Pref64FromDns', 'Pref64FromRA', 'AutoEnable')) {

        If ($Settings -and $Settings.ContainsKey($Name)) {

            $Result[$Name] = $Settings[$Name]

        }

    }

    If ($PSBoundParameters.ContainsKey('PolicyControlled')) {

        $Result['PolicyControlled'] = $PolicyControlled

    }

    If ($Message) {

        $Result['Message'] = $Message

    }

    If ($TypeName -eq 'WinClat.ExportData') {

        $Result['Content'] = $Content

    }

    [PSCustomObject]$Result

}
