# backup-mongodb.sh

#!/bin/bash
set -e

### Define the MongoDB host and port
MONGODB_HOST="my-mongodb-mongodb.default.svc.cluster.local"
MONGODB_PORT=27017
BACKUP_DIR="/backup"
TIMESTAMP=$(date +%F_%T)

### Create the backup directory if it does not exist
mkdir -p ${BACKUP_DIR}

### Dump the MongoDB database
mongodump --host ${MONGODB_HOST}:${MONGODB_PORT} --out ${BACKUP_DIR}/backup-${TIMESTAMP}

### Optional: Archive the backup
tar -czvf ${BACKUP_DIR}/backup-${TIMESTAMP}.tar.gz -C ${BACKUP_DIR} backup-${TIMESTAMP}

### Clean up the uncompressed backup directory
rm -rf ${BACKUP_DIR}/backup-${TIMESTAMP}

---------------------------------------------------------

# backup-job.yaml

apiVersion: batch/v1
kind: Job
metadata:
  name: mongodb-backup
spec:
  template:
    spec:
      containers:
      - name: mongodb-backup
        image: bitnami/mongodb:latest
        command: ["/bin/bash", "-c"]
        args: ["/scripts/backup-mongodb.sh"]
        volumeMounts:
        - name: backup-script
          mountPath: /scripts
        - name: backup-storage
          mountPath: /backup
      restartPolicy: OnFailure
      volumes:
      - name: backup-script
        configMap:
          name: mongodb-backup-script
      - name: backup-storage
        persistentVolumeClaim:
          claimName: mongodb-backup-pvc
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: mongodb-backup-script
data:
  backup-mongodb.sh: |
    #!/bin/bash
    set -e

    MONGODB_HOST="my-mongodb-mongodb.default.svc.cluster.local"
    MONGODB_PORT=27017
    BACKUP_DIR="/backup"
    TIMESTAMP=$(date +%F_%T)

    mkdir -p ${BACKUP_DIR}

    mongodump --host ${MONGODB_HOST}:${MONGODB_PORT} --out ${BACKUP_DIR}/backup-${TIMESTAMP}

    tar -czvf ${BACKUP_DIR}/backup-${TIMESTAMP}.tar.gz -C ${BACKUP_DIR} backup-${TIMESTAMP}

    rm -rf ${BACKUP_DIR}/backup-${TIMESTAMP}

------------------------------------------------------------------------

# backup-pvc.yaml

apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mongodb-backup-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi

----------------------------------------------------------------------------

kubectl apply -f backup-pvc.yaml
kubectl apply -f backup-job.yaml

----------------------------------------------------------------------------

# restore-mongodb.sh

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

--------------------------------------------------------------------------

# restore-job.yaml

apiVersion: batch/v1
kind: Job
metadata:
  name: mongodb-restore
spec:
  template:
    spec:
      containers:
      - name: mongodb-restore
        image: bitnami/mongodb:latest
        command: ["/bin/bash", "-c"]
        args: ["/scripts/restore-mongodb.sh", "TIMESTAMP"]  # Replace TIMESTAMP with your actual backup timestamp
        volumeMounts:
        - name: restore-script
          mountPath: /scripts
        - name: backup-storage
          mountPath: /backup
      restartPolicy: OnFailure
      volumes:
      - name: restore-script
        configMap:
          name: mongodb-restore-script
      - name: backup-storage
        persistentVolumeClaim:
          claimName: mongodb-backup-pvc
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: mongodb-restore-script
data:
  restore-mongodb.sh: |
    #!/bin/bash
    set -e

    MONGODB_HOST="my-mongodb-mongodb.default.svc.cluster.local"
    MONGODB_PORT=27017
    BACKUP_DIR="/backup"
    BACKUP_FILE=${BACKUP_DIR}/backup-$1.tar.gz

    tar -xzvf ${BACKUP_FILE} -C ${BACKUP_DIR}

    mongorestore --host ${MONGODB_HOST}:${MONGODB_PORT} --dir ${BACKUP_DIR}/backup-$1

    rm -rf ${BACKUP_DIR}/backup-$1

---------------------------------------------------------------------------

kubectl apply -f restore-job.yaml

-------------------------------------------------------------------------

# helm add mongodb

