# K8s Volume Report utility

Provided as script [bin/k8s-volume-report.sh](/bin/k8s-volume-report.sh).

This utility will generate a variety of reports on storage volumes in your Kubernetes cluster.

It is self-documenting and provides help info when invoked without parameters.

## Example outputs

The K8s Volume Report utility produces different output as directed.

### Namespace Report (`-n` switch)

A summary list of storage types, their counts, number of pods using those types, and supporting details.

```text
$PMP_HOME/bin/k8s-volume-report.sh -n viya
Fetching data from namespace 'viya'...

Volume Summary — namespace: viya  (111 pods)
─────────────────────────────────────────────────────────────────────────────────────────────────────────
TYPE            COUNT  PODS W/TYPE  DETAILS
─────────────────────────────────────────────────────────────────────────────────────────────────────────
emptyDir          295          110  4 w/ sizeLimit  |  3 w/ Memory medium
hostPath            0            0  (none)
PVC                25           19  19 unique claims  |  StorageClasses: viya-shared-sc, viya-standard-sc
GeV                 3            2  viya-scratch-sc: 50Gi×1, 64Gi×2
─────────────────────────────────────────────────────────────────────────────────────────────────────────
```

### Pod Report (`-p` switch)

Provide a pod's full name and a listing of all volume types used by the pod are returned.

```text
$PMP_HOME/bin/k8s-volume-report.sh -n viya -p 'sas-compute-server-0734183f-5a03-4826-bc26-98ba0271b5fb-24'
Fetching data from namespace 'viya'...

Pod: sas-compute-server-0734183f-5a03-4826-bc26-98ba0271b5fb-24
────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
VOLUME NAME                             TYPE        CLAIM / PATH                                         ACCESS    STORAGECLASS        SIZE         MEDIUM  
────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
commonfilesvols                         PVC         sas-commonfiles                                      RWX       viya-shared-sc      60Gi         -       
sas-quality-knowledge-base-volume       PVC         sas-quality-knowledge-base                           RWX       viya-shared-sc      8Gi          -       
tmp                                     GeV         -                                                    RWO       viya-scratch-sc     64Gi         -       
viya                                    GeV         -                                                    RWO       viya-scratch-sc     64Gi         -       
config-init-tmp                         emptyDir    -                                                    -         -                   unlimited    -       
sasuser                                 emptyDir    -                                                    -         -                   unlimited    -       
sashelp                                 emptyDir    -                                                    -         -                   unlimited    -       
config                                  emptyDir    -                                                    -         -                   unlimited    -       
security                                emptyDir    -                                                    -         -                   unlimited    -       
customer-provided-ca-certificates       configMap   sas-customer-provided-ca-certificates-6ct58987ht     -         -                   -            -       
sas-rdutil-dir                          configMap   sas-qkb-management-scripts                           -         -                   -            -       
certframe-token                         secret      sas-certframe-token                                  -         -                   -            -       
kube-api-access-94jwq                   projected   -                                                    -         -                   -            -       

Matched 1 pod(s).
```

If the pod name contains a wildcard character, then a summary report of volumes for each of the matching pods will be generated.

> Note, for wildcard values, be sure to single-quote the pod's name parameter to prevent unwanted shell expansion. 

### Individual PVC Report (`-c` switch)

Provide a PVC's name and get details about that persistent volume and the pod(s) bound to use it. Especially useful for RWX volumes used by multiple pods.

```text
$PMP_HOME/bin/k8s-volume-report.sh -n viya -c sas-commonfiles
Fetching data from namespace 'viya'...

PVC Report — sas-commonfiles  namespace: viya
────────────────────────────────────────────────────────────────────────────────
  Claim:                 sas-commonfiles
  Status:                Bound
  Access Mode:           RWX
  Storage Class:         viya-shared-sc
  Size:                  60Gi
  Volume (PV):           pvc-370cfb77-b575-4aae-bf64-488d6c05a8e4
  Reclaim Policy:        Retain
  CSI Driver:            nfs.csi.k8s.io
    mountPermissions:    0777
    server:              ip-192-168-38-41.ec2.internal
    share:               /export
    subDir:              pvs/viya-sas-commonfiles
  Created:               2026-07-28T17:12:19Z

──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
  POD                                               STATE       NODE                              MOUNT PATH                              
──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
  sas-cas-server-default-controller                 Running     ip-192-168-18-93.ec2.internal     /opt/sas/viya/home/commonfiles          
  sas-compute-server-0734183f-5a03-4826-bc26-98ba…  Running     ip-192-168-17-22.ec2.internal     /opt/sas/viya/home/commonfiles          
  sas-microanalytic-score-6f8c68fd5b-xdcf2          Running     ip-192-168-16-182.ec2.internal    /opt/sas/viya/home/commonfiles          
──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
```

