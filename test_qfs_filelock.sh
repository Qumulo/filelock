#!/bin/bash
################################################################################
#
# Script Name:  test_qfs_filelock.sh
# Date:         2024-08-12
# Author:       kmac@qumulo.com
#
# Description:
# This script demonstrates how to create a test file, apply a file lock using
# qfs_filelock.py, and retrieve the file's attributes. It is designed to be
# modular and reusable for various test cases.
#
# This script performs the following tasks:
# 1. Creates a test file with a random size.
# 2. Locks the file with specified options.
# 3. Retrieves and displays the file's attributes.
# 4. Cleans up by terminating the file lock process.
#
################################################################################


################################################################################
# Function to generate and print a hash block with a message in it
################################################################################
print_hash_block() {
    local message="$1"
    local bordercolor="$2"
    local textcolor="$3"
    local HASHLENGTH=$(( ${#message} + 3 ))
    local HEADER=$(printf "%0.s#" $(seq 1 $HASHLENGTH))

    print_colored "$HEADER" "${bordercolor}" true
    print_colored "# " "${bordercolor}" false
    print_colored "$message" "${textcolor}" true
    print_colored "$HEADER" "${bordercolor}" true
}

################################################################################
# Function to print colored text with an optional newline
################################################################################
print_colored() {
    local text="$1"
    local color_name="$2"
    local newline="${3:-true}"
    local color_code
    local NC='\e[0m'

    case "${color_name^^}" in
        "RED") color_code='\e[31m' ;;
        "GREEN") color_code='\e[32m' ;;
        "YELLOW") color_code='\e[33m' ;;
        "BLUE") color_code='\e[34m' ;;
        "MAGENTA") color_code='\e[35m' ;;
        "CYAN") color_code='\e[36m' ;;
        "WHITE") color_code='\e[37m' ;;
        "BRIGHT RED") color_code='\e[91m' ;;
        "BRIGHT GREEN") color_code='\e[92m' ;;
        "BRIGHT YELLOW") color_code='\e[93m' ;;
        "BRIGHT BLUE") color_code='\e[94m' ;;
        "BRIGHT MAGENTA") color_code='\e[95m' ;;
        "BRIGHT CYAN") color_code='\e[96m' ;;
        "BRIGHT WHITE") color_code='\e[97m' ;;
        *) printf "%s" "$text"; return ;;
    esac

    printf "%b%s%b" "$color_code" "$text" "$NC"
    if [ "$newline" = true ]; then
        printf "\n"
    fi
}

################################################################################
# Function to create a test file with a unique name
################################################################################
create_test_file() {
    local filename="${BASE_DIR}/uat-test-${1}.${RANDOM}"

    if [ -f "$filename" ]; then
        print_colored "File already exists: $filename. Skipping creation." "YELLOW" true
        return 1
    fi

    local MYRAND=$(($RANDOM % 100 + 1))

    if ! { time dd if=/dev/urandom of="$filename" bs=1M count=$MYRAND; } >> dd.log 2>&1; then
        print_colored "Failed to create file: $filename. Check permissions or if the file is locked." "RED" true
        return 1
    fi

    sleep "${WAITTIME}"
    echo "$filename"
}

################################################################################
# Function to lock a file using qfs_filelock.py with specified options
################################################################################
start_qfs_filelock() {
    local options="$1"
    print_hash_block "Spawned: qfs_filelock.py $options" "BRIGHT CYAN" "BRIGHT WHITE"

    local DPATH="$PATH:/opt/qumulo/bin:/opt/qumulo/cli"
    local DPP=$(python3 -c 'import sys; import site; paths = sys.path + site.getsitepackages(); print(":".join(paths))')

    bash -euo pipefail -E -c "
    export PATH=\"$DPATH\"
    export PYTHONPATH=\"$DPP\"
    /usr/bin/python3 ./qfs_filelock.py $options " 2>&1 | tee -a /tmp/qfs_filelock_bash.$$.log &
    sleep "${WAITTIME}"

}

################################################################################
# Function to retrieve and display file attributes
################################################################################
display_lock_details() {
    local filename="$1"
    qfilename=$(echo "$filename" | sed 's|/mnt||')
    /opt/qumulo/qq_internal --port "${QAPI_PORT}" --host "$QHOST" login -u admin -p 'Qumulo1!'
    lock_info=$(/opt/qumulo/qq_internal --port "${QAPI_PORT}" --host "$QHOST" fs_file_get_attr --path "$qfilename" --retrieve-file-lock | jq .lock)

    if [[ -n "$lock_info" ]]; then
        print_colored "Lock details:" "BRIGHT CYAN" true
        print_colored "$lock_info" "BRIGHT CYAN" true
    else
        print_colored "Error retrieving lock details for ${filename}" "RED" true
    fi
}

################################################################################
# Function to handle cleanup on script exit
################################################################################
cleanup() {
    print_colored "Caught interrupt signal. Killing qfs_filelock.py..." "RED" true
    pkill qfs_filelock.py || print_colored "No qfs_filelock.py process found." "YELLOW" true
    echo ""
    print_colored "exiting..." "RED" true
    exit 1
}

################################################################################
# Function to read configuration from a file and set up trap
################################################################################
load_config() {
    local config_file="$1"
    if [[ -f "$config_file" ]]; then
        source "$config_file"
    else
        print_colored "Configuration file not found: $config_file" "RED" true
        exit 1
    fi
    trap cleanup SIGINT
}

