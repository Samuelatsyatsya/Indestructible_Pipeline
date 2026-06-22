import boto3
import json
import os
import time

DR_REGION        = os.environ["DR_REGION"]
DR_VAULT_NAME    = os.environ["DR_VAULT_NAME"]
IAM_ROLE_ARN     = os.environ["IAM_ROLE_ARN"]
RESTORED_DB_ID   = os.environ["RESTORED_DB_ID"]
ROUTE53_ZONE_ID  = os.environ["ROUTE53_ZONE_ID"]
ROUTE53_RECORD   = os.environ["ROUTE53_RECORD"]
SNS_TOPIC_ARN    = os.environ["SNS_TOPIC_ARN"]

def lambda_handler(event, context):
    print(f"DR failover triggered. Event: {json.dumps(event)}")

    backup  = boto3.client("backup",  region_name=DR_REGION)
    rds     = boto3.client("rds",     region_name=DR_REGION)
    r53     = boto3.client("route53")
    sns     = boto3.client("sns")

    # Find the most recent completed recovery point in the DR vault.
    resp = backup.list_recovery_points_by_backup_vault(
        BackupVaultName=DR_VAULT_NAME,
        ByResourceType="RDS",
    )
    points = [p for p in resp["RecoveryPoints"] if p["Status"] == "COMPLETED"]
    if not points:
        _notify(sns, "DR FAILED: no completed recovery points found in DR vault.")
        raise RuntimeError("No completed recovery points in DR vault")

    latest = sorted(points, key=lambda p: p["CreationDate"], reverse=True)[0]
    recovery_arn = latest["RecoveryPointArn"]
    print(f"Latest recovery point: {recovery_arn}")

    # Start the restore job in eu-west-1.
    backup.start_restore_job(
        RecoveryPointArn=recovery_arn,
        IamRoleArn=IAM_ROLE_ARN,
        Metadata={
            "DBInstanceIdentifier": RESTORED_DB_ID,
            "DBInstanceClass":      "db.t3.micro",
            "Engine":               "postgres",
            "MultiAZ":              "false",
        },
    )
    print(f"Restore job started for {RESTORED_DB_ID}")

    # Poll until the restored DB is available (max 40 minutes).
    endpoint = _wait_for_db(rds, RESTORED_DB_ID)

    # Strip the port suffix from the endpoint (Route 53 CNAME needs host only).
    host = endpoint.split(":")[0]

    # Update the Route 53 CNAME to point to the restored DB.
    r53.change_resource_record_sets(
        HostedZoneId=ROUTE53_ZONE_ID,
        ChangeBatch={
            "Comment": "DR failover — pointing to restored DB in eu-west-1",
            "Changes": [{
                "Action": "UPSERT",
                "ResourceRecordSet": {
                    "Name": ROUTE53_RECORD,
                    "Type": "CNAME",
                    "TTL":  30,
                    "ResourceRecords": [{"Value": host}],
                },
            }],
        },
    )
    print(f"Route53 updated: {ROUTE53_RECORD} → {host}")

    msg = (
        f"DR COMPLETE\n\n"
        f"Restored DB : {RESTORED_DB_ID}\n"
        f"Endpoint    : {host}\n"
        f"Region      : {DR_REGION}\n"
        f"DNS record  : {ROUTE53_RECORD} updated automatically.\n"
        f"App will reconnect on next DB connection attempt — no restart needed."
    )
    _notify(sns, msg)
    return {"status": "ok", "endpoint": host}


def _wait_for_db(rds_client, db_id, timeout=2400, interval=30):
    # Poll RDS until the instance is available or timeout is reached.
    elapsed = 0
    while elapsed < timeout:
        try:
            resp   = rds_client.describe_db_instances(DBInstanceIdentifier=db_id)
            status = resp["DBInstances"][0]["DBInstanceStatus"]
            endpoint = resp["DBInstances"][0].get("Endpoint", {}).get("Address")
            print(f"Restore status: {status} ({elapsed}s elapsed)")
            if status == "available" and endpoint:
                return resp["DBInstances"][0]["Endpoint"]["Address"] + ":" + str(resp["DBInstances"][0]["Endpoint"]["Port"])
        except rds_client.exceptions.DBInstanceNotFoundFault:
            print(f"DB not yet visible ({elapsed}s elapsed)")
        time.sleep(interval)
        elapsed += interval
    raise TimeoutError(f"DB {db_id} did not become available within {timeout}s")


def _notify(sns_client, message):
    sns_client.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject="FinCorp — Automatic DR Failover",
        Message=message,
    )
