#!/bin/bash
# Fetch short-term AWS credentials via AWS IAM Identity Center (SSO) and export them as environment variables.
#
# Usage: source this script to export credentials to current shell
#   . ./get-aws-creds.sh [account]
#   source ./get-aws-creds.sh [account]
#
# Valid accounts: sb, dev, prod, omdev, omstaging, omprod
#
# Requirements:
# - AWS CLI v2
# - jq (for JSON parsing)
# - aws-config.json in the same directory as this script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="${SCRIPT_DIR}/aws-config.json"
PROFILE="${AWS_SSO_PROFILE:-sso}"
VALID_ACCOUNTS="sb dev prod omdev omstaging omprod"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

_error() { echo -e "${RED}Error: $1${NC}" >&2; }
_info() { echo -e "${CYAN}$1${NC}"; }
_success() { echo -e "${GREEN}$1${NC}"; }
_warn() { echo -e "${YELLOW}$1${NC}"; }

# Check dependencies
_check_deps() {
    if ! command -v aws &>/dev/null; then
        _error "AWS CLI v2 is required but was not found in PATH."
        return 1
    fi
    if ! aws --version 2>&1 | grep -q "^aws-cli/2"; then
        _error "AWS CLI v2 is required. Detected: $(aws --version 2>&1)"
        return 1
    fi
    if ! command -v jq &>/dev/null; then
        _error "jq is required but was not found in PATH."
        return 1
    fi
}

# Load config
_load_config() {
    if [[ ! -f "$CONFIG_PATH" ]]; then
        _error "Configuration file not found: $CONFIG_PATH. Please copy aws-config.json.example to aws-config.json and update with your settings."
        return 1
    fi
}

# Get account ID from config
_get_account_id() {
    local account="$1"
    jq -r ".accounts.$account // empty" "$CONFIG_PATH"
}

# Ensure SSO profile exists with valid values
_ensure_sso_profile() {
    local needs_setup=false
    local current_sso_region

    # Check if profile exists
    if ! aws configure list-profiles 2>/dev/null | grep -qx "$PROFILE"; then
        needs_setup=true
    else
        # Check if profile has valid sso_region (not empty)
        current_sso_region=$(aws configure get sso_region --profile "$PROFILE" 2>/dev/null)
        if [[ -z "$current_sso_region" ]]; then
            needs_setup=true
        fi
    fi

    if [[ "$needs_setup" == "true" ]]; then
        _warn "Profile '$PROFILE' not found or incomplete. Creating it now ..."
        local sso_start_url sso_region region
        sso_start_url=$(jq -r '.sso_start_url' "$CONFIG_PATH")
        sso_region=$(jq -r '.sso_region' "$CONFIG_PATH")
        region=$(jq -r '.region' "$CONFIG_PATH")

        aws configure set sso_start_url "$sso_start_url" --profile "$PROFILE"
        aws configure set sso_region "$sso_region" --profile "$PROFILE"
        aws configure set region "$region" --profile "$PROFILE"
        _success "Profile '$PROFILE' created."
    fi
}

# Perform SSO login
_sso_login() {
    _ensure_sso_profile || return 1
    aws sso login --profile "$PROFILE" || return 1
    export AWS_PROFILE="$PROFILE"
}

# Get access token from cache
_get_access_token() {
    local cache_dir="$HOME/.aws/sso/cache"
    if [[ ! -d "$cache_dir" ]]; then
        _error "SSO cache directory not found."
        return 1
    fi

    local latest_file
    latest_file=$(ls -t "$cache_dir"/*.json 2>/dev/null | head -1)
    if [[ -z "$latest_file" ]]; then
        _error "No cached SSO token file found."
        return 1
    fi

    local token expires_at now_epoch expires_epoch
    token=$(jq -r '.accessToken // empty' "$latest_file")
    expires_at=$(jq -r '.expiresAt // empty' "$latest_file")

    if [[ -z "$token" ]]; then
        _error "No access token in cache file."
        return 1
    fi

    # Check expiry
    if [[ -n "$expires_at" ]]; then
        now_epoch=$(date +%s)
        expires_epoch=$(date -d "$expires_at" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$expires_at" +%s 2>/dev/null || echo 0)
        if (( expires_epoch > 0 && expires_epoch < now_epoch - 300 )); then
            _error "Cached SSO token is expired. Run aws sso login again."
            return 1
        fi
    fi

    echo "$token"
}

# Choose role (if multiple available)
_choose_role() {
    local account_id="$1"
    local access_token="$2"

    local roles_json role_count
    roles_json=$(aws sso list-account-roles --account-id "$account_id" --access-token "$access_token" --output json 2>&1)
    if [[ $? -ne 0 ]]; then
        _error "Failed to list roles: $roles_json"
        return 1
    fi

    role_count=$(echo "$roles_json" | jq '.roleList | length')

    if (( role_count == 0 )); then
        _error "No roles found for account $account_id."
        return 1
    fi

    if (( role_count == 1 )); then
        echo "$roles_json" | jq -r '.roleList[0].roleName'
        return 0
    fi

    _info "Available roles:"
    local i=1
    while read -r role_name; do
        echo "[$i] $role_name"
        ((i++))
    done < <(echo "$roles_json" | jq -r '.roleList[].roleName')

    local sel
    while true; do
        read -rp "Select role number: " sel
        if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= role_count )); then
            break
        fi
    done

    echo "$roles_json" | jq -r ".roleList[$((sel-1))].roleName"
}

# Main
_get_aws_creds_main() {
    local account="$1"

    _check_deps || return 1
    _load_config || return 1

    # Prompt for account if not provided
    if [[ -z "$account" ]]; then
        read -rp "Enter account name ($VALID_ACCOUNTS): " account
    fi

    # Validate account
    if ! echo "$VALID_ACCOUNTS" | grep -qw "$account"; then
        _error "Unknown account '$account'. Valid: $VALID_ACCOUNTS"
        return 1
    fi

    local account_id
    account_id=$(_get_account_id "$account")
    if [[ -z "$account_id" ]]; then
        _error "Account '$account' not found in config."
        return 1
    fi

    _sso_login || return 1

    local token role creds_json
    token=$(_get_access_token) || return 1
    if [[ -z "$token" ]]; then
        _error "Failed to get access token."
        return 1
    fi

    role=$(_choose_role "$account_id" "$token") || return 1
    if [[ -z "$role" ]]; then
        _error "Failed to select role."
        return 1
    fi

    creds_json=$(aws sso get-role-credentials --account-id "$account_id" --role-name "$role" --access-token "$token" --output json 2>&1)
    if [[ $? -ne 0 ]]; then
        _error "Failed to get credentials: $creds_json"
        return 1
    fi

    # Export credentials
    export AWS_ACCESS_KEY_ID=$(echo "$creds_json" | jq -r '.roleCredentials.accessKeyId')
    export AWS_SECRET_ACCESS_KEY=$(echo "$creds_json" | jq -r '.roleCredentials.secretAccessKey')
    export AWS_SESSION_TOKEN=$(echo "$creds_json" | jq -r '.roleCredentials.sessionToken')

    local expiration_ms expiry_date
    expiration_ms=$(echo "$creds_json" | jq -r '.roleCredentials.expiration')
    expiry_date=$(date -d "@$((expiration_ms / 1000))" 2>/dev/null || date -r "$((expiration_ms / 1000))" 2>/dev/null || echo "unknown")

    _success "Credentials set for account $account ($account_id), role $role. Expires $expiry_date."
}

_get_aws_creds_main "$@"
