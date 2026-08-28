#!/usr/bin/env bash
set -euo pipefail

: "${AWS_REGION:?AWS_REGION is required}"
: "${TF_STATE_BUCKET:?TF_STATE_BUCKET is required}"
: "${TF_LOCK_TABLE:?TF_LOCK_TABLE is required}"

echo "Ensuring Terraform state bucket exists: ${TF_STATE_BUCKET}"
if ! aws s3api head-bucket --bucket "$TF_STATE_BUCKET" --region "$AWS_REGION" >/dev/null 2>&1; then
  if [[ "$AWS_REGION" == "us-east-1" ]]; then
    create_bucket=(aws s3api create-bucket --bucket "$TF_STATE_BUCKET" --region "$AWS_REGION")
  else
    create_bucket=(
      aws s3api create-bucket
      --bucket "$TF_STATE_BUCKET"
      --region "$AWS_REGION"
      --create-bucket-configuration "LocationConstraint=${AWS_REGION}"
    )
  fi

  if ! "${create_bucket[@]}" >/dev/null 2>&1; then
    # Another run may have created it between head-bucket and create-bucket.
    aws s3api head-bucket --bucket "$TF_STATE_BUCKET" --region "$AWS_REGION" >/dev/null
  fi
fi

aws s3api put-public-access-block \
  --bucket "$TF_STATE_BUCKET" \
  --region "$AWS_REGION" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

aws s3api put-bucket-versioning \
  --bucket "$TF_STATE_BUCKET" \
  --region "$AWS_REGION" \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket "$TF_STATE_BUCKET" \
  --region "$AWS_REGION" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

aws s3api put-bucket-policy \
  --bucket "$TF_STATE_BUCKET" \
  --region "$AWS_REGION" \
  --policy "$(cat <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyInsecureTransport",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::$TF_STATE_BUCKET",
        "arn:aws:s3:::$TF_STATE_BUCKET/*"
      ],
      "Condition": {"Bool": {"aws:SecureTransport": "false"}}
    }
  ]
}
POLICY
)"

aws s3api put-bucket-tagging \
  --bucket "$TF_STATE_BUCKET" \
  --region "$AWS_REGION" \
  --tagging 'TagSet=[{Key=ManagedBy,Value=Terraform},{Key=Project,Value=BulletinBoard}]'

echo "Ensuring Terraform lock table exists: ${TF_LOCK_TABLE}"
if ! aws dynamodb describe-table \
  --table-name "$TF_LOCK_TABLE" \
  --region "$AWS_REGION" >/dev/null 2>&1; then
  if ! aws dynamodb create-table \
      --table-name "$TF_LOCK_TABLE" \
      --region "$AWS_REGION" \
      --attribute-definitions AttributeName=LockID,AttributeType=S \
      --key-schema AttributeName=LockID,KeyType=HASH \
      --billing-mode PAY_PER_REQUEST \
      --sse-specification Enabled=true \
      --tags Key=ManagedBy,Value=Terraform Key=Project,Value=BulletinBoard; then
    # Another run may have created it between describe-table and create-table.
    aws dynamodb describe-table \
      --table-name "$TF_LOCK_TABLE" \
      --region "$AWS_REGION" >/dev/null
  fi
fi

aws dynamodb wait table-exists \
  --table-name "$TF_LOCK_TABLE" \
  --region "$AWS_REGION"

aws dynamodb update-continuous-backups \
  --table-name "$TF_LOCK_TABLE" \
  --region "$AWS_REGION" \
  --point-in-time-recovery-specification PointInTimeRecoveryEnabled=true >/dev/null

echo "Terraform backend is ready."
