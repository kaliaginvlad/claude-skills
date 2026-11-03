#!/bin/bash
#
# Automatically start an Azure VM with state checking.
# Checks the VM's power state, starts it if needed,
# then re-checks periodically until it's running.
#
# Requirements:
#   - Azure CLI installed (az)
#   - jq installed (sudo apt install jq)
#   - Logged in: az login
#   - Correct subscription selected: az account set --subscription "<ID or name>"
#
# Usage:
#   ./start_vm_azure_en.sh --resource-group "myRG" --vm-name "myVM" [--interval 120]
#
# If --resource-group or --vm-name is omitted, the script will prompt for it.

set -euo pipefail

# ==== Defaults ====
CHECK_INTERVAL=120
RESOURCE_GROUP=""
VM_NAME=""
# ===================

usage() {
    echo "Usage: $0 --resource-group <name> --vm-name <name> [--interval <seconds>]"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        --vm-name)
            VM_NAME="$2"
            shift 2
            ;;
        --interval)
            CHECK_INTERVAL="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown argument: $1"
            usage
            ;;
    esac
done

if [[ -z "$RESOURCE_GROUP" ]]; then
    read -rp "Resource group: " RESOURCE_GROUP
fi

if [[ -z "$VM_NAME" ]]; then
    read -rp "VM name: " VM_NAME
fi

if [[ -z "$RESOURCE_GROUP" || -z "$VM_NAME" ]]; then
    echo "Error: resource group and VM name are required." >&2
    usage
fi

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

check_login_and_subscription() {
    local account_json
    if ! account_json=$(az account show -o json 2>/dev/null); then
        echo "Error: Not logged in to Azure. Run az login first." >&2
        exit 1
    fi

    local sub_id sub_name user
    sub_id=$(echo "$account_json" | jq -r '.id')
    sub_name=$(echo "$account_json" | jq -r '.name')
    user=$(echo "$account_json" | jq -r '.user.name')

    if [[ -z "$sub_id" || "$sub_id" == "null" ]]; then
        echo "Error: No subscription selected. Run az account set --subscription \"<ID or name>\" first." >&2
        exit 1
    fi

    log "Logged in as $user, subscription: $sub_name ($sub_id)"
}

get_vm_state() {
    local statuses
    if ! statuses=$(az vm get-instance-view \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VM_NAME" \
        --query "instanceView.statuses" \
        --output json 2>/tmp/az_error.log); then
        echo "Warning: az vm get-instance-view failed: $(cat /tmp/az_error.log)" >&2
        echo "Unknown"
        return
    fi

    # A power state means the VM has an actual running/deallocated/etc status.
    local power_status
    power_status=$(echo "$statuses" | jq -r '[.[] | select(.code | startswith("PowerState/"))][0].displayStatus // empty')
    if [[ -n "$power_status" ]]; then
        echo "$power_status"
        return
    fi

    # No power state yet - check whether the last operation failed outright
    # (e.g. capacity/allocation errors), which Azure reports as a
    # ProvisioningState status rather than a PowerState one.
    local failed_message
    failed_message=$(echo "$statuses" | jq -r '[.[] | select(.code | startswith("ProvisioningState/failed"))][0].message // empty')
    if [[ -n "$failed_message" ]]; then
        echo "Warning: Provisioning failed: $failed_message" >&2
        echo "Failed"
        return
    fi

    echo "Warning: Could not determine power state from the returned object. Raw statuses:" >&2
    echo "$statuses" | jq . >&2
    echo "Unknown"
}

show_countdown() {
    local seconds=$1
    local i
    for ((i = seconds; i >= 1; i--)); do
        printf "\rNext check in %3d s... " "$i"
        sleep 1
    done
    printf "\r%30s\r" " "
}

check_login_and_subscription

log "Starting monitoring of VM '$VM_NAME' (resource group: $RESOURCE_GROUP)"

while true; do
    STATE=$(get_vm_state)
    log "Current state: $STATE"

    if [[ "$STATE" == "VM running" ]]; then
        log "VM '$VM_NAME' started successfully!"
        echo "Success: VM '$VM_NAME' is now Running."
        break
    fi

    log "State is not 'running'. Sending start command..."
    az vm start --resource-group "$RESOURCE_GROUP" --name "$VM_NAME" --no-wait \
        || log "Warning: failed to send start command, will retry next iteration"

    show_countdown "$CHECK_INTERVAL"
done
