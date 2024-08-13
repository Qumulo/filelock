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
# How to use:
# 1. Save this script as test_qfs_filelock.sh.
# 2. Make the script executable: chmod +x test_qfs_filelock.sh
# 3. Run the script: ./test_qfs_filelock.sh
# 4. Modify the test cases as needed to suit your testing requirements.
#
################################################################################

WAITTIME=20
QAPI_PORT=28583

################################################################################
# Function to create a test file with a unique name
################################################################################
create_test_file() {
    local filename="/mnt/test/vault/uat-test-${1}.${RANDOM}"
    local MYRAND=$(($RANDOM % 100 + 1))
    sleep ${WAITTIME}
    { time dd if=/dev/urandom of="$filename" bs=1M count=$MYRAND; } >> dd.log 2>&1    
    sleep ${WAITTIME}
    echo "$filename"
}

################################################################################
# Function to lock a file using qfs_filelock.py with specified options
################################################################################
start_qfs_filelock() {
    local options="$1"
    q_filename=$(echo "$filename" | sed 's|/mnt||')
    printf "#################################################################\n# Starting qfs_filelock.py with options: %s\n" "$options" 
    printf "#################################################################\n\n"
    
    bash -c "./qfs_filelock.py $options" & 
}

################################################################################
# Function to retrieve and display file attributes
################################################################################
display_lock_details() {
    local filename="$1"
    qfilename=$(echo "$filename" | sed 's|/mnt||')
    printf "Retrieving lock details for %s\n" "$filename"
    ~/src/api/client/qq_internal --port ${QAPI_PORT} --host localhost login -u admin -p Admin123
    ~/src/api/client/qq_internal --port ${QAPI_PORT} --host localhost fs_file_get_attr --path "$qfilename" --retrieve-file-lock | jq .lock 
    echo ""
}
################################################################################
# Function to retrieve and validate file lock status
################################################################################
retrieve_file_lock_status() {
    local filename="$1"
    qfilename=$(echo "$filename" | sed 's|/mnt||')
    printf "Retrieving lock status for %s\n" "$filename"
    ~/src/api/client/qq_internal --port ${QAPI_PORT} --host localhost login -u admin -p Admin123
    raw_output=$(~/src/api/client/qq_internal --port ${QAPI_PORT} --host localhost fs_file_get_attr --path "$qfilename" --retrieve-file-lock)
    
    if echo "$raw_output" | jq . > /dev/null 2>&1; then
        legal_hold=$(echo "$raw_output" | jq -r .lock.legal_hold)
        retention_period=$(echo "$raw_output" | jq -r .lock.retention_period)
        
        if [ "$legal_hold" == "true" ] || [ -n "$retention_period" ]; then
            echo -e "Test: $filename - \e[32mPASS\e[0m"
        else
            echo -e "Test: $filename - \e[31mFAIL\e[0m"
        fi
    else
        echo -e "Error: Output is not valid JSON. Test: $filename - \e[31mFAIL\e[0m"
    fi
    echo ""
}
################################################################################
# Function to run a test case and check for PASS/FAIL
################################################################################
run_test() {
    local test_name="$1"
    local custom_options="$2"
    local filename

    # Cleaning up any leftover procs from bad runs
    pkill qfs_filelock.py

    printf "Starting Test at `date`: %s\n" "$test_name"
    start_qfs_filelock "$custom_options"
    filename=$(create_test_file "$test_name")
    echo "Created: ${filename}"
    display_lock_details "$filename"
    retrieve_file_lock_status "$filename"
    pkill qfs_filelock.py
}

################################################################################
# Main script execution
################################################################################

# Existing Test Cases
run_test "Legal_hold_2days_retention" "--directory-path /test/vault --interval 15 --output my.log --recursive --retention 2d --legal-hold "

run_test "Legal_hold_2days_retention_no_retention" "--directory-path /test/vault --interval 15 --output my.log --recursive --legal-hold"

run_test "Using_FileNum_Log_Output_to_File" "--file-num 13 --interval 15 --output my.log --retention 2d --legal-hold"

run_test "Using_Debug_to_STDOUT_With_retention_7days" "--directory-path /test/vault --interval 15 --debug --output my.log --retention 7d"

run_test "Using_Debug_to_STDOUT_With_retention_7days_2" "--directory-path /test/vault --interval 15 --debug --output my.log --retention 7d"

run_test "Legal_hold_2days_retention" "--directory-path /test/vault --interval 0 --output my.log --recursive --retention 2d --legal-hold"

run_test "Invalid_FileNum" "--file-num 9999999 --interval 15 --output invalid_filenum.log --legal-hold"

run_test "No_LegalHold_No_Retention" "--directory-path /test/vault --interval 15 --output no_hold_no_retention.log"

run_test "Minimum_Retention" "--directory-path /test/vault --interval 15 --output min_retention.log --retention 1d --legal-hold"

run_test "Maximum_Retention" "--directory-path /test/vault --interval 15 --output max_retention.log --retention 10y --legal-hold"

run_test "Invalid_Retention_Format" "--directory-path /test/vault --interval 15 --output invalid_retention.log --retention 5x --legal-hold"

run_test "Immediate_Locking" "--directory-path /test/vault --interval 0 --output immediate_locking.log --retention 2d --legal-hold"

run_test "Non_Recursive_Monitoring" "--directory-path /test/vault --interval 15 --output non_recursive.log --retention 2d --legal-hold"

run_test "Special_Char_Directory" "--directory-path '/test/vault/dir with spaces & special#chars!' --interval 15 --output special_char_dir.log --retention 2d --legal-hold"

run_test "Large_Directory_Test" "--directory-path /test/vault/large_dir --interval 15 --output large_dir.log --retention 7d --legal-hold --recursive"

run_test "Network_Issues_Test" "--directory-path /test/vault --interval 15 --output network_issues.log --retention 7d --legal-hold"

run_test "Empty_Directory_Test" "--directory-path /test/vault/empty_dir --interval 15 --output empty_dir.log --retention 2d --legal-hold"


echo "Reminder to manually check with --configure"




