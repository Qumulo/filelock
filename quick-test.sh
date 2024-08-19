print_colored() {
    local text="$1"
    local color_name="$2"
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
}

display_test_result() {
    local filename="$1"
    local legal_hold="$2"
    local retention_period="$3"
    local result_message="$4"
    local result_color="$5"
    local value_color="$6"

    printf "\n"
    print_colored "${filename}: " "WHITE"
    print_colored "$result_message " "$result_color"
    
    if [[ "$legal_hold" == "true" ]] || [[ "$retention_period" != "null" ]]; then
        [[ "$legal_hold" == "true" ]] && print_colored "Legal_hold: $legal_hold " "$value_color"
        [[ "$retention_period" != "null" ]] && print_colored "Retention_period: $retention_period" "$value_color"
    else
        print_colored "Legal_hold: $legal_hold " "MAGENTA"
        print_colored "Retention_period: $retention_period" "MAGENTA"
    fi
    printf "\n"
}

retrieve_file_lock_status() {
    local filename="$1"
    qfilename=$(echo "$filename" | sed 's|/mnt||')
    /opt/qumulo/qq_internal --host localhost login -u admin -p 'Qumulo1!'
    raw_output=$(/opt/qumulo/qq_internal --host localhost fs_file_get_attr --path "$qfilename" --retrieve-file-lock)

    if printf "%s" "$raw_output" | jq . > /dev/null 2>&1; then
        legal_hold=$(echo "$raw_output" | jq -r .lock.legal_hold)
        retention_period=$(echo "$raw_output" | jq -r .lock.retention_period)

        if [[ "$legal_hold" == "true" ]] && [[ "$retention_period" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
            display_test_result "$filename" "$legal_hold" "$retention_period" "BOTH ARE SET" "GREEN" "GREEN"
        elif [ "$legal_hold" == "false" ] && [ "$retention_period" == "null" ] ; then
            display_test_result "$filename" "$legal_hold" "$retention_period" "NOTHING SET" "RED" "MAGENTA"
        elif [[ "$legal_hold" == "true" ]]; then
            display_test_result "$filename" "$legal_hold" "$retention_period" "LEGAL HOLD IS SET" "YELLOW" "YELLOW"
        elif [[ "$retention_period" != "null" ]]; then
            display_test_result "$filename" "$legal_hold" "$retention_period" "RETENTION PERIOD IS SET" "YELLOW" "YELLOW"
        fi
    else
        print_colored "Error: Output is not valid JSON. " "RED"
        print_colored "$filename" "WHITE"
        print_colored " FAIL" "RED"
        printf "\n"
    fi
    printf "\n"
}

for file in locked_file.txt legal_hold_file.txt not_locked.txt both_legal_and_retention_locked.txt
do
    printf "\n"
    printf '%0.s#' {1..80}
    printf "\n# %s\n" "$file"
    printf '%0.s#' {1..80}
    printf "\n"
    retrieve_file_lock_status "/mnt/demo/test/${file}"
done

exit