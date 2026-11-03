---
name: scripts
description: Library of ready-made admin scripts (Windows CMD/PowerShell, Bash) — Azure VM start with status polling, safe "smart" reboot that checks for running lab software, planned reboot, IP/MAC address logging, file listing of a folder, cloning a Linux user with its group memberships. Use when the user asks to start/wake an Azure VM, reboot a PC (safely or on schedule), collect IP/MAC of a machine, dump a list of files in a directory, create a Linux user with the same groups/permissions as an existing one, or asks for "my script", "a ready script", "скрипт из библиотеки", "готовый скрипт" for one of these tasks. Prefer a script from this library over writing a new one.
---

# Ready-made script library

A set of the user's tested scripts for routine admin tasks.
All scripts are in the `My scripts/` folder next to this file (the path contains a space — always quote it).

## How to use

1. Find a matching script in the catalog below.
2. Read the whole file before using it — the version on disk takes precedence over the description here.
3. To change settings (VM name, output path, process list), pass them as arguments; if the script does not accept them, make an adapted copy. Do not modify the original unless the user asks.
4. **Never run** scripts that reboot the machine, start paid cloud resources, or create users / change permissions without explicit confirmation from the user.
5. If no script fits, tell the user so. Write a new script only when the user explicitly asks for one.
6. **Search requests** ("find", "search", "найди", "поищи"): search only within this skill's `My scripts/` folder — first the catalog below, then the contents of the files. Do not search anywhere outside that folder (current project, other directories, the web). If nothing matches, reply "Not found in the library" and do not offer alternatives unless the user asks for them.

## Catalog

| Script | Platform | Purpose |
|---|---|---|
| `start_vm_azure.ps1` | PowerShell + Az module | Start an Azure VM and keep re-checking until it is Running |
| `start_vm_azure.sh` | Bash + Azure CLI + jq | Same as above for Linux/macOS/WSL |
| `smart_reboot.ps1` | PowerShell | Reboot the PC only if no "blocking" programs are running |
| `reboot.cmd` | CMD | Planned reboot after 10 seconds |
| `Get_mac.cmd` | CMD | Append the machine's IPv4 address, date/time and MAC addresses to a log file |
| `cmd_file_names_list.cmd` | CMD | Save a list of files in the current folder to `files.txt` |
| `clone_user.sh` | Bash (Linux, root) | Create a new Linux user with the same supplementary groups as an existing one |

---

### start_vm_azure.ps1

Checks the VM power state, sends a start command if needed (`Start-AzVM -NoWait`) and re-checks every N seconds until the VM reaches `VM running`. Useful when a start fails because of insufficient capacity in the region (allocation failure) — the script keeps retrying.

- Parameters: `-ResourceGroup` (required), `-VMName` (required), `-CheckInterval` (seconds, default 120).
- Requirements: `Install-Module -Name Az -Scope CurrentUser`, `Connect-AzAccount`, `Set-AzContext -Subscription "<ID or name>"`. The script verifies login and subscription on startup and exits with an error if either is missing.
- Loops until the VM is running — stop with Ctrl+C.

```powershell
& ".\My scripts\start_vm_azure.ps1" -ResourceGroup "SCHRODINGER_FEP" -VMName "SchFEP-pc1" -CheckInterval 60
```

> The `.EXAMPLE` block inside the file uses the old name `start_vm_azure_en.ps1`; the actual file name is `start_vm_azure.ps1`.

### start_vm_azure.sh

Bash version of the same logic using `az vm get-instance-view` / `az vm start --no-wait`.

- Arguments: `--resource-group`, `--vm-name`, `--interval` (default 120). If the resource group or VM name is omitted, the script prompts for it interactively.
- Requirements: Azure CLI, `jq`, `az login`, `az account set --subscription "<ID or name>"`.

```bash
./start_vm_azure.sh --resource-group "SCHRODINGER_FEP" --vm-name "SchFEP-pc1" --interval 60
```

> The Usage comment inside the file uses the old name `start_vm_azure_en.sh`.

### smart_reboot.ps1

Checks whether any process from the `$processes` list is running (currently `PHERAstar`, plate reader software). If at least one is found, the reboot is cancelled and a popup lists the processes (it waits for the user to click OK). Otherwise it runs `Restart-Computer -Force`.

- To protect more programs, add their process names (without `.exe`) to the `$processes` array.
- Suitable for Task Scheduler (nightly reboot of lab PCs without the risk of interrupting a measurement).

```powershell
powershell -ExecutionPolicy Bypass -File ".\My scripts\smart_reboot.ps1"
```

### reboot.cmd

`shutdown /r /t 10 /c "Planned reboot" /d p:0:0` — planned reboot after 10 seconds with a comment and the "Other (Planned)" reason code. To cancel within those 10 seconds: `shutdown /a`.

### Get_mac.cmd

Appends to `mac.txt` on the Desktop: an empty line, the IPv4 address (from `ipconfig`), date and time, `getmac` output and a separator line. Handy for inventory: run it on each machine to build a log of addresses.

- Output file: `%USERPROFILE%\Desktop\mac.txt` (current user's Desktop).
- With multiple network adapters, only the first IPv4 address found is recorded.

### cmd_file_names_list.cmd

`dir /a /b /-p /o:gen >files.txt` — lists all files and folders (including hidden/system) in the current directory, names only, sorted folders first, then by extension and name. Output goes to `files.txt` in the same folder (overwritten each run). Run it from the target folder, e.g. by placing the script there or `cd`-ing into it first.

### clone_user.sh

Creates a new Linux user and copies the group memberships of an existing user. Steps:

1. Checks root privileges, that the existing user exists and that the new one does not.
2. Creates the new user with `adduser` (home directory is created; password and user details are prompted interactively).
3. Adds the new user to all groups of the existing user except its own primary group (`usermod -aG`).
4. If `sudo` was among the copied groups, asks whether to enable passwordless sudo (`NOPASSWD`) by writing `/etc/sudoers.d/<new_user>`. Default is No.
5. Prints `id <new_user>`.

- Arguments: `<existing_user> <new_user>`; if either is missing, the script prompts for both.
- Requirements: root (`sudo`), `adduser` — Debian/Ubuntu-family distributions (on RHEL/Fedora `adduser` behaves differently and does not prompt for a password).
- Copies only groups. Home directory contents, shell settings, SSH keys and the existing user's own sudoers entries are not copied.
- Always interactive (password prompt), so not suitable for unattended runs.

```bash
sudo ./clone_user.sh olduser newuser
```
