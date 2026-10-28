Function Complete-WinClatResult {

    <#

    .SYNOPSIS
        Returns the results held for a single computer, marking a lone result for the list view.

    .DESCRIPTION
        A run returns one result as a list and several as a table (DESIGN.md, section 6). Views are selected by type name, so when exactly one result was held, the type name '<type>#Single' is inserted ahead of its normal one, for example WinClat.Instance#Single, and WinCLAT.Format.ps1xml shows it as a list of every property. Several held results are returned unchanged and shown as a table.

        Results are held by Measure-WinClatResult only when the run is for a single computer; for several computers they stream as they arrive and this function returns nothing.

    .PARAMETER Tally
        The tally from New-WinClatTally, filled by Measure-WinClatResult.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSObject. The held results.

    .EXAMPLE
        Complete-WinClatResult -Tally $Tally

        Returns the one result of a single-computer run marked for the list view.

    .LINK
        https://learn.microsoft.com/powershell/scripting/developer/format/format-schema-xml-reference

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
    [OutputType([PSObject])]

    Param (

        [Parameter(Mandatory)]
        [hashtable]$Tally

    )

    If ($Tally.Held.Count -eq 1) {

        $Result = $Tally.Held[0]
        $TypeName = $Result.PSObject.TypeNames[0]

        If ($TypeName -like 'WinClat.*' -and $TypeName -notlike '*#Single') {

            $Result.PSObject.TypeNames.Insert(0, "$TypeName#Single")

        }

    }

    ForEach ($Result in $Tally.Held) {

        $Result

    }

    $Tally.Held.Clear()

}
