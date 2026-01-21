#!/bin/bash

# Creates an AWS Secrets Manager secret with standard tags.
# Usage: ./create-aws-secret.sh <secret-name> <secret-value>
# Example: ./create-aws-secret.sh my-app/api-key "supersecretvalue"

set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <secret-name> <secret-value>"
    echo "Example: $0 my-app/api-key \"supersecretvalue\""
    exit 1
fi

SECRET_NAME="$1"
SECRET_VALUE="$2"

# Standard tags - customize these for your organization
TAGS='[
    {"Key": "owner-product-name", "Value": "my-product"},
    {"Key": "cost-department", "Value": "engineering"},
    {"Key": "cost-center", "Value": "eng-001"},
    {"Key": "contact-email", "Value": "team@example.com"},
    {"Key": "environment", "Value": "dev"},
    {"Key": "creator-method", "Value": "cli"},
    {"Key": "criticality", "Value": "2"},
    {"Key": "data-classification", "Value": "confidential"},
    {"Key": "creator", "Value": "user@example.com"},
    {"Key": "last-modified-by", "Value": "user@example.com"},
    {"Key": "lifecycle-review", "Value": "12/31/2026"}
]'

echo "Creating secret: $SECRET_NAME"

aws secretsmanager create-secret \
    --name "$SECRET_NAME" \
    --secret-string "$SECRET_VALUE" \
    --tags "$TAGS"

echo "Secret '$SECRET_NAME' created successfully."
