#!/bin/bash
# Updates an AWS Secrets Manager secret with key/value pairs from a .env file.

set -euo pipefail

usage() {
    echo "Usage: $0 -s <secret-name> -e <env-file> [-p <profile>]"
    echo ""
    echo "Options:"
    echo "  -s    AWS Secrets Manager secret name or ARN"
    echo "  -e    Path to .env file"
    echo "  -p    AWS SSO profile name (optional, uses default if not specified)"
    exit 1
}

SECRET_NAME=""
ENV_FILE=""
AWS_PROFILE_OPT=""

while getopts "s:e:p:h" opt; do
    case $opt in
        s) SECRET_NAME="$OPTARG" ;;
        e) ENV_FILE="$OPTARG" ;;
        p) AWS_PROFILE_OPT="--profile $OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

if [[ -z "$SECRET_NAME" || -z "$ENV_FILE" ]]; then
    echo "Error: Secret name and env file are required."
    usage
fi

if [[ ! -r "$ENV_FILE" ]]; then
    echo "Error: File not found or not readable: $ENV_FILE"
    exit 1
fi

echo "Authenticating via AWS SSO..."
if ! aws sso login $AWS_PROFILE_OPT; then
    echo "Error: AWS SSO authentication failed."
    exit 1
fi

echo "Parsing .env file: $ENV_FILE"
json_payload="{"
first=true

while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip empty lines and comments.
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

    # Extract key and value from KEY=value format.
    if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"

        # Remove surrounding quotes if present.
        value="${value#\"}"
        value="${value%\"}"
        value="${value#\'}"
        value="${value%\'}"

        # Escape special JSON characters in value.
        value="${value//\\/\\\\}"
        value="${value//\"/\\\"}"
        value="${value//$'\n'/\\n}"
        value="${value//$'\r'/\\r}"
        value="${value//$'\t'/\\t}"

        if [[ "$first" == true ]]; then
            first=false
        else
            json_payload+=","
        fi
        json_payload+="\"$key\":\"$value\""
    fi
done < "$ENV_FILE"

json_payload+="}"

echo "Updating secret: $SECRET_NAME"
if aws secretsmanager put-secret-value \
    $AWS_PROFILE_OPT \
    --secret-id "$SECRET_NAME" \
    --secret-string "$json_payload"; then
    echo "Secret updated successfully."
else
    echo "Error: Failed to update secret."
    exit 1
fi
