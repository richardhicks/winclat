Function New-WinClatTally {

    <#

    .SYNOPSIS
        Creates the tally that Measure-WinClatResult fills and that Complete-WinClatResult and Write-WinClatFailureSummary report.

    .DESCRIPTION
        Returns a hashtable with:
          - Computers: the distinct computer names seen (case-insensitive).
          - Failed: the first failure status of each computer that did not complete.
          - FailureStatus: the statuses that count as not completed (DESIGN.md, section 4.6).
          - Single: $true when the targets reduce to one name, after trimming, dropping blanks and '#' comments, and removing case-insensitive duplicates.
          - Held: the results held back for a single computer, so Complete-WinClatResult can show exactly one result as a list and several as a table (DESIGN.md, section 6).

        New- creates an object in memory only and changes no system state.

    .PARAMETER ComputerName
        The targets of the run, used to decide whether it is for a single computer. When omitted, the run is treated as several computers and nothing is held.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Collections.Hashtable.

    .EXAMPLE
        $Tally = New-WinClatTally -ComputerName $Targets.ToArray()

        Creates an empty tally for one run of a public function.

    .LINK
        https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_hash_tables

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
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Creates an in-memory object only.')]

    Param (

        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$ComputerName

    )

    $Names = @($ComputerName | ForEach-Object -Process { "$_".Trim() } | Where-Object -FilterScript { $_ -and -not $_.StartsWith('#') } | Sort-Object -Unique)

    @{

        Computers     = New-Object -TypeName 'System.Collections.Generic.HashSet[string]' -ArgumentList ([System.StringComparer]::OrdinalIgnoreCase)
        Failed        = New-Object -TypeName 'System.Collections.Generic.Dictionary[string,string]' -ArgumentList ([System.StringComparer]::OrdinalIgnoreCase)
        FailureStatus = @('Unreachable', 'FeatureNotAvailable', 'ElevationRequired', 'Failed')
        Single        = $Names.Count -eq 1
        Held          = New-Object -TypeName 'System.Collections.Generic.List[object]'

    }

}
