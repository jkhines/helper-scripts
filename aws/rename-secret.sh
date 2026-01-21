#!/bin/bash

set -e

# Configure these variables for your environment
PROFILE="my-aws-profile"
REGION="us-east-1"
OLD_SECRET="dev/my-app/old-secret-name"
NEW_SECRET="dev/my-app/new-secret-name"

echo "Retrieving secret value from: $OLD_SECRET"
SECRET_VALUE=$(aws secretsmanager get-secret-value \
    --secret-id "$OLD_SECRET" \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query SecretString \
    --output text)

echo "Retrieving tags from: $OLD_SECRET"
TAGS=$(aws secretsmanager describe-secret \
    --secret-id "$OLD_SECRET" \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query 'Tags' \
    --output json)

echo "Creating new secret: $NEW_SECRET"
if [[ "$TAGS" != "null" && "$TAGS" != "[]" ]]; then
    aws secretsmanager create-secret \
        --name "$NEW_SECRET" \
        --secret-string "$SECRET_VALUE" \
        --tags "$TAGS" \
        --region "$REGION" \
        --profile "$PROFILE"
else
    aws secretsmanager create-secret \
        --name "$NEW_SECRET" \
        --secret-string "$SECRET_VALUE" \
        --region "$REGION" \
        --profile "$PROFILE"
fi

echo "Verifying new secret exists..."
aws secretsmanager get-secret-value \
    --secret-id "$NEW_SECRET" \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query SecretString \
    --output text > /dev/null

echo "New secret created and verified successfully."
echo ""
read -p "Delete the old secret '$OLD_SECRET'? (y/N): " CONFIRM

if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
    aws secretsmanager delete-secret \
        --secret-id "$OLD_SECRET" \
        --region "$REGION" \
        --profile "$PROFILE"
    echo "Old secret scheduled for deletion (30-day recovery window)."
else
    echo "Old secret retained. Remember to delete it manually when ready."
fi

echo "Done."
