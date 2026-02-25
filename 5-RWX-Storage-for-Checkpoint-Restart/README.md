# ![pmp icon](/images/pmp-icon-40x40.png) RWX Storage for Checkpoint-Restart

The SAS Batch Server can be optionally configured to support Checkpoint-Restart functionality.

- Checkpoint-Restart is a feature enabled when a job is submitted to SAS Batch Server.

- Checkpoints specified in code are saved in SASWORK. This means that we need a *persistent* volume for SASWORK for SAS Batch. That way a **later** SAS Batch Server pod can access the **same** SASWORK volume as a **prior** SAS Batch Server pod.

- And in environments where the SAS Batch Server can run on **multiple** nodes, then that persistent volume must be placed in an RWX storage provider so it can be accessed from any node labeled for "`compute`" workload in the cluster.

- This requires a **static PVC** that references the RWX storage class for shared volumes. The SAS Batch Server's podTemplate will be updated to use that PVC for SASWORK.

## Two ways to do this

Modifying the pod template for the SAS Batch Server can be done either:

1.  [old] **During deployment** (or updates), in `site-config` configuration with a patchTransformer. This sets up all SAS Batch Servers to use the same RWX shared storage volume for all jobs.

    

1.  [preferred] **After deployment** by manually creating a new pod template with associate contexts in SAS Viya's environment. This is preferred to ensure SAS Batch jobs that don't need Checkpoint-Restart can still use the original scratch volume for best performance.

Going with the preferred approach means we're employing a targeted implementation of the [Multiple SASWORK Providers](/4-Multiple-SASWORK-Providers/README.md) concept.

![PMP Multiwork Relationships](/images/pmp-multiwork-relationships.png)

> {{ User Choice - SAS Batch/Compute/Connect Context — SAS Launcher Context — Pod Template — Volume Type/Storage Class - Storage Provider }}

In this case, the "volume type" will be specified as a static PVC for a new SAS Viya batch context configuration.

## Create the static PVC to RWX shared storage

Instead of the generic ephemeral volumes preferred by Project Mountpoint for SASWORK, we need a static persistent volume that will remain in existence after the SAS Batch Server instance has used it.

For most flexibility, we will still use a storage class so that it will be dynamically provisioned on first use. From that point on, it will remain in existence - ahem, *persisting* - until it's explicitly deleted.

1.  Create the static PVC to use RWX shared storage:

    ```sh
    # Where are the order assets?
    export VIYA_NS=${VIYA_NS:-"$MY_NS"}                    # your Viya namespace
    export VIYA_ORDER_HOME=$HOME/project/deploy/$VIYA_NS   # your order assets home
    
    # Define the PVC
    cat << EOF > $VIYA_ORDER_HOME/definePVC-RWX-SASWORK.yaml
    # Shared RWX PVC for SASWORK to enable 
    # checkpoint-restart functionality
    # ===
    # The RWX access mode allows multiple batch 
    # pods running on different nodes to mount 
    # simultaneously
    # ===
    # In kustomization.yaml, this file can be included 
    # as a Resource (not Transformer)
    # ===
    apiVersion: v1
    kind: PersistentVolumeClaim
    metadata:
      name: saswork-rwx-pvc
    spec:
      accessModes:
        - ReadWriteMany
      storageClassName: viya-shared-sc  # Specify your RWX storage class
      resources:
        requests:
          storage: 1Ti  # Adjust size based on your SASWORK requirements
    EOF
    
    # And create it in Kubernetes
    kubectl -n $VIYA_NS apply -f $VIYA_ORDER_HOME/definePVC-RWX-SASWORK.yaml
    ```

    With success:

    ```log
    persistentvolumeclaim/saswork-rwx-pvc created
    ```

    > We can refer to that "`saswork-rwx-pvc`" name in our pod template definitions as the location for SASWORK (`/viya` mount).

