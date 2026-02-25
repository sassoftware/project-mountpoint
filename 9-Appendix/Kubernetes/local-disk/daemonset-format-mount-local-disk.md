# Format and Mount Local Disk on Instance

Cloud providers offer some instance types that include local disk. That's useful for SASWORK and CAS_DISK_CACHE because it's fast, low latency, and can be treated ephemerally.

This example shows how to setup a DaemonSet that will run on instances with local disk. If it finds a local disk, it will format it xfs and then mount it.

The DaemonSet below is configured to only run on nodes with label `attr.sas.com/local-nvme="true"`. You can specify a different label if you prefer.

## Label nodes that have local disk we can use

The viya4-iac projects can be configured to include the `attr.sas.com/local-nvme="true"` label along with others used by Viya.

```terraform
compute = {
    "vm_type"   = "r6idn.4xlarge"           # includes local NVMe
    "cpu_type"  = "AL2023_x86_64_STANDARD"
    "min_nodes" = 1
    "max_nodes" = 5
    "node_labels" = {
    "workload.sas.com/class"  = "compute"
    "attr.sas.com/local-nvme" = "true"      # our custom label
    }
```

If needed you can also label nodes individually:

```bash
# Label the node 
kubectl label node {{ NODE NAME }} attr.sas.com/local-nvme="true"
```

## Create daemonSet to format and mount local NVMe drives

For the "CAS" and "Compute" node pool definitions, we may specify instance types that include local NVMe disk. Recommend to give them special labels like `attr.sas.com/local-nvme=true` to be used in the `nodeSelector:` directives below.

This spec will target those nodes with a daemonSet that will run commands directly on the host operating system to find, format, and mount the local disk as `/viya-scratch`.

```bash
# Generate DaemonSet YAML for mounting local NVMe SSD
cat << 'EOF' > ./nvme-mounter-daemonset.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: nvme-mounter
  namespace: kube-system
  labels:
    app: nvme-mounter
spec:
  selector:
    matchLabels:
      app: nvme-mounter
  template:
    metadata:
      labels:
        app: nvme-mounter
    spec:
      nodeSelector:
        attr.sas.com/local-nvme: "true"
      hostPID: true
      hostNetwork: true
      tolerations:
      - operator: Exists
      containers:
      - name: nvme-mounter
        image: alpine:3.18
        securityContext:
          privileged: true
        command: ["/bin/sh"]
        args:
        - -c
        - |
          set -euo pipefail

          # Use host tools via nsenter
          NSENTER="nsenter -t 1 -m -u -n -p --"

          DEVICE="/dev/nvme1n1"
          MOUNT_POINT="/viya-scratch"
          LABEL="VIYA_SCRATCH"

          echo "Starting NVMe setup for SAS Viya ephemeral storage..."

          if [ -b "${DEVICE}" ]; then
              echo "Found NVMe device: ${DEVICE}"

              # Skip partitioning - format the entire device directly
              echo "Checking if device is already formatted..."
              if ! $NSENTER blkid "${DEVICE}" | grep -q xfs; then
                  echo "Formatting entire device with XFS: ${DEVICE}"
                  $NSENTER mkfs.xfs -f -L "${LABEL}" "${DEVICE}"
              else
                  echo "Device ${DEVICE} already formatted with XFS"
              fi

              # Create mount point if it doesn't exist (via host root mount)
              if [ ! -d "/host${MOUNT_POINT}" ]; then
                  echo "Creating mount point: ${MOUNT_POINT}"
                  mkdir -p "/host${MOUNT_POINT}"
              fi

              # Get UUID of the device using host blkid
              UUID=$($NSENTER blkid -s UUID -o value "${DEVICE}")

              # Check if already mounted using host mountpoint
              if ! $NSENTER mountpoint -q "${MOUNT_POINT}"; then
                  echo "Mounting ${DEVICE} to ${MOUNT_POINT}"
                  $NSENTER mount -t xfs -o discard,noatime "${DEVICE}" "${MOUNT_POINT}"
              else
                  echo "${MOUNT_POINT} already mounted"
              fi

              # Add to fstab if not already present (via host root mount)
              if ! grep -q "${UUID}" /host/etc/fstab; then
                  echo "Adding entry to /etc/fstab"
                  echo "UUID=${UUID} ${MOUNT_POINT} xfs defaults,nofail,discard,noatime 0 2" >> /host/etc/fstab
              else
                  echo "Entry already exists in /etc/fstab"
              fi

              # Set permissions for SAS workloads
              echo "Setting permissions on ${MOUNT_POINT}"
              $NSENTER chmod 1777 "${MOUNT_POINT}"

              echo "NVMe SSD setup completed successfully for SAS Viya"
              echo "Mount point ${MOUNT_POINT} ready for SASWORK and CAS_DISK_CACHE"
              echo "Device: ${DEVICE}, UUID: ${UUID}, Size: $($NSENTER df -h ${MOUNT_POINT} | tail -1)"

              # Keep container running to maintain mount monitoring
              echo "Monitoring mount point..."
              while true; do
                  if ! $NSENTER mountpoint -q "${MOUNT_POINT}"; then
                      echo "ERROR: Mount point ${MOUNT_POINT} no longer mounted!"
                      exit 1
                  fi
                  sleep 30
              done

          else
              echo "NVMe device ${DEVICE} not found"
              exit 1
          fi
        volumeMounts:
        - name: host-root
          mountPath: /host
          mountPropagation: Bidirectional
      volumes:
      - name: host-root
        hostPath:
          path: /
      restartPolicy: Always
EOF

# And apply it
kubectl apply -f ./nvme-mounter-daemonset.yaml
```

