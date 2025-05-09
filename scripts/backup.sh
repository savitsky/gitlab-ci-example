#!/bin/sh
set -eo pipefail

SRC_HOST="ip_mongo_host"
SSH_USER="your_user"

SRC_DUMP_PATH="/mnt/mongodump"
LOCAL_DUMP="/tmp"
DUMP_NAME="mongodb_backup_$(date +%Y_%m_%d).gz"

MODE="$1"
NS="$2"
ENVNAME="$3"

case "$MODE" in
  BACKUP)
    echo "$MONGO_BRN_SSH_KEY_B64" | base64 -d > /tmp/id_rsa && chmod 600 /tmp/id_rsa
    echo "Testing SSH key"
    if ssh -i /tmp/id_rsa -o StrictHostKeyChecking=no "$SSH_USER@$SRC_HOST" true; then
        echo "[INFO] SSH connection established"
        echo "[INFO] Starting backup"
        echo "[INFO] Backup path: $SRC_DUMP_PATH/$DUMP_NAME"
        ssh -i /tmp/id_rsa -o StrictHostKeyChecking=no $SSH_USER@$SRC_HOST mongodump --gzip --archive=$SRC_DUMP_PATH/$DUMP_NAME
        echo "[INFO] Backup completed"
        ssh -i /tmp/id_rsa -o StrictHostKeyChecking=no $SSH_USER@$SRC_HOST ls -lah $SRC_DUMP_PATH/
        echo "[INFO] Copying backup to local container"
        #scp -i /tmp/id_rsa -o StrictHostKeyChecking=no $SSH_USER@$SRC_HOST:$SRC_DUMP_PATH/$DUMP_NAME $LOCAL_DUMP/$DUMP_NAME
        rsync -avz -e "ssh -i /tmp/id_rsa -o StrictHostKeyChecking=no" $SSH_USER@$SRC_HOST:$SRC_DUMP_PATH/$DUMP_NAME $LOCAL_DUMP/$DUMP_NAME
        echo "[INFO] Done"
        echo "[INFO] Uploading backup to MinIO"
        mc alias set myminio "$MINIO_HOST" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY"
        mc cp $LOCAL_DUMP/$DUMP_NAME myminio/$MINIO_BUCKET/
        echo "[INFO] Finished!"
    else
        echo "[ERROR] Failed to establish SSH connection"
        exit 1
    fi
    ;;

  RESTORE)
    echo "[INFO] Starting restore"
    echo "$KUBECONFIG_B64" | base64 -d > /tmp/kubeconfig
    export KUBECONFIG=/tmp/kubeconfig
    echo "[INFO] Connecting to MongoDB pod and listing databases"
    echo "[INFO] NS: $NS"
    echo "[INFO] env: $ENVNAME"
    MONGO_POD=$(kubectl get pod -n $NS -l app=mongo,env=$ENVNAME -o jsonpath="{.items[0].metadata.name}")
    if [ -z "$MONGO_POD" ]; then
      echo "[ERROR] MongoDB pod not found"
      exit 1
    else
      echo "[INFO] Pod name is: $MONGO_POD"
      kubectl -n $NS exec "$MONGO_POD" -- mongo -u "$MONGO_K8S_USER" -p "$MONGO_K8S_PASS" --quiet --eval "db.adminCommand('listDatabases')"
      echo "###################################"
      echo "[INFO] Checking backup bucket"
      mc alias set myminio "$MINIO_HOST" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY"
      mc ls myminio/$MINIO_BUCKET/
      echo "###################################"
      LATEST_DUMP=$(mc ls myminio/$MINIO_BUCKET/ | awk '{print $NF}' | grep -E '^mongodb_backup_[0-9]{4}_[0-9]{2}_[0-9]{2}\.gz$' | sort | tail -n 1)

      if [ -z "$LATEST_DUMP" ]; then
        echo "[ERROR] Archive not found in MinIO bucket"
        exit 1
      else
        echo "[INFO] Using dump: $LATEST_DUMP"
        LOCAL_DUMP="/tmp/$LATEST_DUMP"
        echo "[INFO] Downloading archive from MinIO: $LATEST_DUMP"
        mc cp "myminio/$MINIO_BUCKET/$LATEST_DUMP" "$LOCAL_DUMP"
        echo "[INFO] Done"
        echo "###################################"
        echo "[INFO] Copying archive to MongoDB pod"
        kubectl cp "$LOCAL_DUMP" "$NS/$MONGO_POD:/data/db/$LATEST_DUMP"
        echo "[INFO] Done"
        echo "###################################"
        echo "[INFO] Starting MongoDB database restore"
        if kubectl exec -n $NS "$MONGO_POD" -- mongorestore --gzip --archive="/data/db/$LATEST_DUMP" --username="$MONGO_K8S_USER" --password="$MONGO_K8S_PASS" --authenticationDatabase=admin; then
          echo "[INFO] Databases restored successfully"
          echo "[INFO] Removing archive from Mongo pod"
          kubectl exec -n $NS "$MONGO_POD" -- rm -f "/data/db/$LATEST_DUMP"
          echo "[INFO] Removing local temporary files"
          rm -f /tmp/kubeconfig
          rm -f "$LOCAL_DUMP"
          echo "[INFO] Done."
        else
          echo "[ERROR] An error occurred during the restore process"
        fi
      fi
    fi

    ;;

  *)
    echo "[ERROR] Unknown mode: $MODE"
    exit 1
    ;;
esac