helm repo add mongodb https://mongodb.github.io/helm-charts
helm repo update
helm install my-mongodb mongodb/mongodb

------------------------------------------------------------------------

kubectl get svc my-mongodb -o jsonpath='{.spec.clusterIP}'
kubectl get secret my-mongodb -o jsonpath='{.data.mongodb-root-password}' | base64 --decode

--------------------------------------------------------------------------

# helm add rocketchat

helm repo add rocketchat https://helm.rocketchat.community
helm repo update

helm install my-rocketchat rocketchat/rocketchat \
  --set mongodb.enabled=false \
  --set mongodb.external.host=my-mongodb.mongodb.svc.cluster.local \
  --set mongodb.external.port=27017 \
  --set mongodb.external.username=admin \
  --set mongodb.external.password=my-password \
  --set mongodb.external.database=admin \
  --set mongodb.external.authSource=admin \
  --set env.MONGO_URL="mongodb://admin:my-password@my-mongodb.mongodb.svc.cluster.local:27017/admin?authSource=admin" \
  --set env.MONGO_OPLOG_URL="mongodb://admin:my-password@my-mongodb.mongodb.svc.cluster.local:27017/local?authSource=admin"

-----------------------------------------------------------------------------

kubectl get pods
kubectl get svc

------------------------------------------------------------------------------

helm upgrade my-rocketchat rocketchat/rocketchat \
  --set mongodb.enabled=false \
  --set mongodb.external.host=my-mongodb.mongodb.svc.cluster.local \
  --set mongodb.external.port=27017 \
  --set mongodb.external.username=admin \
  --set mongodb.external.password=my-password \
  --set mongodb.external.database=admin \
  --set mongodb.external.authSource=admin \
  --set env.MONGO_URL="mongodb://admin:my-password@my-mongodb.mongodb.svc.cluster.local:27017/admin?authSource=admin" \
  --set env.MONGO_OPLOG_URL="mongodb://admin:my-password@my-mongodb.mongodb.svc.cluster.local:27017/local?authSource=admin"

-------------------------------------------------------------------------------

# Full solution for helm rocketchat statefulset

kubectl create namespace rocketchat

Deploy mongodb as statefulsets

apiVersion: v1
kind: Service
metadata:
  name: mongodb
  namespace: rocketchat
  labels:
    app: mongodb
spec:
  ports:
  - port: 27017
    name: mongodb
  clusterIP: None
  selector:
    app: mongodb
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mongodb
  namespace: rocketchat
spec:
  serviceName: "mongodb"
  replicas: 1
  selector:
    matchLabels:
      app: mongodb
  template:
    metadata:
      labels:
        app: mongodb
    spec:
      containers:
      - name: mongodb
        image: mongo:4.4
        ports:
        - containerPort: 27017
          name: mongodb
        volumeMounts:
        - name: mongo-persistent-storage
          mountPath: /data/db
        env:
        - name: MONGO_INITDB_ROOT_USERNAME
          value: "admin"
        - name: MONGO_INITDB_ROOT_PASSWORD
          value: "password"
  volumeClaimTemplates:
  - metadata:
      name: mongo-persistent-storage
      namespace: rocketchat
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 10Gi


kubectl apply -f mongodb-statefulset.yaml

---------------------------------------------------------------

helm repo add rocketchat https://helm.rocketchat.community
helm repo update

replicaCount: 1

mongodb:
  enabled: false
  external:
    host: mongodb.rocketchat.svc.cluster.local
    port: 27017
    username: admin
    password: password
    database: admin
    authSource: admin

env:
  MONGO_URL: "mongodb://admin:password@mongodb.rocketchat.svc.cluster.local:27017/admin?authSource=admin"
  MONGO_OPLOG_URL: "mongodb://admin:password@mongodb.rocketchat.svc.cluster.local:27017/local?authSource=admin"

helm install my-rocketchat rocketchat/rocketchat -n rocketchat -f rocketchat-values.yaml

kubectl get pods -n rocketchat
kubectl get svc -n rocketchat

apiVersion: v1
kind: Service
metadata:
  name: rocketchat
  namespace: rocketchat
spec:
  type: LoadBalancer
  ports:
  - port: 80
    targetPort: 3000
  selector:
    app: rocketchat

kubectl apply -f rocketchat-service.yaml

-----------------------------------------------------------