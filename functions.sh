#!/usr/bin/bash

error_message() {
    echo "$1" >&2
}

info_message() {
    echo "$1"
}

list_timezones() {
    echo "Here is the list of available timezones:"
    echo "Use the arrow keys to scroll, and press 'q' to quit the pager."
    find /usr/share/zoneinfo -type f | sed 's|/usr/share/zoneinfo/||' | sort | less
}

select_timezone() {
    local timezones
    local choice

    timezones=$(mktemp)
    find /usr/share/zoneinfo -type f | sed 's|/usr/share/zoneinfo/||' | sort > "$timezones"

    echo "You will now see a list of available timezones."
    echo "Use the arrow keys to scroll through the list, and press 'q' to exit the pager."
    echo "Please make a note of the timezone you want to select."
    echo
    read -p "Press Enter to continue and view the list of timezones..."

    list_timezones

    echo
    while true; do
        read -p "Enter the timezone from the list (e.g., Europe/Paris): " TIMEZONE

        if grep -q "^$TIMEZONE$" "$timezones"; then
            info_message "Selected timezone: $TIMEZONE"
            break
        else
            error_message "Error: Invalid selection. Please enter a valid timezone from the list."
        fi
    done

    rm "$timezones"
}
