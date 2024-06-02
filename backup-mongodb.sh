#!/bin/bash
set -e

# Define the MongoDB host and port
MONGODB_HOST="my-mongodb-mongodb.default.svc.cluster.local"
MONGODB_PORT=27017
BACKUP_DIR="/backup"
TIMESTAMP=$(date +%F_%T)

# Create the backup directory if it does not exist
mkdir -p ${BACKUP_DIR}

# Dump the MongoDB database
mongodump --host ${MONGODB_HOST}:${MONGODB_PORT} --out ${BACKUP_DIR}/backup-${TIMESTAMP}

# Optional: Archive the backup
tar -czvf ${BACKUP_DIR}/backup-${TIMESTAMP}.tar.gz -C ${BACKUP_DIR} backup-${TIMESTAMP}

# Clean up the uncompressed backup directory
rm -rf ${BACKUP_DIR}/backup-${TIMESTAMP}