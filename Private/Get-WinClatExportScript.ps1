Function Get-WinClatExportScript {

    <#

    .SYNOPSIS
        Returns the self-contained script block that Export-WinClatConfiguration runs on each target.

    .DESCRIPTION
        The script block takes no arguments and returns one object (DESIGN.md, section 7.5):
          1. Feature check: 'clat' in the 'netsh interface ?' sub-context list. If absent, returns a WinClat.ExportResult with Status NotSupported on Windows Server or FeatureNotAvailable on a client (Get-WinClatFeatureFailure).
          2. Runs 'netsh.exe interface clat dump', which does not require elevation. A non-zero exit code is classified with Get-WinClatNetshFailure.
          3. Parses the output with ConvertFrom-WinClatDump, the strict parser Import-WinClatConfiguration also uses, into Permit, Pref64FromDns, Pref64FromRA, and AutoEnable. Output that is not a WinCLAT configuration script returns Failed, so no file is written.
          4. Reads the policy registry key with Get-WinClatPolicyControlled and returns a WinClat.ExportData object with the dump text in Content.

        dump exports the persistent (local) values, not values set by Group Policy (section 10), so replaying a file restores the local configuration.

        Export-WinClatConfiguration and the unit tests both use this function, so the tests exercise the script block that is sent remotely.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.ScriptBlock.

    .EXAMPLE
        & (Get-WinClatExportScript)

        Returns the dump of the local computer as a WinClat.ExportData object.

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
    [OutputType([scriptblock])]

    Param ()

    $HelperName = @(

        'ConvertFrom-WinClatDump'
        'ConvertTo-WinClatExportResult'
        'Get-WinClatNetshFailure'
        'Get-WinClatPolicyControlled'
        'Get-WinClatFeatureFailure'
        'Test-WinClatFeature'

    )

    $Body = {

        If (-not (Test-WinClatFeature -InputObject @(netsh.exe interface '?'))) {

            # NotSupported on Windows Server, FeatureNotAvailable on a client that has not received the feature.
            $Missing = Get-WinClatFeatureFailure

            $Failure = @{

                ComputerName   = $env:COMPUTERNAME
                Status         = $Missing.Status
                CollectedAtUtc = (Get-Date).ToUniversalTime()
                Message        = $Missing.Message

            }

            ConvertTo-WinClatExportResult @Failure
            Return

        }

        $Output = @(netsh.exe interface clat dump)
        $ExitCode = $LASTEXITCODE
        $CollectedAtUtc = (Get-Date).ToUniversalTime()

        If ($ExitCode -ne 0) {

            $Classified = Get-WinClatNetshFailure -InputObject $Output -ExitCode $ExitCode
            ConvertTo-WinClatExportResult -ComputerName $env:COMPUTERNAME -Status $Classified.Status -CollectedAtUtc $CollectedAtUtc -Message $Classified.Message
            Return

        }

        # The same strict parser that Import-WinClatConfiguration uses, so every file written can be imported.
        $Parsed = ConvertFrom-WinClatDump -InputObject $Output

        If ($Parsed.Problem) {

            ConvertTo-WinClatExportResult -ComputerName $env:COMPUTERNAME -Status 'Failed' -CollectedAtUtc $CollectedAtUtc -Message "netsh.exe did not return a WinCLAT configuration script, so nothing was exported: $($Parsed.Problem)"
            Return

        }

        $Settings = $Parsed.Settings

        $Result = @{

            ComputerName     = $env:COMPUTERNAME
            Status           = 'Success'
            Settings         = $Settings
            PolicyControlled = Get-WinClatPolicyControlled
            CollectedAtUtc   = $CollectedAtUtc
            Content          = (@($Output | ForEach-Object -Process { "$_" }) -join "`r`n") + "`r`n"

        }

        ConvertTo-WinClatExportResult @Result

    }

    Get-WinClatRemoteScript -HelperName $HelperName -ScriptBlock $Body

}
