#!/bin/bash

# Function to check if UID or GID already exists
check_existing() {
    local uid=$1
    local gid=$2
    local user_exists=$(getent passwd $uid >/dev/null; echo $?)
    local group_exists=$(getent group $gid >/dev/null; echo $?)
    return $((user_exists || group_exists))
}

# Function to create user and groups
create_user_and_group() {
    local username=$1
    local uid=$2
    local primary_gid=$3
    local additional_group=$4
    local additional_gid=$5

    # Create the primary group with the same name as the user and GID (same as UID)
    if ! getent group $primary_gid >/dev/null; then
        groupadd -g $primary_gid $username
        echo "Created primary group $username with GID $primary_gid"
    else
        echo "Primary group with GID $primary_gid already exists, using existing group"
    fi

    # Create the additional group if specified and it doesn't exist
    if [ -n "$additional_group" ]; then
        if ! getent group $additional_gid >/dev/null; then
            groupadd -g $additional_gid $additional_group
            echo "Created additional group $additional_group with GID $additional_gid"
        else
            echo "Additional group with GID $additional_gid already exists, using existing group"
        fi
    fi

    # Create user if it doesn't exist
    if ! getent passwd $uid >/dev/null; then
        useradd -u $uid -g $primary_gid -d "/home/$username" -M -s /bin/bash $username
        echo "Created user $username with UID $uid in group with GID $primary_gid"
    else
        echo "User with UID $uid already exists"
    fi
}

# Main script
for dir in /home/*/; do
    dir=${dir%*/}  # Remove trailing slash
    dirname=${dir##*/}  # Extract directory name
    
    # Get UID and GID
    uid=$(stat -c '%u' "$dir")
    gid=$(stat -c '%g' "$dir")

    if check_existing $uid $gid; then
        echo "Skipping $dirname: UID $uid or GID $gid already exists"
        continue
    fi

    if [ "$uid" == "$gid" ]; then
        # Check if any other directory has the same UID or GID
        if [ $(find /home -maxdepth 1 -type d \( -uid $uid -o -gid $gid \) | wc -l) -eq 1 ]; then
            # Only create the user and primary group without extra prompts
            create_user_and_group $dirname $uid $uid
        else
            echo "Conflict detected for $dirname. Multiple directories with UID $uid or GID $gid"
            read -p "Enter username: " username
            read -p "Enter additional group name: " additional_group
            create_user_and_group $username $uid $uid $additional_group $gid
        fi
    else
        echo "UID ($uid) and GID ($gid) mismatch for $dirname"
        
        # Check if the user already exists before prompting for username
        if ! getent passwd $uid >/dev/null; then
            read -p "Enter username: " username
        else
            echo "User with UID $uid already exists, skipping username prompt"
            username=$(getent passwd $uid | cut -d: -f1)
        fi

        # Prompt for additional group name only if it doesn't already exist
        if ! getent group $gid >/dev/null; then
            read -p "Enter additional group name: " additional_group
            create_user_and_group $username $uid $uid $additional_group $gid
        else
            echo "Group with GID $gid already exists, using existing group"
            create_user_and_group $username $uid $uid "" $gid
        fi
    fi
done