And confirm it's running:

```sh
# Get status on the new daemonset
kubectl get daemonsets.apps nvme-mounter
```

```log
NAME           DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR                  AGE
nvme-mounter   5         5         5       5            5           attr.sas.com/local-nvme=true   19s
```

For further confirmation, you can use K9s to find look inside one of the nvme-mounter daemonset instances to get the log showing what it's doing, similar to:

```log
 Starting NVMe setup for SAS Viya ephemeral storage...                                                                              │
│ Found NVMe device: /dev/nvme1n1                                                                                                    │
│ Checking if device is already formatted...                                                                                         │
│ Formatting entire device with XFS: /dev/nvme1n1                                                                                    │
│ meta-data=/dev/nvme1n1           isize=512    agcount=4, agsize=28930664 blks                                                      │
│          =                       sectsz=512   attr=2, projid32bit=1                                                                │
│          =                       crc=1        finobt=1, sparse=1, rmapbt=0                                                         │
│          =                       reflink=1    bigtime=1 inobtcount=1                                                               │
│ data     =                       bsize=4096   blocks=115722656, imaxpct=25                                                         │
│          =                       sunit=0      swidth=0 blks                                                                        │
│ naming   =version 2              bsize=4096   ascii-ci=0, ftype=1                                                                  │
│ log      =internal log           bsize=4096   blocks=56505, version=2                                                              │
│          =                       sectsz=512   sunit=0 blks, lazy-count=1                                                           │
│ realtime =none                   extsz=4096   blocks=0, rtextents=0                                                                │
│ Discarding blocks...Done.                                                                                                          │
│ Creating mount point: /viya-scratch                                                                                                │
│ Mounting /dev/nvme1n1 to /viya-scratch                                                                                             │
│ Adding entry to /etc/fstab                                                                                                         │
│ Setting permissions on /viya-scratch                                                                                               │
│ NVMe SSD setup completed successfully for SAS Viya                                                                                 │
│ Mount point /viya-scratch ready for SASWORK and CAS_DISK_CACHE                                                                     │
│ Device: /dev/nvme1n1, UUID: 803d05e1-a77c-4d4b-bb15-4850cdcf6e66, Size: /dev/nvme1n1    442G  3.2G  439G   1% /viya-scratch        │
│ Monitoring mount point...  
```

> Notes:
>
> Formatting and mounting a disk volume requires privileged container access. The risk is a bad actor escaping the container with root-access to the underlying node. Some sites won't allow pods with this escalated privilege.
>
> Alternative to daemonSet might be to [use cloud_init scripts](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.html) that a cloud provider executes when the instances are created. Same privilege risk - just in another place. And it's less accessible and auditable because it's hard to troubleshoot. Basically a hope-and-pray-it-works-in-the-dark approach.
>
> Point is, there's more than one way to do this. The daemonSet approach here relies on the same kinds of priveleges we already require for other aspects of Viya platform deployment. And, unlike the cloud_init scripts, this approach can be used with minimal change across infrastructure providers.

## Alternatives

> To do: **Use OpenEBS Local PV LVM instead**:
> - format Instance Store with xfs
> - create mount points dynamically
> - manage ephemeral storage with LVM
> - should work across cloud providers

Also, on github.com, Norman Johnson offers a couple of cloud-specific projects intended for use with SAS Viya:

- [AKS Nvme Ssd Provisioner](https://your-git-repo.example.com/nojohn/aks-nvme-ssd-provisioner)
- [Eks Nvme Ssd Provisioner](https://your-git-repo.example.com/nojohn/eks-nvme-ssd-provisioner)


## Takeaway

Using a DaemonSet to format and mount local disk is just one way to do this. Your site might have standardized on a different approach.