################################################################################
# Function to retrieve and validate file lock status
################################################################################
retrieve_file_lock_status() {
    local filename="$1"
    qfilename=$(echo "$filename" | sed 's|/mnt||')
    /opt/qumulo/qq_internal --port "${QAPI_PORT}" --host "$QHOST" login -u admin -p 'Qumulo1!'
    raw_output=$(/opt/qumulo/qq_internal --port "${QAPI_PORT}" --host "$QHOST" fs_file_get_attr --path "$qfilename" --retrieve-file-lock)

    if echo "$raw_output" | jq . > /dev/null 2>&1; then
        legal_hold=$(echo "$raw_output" | jq -r .lock.legal_hold)
        retention_period=$(echo "$raw_output" | jq -r .lock.retention_period)

        if [[ "$legal_hold" == "true" ]] && [[ "$retention_period" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
            print_hash_block "${filename}: LEGAL HOLD AND RETENTION SET" "BLUE" "BRIGHT GREEN"
            printf "\n"            
            print_colored "Legal_hold: $legal_hold Retention_period: $retention_period" "GREEN" true
            printf "\n"
            return 1
        elif [ "$legal_hold" == "false" ] && [ "$retention_period" == "null" ]; then
            print_hash_block "FAIL: ${filename}: NO LOCK SET! Legal_hold: $legal_hold Retention_period: $retention_period" "BRIGHT RED" "BRIGHT YELLOW"
            printf "\n"
            return 2
        elif [[ "$legal_hold" == "true" ]]; then
            print_hash_block "${filename}: LEGAL HOLD SET" "BLUE" "BRIGHT YELLOW"
            printf "\n"            
            print_colored "Legal_hold: $legal_hold Retention_period: $retention_period" "YELLOW" true
            printf "\n"
            return 3
        elif [[ "$retention_period" != "null" ]]; then
            print_hash_block "${filename}: RETENTION PERIOD SET" "BLUE" "BRIGHT YELLOW"
            printf "\n"            
            print_colored "Legal_hold: $legal_hold Retention_period: $retention_period" "YELLOW" true
            printf "\n"
            return 4
        fi
    else
        print_hash_block "${filename}: INVALID: Output is not valid JSON. FAIL." "RED" "BRIGHT RED"
        printf "\n"
        return 255  
    fi
}

################################################################################
# Function to run a test case and check for PASS/FAIL
################################################################################
run_test() {
    local test_name="$1"
    local custom_options="$2"
    local filename

    # Cleaning up any leftover processes from bad runs (just in case)
    pkill qfs_filelock.py || print_colored "No qfs_filelock.py process found." "YELLOW" true
    print_hash_block "Starting Test: $test_name at $(date)" "BLUE" "BRIGHT GREEN"

    start_qfs_filelock "$custom_options"
    filename=$(create_test_file "$test_name")
    if [ $? -ne 0 ]; then
        print_colored "Skipping test case due to file creation error." "RED" true
        return
    fi

    print_colored "New file created: ${filename}" "BRIGHT YELLOW" true
    sleep "${WAITTIME}"

    display_lock_details "$filename"
    retrieve_file_lock_status "$filename"
    status=$?

    case $status in
        1)
            print_hash_block "Finished Test: $test_name at $(date)" "BLUE" "GREEN"
            ;;
        2)
            print_hash_block "Finished Test: $test_name at $(date)" "BRIGHT RED" "BRIGHT YELLOW"
            ;;
        3|4)
            print_hash_block "Finished Test: $test_name at $(date)" "BLUE" "YELLOW"
            ;;
        *)
            print_hash_block "Finished Test: $test_name at $(date)" "BRIGHT RED" "RED"
            ;;
    esac

    printf "\n"
    pkill qfs_filelock.py || print_colored "No qfs_filelock.py process found." "YELLOW" true
}

################################################################################
# Main script
################################################################################

load_config "test_qfs_filelock.ini"

run_test "Legal_hold_2days_retention_SHOULD_PASS" "--directory-path ${QBASE_DIR} --interval 5 --output my.log --recursive --retention 2d --legal-hold "

run_test "Legal_hold_2days_SHOULD_PASS" "--directory-path ${QBASE_DIR} --interval 5 --output my.log --recursive --legal-hold"

run_test "Using_FileNum_PROBLEM" "--file-num 13 --interval 5 --output my.log --retention 2d --legal-hold"

run_test "Using_Debug_to_STDOUT_SHOULD_PASS" "--directory-path ${QBASE_DIR} --interval 5 --debug --output my.log --retention 7d"

run_test "Legal_hold_2days_retention_SHOULD_PASS" "--directory-path ${QBASE_DIR} --interval 0 --output my.log --recursive --retention 2d --legal-hold"

run_test "Invalid_FileNum_SHOULD_FAIL" "--file-num 9999999 --interval 5 --output invalid_filenum.log --legal-hold"

run_test "No_LegalHold_No_Retention_SHOULD_BE_RED" "--directory-path ${QBASE_DIR} --interval 5 --output no_hold_no_retention.log"

run_test "Minimum_Retention_SHOULD_PASS" "--directory-path ${QBASE_DIR} --interval 5 --output min_retention.log --retention 1d --legal-hold"

run_test "Maximum_Retention_SHOULD_PASS" "--directory-path ${QBASE_DIR} --interval 5 --output max_retention.log --retention 10y --legal-hold"

run_test "Invalid_Retention_Format_SHOULD_FAIL" "--directory-path ${QBASE_DIR} --interval 5 --output invalid_retention.log --retention 5x --legal-hold"            
