#!/bin/bash
set -e

# Define the MongoDB host and port
MONGODB_HOST="my-mongodb-mongodb.default.svc.cluster.local"
MONGODB_PORT=27017
BACKUP_DIR="/backup"
BACKUP_FILE=${BACKUP_DIR}/backup-$1.tar.gz

# Extract the backup
tar -xzvf ${BACKUP_FILE} -C ${BACKUP_DIR}

# Restore the MongoDB database
mongorestore --host ${MONGODB_HOST}:${MONGODB_PORT} --dir ${BACKUP_DIR}/backup-$1

# Clean up the extracted backup
rm -rf ${BACKUP_DIR}/backup-$1