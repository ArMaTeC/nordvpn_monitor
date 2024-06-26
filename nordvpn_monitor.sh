#!/bin/bash

# Constants
LOG_OUTPUT=true              # Set to false to disable log output
LOG_LOOP_OUTPUT=true         # Set to false to disable loop log output
LOG_FILE="/root/nordvpn_monitor.txt"
TOKEN_FILE="/root/nordtoken.txt"
LOOP_SLEEP=60
LOGIN_ATTEMPT_LIMIT=3
CHANGEHOST_INTERVAL=300      # 300 minutes = 5 hours
MAX_LOG_SIZE=$((1024*1024*1024)) # 1GB in bytes

# Function to log output to screen and file if it's different from the previous log
last_log=""
log() {
    local message="$1"
    local timestamp=$(date +"%Y-%m-%d %T")
    if [ "$message" != "$last_log" ]; then
        echo "$timestamp - $message"
        if [ "$LOG_OUTPUT" = true ]; then
            echo "== $timestamp == $message" >> "$LOG_FILE" || echo "Failed to write to log file."
            # Check log file size and truncate if over 1GB
            if [ -f "$LOG_FILE" ] && [ $(stat -c %s "$LOG_FILE") -gt $MAX_LOG_SIZE ]; then
                truncate -s 0 "$LOG_FILE" || echo "Failed to truncate log file."
                log "Log file truncated as it exceeded 1GB."
            fi
        fi
        last_log="$message"
    fi
}

# Function to execute NordVPN command and log output
execute_nordvpn() {
    local command="$1"
    local output
	output=$(eval "nordvpn $command") || { log "Error executing nordvpn $command"; return 1; }
    log "$output"
}

# Function to check if NordVPN is connected
check_connection() {
    local status
    status=$(execute_nordvpn "status") || return 1
    [[ $status == *"Status: Connected"* ]]
}

# Function to check if NordVPN is logged in
check_login() {
    local account_info
    account_info=$(execute_nordvpn "account") || return 1
    [[ $account_info == *"Email Address:"* && $account_info == *"VPN Service: Active"* ]]
}

# Function to log in to NordVPN
login() {
    local token
    if [ -f "$TOKEN_FILE" ]; then
        token=$(<"$TOKEN_FILE")
        execute_nordvpn "login --token $token"
    else
        log "Error: Token file not found."
        exit 1
    fi
}

# Function to log out of NordVPN
logout() {
    execute_nordvpn "logout --persist-token"
}

# Function to reconnect NordVPN
reconnect() {
    execute_nordvpn "connect P2P"
}

# Function to check flaresolverr service and restart if failed
flaresolverrcheck() {
    local output
    # Run the curl command and capture its output
    output=$(curl -s -L -X POST 'http://localhost:8191/v1' \
        -H 'Content-Type: application/json' \
        --data-raw '{
          "cmd": "request.get",
          "url": "http://www.google.com/",
          "maxTimeout": 60000
        }')

    # Check if the output contains the error message
    if [[ $output == *"Error: Error solving the challenge. [Errno 24] Too many open files"* ]]; then
        log "Restarting flaresolverr.service"
        systemctl stop flaresolverr.service
        systemctl start flaresolverr.service
    fi
}

# Main loop
login_attempts=0
changehost_count=0
while true; do
    if ! check_login; then
        ((login_attempts++))
        if (( login_attempts >= LOGIN_ATTEMPT_LIMIT )); then
            log "Failed to login $LOGIN_ATTEMPT_LIMIT times. Disconnecting from NordVPN."
            logout
            login_attempts=0
        else
            login
        fi
    else
        login_attempts=0
    fi

    if ! check_connection; then
        reconnect
        changehost_count=0
    else
        ((changehost_count++))
        if (( changehost_count >= CHANGEHOST_INTERVAL )); then
            log "Changing host after $CHANGEHOST_INTERVAL minutes."
            reconnect
            changehost_count=0
        fi
    fi
    
    if [ "$LOG_LOOP_OUTPUT" = true ]; then
        log "Loop Stats:"
        log "Change Host: $changehost_count/$CHANGEHOST_INTERVAL"
        log "Login Attempts: $login_attempts/$LOGIN_ATTEMPT_LIMIT"
    fi
    
    flaresolverrcheck
    sleep "$LOOP_SLEEP"
done
