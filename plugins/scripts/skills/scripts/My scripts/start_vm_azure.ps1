<#
.SYNOPSIS
    Automatically start an Azure VM with state checking.
.DESCRIPTION
    Checks the VM's power state, starts it if needed,
    then re-checks periodically until it's running.
.PARAMETER ResourceGroup
    Name of the resource group containing the VM.
.PARAMETER VMName
    Name of the VM to start.
.PARAMETER CheckInterval
    Seconds to wait between checks. Defaults to 120 (2 minutes).
.EXAMPLE
    .\start_vm_azure_en.ps1 -ResourceGroup "SCHRODINGER_FEP" -VMName "SchFEP-pc1"
.EXAMPLE
    .\start_vm_azure_en.ps1 -ResourceGroup "SCHRODINGER_FEP" -VMName "SchFEP-pc1" -CheckInterval 60
.NOTES
    Requirements:
      - Az module installed (Install-Module -Name Az -Scope CurrentUser)
      - Logged in: Connect-AzAccount
      - Correct subscription selected: Set-AzContext -Subscription "<ID or name>"

    The script checks login and subscription selection on startup and
    exits with an error if either is missing.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $true)]
    [string]$VMName,

    [int]$CheckInterval = 120   # seconds between checks (default: 2 minutes)
)

function Get-VMPowerState {
    param($ResourceGroup, $VMName)

    try {
        $vm = Get-AzVM -ResourceGroupName $ResourceGroup -Name $VMName -Status -ErrorAction Stop
    }
    catch {
        Write-Warning "Get-AzVM failed: $($_.Exception.Message)"
        return "Unknown"
    }

    # Depending on the Az module version, statuses can be either directly
    # on the VM object or nested under InstanceView. Check both.
    $statuses = $vm.Statuses
    if (-not $statuses -and $vm.InstanceView) {
        $statuses = $vm.InstanceView.Statuses
    }

    # A power state means the VM has an actual running/deallocated/etc status.
    $powerStatus = $statuses | Where-Object { $_.Code -like "PowerState/*" }
    if ($powerStatus) {
        return $powerStatus.DisplayStatus
    }

    # No power state yet - check whether the last operation failed outright
    # (e.g. capacity/allocation errors), which Azure reports as a
    # ProvisioningState status rather than a PowerState one.
    $failedStatus = $statuses | Where-Object { $_.Code -like "ProvisioningState/failed*" }
    if ($failedStatus) {
        Write-Warning "Provisioning failed: $($failedStatus.Message)"
        return "Failed"
    }

    Write-Warning "Could not determine power state from the returned object. Raw statuses:"
    $statuses | Format-List | Out-String | Write-Warning
    return "Unknown"
}

function Write-Log {
    param($Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$timestamp - $Message"
}

function Show-Countdown {
    param([int]$Seconds)
    for ($i = $Seconds; $i -ge 1; $i--) {
        Write-Host -NoNewline ("`rNext check in {0,3} s... " -f $i)
        Start-Sleep -Seconds 1
    }
    Write-Host ("`r" + (" " * 30) + "`r") -NoNewline
}

function Test-AzLoginAndSubscription {
    $context = Get-AzContext
    if (-not $context -or -not $context.Account) {
        Write-Error "Not logged in to Azure. Run Connect-AzAccount first."
        exit 1
    }
    if (-not $context.Subscription) {
        Write-Error "No subscription selected. Run Set-AzContext -Subscription `"<ID or name>`" first."
        exit 1
    }
    Write-Log "Logged in as $($context.Account.Id), subscription: $($context.Subscription.Name) ($($context.Subscription.Id))"
}

Test-AzLoginAndSubscription

Write-Log "Starting monitoring of VM '$VMName' (resource group: $ResourceGroup)"

while ($true) {
    $state = Get-VMPowerState -ResourceGroup $ResourceGroup -VMName $VMName
    Write-Log "Current state: $state"

    if ($state -eq "VM running") {
        Write-Log "VM '$VMName' started successfully!"
        Write-Host "Success: VM '$VMName' is now Running." -ForegroundColor Green
        break
    }

    Write-Log "State is not 'running'. Sending start command..."
    Start-AzVM -ResourceGroupName $ResourceGroup -Name $VMName -NoWait | Out-Null

    Show-Countdown -Seconds $CheckInterval
}
