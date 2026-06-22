#!/bin/bash
set -e

AWS_PROFILE="CostDetective"
PRIMARY_REGION="eu-central-1"
DR_REGION="eu-west-1"
PRIMARY_DB_ID="fincorp-primary-db"
RESTORED_DB_ID="fincorp-restored-db"
ALARM_NAME="fincorp-rds-primary-down"
ROUTE53_RECORD="primary.db.fincorp.internal"

# Logging helpers — output to stderr with UTC timestamp and level prefix.
log_info()  { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [INFO]  $*" >&2; }
log_warn()  { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [WARN]  $*" >&2; }
log_ok()    { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [OK]    $*" >&2; }
log_error() { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [ERROR] $*" >&2; }

log_warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_warn "  DISASTER RECOVERY SIMULATION — STARTING"
log_warn "  This will DELETE the primary RDS in $PRIMARY_REGION."
log_warn "  The automatic failover stack will then take over."
log_warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Step 1: Confirm primary DB exists before proceeding ────────────────────────
log_info "Checking primary DB status..."
if ! aws rds describe-db-instances \
  --db-instance-identifier "$PRIMARY_DB_ID" \
  --region "$PRIMARY_REGION" \
  --profile "$AWS_PROFILE" > /dev/null 2>&1; then
  log_error "Primary DB '$PRIMARY_DB_ID' not found in $PRIMARY_REGION. Nothing to simulate."
  exit 1
fi
log_ok "Primary DB found. Proceeding with simulation."

# ── Step 2: Delete primary RDS to simulate region failure ──────────────────────
log_warn "STEP 1/4 — Deleting primary RDS '$PRIMARY_DB_ID' (simulating region failure)..."
aws rds delete-db-instance \
  --db-instance-identifier "$PRIMARY_DB_ID" \
  --skip-final-snapshot \
  --region "$PRIMARY_REGION" \
  --profile "$AWS_PROFILE" > /dev/null
log_info "Primary DB deletion initiated. CloudWatch will detect zero connections within 2 minutes."

# ── Step 3: Watch the CloudWatch alarm transition to ALARM state ───────────────
log_info "STEP 2/4 — Watching CloudWatch alarm '$ALARM_NAME' (polls every 30s)..."
while true; do
  ALARM_STATE=$(aws cloudwatch describe-alarms \
    --alarm-names "$ALARM_NAME" \
    --region "$PRIMARY_REGION" \
    --profile "$AWS_PROFILE" \
    --query 'MetricAlarms[0].StateValue' \
    --output text 2>/dev/null || echo "UNKNOWN")

  log_info "Alarm state: $ALARM_STATE"

  if [ "$ALARM_STATE" = "ALARM" ]; then
    log_ok "Alarm entered ALARM state — SNS has notified Lambda. Failover in progress."
    break
  fi

  sleep 30
done

# ── Step 4: Watch Lambda trigger the restore in eu-west-1 ─────────────────────
log_info "STEP 3/4 — Watching for restored DB '$RESTORED_DB_ID' in $DR_REGION (polls every 30s)..."
while true; do
  STATUS=$(aws rds describe-db-instances \
    --db-instance-identifier "$RESTORED_DB_ID" \
    --region "$DR_REGION" \
    --profile "$AWS_PROFILE" \
    --query 'DBInstances[0].DBInstanceStatus' \
    --output text 2>/dev/null || echo "not-found")

  log_info "Restored DB status: $STATUS"

  if [ "$STATUS" = "available" ]; then
    ENDPOINT=$(aws rds describe-db-instances \
      --db-instance-identifier "$RESTORED_DB_ID" \
      --region "$DR_REGION" \
      --profile "$AWS_PROFILE" \
      --query 'DBInstances[0].Endpoint.Address' \
      --output text)
    log_ok "Restored DB is available at: $ENDPOINT"
    break
  fi

  sleep 30
done

# ── Step 5: Verify Route 53 CNAME was updated by Lambda ───────────────────────
log_info "STEP 4/4 — Verifying Route 53 CNAME was updated..."
CNAME_VALUE=$(aws route53 list-resource-record-sets \
  --hosted-zone-id "$(aws route53 list-hosted-zones-by-name \
    --dns-name "db.fincorp.internal" \
    --profile "$AWS_PROFILE" \
    --query 'HostedZones[0].Id' \
    --output text | cut -d'/' -f3)" \
  --profile "$AWS_PROFILE" \
  --query "ResourceRecordSets[?Name=='${ROUTE53_RECORD}.'].ResourceRecords[0].Value" \
  --output text 2>/dev/null || echo "unknown")

log_info "Route 53 '$ROUTE53_RECORD' now points to: $CNAME_VALUE"

if echo "$CNAME_VALUE" | grep -q "$DR_REGION"; then
  log_ok "Route 53 CNAME successfully updated to DR endpoint in $DR_REGION."
else
  log_warn "CNAME may not have updated yet — Lambda could still be running. Check manually."
fi

# ── Summary ────────────────────────────────────────────────────────────────────
log_ok "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_ok "  DR SIMULATION COMPLETE"
log_ok "  Primary DB  : DELETED ($PRIMARY_REGION)"
log_ok "  Restored DB : $ENDPOINT ($DR_REGION)"
log_ok "  DNS record  : $ROUTE53_RECORD → $CNAME_VALUE"
log_ok "  Check your email for the SNS 'DR COMPLETE' notification."
log_ok "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