> Note that the CSI Driver and dependent attributes are parsed based on spec formatting. This only works for storage defined to use a CSI Driver. If you use a different storage provider resource, these fields may be blank.

### Type Reports (`-t` switch)

Specify a volume type to get a report of pods with that type and relevant details. Types include: `PVC`, `GeV`, `hostPath`, `emptyDir`, `configMap`, `secret`, `projected`, `downwardAPI`.

#### Type: GeV report

```text
$PMP_HOME/bin/k8s-volume-report.sh -n viya -t GeV
Fetching data from namespace 'viya'...

Type Report — GeV  namespace: viya
───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
POD                                               VOLUME NAME                         ACCESS    STORAGECLASS        SIZE       
───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
sas-cas-server-default-controller                 cas-cache-gev                       RWO       viya-scratch-sc     50Gi       

sas-compute-server-0734183f-5a03-4826-bc26-98ba…  tmp                                 RWO       viya-scratch-sc     64Gi       
                                                  viya                                RWO       viya-scratch-sc     64Gi       
───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

3 matching volume(s) found.
```

> In my environment, generic ephemeral volumes defined for:
> - `sas-cas-server-` pods: CAS_DISK_CACHE
> - `sas-compute-server-` pods: ECE Cache (`/tmp`)
> - `sas-compute-server-` pods: SASWORK (`/viya`)

#### Type: PVC report

```text
$PMP_HOME/bin/k8s-volume-report.sh -n viya -t PVC
Fetching data from namespace 'viya'...

Type Report — PVC  namespace: viya
─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
POD                                               VOLUME NAME                         CLAIM                                         ACCESS    STORAGECLASS        SIZE       
─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
sas-cas-server-default-controller                 backup                              sas-cas-backup-data                           RWX       viya-shared-sc      8Gi        
                                                  cas-default-data-volume             cas-default-data                              RWX       viya-shared-sc      8Gi        
                                                  cas-default-permstore-volume        cas-default-permstore                         RWX       viya-shared-sc      100Mi      
                                                  commonfilesvols                     sas-commonfiles                               RWX       viya-shared-sc      60Gi       
                                                  sas-quality-knowledge-base-volume   sas-quality-knowledge-base                    RWX       viya-shared-sc      8Gi        

sas-commonfiles-49fc2                             commonfilesvol                      sas-commonfiles                               RWX       viya-shared-sc      60Gi       

sas-compute-server-0734183f-5a03-4826-bc26-98ba…  commonfilesvols                     sas-commonfiles                               RWX       viya-shared-sc      60Gi       
                                                  sas-quality-knowledge-base-volume   sas-quality-knowledge-base                    RWX       viya-shared-sc      8Gi        

sas-consul-server-0                               sas-viya-consul-data-volume         sas-viya-consul-data-volume-sas-consul-serv…  RWO       viya-standard-sc    1Gi        

sas-consul-server-1                               sas-viya-consul-data-volume         sas-viya-consul-data-volume-sas-consul-serv…  RWO       viya-standard-sc    1Gi        

sas-consul-server-2                               sas-viya-consul-data-volume         sas-viya-consul-data-volume-sas-consul-serv…  RWO       viya-standard-sc    1Gi        

sas-crunchy-platform-postgres-00-bqgf-0           postgres-data                       sas-crunchy-platform-postgres-00-bqgf-pgdata  RWO       viya-standard-sc    128Gi      

sas-crunchy-platform-postgres-00-hq8s-0           postgres-data                       sas-crunchy-platform-postgres-00-hq8s-pgdata  RWO       viya-standard-sc    128Gi      

sas-crunchy-platform-postgres-00-nf2j-0           postgres-data                       sas-crunchy-platform-postgres-00-nf2j-pgdata  RWO       viya-standard-sc    128Gi      

sas-crunchy-platform-postgres-repo-host-0         repo1                               sas-crunchy-platform-postgres-repo1           RWO       viya-standard-sc    128Gi      

sas-data-quality-services-79f467b89d-fqcbg        sas-quality-knowledge-base-volume   sas-quality-knowledge-base                    RWX       viya-shared-sc      8Gi        

sas-microanalytic-score-5c5fcb5c67-8x2z5          commonfilesvols                     sas-commonfiles                               RWX       viya-shared-sc      60Gi       
                                                  sas-quality-knowledge-base-volume   sas-quality-knowledge-base                    RWX       viya-shared-sc      8Gi        

sas-opendistro-default-0                          data                                data-sas-opendistro-default-0                 RWO       viya-standard-sc    128Gi      

sas-pyconfig-cjinitial-vzdl4                      saspyconfigvol                      sas-pyconfig                                  RWX       viya-shared-sc      20Gi       

sas-rabbitmq-server-0                             sas-viya-rabbitmq-data-volume       sas-viya-rabbitmq-data-volume-sas-rabbitmq-…  RWO       viya-standard-sc    2Gi        

sas-rabbitmq-server-1                             sas-viya-rabbitmq-data-volume       sas-viya-rabbitmq-data-volume-sas-rabbitmq-…  RWO       viya-standard-sc    2Gi        

sas-rabbitmq-server-2                             sas-viya-rabbitmq-data-volume       sas-viya-rabbitmq-data-volume-sas-rabbitmq-…  RWO       viya-standard-sc    2Gi        

sas-redis-server-0                                sas-viya-redis-data-volume          sas-viya-redis-data-volume-sas-redis-server…  RWO       viya-standard-sc    1Gi        

sas-redis-server-1                                sas-viya-redis-data-volume          sas-viya-redis-data-volume-sas-redis-server…  RWO       viya-standard-sc    1Gi        
─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

25 matching volume(s) found.
```

