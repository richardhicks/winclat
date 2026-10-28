Function Get-WinClatTargetName {

    <#

    .SYNOPSIS
        Returns the computer name to use for one pipeline input object.

    .DESCRIPTION
        Called from the Process block of each public function with the current pipeline object and the bound ComputerName value (DESIGN.md, section 4.2).

        For objects such as those from Get-ADComputer and Get-ADObject, the first non-empty property of DNSHostName, ComputerName, Name, and CN is used. DNSHostName is preferred over Name, which matters in multi-domain and disjoint namespace environments. The object's string form is never used, because for an ADComputer object it is the distinguished name.

        For strings, or when no pipeline object is present, the bound ComputerName value is returned unchanged. Trimming, comment handling, and de-duplication happen in Invoke-WinClatRemote.

    .PARAMETER InputObject
        The current pipeline object ($_), or $null when ComputerName was supplied as a parameter.

    .PARAMETER ComputerName
        The bound ComputerName parameter value.

    .PARAMETER Cmdlet
        The $PSCmdlet of the public function. The error for an object without a usable name is written through it, so it is attributed to that function. When omitted, the error is written through this function.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.String.

    .EXAMPLE
        Get-WinClatTargetName -InputObject $_ -ComputerName $ComputerName -Cmdlet $PSCmdlet

        Returns 'client4.corp.example.com' for an ADComputer object whose DNSHostName is client4.corp.example.com.

    .LINK
        https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_pipelines

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
    [OutputType([string])]

    Param (

        [AllowNull()]
        [object]$InputObject,

        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$ComputerName,

        [System.Management.Automation.PSCmdlet]$Cmdlet

    )

    If ($null -ne $InputObject -and $InputObject -isnot [string]) {

        ForEach ($Property in @('DNSHostName', 'ComputerName', 'Name', 'CN')) {

            $Member = $InputObject.PSObject.Properties[$Property]

            If ($Member -and $null -ne $Member.Value -and [string]$Member.Value -ne '') {

                Return [string]$Member.Value

            }

        }

        If (-not $Cmdlet) {

            $Cmdlet = $PSCmdlet

        }

        $Exception = New-Object -TypeName System.ArgumentException -ArgumentList 'The input object has no DNSHostName, ComputerName, Name, or CN property with a value, so no computer name can be determined.'
        $Cmdlet.WriteError((New-Object -TypeName System.Management.Automation.ErrorRecord -ArgumentList $Exception, 'WinClatNoComputerName', 'InvalidArgument', $InputObject))
        Return

    }

    ForEach ($Name in $ComputerName) {

        $Name

    }

}
