Function Get-WinClatRpcFailure {

    <#

    .SYNOPSIS
        Explains a failed 'show instance' that reports the RPC server is unavailable.

    .DESCRIPTION
        netsh.exe reads instance state from the IP Translation Configuration Service (IPxlatCfgSvc). The service is trigger-started and stays stopped while CLAT has nothing to translate, and 'show instance' then fails with "The RPC server is unavailable." (DESIGN.md, section 10). 'show global' does not need the service.

        Returns $null when the netsh output does not contain that message. Otherwise returns an object with:
          - Idle: $true when IPxlatCfgSvc is stopped and not disabled, which means no CLAT instance exists. $false in every other case.
          - Message: for an idle service, a message saying there is no active instance and why. For a disabled service, the netsh message followed by a sentence saying the service is disabled. Otherwise, the netsh message.

        This function must also be available in the remote session. See DESIGN.md, section 4.3.

    .PARAMETER InputObject
        The output of the failed 'netsh interface clat show instance' command.

    .INPUTS
        None. This function does not accept pipeline input.

    .OUTPUTS
        System.Management.Automation.PSCustomObject with Idle and Message properties, or $null.

    .EXAMPLE
        Get-WinClatRpcFailure -InputObject $Output

        Returns Idle $true when $Output is "The RPC server is unavailable." and IPxlatCfgSvc is stopped with a Manual start type.

    .LINK
        https://learn.microsoft.com/powershell/module/microsoft.powershell.management/get-service

    .NOTES
        Version:        1.2.0
        Creation Date:  November 13, 2026
        Last Updated:   November 13, 2026
        Author:         Richard Hicks
        Organization:   Richard M. Hicks Consulting, Inc.
        Contact:        rich@richardhicks.com
        Website:        https://www.richardhicks.com/

    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]

    Param (

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [AllowEmptyCollection()]
        [string[]]$InputObject

    )

    $Lines = @($InputObject | ForEach-Object -Process { $_ -split '\r?\n' } | ForEach-Object -Process { $_.Trim() } | Where-Object -FilterScript { $_ -ne '' })
    $NetshMessage = $Lines -join ' '

    If ($NetshMessage -notmatch 'The RPC server is unavailable') {

        Return $null

    }

    $Idle = $false
    $Message = $NetshMessage

    Try {

        $Service = Get-Service -Name 'IPxlatCfgSvc' -ErrorAction Stop

        If ("$($Service.StartType)" -eq 'Disabled') {

            $Message = "$NetshMessage The IP Translation Configuration Service (IPxlatCfgSvc) is disabled, so CLAT cannot start."

        }

        ElseIf ("$($Service.Status)" -eq 'Stopped') {

            $Idle = $true
            $Message = 'No active CLAT instance. The IP Translation Configuration Service (IPxlatCfgSvc) is not running, which is normal when CLAT has nothing to translate.'

        }

    }

    Catch {

        Write-Verbose -Message "The IP Translation Configuration Service (IPxlatCfgSvc) could not be read: $($_.Exception.Message)"

    }

    [PSCustomObject]@{

        Idle    = $Idle
        Message = $Message

    }

}
