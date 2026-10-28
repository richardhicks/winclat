Function ConvertTo-WinClatTestSummary {

    <#

    .SYNOPSIS
        Summarizes the WinClat.TestResult rows of one computer.

    .DESCRIPTION
        Builds the WinClat.TestSummary object that Test-WinClat returns by default (DESIGN.md, sections 6 and 8.6):
          - Status: the first non-Success Status among the rows, or Success.
          - Overall: Fail when any row failed, otherwise Warning when any row warned, otherwise Pass. NotApplicable when Status is NotSupported (Windows Server).
          - Passed, Warnings, Failures: the number of rows with each Result. Info and Skipped rows are not counted.
          - Translating: $true when an 'Instance active' check passed, $false when it ran on at least one interface without passing, and $null when it did not run.
          - Issues: the checks with Result Fail or Warning, in row order and each once, as 'Check (InterfaceAlias)' or 'Check' for checks without an interface, joined with '; ', for example 'CLAT address (Internal); Functional test'. $null when there are none.

        Runs on the calling computer only.

    .PARAMETER ComputerName
        The computer name as supplied by the caller.

    .PARAMETER InputObject
        The WinClat.TestResult rows for that computer.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        WinClat.TestSummary.

    .EXAMPLE
        ConvertTo-WinClatTestSummary -ComputerName 'CLIENT4' -InputObject $Rows

        Returns one summary object for CLIENT4.

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
    [OutputType('WinClat.TestSummary')]

    Param (

        [Parameter(Mandatory)]
        [string]$ComputerName,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$InputObject

    )

    $Status = 'Success'
    $NonSuccess = @($InputObject | Where-Object -FilterScript { $_.Status -and $_.Status -ne 'Success' })

    If ($NonSuccess.Count -gt 0) {

        $Status = $NonSuccess[0].Status

    }

    $Passed = @($InputObject | Where-Object -FilterScript { $_.Result -eq 'Pass' }).Count
    $Warnings = @($InputObject | Where-Object -FilterScript { $_.Result -eq 'Warning' }).Count
    $Failures = @($InputObject | Where-Object -FilterScript { $_.Result -eq 'Fail' }).Count

    $Overall = 'Pass'

    If ($Failures -gt 0) {

        $Overall = 'Fail'

    }

    ElseIf ($Warnings -gt 0) {

        $Overall = 'Warning'

    }

    # Windows Server never receives WinCLAT, so its checks are not applicable rather than passed.
    If ($Status -eq 'NotSupported') {

        $Overall = 'NotApplicable'

    }

    $Translating = $null
    $InstanceRows = @($InputObject | Where-Object -FilterScript { $_.Check -eq 'Instance active' -and $_.Result -ne 'Skipped' })

    If ($InstanceRows.Count -gt 0) {

        $Translating = @($InstanceRows | Where-Object -FilterScript { $_.Result -eq 'Pass' }).Count -gt 0

    }

    # The failed and warning checks in row order, with the interface when there is one, as one string so the summary
    # stays flat for Export-Csv (DESIGN.md, section 8.6).
    $Issues = New-Object -TypeName 'System.Collections.Generic.List[string]'

    ForEach ($Row in @($InputObject | Where-Object -FilterScript { $_.Result -eq 'Fail' -or $_.Result -eq 'Warning' })) {

        $Name = [string]$Row.Check

        If ($Row.InterfaceAlias) {

            $Name = "$($Row.Check) ($($Row.InterfaceAlias))"

        }

        If (-not $Issues.Contains($Name)) {

            $Issues.Add($Name)

        }

    }

    $IssueText = $null

    If ($Issues.Count -gt 0) {

        $IssueText = $Issues.ToArray() -join '; '

    }

    [PSCustomObject]@{

        PSTypeName   = 'WinClat.TestSummary'
        ComputerName = $ComputerName
        Status       = $Status
        Overall      = $Overall
        Passed       = $Passed
        Warnings     = $Warnings
        Failures     = $Failures
        Translating  = $Translating
        Issues       = $IssueText

    }

}
