#!/bin/bash

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
  echo "Error: This script must be run as root (sudo)."
  exit 1
fi

# Get usernames (from parameters or interactive prompt)
if [ -n "$1" ] && [ -n "$2" ]; then
  OLD_USER="$1"
  NEW_USER="$2"
else
  read -p "Enter the name of the EXISTING user: " OLD_USER
  read -p "Enter the name of the NEW user: " NEW_USER
fi

# Check for empty input
if [ -z "$OLD_USER" ] || [ -z "$NEW_USER" ]; then
  echo "Error: Usernames cannot be empty."
  exit 1
fi

# Check if the old user exists
if ! id "$OLD_USER" >/dev/null 2>&1; then
  echo "Error: User '$OLD_USER' does not exist."
  exit 1
fi

# Check if the new user already exists
if id "$NEW_USER" >/dev/null 2>&1; then
  echo "Error: User '$NEW_USER' already exists."
  exit 1
fi

echo "======================================"
echo "Step 1: Creating user '$NEW_USER'"
echo "======================================"
# The adduser command will create the home directory and interactively ask for a password
if ! adduser "$NEW_USER"; then
  echo "Critical error creating the user."
  exit 1
fi

echo -e "\n======================================"
echo "Step 2: Copying permissions (groups)"
echo "======================================"
# Get all groups of the old user except its primary group.
# tr puts one group per line, grep -vx drops the exact primary group name, paste joins with commas.
PRIMARY_GROUP=$(id -gn "$OLD_USER")
GROUPS_TO_ADD=$(id -nG "$OLD_USER" | tr ' ' '\n' | grep -vx "$PRIMARY_GROUP" | paste -sd, -)

if [ -n "$GROUPS_TO_ADD" ]; then
  echo "Adding '$NEW_USER' to groups: $GROUPS_TO_ADD"
  usermod -aG "$GROUPS_TO_ADD" "$NEW_USER"
  echo "Permissions copied successfully!"
else
  echo "User '$OLD_USER' has no additional groups to copy."
fi

# Check if 'sudo' is in the list of copied groups (using comma delimiters for exact match)
if [[ ",$GROUPS_TO_ADD," == *",sudo,"* ]]; then
  echo -e "\n======================================"
  echo "Step 3: Optional Sudo Configuration"
  echo "======================================"
  read -p "The 'sudo' group was copied. Do you want to add passwordless sudo usage (NOPASSWD) for '$NEW_USER'? [y/N]: " NOPASSWD_CHOICE
  
  case "$NOPASSWD_CHOICE" in
    [yY][eE][sS]|[yY])
      echo "Configuring passwordless sudo for '$NEW_USER'..."
      # Create a new sudoers file for the user and set strict permissions
      echo "$NEW_USER ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/$NEW_USER"
      chmod 0440 "/etc/sudoers.d/$NEW_USER"
      echo "Passwordless sudo enabled successfully."
      ;;
    *)
      echo "Skipping passwordless sudo setup (default behavior kept)."
      ;;
  esac
fi

echo -e "\n======================================"
echo "Done! Final profile for '$NEW_USER':"
id "$NEW_USER"