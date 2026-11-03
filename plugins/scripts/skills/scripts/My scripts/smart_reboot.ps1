# List of processes to check (specify without .exe)
$processes = @("PHERAstar")
$foundProcesses = @() # Array to store all found processes

foreach ($proc in $processes) {
    # If the process is found, add it to the array
    if (Get-Process $proc -ErrorAction SilentlyContinue) {
        $foundProcesses += $proc
    }
}

# Check if the array has any items (meaning at least one process was found)
if ($foundProcesses.Count -gt 0) {
    # Visual emphasis: convert to uppercase and wrap in square brackets
    $highlightedProcesses = $foundProcesses | ForEach-Object { "[$($_.ToUpper())]" }
    
    # Join the result with a comma and a space
    $processList = $highlightedProcesses -join ", "
    
    # If blocking processes are found, display a popup window
    $wshell = New-Object -ComObject Wscript.Shell
    $message = "Reboot cancelled.`nRunning processes detected: $processList"
    $title = "Smart Reboot"
    
    # A value of 0 means the window will wait indefinitely for user input
    $wshell.Popup($message, 0, $title, 48)
} else {
    # If no blocking processes are found, restart the PC
    Restart-Computer -Force
}