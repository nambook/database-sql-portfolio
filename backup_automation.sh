#!/bin/bash

# ============================================================================
# SQL Server Database Backup Automation Script
# Purpose: Automate multi-database backups with integrity checks and alerts
# Author: Hernan Rubio Pacheco
# Date: 2026
# ============================================================================

set -e  # Exit on error

# Configuration
BACKUP_DIR="/var/backups/sqlserver"
LOG_DIR="/var/log/sqlserver"
RETENTION_DAYS=30
EMAIL="hernanrubiopacheco@gmail.com"
DATABASES=("database1" "database2" "database3")

# Create directories if they don't exist
mkdir -p "$BACKUP_DIR" "$LOG_DIR"

# Log function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_DIR/backup_$(date '+%Y-%m-%d').log"
}

# Error handling
error_exit() {
    log "ERROR: $1"
    echo "Backup failed on $(date)" | mail -s "SQL Server Backup Failed" "$EMAIL"
    exit 1
}

log "Starting SQL Server backup routine..."

# ============================================================================
# STEP 1: BACKUP EACH DATABASE
# ============================================================================
for db in "${DATABASES[@]}"; do
    log "Backing up database: $db"
    
    BACKUP_FILE="$BACKUP_DIR/${db}_$(date '+%Y%m%d_%H%M%S').bak"
    
    # Execute SQL Server backup
    sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -Q "
    BACKUP DATABASE [$db]
    TO DISK = N'$BACKUP_FILE'
    WITH CHECKSUM, COMPRESSION
    " || error_exit "Failed to backup $db"
    
    log "Backup completed for $db: $BACKUP_FILE"
done

# ============================================================================
# STEP 2: VERIFY BACKUP INTEGRITY
# ============================================================================
log "Verifying backup integrity..."

for backup_file in "$BACKUP_DIR"/*.bak; do
    log "Verifying: $backup_file"
    
    sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -Q "
    RESTORE VERIFYONLY
    FROM DISK = N'$backup_file'
    " || log "WARNING: Integrity check failed for $backup_file"
done

log "Integrity verification complete."

# ============================================================================
# STEP 3: ENFORCE RETENTION POLICY
# ============================================================================
log "Enforcing retention policy (keeping $RETENTION_DAYS days)..."

find "$BACKUP_DIR" -name "*.bak" -type f -mtime +$RETENTION_DAYS -exec rm {} \; && \
log "Old backups removed (> $RETENTION_DAYS days)" || \
log "WARNING: Could not remove old backups"

# ============================================================================
# STEP 4: DISK SPACE CHECK
# ============================================================================
DISK_USAGE=$(du -sh "$BACKUP_DIR" | cut -f1)
log "Current backup directory size: $DISK_USAGE"

AVAILABLE_SPACE=$(df "$BACKUP_DIR" | awk 'NR==2 {print $4}')
if [ "$AVAILABLE_SPACE" -lt 10485760 ]; then  # Less than 10GB
    log "WARNING: Low disk space available: ${AVAILABLE_SPACE}KB"
    echo "Disk space warning: $AVAILABLE_SPACE KB available" | \
        mail -s "SQL Server Backup: Low Disk Space" "$EMAIL"
fi

# ============================================================================
# STEP 5: SUCCESS NOTIFICATION
# ============================================================================
log "SQL Server backup routine completed successfully."
echo "All backups completed successfully on $(date)" | \
    mail -s "SQL Server Backup Completed" "$EMAIL"

exit 0

# ============================================================================
# DEPLOYMENT:
# 1. Save this file as: /usr/local/bin/backup_sqlserver.sh
# 2. Make executable: chmod +x /usr/local/bin/backup_sqlserver.sh
# 3. Add to crontab (run daily at 2 AM):
#    0 2 * * * /usr/local/bin/backup_sqlserver.sh
# ============================================================================
