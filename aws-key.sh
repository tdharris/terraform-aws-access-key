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
    delete      Delete an existing AWS Key.
    rotate      Rotate an existing AWS Key.
    decrypt     Output decrypted AWS Key.
    update      Update the status of an AWS Key (active or inactive). (default is active)
    bw-sync     Sync the AWS Key to the BW Vault (customized).

EOF
    exit
}

COMMANDS=("create" "delete" "rotate" "decrypt" "update" "bw-sync")

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

function delete_key {
    local -r access_key_id="$(terraform output -raw aws_access_key_id)"
    if ! ask "Delete aws access key '$access_key_id' ?"; then exit 1; fi
    echo -e "Deleting access key with terraform destroy..."
    terraform destroy -auto-approve && \
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

function exec_delete {
    echo "INFO: Exec Delete AWS Key..."
    validate_identity
    delete_key
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

function bw_update_item_json {
    local -r item="$1"
    local -r key="$2"
    local -r value="$3"
    echo "$item" | jq -r --arg KEY "$key" --arg VALUE "$value" '(.fields[] | select(.name == $KEY)).value |= $VALUE'
}

function exec_wrap_bw_vault_sync {
    local -r stdin="$1"
    local bw_item_name="$2"

    echo -e "$stdin\n"

    echo "INFO: Exec BW Vault Sync..."
    if [[ -z "$stdin" ]]; then
        echo "ERROR: Missing stdin"
        return 1
    fi

    local -r key_name="aws_access_key_id"
    local -r value_name="aws_decrypted_secret"

    local -r key="$(echo "$stdin" | grep "$key_name" | cut -d= -f2 | jq -r)"
    local -r value="$(echo "$stdin" | grep "$value_name" | cut -d= -f2 | jq -r)"

    command -v bw >/dev/null 2>&1 || { echo >&2 "bw could not be found."; exit 1; }
    command -v jq >/dev/null 2>&1 || { echo >&2 "jq could not be found."; exit 1; }

    local -r bw_vault_status="$(bw status | jq -r '.status')"
    if [[ "$bw_vault_status"  != 'unlocked' ]]; then
        echo "ERROR: BW Vault is not unlocked. Please run 'bw unlock' first."
        exit 1
    fi

    if [[ -z "$bw_item_name" ]]; then
        local -r default_item_suffix="-env"
        bw_item_name="$(terraform workspace show)$default_item_suffix" || {
            echo "ERROR: Failed to get current workspace name"
            return 1
        }
    fi

    declare -A REPLACEMENTS=(
        ["AWS_ACCESS_KEY_ID"]="$key" 
        ["AWS_SECRET_ACCESS_KEY"]="$value" 
    )

    exec_bw_vault_sync "$bw_item_name"
}

function bw_vault_sync_cleanup {
    rm -f "/tmp/.bw_item.json" "/tmp/.bw_item_new.json" 2>/dev/null
}

function exec_bw_vault_sync {
    local item_name="${1}"
    local -r git_diff_orig="/tmp/.bw_item.json"
    local -r git_diff_new="/tmp/.bw_item_new.json"
    # DEPENDS_ON: global env var "REPLACEMENTS"

    echo "INFO: Getting BW Vault item '$item_name'..."
    local bw_item="$(bw get item "$item_name")" || {
        echo "ERROR: Failed to get item '$item_name'"
        bw_vault_sync_cleanup
        return 1
    }
    local -r bw_item_id="$(echo "$bw_item" | jq -r '.id')"

    # For later git diff
    echo "$bw_item" | jq -r '.' > "$git_diff_orig"

    for k in "${!REPLACEMENTS[@]}"; do
        local v="${REPLACEMENTS[$k]}"
        echo "INFO: Setting '$k' => '$v'"
        bw_item="$(bw_update_item_json "$bw_item" "$k" "$v")" || {
            echo "ERROR: Failed to update item '$item_name'"
            bw_vault_sync_cleanup
            return 1
        }
    done

    echo -e "INFO: Updated BW Vault item:"
    echo "$bw_item" > "$git_diff_new"
    # Handling possible errors internally here..
    set +e
    git diff --no-index "$git_diff_orig" "$git_diff_new"
    local -r rc="$?"
    # expecting $? to be 1 if there is a diff
    if [[ "$rc" -eq 0 ]]; then
        echo "INFO: No changes to sync"
        bw_vault_sync_cleanup
        return 0
    elif [[ "$rc" -gt 1 ]]; then
        echo "ERROR: Unanticipated git diff result '$rc'"
        bw_vault_sync_cleanup
        return 1
    fi

    echo
    if ! ask "Update item '$item_name' with above field value changes?"; then
        echo "INFO: Skipping..."
        bw_vault_sync_cleanup
        return 1
    fi   

    echo "INFO: Editing BW Vault item..."
    echo "$bw_item" | bw encode | bw edit item "$bw_item_id" || {
        echo "ERROR: Failed to edit item"
        bw_vault_sync_cleanup
        return 1
    }

    echo "INFO: Syncing BW Vault item '$item_name'..."
    bw sync || {
        echo "ERROR: Failed to sync item with bw"
        bw_vault_sync_cleanup
        return 1
    }

    echo -e "\n${color_success}✔${color_normal} Success\n"
}

# Execute
case $COMMAND in
    create) exec_create ;;
    delete) exec_delete ;;
    rotate) exec_rotate ;;
    decrypt) exec_decrypt ;;
    bw-sync) exec_wrap_bw_vault_sync "$(exec_decrypt)" ;;
    update) exec_update "$1" ;;
    *) echo "ERROR: Unknown COMMAND: '$COMMAND'"; exit 1 ;;
esac
