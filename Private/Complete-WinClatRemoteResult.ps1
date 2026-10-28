Function Complete-WinClatRemoteResult {

    <#

    .SYNOPSIS
        Normalizes an object returned by Invoke-WinClatRemote.

    .DESCRIPTION
        Prepares an object returned from a local or remote run for output (DESIGN.md, section 4.3):
          - Sets ComputerName to the name as supplied by the caller, adding the property when it is missing.
          - Removes the properties added by Invoke-Command (PSComputerName, PSShowComputerName, RunspaceId) so Export-Csv output stays clean.
          - Restores the WinClat.* type name lost to deserialization ('Deserialized.WinClat.Instance' becomes 'WinClat.Instance') so the default views apply.

        Returns the same object.

    .PARAMETER InputObject
        The object to normalize.

    .PARAMETER ComputerName
        The computer name as supplied by the caller.

    .PARAMETER RemoveProperty
        The names of properties to remove.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSObject. The normalized input object.

    .EXAMPLE
        Complete-WinClatRemoteResult -InputObject $Result -ComputerName 'client4.corp.example.com' -RemoveProperty 'PSComputerName', 'PSShowComputerName', 'RunspaceId'

        Returns $Result with ComputerName set to client4.corp.example.com and the remoting properties removed.

    .LINK
        https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_remote_output

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
        [PSObject]$InputObject,

        [Parameter(Mandatory)]
        [string]$ComputerName,

        [string[]]$RemoveProperty = @()

    )

    ForEach ($Property in $RemoveProperty) {

        $InputObject.PSObject.Properties.Remove($Property)

    }

    If ($InputObject.PSObject.Properties['ComputerName']) {

        $InputObject.ComputerName = $ComputerName

    }

    Else {

        Add-Member -InputObject $InputObject -MemberType NoteProperty -Name 'ComputerName' -Value $ComputerName

    }

    $TypeNames = $InputObject.PSObject.TypeNames

    If ($TypeNames.Count -gt 0 -and $TypeNames[0] -like 'Deserialized.WinClat.*') {

        $TypeNames.Insert(0, $TypeNames[0].Substring('Deserialized.'.Length))

    }

    $InputObject

}
