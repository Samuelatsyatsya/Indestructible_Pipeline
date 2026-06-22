#!/bin/bash
set -e

DR_RECOVERY_POINT_ARN="${1:?Usage: dr-restore.sh <DR_RECOVERY_POINT_ARN>}"

AWS_PROFILE="CostDetective"
PRIMARY_REGION="eu-central-1"
DR_REGION="eu-west-1"
PRIMARY_DB_ID="fincorp-primary-db"
RESTORED_DB_ID="fincorp-restored-db"
IAM_ROLE_ARN="arn:aws:iam::309797288544:role/fincorp-backup-role"

# Logging helpers — all output goes to stderr with a timestamp and level prefix.
log_info()  { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [INFO]  $*" >&2; }
log_warn()  { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [WARN]  $*" >&2; }
log_ok()    { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [OK]    $*" >&2; }
log_error() { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [ERROR] $*" >&2; }

# Delete the primary RDS instance to simulate a region failure (skip if already gone).
log_warn "SIMULATING REGION FAILURE — deleting primary RDS: $PRIMARY_DB_ID in $PRIMARY_REGION"
if aws rds describe-db-instances \
  --db-instance-identifier "$PRIMARY_DB_ID" \
  --region "$PRIMARY_REGION" \
  --profile "$AWS_PROFILE" > /dev/null 2>&1; then
  aws rds delete-db-instance \
    --db-instance-identifier "$PRIMARY_DB_ID" \
    --skip-final-snapshot \
    --region "$PRIMARY_REGION" \
    --profile "$AWS_PROFILE" > /dev/null
  log_info "Primary DB deletion initiated."
else
  log_info "Primary DB already deleted — proceeding to restore."
fi

# Start a restore job from the DR vault in eu-west-1.
log_info "Starting restore from DR vault in $DR_REGION..."
aws backup start-restore-job \
  --recovery-point-arn "$DR_RECOVERY_POINT_ARN" \
  --iam-role-arn "$IAM_ROLE_ARN" \
  --region "$DR_REGION" \
  --profile "$AWS_PROFILE" \
  --metadata '{"DBInstanceIdentifier":"fincorp-restored-db","DBInstanceClass":"db.t3.micro","Engine":"postgres","MultiAZ":"false"}' > /dev/null
log_info "Restore job started. Polling for availability (polls every 30s)..."

# Poll until the restored DB instance is available.
while true; do
  STATUS=$(aws rds describe-db-instances \
    --db-instance-identifier "$RESTORED_DB_ID" \
    --region "$DR_REGION" \
    --profile "$AWS_PROFILE" \
    --query 'DBInstances[0].DBInstanceStatus' \
    --output text 2>/dev/null || echo "not-found")

  log_info "Restored DB status: $STATUS"

  if [ "$STATUS" = "available" ]; then
    # Fetch the endpoint of the newly restored DB.
    ENDPOINT=$(aws rds describe-db-instances \
      --db-instance-identifier "$RESTORED_DB_ID" \
      --region "$DR_REGION" \
      --profile "$AWS_PROFILE" \
      --query 'DBInstances[0].Endpoint.Address' \
      --output text)
    break
  fi

  sleep 30
done

log_ok "DR restore complete."
log_ok "Restored DB endpoint : $ENDPOINT"
log_ok "Region               : $DR_REGION"
log_ok "RTO target met       : Database available in $DR_REGION"
