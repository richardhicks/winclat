Function Get-WinClatRemoteScript {

    <#

    .SYNOPSIS
        Builds a self-contained script block that carries the private helpers it needs.

    .DESCRIPTION
        Private helpers do not exist in a remote session (DESIGN.md, section 4.3). This function prepends the definition of each named helper, taken from the module's own function bodies, to the body script block and returns the result as one script block.

        The body is wrapped as '& { <body> } @args', so it can keep its own Param block while the helper definitions come first. Arguments passed with Invoke-Command -ArgumentList reach the body's parameters positionally.

        The script does not set $VerbosePreference. Invoke-WinClatRemote sends the caller's preference with it, because over WinRM only the target's preference decides whether verbose records are displayed (DESIGN.md, section 4.3).

        The same script block is used for local runs, remote runs, and unit tests.

    .PARAMETER HelperName
        The private helper functions the body calls.

    .PARAMETER ScriptBlock
        The body to run on the target.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.ScriptBlock.

    .EXAMPLE
        Get-WinClatRemoteScript -HelperName 'ConvertFrom-WinClatNetshOutput', 'ConvertTo-WinClatTimeSpan' -ScriptBlock { ConvertFrom-WinClatNetshOutput -InputObject (netsh.exe interface clat show global) }

        Returns a script block that defines both helpers and then runs the body.

    .LINK
        https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_script_blocks

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

    Param (

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$HelperName,

        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock

    )

    $Definitions = ForEach ($Name in $HelperName) {

        $Command = Get-Command -Name $Name -CommandType Function -ErrorAction Stop
        "Function $Name {`n$($Command.ScriptBlock.ToString())`n}`n"

    }

    $Text = (@($Definitions) -join "`n") + "`n& {`n$($ScriptBlock.ToString())`n} @args`n"

    [scriptblock]::Create($Text)

}
