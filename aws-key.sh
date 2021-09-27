#!/bin/bash

# Exit if any of the intermediate steps fail
set -e

# ---------------------------------------------------------------------------------------------------------------------
# INITIALIZE
# ---------------------------------------------------------------------------------------------------------------------
NAME="${0##*/}"

command -v keybase >/dev/null 2>&1 || { echo >&2 "keybase could not be found."; exit 1; }
command -v terraform >/dev/null 2>&1 || { echo >&2 "terraform could not be found."; exit 1; }

usage() {

    cat <<EOF

Usage: $NAME [OPTIONS] <COMMAND>

Manage AWS Keys.

Options:
    -h, --help      Displays this help.
    -D, --debug     Enable Debug.

Commands:
    create      Create a new AWS Key.
    rotate      Rotate an existing AWS Key.
    decrypt     Output decrypted AWS Key.
    update      Update the status of an AWS Key (active or inactive). (default is active)

EOF
    exit
}

COMMANDS=("create" "rotate" "decrypt" "update")

[[ $# -eq 0 ]] && usage

# Parse Options
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
    -h | --help)
        usage
        exit
        ;;
    -v | --version)
        show_version
        exit
        ;;
    -D | --debug)
        set -x
        ;;
    *)
        # Parse Command 
        # shellcheck disable=SC2076
        if [[ " ${COMMANDS[*]} " =~ " ${1} " ]]; then
            COMMAND="$1"
            shift
            break
        else
            echo "ERROR: unknown option or command \"$key\""
            exit 1
        fi
        ;;

    esac
    shift
done

# ---------------------------------------------------------------------------------------------------------------------
# HELPER FUNCTIONS
# ---------------------------------------------------------------------------------------------------------------------
color_normal='\033[0m'
color_success='\e[1m\e[92m'

function ask {
    local prompt default reply

    if [[ ${2:-} = 'Y' ]]; then
        prompt='Y/n'
        default='Y'
    elif [[ ${2:-} = 'N' ]]; then
        prompt='y/N'
        default='N'
    else
        prompt='y/n'
        default=''
    fi

    while true; do

        # Ask the question (not using "read -p" as it uses stderr not stdout)
        echo -n "$1 [$prompt] "

        # Read the answer (use /dev/tty in case stdin is redirected from somewhere else)
        read -r reply </dev/tty

        # Default?
        if [[ -z $reply ]]; then
            reply=$default
        fi

        # Check if the reply is valid
        case "$reply" in
            Y*|y*) return 0 ;;
            N*|n*) return 1 ;;
        esac

    done
}

function is_equal {
    local -r orig="$1"
    local -r new="$2"

    if [[ "$new" == "$orig" ]]; then
        return 0
    else
        echo "ERROR: Detected Identity mismatch! '$orig' != '$new'"
        return 1
    fi
}

function parse_tf_output {
    # local -r output="$1"
    local -r key="$1"
    
    grep "$key" | cut -d= -f2 | tr -d \" | sed 's/^\s*//;s/\s*$//'
}

# ---------------------------------------------------------------------------------------------------------------------
# EXEC FUNCTIONS
# ---------------------------------------------------------------------------------------------------------------------
function validate_identity {
    # Get data from terraform outputs
    o="$(terraform output aws_caller_identity)"

    # Original Identity
    echo "Previously invoked identity (tfstate): " 
    echo "$o"
    o_account_id="$(echo "$o" | parse_tf_output 'account_id')"
    o_arn="$(echo "$o" | parse_tf_output 'arn')"
    o_user_id="$(echo "$o" | parse_tf_output 'user_id')"

    # Current Identity
    echo "Current AWS Identity: "
    c="$(aws sts get-caller-identity)"
    echo "$c"
    c_account_id="$(echo "$c" | jq -r '.Account')"
    c_arn="$(echo "$c" | jq -r '.Arn')"
    c_user_id="$(echo "$c" | jq -r '.UserId')"

    echo "Validating tfstate identity is the same as current aws identity..."
    is_equal "$o_account_id" "$c_account_id"
    is_equal "$o_arn" "$c_arn"
    is_equal "$o_user_id" "$c_user_id"
    echo -e "${color_success}✔${color_normal} Success\n"
}

function rotate_keys {
    # TODO: HERE
    access_key_id="$(terraform output -raw aws_access_key_id)"
    if ! ask "Rotate aws access key '$access_key_id' ?"; then exit 1; fi
    echo -e "Rotating access key with terraform destroy, then apply..."
    terraform destroy -auto-approve && \
    terraform apply -auto-approve
}

function decrypt_key_info {
    aws_user_name="$(terraform output -raw aws_user_name)"
    access_key_id="$(terraform output -raw aws_access_key_id)"
    secret="$(terraform output -raw encrypted_secret | base64 --decode | keybase pgp decrypt)"

    title="$(echo -e "${color_success}Decrypted Outputs:${color_normal}")"
    cat << EOF

$title

aws_user_name = "$aws_user_name"
aws_access_key_id = "$access_key_id"
aws_decrypted_secret = "$secret"

EOF

}

function update_key {
    local status="$1"
    local -r user="$(terraform output -raw aws_user_name)"
    local -r key_id="$(terraform output -raw aws_access_key_id)"

    echo "INFO: Updating $user '$key_id' to status '$status'"
    aws iam update-access-key \
        --access-key-id "$key_id" \
        --status "$status" \
        --user-name "$user" && \
    echo -e "${color_success}✔${color_normal} Success\n"
}

function exec_rotate {
    echo "INFO: Exec Rotate AWS Key..."
    validate_identity
    rotate_keys
    decrypt_key_info
}

function exec_create {
    echo "INFO: Exec Create AWS Key..."
    terraform apply -auto-approve
    decrypt_key_info
}

function exec_decrypt {
    echo "INFO: Exec Decrypt AWS Key..."
    decrypt_key_info
}

function exec_update {
    local status="${1:-Active}"
    
    # Uppercase the first character
    status="${status^}"

    if [[ "$status" != "Active" && "$status" != "Inactive" ]]; then
        echo "ERROR: Value '$status' at 'status' failed to satisfy constraint: Member must satisfy enum value set: [Active, Inactive]"
        exit 1
    fi

    echo "INFO: Exec Update AWS Key..."
    validate_identity
    update_key "$status"
}

# Execute
case $COMMAND in
    create) exec_create ;;
    rotate) exec_rotate ;;
    decrypt) exec_decrypt ;;
    update) exec_update "$1" ;;
    *) echo "ERROR: Unknown COMMAND: '$COMMAND'"; exit 1 ;;
esac
