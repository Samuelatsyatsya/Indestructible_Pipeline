#!/bin/bash
set -e

AWS_PROFILE="CostDetective"
PRIMARY_REGION="eu-central-1"
DR_REGION="eu-west-1"
VAULT_NAME="fincorp-primary-vault"
DR_VAULT_ARN="arn:aws:backup:eu-west-1:309797288544:backup-vault:fincorp-dr-vault"
RDS_ARN="arn:aws:rds:eu-central-1:309797288544:db:fincorp-primary-db"
IAM_ROLE_ARN="arn:aws:iam::309797288544:role/fincorp-backup-role"

# Logging helpers — all output goes to stderr with a timestamp and level prefix.
log_info()  { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [INFO]  $*" >&2; }
log_ok()    { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [OK]    $*" >&2; }
log_error() { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [ERROR] $*" >&2; }

# Trigger an on-demand backup of the primary RDS instance.
log_info "Starting on-demand backup of $RDS_ARN..."
BACKUP_JOB_ID=$(aws backup start-backup-job \
  --backup-vault-name "$VAULT_NAME" \
  --resource-arn "$RDS_ARN" \
  --iam-role-arn "$IAM_ROLE_ARN" \
  --region "$PRIMARY_REGION" \
  --profile "$AWS_PROFILE" \
  --query 'BackupJobId' \
  --output text)
log_info "Backup job created: $BACKUP_JOB_ID"

# Poll until the backup job reaches a terminal state.
log_info "Waiting for backup to complete (polls every 30s)..."
while true; do
  RESULT=$(aws backup describe-backup-job \
    --backup-job-id "$BACKUP_JOB_ID" \
    --region "$PRIMARY_REGION" \
    --profile "$AWS_PROFILE" \
    --query '{Status: State, Arn: RecoveryPointArn}' \
    --output json)

  STATUS=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['Status'])")
  RECOVERY_ARN=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['Arn'] or '')")

  log_info "Backup status: $STATUS"

  if [ "$STATUS" = "COMPLETED" ]; then
    log_ok "Backup complete. Recovery point: $RECOVERY_ARN"
    break
  elif [ "$STATUS" = "FAILED" ] || [ "$STATUS" = "ABORTED" ]; then
    log_error "Backup job failed with status: $STATUS"
    exit 1
  fi

  sleep 30
done

# Copy the completed backup to the DR vault in eu-west-1.
log_info "Copying backup to DR vault in $DR_REGION..."
COPY_JOB_ID=$(aws backup start-copy-job \
  --recovery-point-arn "$RECOVERY_ARN" \
  --source-backup-vault-name "$VAULT_NAME" \
  --destination-backup-vault-arn "$DR_VAULT_ARN" \
  --iam-role-arn "$IAM_ROLE_ARN" \
  --region "$PRIMARY_REGION" \
  --profile "$AWS_PROFILE" \
  --query 'CopyJobId' \
  --output text)
log_info "Copy job created: $COPY_JOB_ID"

# Poll until the cross-region copy reaches a terminal state.
log_info "Waiting for cross-region copy to complete (polls every 30s)..."
while true; do
  RESULT=$(aws backup describe-copy-job \
    --copy-job-id "$COPY_JOB_ID" \
    --region "$PRIMARY_REGION" \
    --profile "$AWS_PROFILE" \
    --query '{Status: CopyJob.State, Arn: CopyJob.DestinationRecoveryPointArn}' \
    --output json)

  STATUS=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['Status'])")
  DR_RECOVERY_ARN=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['Arn'] or '')")

  log_info "Copy status: $STATUS"

  if [ "$STATUS" = "COMPLETED" ]; then
    log_ok "Cross-region copy complete. DR recovery point: $DR_RECOVERY_ARN"
    break
  elif [ "$STATUS" = "FAILED" ] || [ "$STATUS" = "ABORTED" ]; then
    log_error "Copy job failed with status: $STATUS"
    exit 1
  fi

  sleep 30
done

# Print the DR recovery ARN to stdout so it can be piped to dr-restore.sh.
log_ok "DR backup ready in $DR_REGION. Run the restore script with:"
log_ok "  ./scripts/dr-restore.sh \"$DR_RECOVERY_ARN\""
echo "$DR_RECOVERY_ARN"