#### Type: emptyDir report

```text
$PMP_HOME/bin/k8s-volume-report.sh -n viya -t emptyDir
Fetching data from namespace 'viya'...

Type Report — emptyDir  namespace: viya
───────────────────────────────────────────────────────────────────────────────────────────────────────────
POD                                               VOLUME NAME                         SIZE LIMIT   MEDIUM  
───────────────────────────────────────────────────────────────────────────────────────────────────────────
sas-analytics-events-777fb8698d-v9hvx             security                            unlimited    -       
                                                  shared-vol                          unlimited    -       
                                                  tmp                                 unlimited    -       

sas-analytics-execution-5f86c66784-vm5vz          security                            unlimited    -       
                                                  shared-vol                          unlimited    -       
                                                  tmp                                 unlimited    -       

sas-analytics-gateway-54cd97bd69-b9pjw            security                            unlimited    -       
                                                  shared-vol                          unlimited    -       
                                                  tmp                                 unlimited    -       

...

sas-crunchy-platform-postgres-00-bqgf-0           dshm                                unlimited    Memory  
                                                  tmp                                 16Mi         -       

sas-crunchy-platform-postgres-00-hq8s-0           dshm                                unlimited    Memory  
                                                  tmp                                 16Mi         -       

sas-crunchy-platform-postgres-00-nf2j-0           dshm                                unlimited    Memory  
                                                  tmp                                 16Mi         -       

sas-crunchy-platform-postgres-repo-host-0         tmp                                 16Mi         -       

sas-crunchy5-postgres-operator-6bcc5b5774-8zhs7   security                            unlimited    -       

...

sas-workload-orchestrator-0                       config-var-log                      unlimited    -       
                                                  config-var-run                      unlimited    -       
                                                  scripts                             unlimited    -       
                                                  security                            unlimited    -       
                                                  shared-vol                          unlimited    -       
                                                  temp-dir                            unlimited    -       

sas-workload-orchestrator-1                       config-var-log                      unlimited    -       
                                                  config-var-run                      unlimited    -       
                                                  scripts                             unlimited    -       
                                                  security                            unlimited    -       
                                                  shared-vol                          unlimited    -       
                                                  temp-dir                            unlimited    -       

sas-workload-orchestrator-server-pzdf5            config-var-log                      unlimited    -       
                                                  config-var-run                      unlimited    -       
                                                  scripts                             unlimited    -       
                                                  security                            unlimited    -       
                                                  temp-dir                            unlimited    -       
───────────────────────────────────────────────────────────────────────────────────────────────────────────

295 matching volume(s) found.
```

> Note that some Crunchy Postgres emptyDir volumes specify a "medium" of "Memory". That means instead of using the default location set aside by Kubernetes on disk, these are assigned to tmpfs Linux volume (basically, it acts as a RAM disk).
