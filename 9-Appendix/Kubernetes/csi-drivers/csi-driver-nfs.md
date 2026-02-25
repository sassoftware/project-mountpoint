# Install CSI Driver for NFS

This page provides general guidance about installing the Kubernetes NFS CSI Driver to your EKS cluster. It will:

- Install the Kubernetes NFS CSI Driver using provided script
- Configure the NFS CSI Driver to set `fsGroupPolicy`
- Demonstrate how to create a storage class for NFS to match the expected directory path implemented by the IAC project.

## Assumes

These instructions assume:

- the kubectl CLI is installed and user has cluster-admin privileges
- an NFS Server has been provisioned with network visibility to the Viya platform in Kubernetes

The user is expected to have the skillset to modify and debug these steps as needed for their site.

## Steps

1.  Local environment variables

    ```bash
    # Provide info about this site

    ## Project Mountpoint home
    export PMP_HOME=${PMP_HOME:-"$HOME/project/deploy/project-mountpoint"}
    # keeps existing value if PMP_HOME is already defined, else takes new value

    ## My Prefix (useful for naming things in AWS)
    export MY_PREFIX=${MY_PREFIX:-"YOUR_PREFIX_HERE"}
    # keeps existing value if MY_PREFIX is already defined, else takes new value

    ## Get the IP address of the NFS server
    export NFS_IP=`terraform output -state /workspace/${MY_PREFIX}.tfstate -raw rwx_filestore_endpoint`
    # if you didn't use terraform (or IAC), then set this yourself
    ```

1.  Install the Kubernetes NFS CSI Driver

    ```bash
    # Install
    curl -skSL https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/v4.11.0/deploy/install-driver.sh | bash -s v4.11.0 --
    ```

1.  Modify the NFS CSI Driver's `Fs Group Policy` attribute from default "`File`" to "`None`":

    ```bash
    # Prevent CSI Driver from changing file permissions
    kubectl patch csidriver nfs.csi.k8s.io -p '{"spec":{"fsGroupPolicy": "None"}}'

    # Verify
    kubectl describe csidriver nfs.csi.k8s.io
    ```

    > Recursive permission changes for the 80,000 files in the `python-volume` can cause timeouts waiting for SAS Programming Runtime servers to start. So, we disable that as an attribute of the CSI driver.
    >
    > For more information, see: microsoft.com &gt; [How to disable recursive group change (fsGroupPolicy) in Azure File CSI Driver on AKS](https://learn.microsoft.com/en-us/answers/questions/2277901/how-to-disable-recursive-group-change-%28fsgrouppoli)

1.  Define storage class

    ```bash
    mkdir -p ~/project/deploy/
    
    echo -e "\n==> NFS_IP = $NFS_IP"

    #NFS_Path="/export/pvs"     # old provisioner
    NFS_Path="/export"          # csi
    NFS_NS="nfs"

    cat << EOF > ~/project/deploy/defineSC_nfs.yaml
    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
        name: ${NFS_NS}
    provisioner: nfs.csi.k8s.io
    parameters:
        server: ${NFS_IP}
        share: ${NFS_Path}
        subDir: "pvs/\${pvc.metadata.namespace}-\${pvc.metadata.name}"   # creates a unique subdir per PVC (resolved by CSI provisioner)
        mountPermissions: "0777"                 # sets permissions on the mount (resolved by CSI provisioner)
    reclaimPolicy: Retain
    volumeBindingMode: WaitForFirstConsumer
    mountOptions:
    #    - vers=4.1
        - noatime
        - nodiratime
        - 'rsize=262144'
        - 'wsize=262144'
        - nolock         # need to get NFS Server set with lock svc?
    EOF

    # Apply to k8s
    kubectl apply -f ~/project/deploy/defineSC_nfs.yaml

    # Validate
    kubectl describe sc nfs
    ```

    > Note that, unlike the local-path-provisioner, the base directory path is defined here in the storage class. We chose a path and naming convention here that matches with the `viya4-deployment` project's approach when using the legacy nfs-subdir-external-provisioner.

## Status

The `nfs.csi.k8s.io` CSI driver has been installed for NFS-mounted volumes and an example storage class named "`nfs`" defined.