1.  And validate:

    ```sh
    # Confirm it is really there
    kubectl describe pvc saswork-rwx-pvc -n $VIYA_NS
    ```

    ```log
    Name:          saswork-rwx-pvc
    Namespace:     viya
    StorageClass:  viya-shared-sc
    Status:        Pending
    Volume:        
    Labels:        <none>
    Annotations:   <none>
    Finalizers:    [kubernetes.io/pvc-protection]
    Capacity:      
    Access Modes:  
    VolumeMode:    Filesystem
    Used By:       <none>
    Events:
      Type    Reason                Age               From                         Message
      ----    ------                ----              ----                         -------
      Normal  WaitForFirstConsumer  2s (x5 over 48s)  persistentvolume-controller  waiting for first consumer to be created before binding
    ```

    > Note that nothing has tried to actually use this PVC yet, so it's following the `WaitForFirstConsumer` directive before creating the physical volume.

## Get the sas-viya CLI

We need the sas-viya CLI to perform the configurations shown here. [Perform these instructions](/9-Appendix/Viya/install-sas-viya-cli.md) before continuing.

## Create the resources for SAS Batch Server to use the SASWORK PVC

We explore configuring SAS Viya to choose from different SASWORK providers in [Mutiple SASWORK Providers](/4-Multiple-SASWORK-Providers/). Here, we just leverage what we learned.

1.  Create the Kubernetes pod template and Viya contexts 

    ```sh
    # Create a new Batch Context (and dependencies) to use RWX shared storage PVC
    bash $PMP_HOME/bin/multi-saswork-tool.sh pmp-batch-saswork-pvc pvc:saswork-rwx-pvc batch "default"
    ```

    With success showing:

    ```log
    ==========================================
    ✓ Successfully created new SASWORK configuration
    Pod Template: pmp-batch-saswork-pvc-pt
    Launcher Context: pmp-batch-saswork-pvc-lc
    Batch Context: pmp-batch-saswork-pvc-bc
    ==========================================
    ```

1.  Validate

    ```sh
    # Get the new batch context info
    sas-viya batch contexts list --name "pmp-batch-saswork-pvc-bc"
    ```

    With results like:

    ```json
    {
        "items": [
            {
                "description": "Batch context for pmp-batch-saswork-pvc (saswork-rwx-pvc)",
                "id": "7a3e42b9-3b5d-4d59-8753-f5ed9c72df5a",
                "isMultiServer": false,
                "launcherContextId": "042f6301-b010-4fbd-99b4-c402829b869e",
                "name": "pmp-batch-saswork-pvc-bc"
            }
        ]
    }
    ```

## Try it out

We now have a new SAS Batch Server context called "`pmp-batch-saswork-pvc-bc`". The name is a bit of a mouthful, but at least it says what it is:

- `bc`: Batch Context
- `pvc`: Persistent Volume Claim (not a GeV like other SASWORK in 3SSC)
- `saswork`: SASWORK is the primary functional element addressed
- `batch`: for SAS Batch Server
- `pmp`: as directed by Project Mountpoint :)

You can name the SAS Batch Server context anything you want, of course.

Refer to the [Validation Examples](/5-RWX-Storage-for-Checkpoint-Restart/Validation-Examples/) for instructions to confirm that Checkpoint-Restart functionality is operating as intended.

## Next

By choosing to provide a persistent volume for SASWORK, then ongoing support and maintenance of that volume is necessary.

SASWORK is scratch space. And the SAS runtime will automatically empty the contents of its own SASWORK space when the job completes normally. However, if the SAS job is terminated unexpectedly, then the SAS process won't get a chance to do that, which orphans any files left in SASWORK.

If the SASWORK volume fills up (either from overuse or from orphaned files), then the SAS runtime will fail to execute. It requires sufficient space in SASWORK.

The easiest thing to do then is to delete that `saswork-rwx-pvc` PVC which will also delete the associated PV it created. Then re-create the PVC anew with the same name. It takes only seconds - not requiring a system outage, however user activity should be paused.

Note, that if the PVC/storage class specify `reclaimPolicy=retain`, then the physical volume in the RWX shared storage will continue to exist after the PVC (and PV) are deleted from Kubernetes. Since SASWORK is ultimately ephemeral in nature, better to ensure `reclaimPolicy=delete` to prevent that.
