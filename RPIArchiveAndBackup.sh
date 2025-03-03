#!/bin/bash

# Variables
BACKUP_DIR="/mnt/usbdata"
ARCHIVE_NAME="backup_$(date +%Y%m%d_%H%M%S).tar.gz"
ARCHIVE_PATH="$BACKUP_DIR/$ARCHIVE_NAME"
SMB_SHARE="//<IP address>/RPI_backup"
TAR_ERROR_LOG="/var/log/tar_errors.log"
LOG_FILE="/var/log/backup_activity.log"

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Ensure backup directory exists
if [ ! -d "$BACKUP_DIR" ]; then
  log "Backup directory $BACKUP_DIR does not exist. Exiting."
  exit 1
fi

# Create the archive, excluding dynamic filesystems and the backup directory
log "Creating archive..."
sudo tar --exclude="$BACKUP_DIR" \
          --exclude="/proc" \
          --exclude="/sys" \
          --exclude="/run" \
          --exclude="/dev" \
          --exclude="/tmp" \
          --warning=no-file-changed \
          --ignore-failed-read \
          -czvf "$ARCHIVE_PATH" / 2> "$TAR_ERROR_LOG"
tar_exit_code=$?

# Check if tar encountered a critical error (exit code not 0 but ignore warnings)
if [ $tar_exit_code -ne 0 ] && ! grep -q "Removing leading \`/' from" $TAR_ERROR_LOG; then
  log "Error creating archive. Check $TAR_ERROR_LOG for details. Exiting."
  exit 1
fi
log "Archive created at $ARCHIVE_PATH"

# Mount the SMB share (if not already mounted)
MOUNT_POINT="/mnt/smbshare"
if [ ! -d "$MOUNT_POINT" ]; then
  sudo mkdir -p "$MOUNT_POINT"
fi

# Check if SMB share is already mounted
if ! mountpoint -q "$MOUNT_POINT"; then
  log "Mounting SMB share..."
    sudo mount -t cifs "$SMB_SHARE" "$MOUNT_POINT" -o credentials=/home/admin/.smbcredentials
  if [ $? -ne 0 ]; then
    log "Error mounting SMB share. Exiting."
    exit 1
  fi
  log "SMB share mounted successfully."
else
  log "SMB share is already mounted."
fi

# Copy the archive to the SMB share
log "Copying archive to SMB share..."
sudo cp "$ARCHIVE_PATH" "$MOUNT_POINT/"

# Check if the copy was successful
if [ $? -eq 0 ]; then
  log "Backup successfully copied to SMB share."
  # Delete the archive after successful copy
  sudo rm -f "$ARCHIVE_PATH"
  log "Local archive deleted after successful copy."
else
  log "Error copying backup to SMB share."
fi

# Unmount the SMB share if it was mounted by this script
if mountpoint -q "$MOUNT_POINT"; then
  sudo umount "$MOUNT_POINT"
  log "SMB share unmounted."
fi

# Clean up
sudo rmdir "$MOUNT_POINT"
log "Cleanup complete."

exit 0
