#!/bin/bash

# Directory to process
HOME_DIR="/home"

# Temporary files to store UIDs, GIDs, and folder names
TEMP_UIDGID="/tmp/uid_gid_pairs.txt"
TEMP_REPEATED="/tmp/repeated_uid_gid.txt"
TEMP_UNIQUE="/tmp/unique_uid_gid.txt"

# Create temporary files
touch "$TEMP_UIDGID" "$TEMP_REPEATED" "$TEMP_UNIQUE"

# Extract UIDs and GIDs from the directories in /home
find "$HOME_DIR" -mindepth 1 -maxdepth 1 -type d | while read -r folder; do
    folder_name=$(basename "$folder")
    uid=$(stat -c '%u' "$folder")
    gid=$(stat -c '%g' "$folder")
    echo "$uid $gid $folder_name" >> "$TEMP_UIDGID"
done

# Identify unique and repeated UID/GID pairs
sort "$TEMP_UIDGID" | uniq -c | awk '$1==1 {print $2, $3, $4}' > "$TEMP_UNIQUE"
sort "$TEMP_UIDGID" | uniq -d | awk '{print $1, $2}' > "$TEMP_REPEATED"

# Function to create a user and group with a given UID and GID
create_user_and_group() {
    local uid=$1
    local gid=$2
    local name=$3

    # Create the group if it doesn't exist
    if ! getent group "$gid" >/dev/null 2>&1; then
        echo "Creating group with GID $gid"
        groupadd -g "$gid" "$name"
    fi

    # Create the user if it doesn't exist
    if ! id -u "$uid" >/dev/null 2>&1; then
        echo "Creating user with UID $uid"
        useradd -u "$uid" -g "$gid" "$name"
    fi
}

# Process unique UID/GID pairs
while read -r uid gid folder_name; do
    echo "Creating user and group named $folder_name with UID $uid and GID $gid."
    create_user_and_group "$uid" "$gid" "$folder_name"
done < "$TEMP_UNIQUE"

# Handle repeated UID/GID pairs
while read -r uid gid; do
    # Get folders with this UID and GID
    grep "$uid $gid" "$TEMP_UIDGID" | while read -r folder_uid folder_gid folder_name; do
        echo "UID $uid and GID $gid are repeated for folder $folder_name."
        echo "Please provide a unique name for the user and group:"
        read -r new_name
        create_user_and_group "$uid" "$gid" "$new_name"
    done
done < "$TEMP_REPEATED"

# Handle folders with same UID and GID
while read -r folder; do
    folder_name=$(basename "$folder")
    uid=$(stat -c '%u' "$folder")
    gid=$(stat -c '%g' "$folder")
    if grep -q "$uid $gid" "$TEMP_UIDGID"; then
        echo "Folder $folder_name has UID $uid and GID $gid."
        if grep -q "$uid $gid" "$TEMP_REPEATED"; then
            echo "UID $uid and GID $gid are repeated."
        else
            echo "UID $uid and GID $gid are unique."
        fi
    else
        echo "Folder $folder_name has UID $uid and GID $gid, which is not accounted for."
        echo "Please provide a unique name for the user and group:"
        read -r new_name
        create_user_and_group "$uid" "$gid" "$new_name"
    fi
done < <(find "$HOME_DIR" -mindepth 1 -maxdepth 1 -type d)

# Clean up temporary files
rm -f "$TEMP_UIDGID" "$TEMP_REPEATED" "$TEMP_UNIQUE"

echo "Script execution completed."
