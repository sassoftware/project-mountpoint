# Install OpenEBS on AWS for 3 Starter Storage Classes

This guide installs OpenEBS as the storage implementation for the 3 Starter Storage Classes (3SSC):

- `viya-standard-sc`: replicated persistent RWO volumes from OpenEBS Replicated PV Mayastor
- `viya-shared-sc`: persistent RWX volumes from an in-cluster NFS server backed by Mayastor RWO storage
- `viya-scratch-sc`: local, non-replicated LVM volumes for Generic Ephemeral Volumes (GeVs)

The guide stops after the storage classes are defined. Test all three classes before deploying SAS Viya.

> **Important:** Mayastor is not a replacement for the Amazon EBS CSI driver. It replicates data across raw disks assigned to Mayastor disk pools; it does not make AWS API calls. Therefore it needs no AWS IAM role, IRSA annotation, or EBS policy on each node.
>
> If dedicated Mayastor pool disks are created or managed by the Amazon EBS CSI driver, install that separate driver using [RWO storage for `viya-standard-sc`: Amazon EBS](./Deploy-Viya-to-AWS-withOpenEBS.md#rwo-storage-for-viya-standard-sc-amazon-ebs). Its IAM role belongs to `kube-system/ebs-csi-controller-sa`, not OpenEBS. Do not attach `AmazonEBSCSIDriverPolicy` to every Kubernetes node role when the controller uses IRSA.

## Storage topology and prerequisites

| Use | OpenEBS implementation | Required backing storage |
| --- | --- | --- |
| Persistent RWO | Replicated PV Mayastor | One dedicated, unformatted raw disk on each of at least three storage nodes |
| Persistent RWX | NFS server on Mayastor RWO storage | The replicated Mayastor storage above |
| Local GeV | Local PV LVM | A separate local NVMe disk or partition configured as an LVM volume group on CAS and Compute nodes |

Never use the same device for a Mayastor disk pool and an LVM volume group. Mayastor destroys existing data on a pool device.

The current AWS exercise uses local NVMe on CAS and Compute nodes for `/viya-scratch`. Reserve that disk for LVM. Provide a **different** raw device on three or more nodes for Mayastor pools. This can be a dedicated EBS data disk attached by node-group configuration, provided it survives node restart and has a stable `/dev/disk/by-id/` path.

Before continuing, ensure:

- At least three storage nodes, preferably in separate Availability Zones, have dedicated raw pool disks.
- Each Mayastor storage node has two free CPU cores, 1 GiB RAM, 2 GiB of 2 MiB HugePages, and `nvme-tcp`.
- Every node that can mount shared storage includes the NFS client package. On Rocky/RHEL-family node images, install `nfs-utils`.
- CAS and Compute node images include `lvm2`, load `dm-snapshot`, and create volume group `viya-scratch-vg` from their local NVMe disk.
- Ports `10124`, `8420`, and `4421` are available between Mayastor storage nodes.

Review the [OpenEBS prerequisites](https://openebs.io/docs/quickstart-guide/prerequisites) before preparing node images or node-group bootstrap configuration.

## Playpen: provision Mayastor pool nodes with IAC

The `viya4-iac-aws` node-pool model can provision a demonstration Mayastor pool without changing its `.tf` source: select an instance type that includes local NVMe instance storage. Add the following `mayastor` object to the `node_pools` map in `${MY_PREFIX}.tfvars`:

```hcl
mayastor = {
  "vm_type"      = "r6idn.2xlarge" # 8 vCPU, 64 GiB RAM, 1 x 474 GB local NVMe
  "cpu_type"     = "AL2023_x86_64_STANDARD"
  "os_disk_type" = "gp3"
  "os_disk_size" = 200
  "os_disk_iops" = 0
  "min_nodes"    = 3
  "max_nodes"    = 3
  "node_taints"  = []
  "node_labels" = {
    "openebs.io/engine"        = "mayastor"
    "workload.sas.com/class"   = "mayastor"
  }
  "custom_data"                          = "/workspace/files/custom-data/mayastor-node-bootstrap.sh"
  "metadata_http_endpoint"               = "enabled"
  "metadata_http_tokens"                 = "required"
  "metadata_http_put_response_hop_limit" = 1
}
```

Create `viya4-iac-aws/files/custom-data/mayastor-node-bootstrap.sh` before planning the update:

```bash
#!/usr/bin/env bash
# Do not format the local NVMe device: OpenEBS claims it later as a DiskPool.
dnf install -y nfs-utils

cat >/etc/modules-load.d/openebs-mayastor.conf <<'EOF'
nvme-tcp
EOF
modprobe nvme-tcp

cat >/etc/sysctl.d/90-openebs-mayastor.conf <<'EOF'
vm.nr_hugepages = 1024
EOF
sysctl --system
```

The existing `terraform` alias mounts `~/viya4-iac-aws` at `/workspace`; the `custom_data` value therefore uses that in-container path and needs neither an alias change nor an image rebuild. Re-plan and apply the updated IAC before continuing:

```bash
terraform plan \
  -input=false \
  -var-file=/workspace/${MY_PREFIX}.tfvars \
  -state=/workspace/${MY_PREFIX}.tfstate \
  -out=/workspace/${MY_PREFIX}-mayastor.tfplan

terraform apply -state=/workspace/${MY_PREFIX}.tfstate \
  /workspace/${MY_PREFIX}-mayastor.tfplan
```

> Review the plan before running `apply`. It should add the Mayastor node group and its dependencies only. If it proposes unrelated changes to existing node pools, security groups, the jump host, NFS server, or kubeconfig, stop and reconcile that Terraform drift first; do not use this storage exercise to apply unrelated infrastructure changes.
>
> This is a playpen-only pattern. `r6idn.2xlarge` provides **instance-store** NVMe, which is erased if EC2 replaces or stops the node. Keep all three nodes on-demand and fixed at three. Three-way Mayastor replication can rebuild after a single node loss, but the pool is degraded until the replacement node and its DiskPool are available. For durable storage, use dedicated persistent EBS pool disks instead.

## Establish attributes

```bash
# Cluster and OpenEBS release
export CLUSTER_NAME="${MY_PREFIX}-eks"
export OPENEBS_NAMESPACE="openebs"
export OPENEBS_RELEASE="openebs"
export OPENEBS_CHART_VERSION="4.5.1"

# Provider classes and 3SSC dependencies
export MAYASTOR_SC="openebs-mayastor-3"
export NFS_NAMESPACE="openebs-nfs"
export NFS_SERVER_NAME="viya-nfs-server"
export NFS_SC="openebs-nfs"
export LVM_SC="openebs-lvm"
export LVM_VG="viya-scratch-vg"
export NFS_BACKEND_SIZE="100Gi"

add_my_var CLUSTER_NAME
add_my_var OPENEBS_NAMESPACE
add_my_var MAYASTOR_SC
add_my_var NFS_NAMESPACE
add_my_var NFS_SERVER_NAME
add_my_var NFS_SC
add_my_var LVM_SC
add_my_var LVM_VG
```

## Prepare the storage nodes

### Label Mayastor storage nodes

This example uses the existing `stateful` node pool. Use a different selector if the site provides separate storage nodes.

```bash
# Review the selected nodes, then label them for the Mayastor I/O engine.
kubectl get nodes -l workload.sas.com/class=stateful
kubectl get nodes -l workload.sas.com/class=stateful -o name \
  | xargs -r -n1 kubectl label --overwrite openebs.io/engine=mayastor

kubectl get nodes -l openebs.io/engine=mayastor
```

### Configure Mayastor prerequisites

Configure these requirements in the node image, cloud-init, or node-group bootstrap logic, so that they persist across replacement and restart. Do not rely on ad-hoc SSH changes.

```bash
# Run on every Mayastor storage node.
grep HugePages /proc/meminfo
lsmod | grep -E 'nvme_tcp|nvme_fabrics'
lsblk -f

cat <<'EOF2' | sudo tee /etc/modules-load.d/openebs-mayastor.conf
nvme-tcp
EOF2
cat <<'EOF2' | sudo tee /etc/sysctl.d/90-openebs-mayastor.conf
vm.nr_hugepages = 1024
EOF2

sudo modprobe nvme-tcp
sudo sysctl --system
```

Restart `kubelet` or reboot the node after changing HugePages. The disk assigned to Mayastor must be unpartitioned, unformatted, and unused by LVM or the operating system.

### Configure LVM scratch devices

`viya-scratch-sc` uses a device other than the Mayastor disk. On each CAS and Compute node, create the `viya-scratch-vg` volume group from its local NVMe device. The existing exercise uses `/dev/nvme1n1`; verify the actual device before changing it.

```bash
# Run on CAS and Compute nodes only.
sudo dnf install -y lvm2
sudo modprobe dm-snapshot

# Confirm this is the local scratch device and has no data to preserve.
lsblk -f /dev/nvme1n1

sudo pvcreate /dev/nvme1n1
sudo vgcreate "${LVM_VG}" /dev/nvme1n1
sudo vgs "${LVM_VG}"
```

Do not also run `deploy-nvme-daemonset.sh` against the device that becomes `viya-scratch-vg`: formatting and mounting it at `/viya-scratch` conflicts with LVM.

## AWS IAM role and Kubernetes service account

No OpenEBS component in this design calls AWS APIs. There is no OpenEBS-specific IAM role or IRSA service account to create, and no AWS policy to attach to Kubernetes node roles.

The Helm chart creates the Kubernetes service accounts and RBAC that OpenEBS requires. If the site also uses the Amazon EBS CSI driver to manage dedicated EBS pool disks, create its controller IAM role and annotate `kube-system/ebs-csi-controller-sa` as documented in the existing [Amazon EBS section](./Deploy-Viya-to-AWS-withOpenEBS.md#rwo-storage-for-viya-standard-sc-amazon-ebs). It is a separate dependency, not an OpenEBS permission.

## Helm: deploy OpenEBS

Install the current OpenEBS chart with Replicated PV Mayastor and Local PV LVM. The default chart also installs other local engines; the storage classes below explicitly select the ones used by Viya.

```bash
helm repo add openebs https://openebs.github.io/openebs
helm repo update

helm upgrade --install "${OPENEBS_RELEASE}" openebs/openebs \
  --namespace "${OPENEBS_NAMESPACE}" \
  --create-namespace \
  --version "${OPENEBS_CHART_VERSION}" \
  --wait

helm status "${OPENEBS_RELEASE}" -n "${OPENEBS_NAMESPACE}"
kubectl get pods -n "${OPENEBS_NAMESPACE}"
kubectl get csidriver
```

## Create Mayastor disk pools

Create one `DiskPool` per Mayastor storage node. Three-replica storage requires at least three online pools on separate nodes. Use a persistent `/dev/disk/by-id/` or `/dev/disk/by-path/` link, never a volatile `/dev/nvme*n*` name.

Identify the stable `/dev/disk/by-id/` link for the dedicated disk on each storage node while preparing the node image or bootstrap configuration. Do not use a transient `/dev/nvme*n*` name. Then create the disk-pool manifest:

```bash
cat <<'EOF2' > ~/project/deploy/defineOpenEBS_MayastorDiskPools.yaml
---
apiVersion: openebs.io/v1beta3
kind: DiskPool
metadata:
  name: mayastor-pool-1
  namespace: openebs
spec:
  node: REPLACE_WITH_FIRST_STORAGE_NODE
  disks:
    - aio:///dev/disk/by-id/REPLACE_WITH_FIRST_DEDICATED_DISK
  maxExpansion: "2x"
---
apiVersion: openebs.io/v1beta3
kind: DiskPool
metadata:
  name: mayastor-pool-2
  namespace: openebs
spec:
  node: REPLACE_WITH_SECOND_STORAGE_NODE
  disks:
    - aio:///dev/disk/by-id/REPLACE_WITH_SECOND_DEDICATED_DISK
  maxExpansion: "2x"
---
apiVersion: openebs.io/v1beta3
kind: DiskPool
metadata:
  name: mayastor-pool-3
  namespace: openebs
spec:
  node: REPLACE_WITH_THIRD_STORAGE_NODE
  disks:
    - aio:///dev/disk/by-id/REPLACE_WITH_THIRD_DEDICATED_DISK
  maxExpansion: "2x"
EOF2

# Substitute all placeholders, review, then apply.
kubectl apply -f ~/project/deploy/defineOpenEBS_MayastorDiskPools.yaml
kubectl get diskpools -n "${OPENEBS_NAMESPACE}"
```

All pools must report `Online` before the three-replica class is consumed. Refer to the [DiskPool documentation](https://openebs.io/docs/user-guides/replicated-storage-user-guide/replicated-pv-mayastor/configuration/rs-create-diskpool) for sizing and expansion.

## Deploy the NFS Server feature

Current OpenEBS 4.5 guidance provides RWX storage through an NFS server backed by a Mayastor RWO PVC and the Kubernetes NFS CSI driver. This avoids the archived OpenEBS Dynamic NFS Provisioner, whose upstream project remains beta.

### Deploy the NFS CSI driver

```bash
helm repo add csi-driver-nfs https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
helm repo update

helm upgrade --install csi-driver-nfs csi-driver-nfs/csi-driver-nfs \
  --namespace kube-system \
  --version v4.11.0 \
  --wait

# Avoid recursive fsGroup changes on large Viya volumes such as python-volume.
kubectl patch csidriver nfs.csi.k8s.io \
  -p '{"spec":{"fsGroupPolicy":"None"}}'
```

### Create the NFS server

The NFS server is one pod. Mayastor replicates its backing data, but this does not make the NFS server itself highly available. Treat this as a workshop/reference implementation; use a production-grade RWX provider where an HA NFS service is required.

```bash
kubectl create namespace "${NFS_NAMESPACE}" --dry-run=client -o yaml \
  | kubectl apply -f -

cat <<EOF2 | kubectl apply -f -
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${NFS_SERVER_NAME}-data
  namespace: ${NFS_NAMESPACE}
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ${MAYASTOR_SC}
  resources:
    requests:
      storage: ${NFS_BACKEND_SIZE}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${NFS_SERVER_NAME}
  namespace: ${NFS_NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: ${NFS_SERVER_NAME}
  template:
    metadata:
      labels:
        app.kubernetes.io/name: ${NFS_SERVER_NAME}
    spec:
      containers:
        - name: nfs-server
          image: itsthenetwork/nfs-server-alpine:12
          env:
            - name: SHARED_DIRECTORY
              value: /nfsshare
          ports:
            - name: nfs
              containerPort: 2049
          securityContext:
            privileged: true
          volumeMounts:
            - name: data
              mountPath: /nfsshare
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: ${NFS_SERVER_NAME}-data
---
apiVersion: v1
kind: Service
metadata:
  name: ${NFS_SERVER_NAME}
  namespace: ${NFS_NAMESPACE}
spec:
  selector:
    app.kubernetes.io/name: ${NFS_SERVER_NAME}
  ports:
    - name: nfs
      port: 2049
      targetPort: nfs
EOF2

kubectl rollout status deployment/"${NFS_SERVER_NAME}" -n "${NFS_NAMESPACE}"
```

## Define OpenEBS storage classes

Create generic provider classes first, then copy them to the names Viya uses. This retains the 3SSC abstraction: Viya configuration need not change when the site changes physical storage.

```bash
mkdir -p ~/project/deploy

cat <<EOF2 > ~/project/deploy/defineOpenEBS_StorageClasses.yaml
---
# Persistent, synchronously replicated RWO storage.
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ${MAYASTOR_SC}
provisioner: io.openebs.csi-mayastor
allowVolumeExpansion: true
reclaimPolicy: Delete
volumeBindingMode: Immediate
parameters:
  repl: "3"
  protocol: "nvmf"
  thin: "true"
  fsType: ext4
---
# Persistent RWX storage. The NFS CSI driver creates one subdirectory per PVC.
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ${NFS_SC}
provisioner: nfs.csi.k8s.io
reclaimPolicy: Retain
volumeBindingMode: Immediate
parameters:
  server: ${NFS_SERVER_NAME}.${NFS_NAMESPACE}.svc.cluster.local
  share: /
  subDir: \${pvc.metadata.namespace}-\${pvc.metadata.name}
  mountPermissions: "0777"
mountOptions:
  - nfsvers=4.1
  - noatime
  - nodiratime
---
# Local non-replicated RWO storage used by Generic Ephemeral Volumes.
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ${LVM_SC}
provisioner: local.csi.openebs.io
allowVolumeExpansion: true
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
parameters:
  storage: lvm
  volgroup: ${LVM_VG}
  fsType: xfs
  scheduler: CapacityWeighted
EOF2

kubectl apply -f ~/project/deploy/defineOpenEBS_StorageClasses.yaml
kubectl get storageclass "${MAYASTOR_SC}" "${NFS_SC}" "${LVM_SC}"
```

`WaitForFirstConsumer` is essential for local scratch storage: Kubernetes must schedule the consumer pod before OpenEBS creates an LVM volume on that node. The 3SSC transformer creates the Generic Ephemeral Volume; `viya-scratch-sc` supplies its local backing volume.

### Create the 3SSC copies

```bash
source "$PMP_HOME/bin/copySC.sh"
cd ~/project/deploy/"${MY_NS}"

copysc "${MAYASTOR_SC}" viya-standard-sc
copysc "${NFS_SC}" viya-shared-sc
copysc "${LVM_SC}" viya-scratch-sc

# Review the generated manifests before applying them.
kubectl apply -f defineSC_viya-standard-sc.yaml
kubectl apply -f defineSC_viya-shared-sc.yaml
kubectl apply -f defineSC_viya-scratch-sc.yaml

kubectl get storageclass \
  "${MAYASTOR_SC}" "${NFS_SC}" "${LVM_SC}" \
  viya-standard-sc viya-shared-sc viya-scratch-sc
```

Expected storage-class mapping:

```log
openebs-lvm         -> local.csi.openebs.io       (local GeV backing)
openebs-mayastor-3  -> io.openebs.csi-mayastor    (replicated RWO)
openebs-nfs         -> nfs.csi.k8s.io             (RWX over the NFS server)
viya-scratch-sc     -> openebs-lvm
viya-shared-sc      -> openebs-nfs
viya-standard-sc    -> openebs-mayastor-3
```

At this point the OpenEBS storage classes required by 3SSC have been defined. Test persistent RWO, shared RWX, and local GeV workloads before continuing with a Viya deployment.