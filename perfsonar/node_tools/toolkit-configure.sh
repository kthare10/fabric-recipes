#!/usr/bin/expect -f

set timeout 10

set webadmin_user "pswebadmin"
set webadmin_pass "YourStrongPasswordHere"

# Step 1: Start the toolkit customization script
spawn sudo /usr/lib/perfsonar/scripts/nptoolkit-configure.py

# Main menu: choose "2" to manage web users
expect "Make a selection:"
send -- "2\r"

# Sub-menu: choose "1" to add user
expect "Make a selection:"
send -- "1\r"

# Enter new username
expect "Enter the user whose account you'd like to add.*:"
send -- "$webadmin_user\r"

# Enter and confirm password
expect "New password:"
send -- "$webadmin_pass\r"
expect "Re-type new password:"
send -- "$webadmin_pass\r"

# Return to user management menu
expect "Make a selection:"
send -- "0\r"

# Return to main menu
expect "Make a selection:"
send -- "0\r"

expect eof
