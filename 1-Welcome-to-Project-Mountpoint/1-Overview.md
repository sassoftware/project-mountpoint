# ![pmp icon](/images/pmp-icon-40x40.png) Project Mountpoint Overview

Storage for the SAS Viya platform is a multi-faceted challenge built atop a collection of abstractions, standards, and concepts.

Project Mountpoint provides guidance, tools, and examples to help you configure the SAS Viya platform to best utilize the storage choices at your site.

![Kubernetes storage path](/images/exempt/Project-Mountpoint-timeline.png)

To kick off, the [Three Starter Storage Classes](/3SSC-Three-Starter-Storage-Classes/) (3SSC) can help with the initial configuration and deployment of SAS Viya. Later on in your site's lifecycle, additional improvements suggested by Project Mountpoint can be implemented as well.

## Use PV and GeV instead

We don't need to rely on Kubernetes builtin storage types to provide the storage for the SAS Viya platform.

| Instead of | Use          | Comments            |
| ---------- | ------------ | ------------------- |
| `emptyDir` | **Generic Ephemeral Volume** | EmptyDir is fine for small volumes. But for more flexibility, GeV also offers space that is dynamically provisioned and automatically deletes contents when pod terminates. Works for node-local disk or network storage.
| `hostPath` | **RWO Persistent Volume**        | HostPath is a significant security problem. Instead, we will define persistent storage that can be either dynamically or statically provisioned, leaving behind what's there. Works for node-local disk or network storage.
| `nfs`      | **RWX Persistent Volume**        | NFS is a flexible protocol supported by multiple providers. But we don't need Kubernetes `nfs` volume type to get persistent storage that can be either dynamically or statically provisioned, leaving behind what's there. Use NFS CSI Driver or other network storage technology.

To modify the Viya podTemplates that refer to the legacy storage types, we just need to define some kustomize `patchTransformers` to make the change. Done properly, **this can provide a *portable* file that works for any site, using any cloud provider, with any storage provisioners**.

For a drop-in, no-edit approach to make this happen for your deployment of SAS Viya, refer to the [Three Starter Storage Classes](/3SSC-Three-Starter-Storage-Classes/) for more information.

## Persistent Volume Lifecyle

The lifecyle of persistent volumes provides us with an abstraction model.

When it comes to configuring the SAS Viya platform software, we have the ability to change the podTemplate and the PVC references.

The site itself is responsible for infrastructure. That includes the storage class definitions as well as the choice of storage providers and associated CSI drivers.

![Kubernetes storage path](/images/k8s-storage-path.png)

> This happens for each persistent volume (and GeV, too) in your environment. Does not include emptyDir, hostPath, or other volume types.

Project Mountpoint uses 3SSC to take the approach that the **Storage Class** is the key. That is, it's the interface between SAS Viya's storage configuration and what the infrastructure provides as storage.

## The 3SSC Approach

To get to a place where we can use the same process to configure storage for the SAS Viya platform that works from site to site, regardless of infrastructure provider or specific storage provisioners, we can standardize to implement a consistent approach.

1.  The site IT team is responsible for infrastructure

    The site selects the infrastructure provider (on-prem or cloud) and will also select the storage providers to employ (along with necessary CSI drivers). Of course, this should be informed by SAS Viya's system requirements to include:

    - Persistent RWO storage
    - Persistent RWX storage
    - Ephemeral local disk (ideally)

    > There could be additional storage classes with additional attributes implemented, if needed.

1.  Perform the prerequisites to ensure readiness for Project Mountpoint.

1.  Project Mountpoint configuration tools:

    - **Three Starter Storage Classes**: drop-in, no-edit configuration for SAS Viya to use three appropriate storage classes for dynamically-provisioned volumes.

    - **Additional Examples**: there are many use-cases that Viya might need to support for your site. Project Mountpoint will continue to add guidance for these as it grows.

1.  Create *copies* of the original storage classes to match the names/attributes of the selected Project Mountpoint storage pattern (or your own).

1. Now, with Viya configuration of storage in place and with the matching storage classes defined in Kubernetes, then the SAS Viya platform can be installed (using `kustomize build` and `kubectl apply`).

1. Project Mountpoint also provides validation exercises to help ensure the desired storage is fully implemented.

## Four-step cycle

There are four main areas to work on.

![Viya configuration Storage Cycle](/images/exempt/StorageCycle.gif)

### 1. Viya's requirements

We need to provide correct storage for the various Viya components, captured in kustomization.yaml.

-   RWO consumers
    -   Consul, postgres, redis, opensearch, rabbitmq

-   RWX consumers
    -   various miscellany service components
    -   HA CAS: CAS_CONTROLLER_TEMP
    -   SPRE Batch: SASWORK

-   Local disk consumers
    -   CAS: CAS_DISK_CACHE
    -   SPRE: SASWORK, ECE Cache

Investigate the storage technology offered at your site for these storage types.

### 2. IAC contributes storage

The IAC project can help to provide storage.

#### > RWX storage

For viya4-iac-AWS, select one RWX storage provider:

-   EC2 instance runs as NFS Server<br />`storage_type=standard`

-   Amazon EFS resources<br />`storage_type=ha` with `storage_type_backend=efs`

-   Amazon FSx for Netapp ONTAP resources<br />`storage_type=ha` with `storage_type_backend=ontap`

You can deploy additional RWX storage manually, as needed.

> Note: the other cloud-specific IAC projects target those cloud provider's storage offerings. It's helpful to include real-world storage references (like FSx) to explain these concepts, but that doesn't mean that 3SSC is *limited* to only those offerings.

#### > Local disk storage

The IAC project can request and label/taint instance types that include local NVMe SSD drives.

Snippet from the terraform variables file:

```terraform
compute = {
    "vm_type"      = "r6idn.4xlarge"  # includes local NVMe
    "cpu_type"     = "AL2023_x86_64_STANDARD"
    "os_disk_type" = "gp3"
    "os_disk_size" = 200
    "os_disk_iops" = 0
    "min_nodes"    = 1
    "max_nodes"    = 5
    "node_taints"  = ["workload.sas.com/class=compute:NoSchedule"]
    "node_labels"  = {
    "workload.sas.com/class"        = "compute"
    "launcher.sas.com/prepullImage" = "sas-programming-environment"
    "attr.sas.com/local-nvme"       = "true"
    }
    "custom_data" = ""
    "metadata_http_endpoint"               = "enabled"
    "metadata_http_tokens"                 = "required"
    "metadata_http_put_response_hop_limit" = 1
},
```

Specifically note:

-   `vm_type`: specifies an instance type that includes local disk, `r6idn.4xlarge` (or as appropriate for your cloud provider and site)
  
-   `node_labels`: identifies "`workload.sas.com/class=compute`" for the kind of work - and - "`attr.sas.com/local-nvme=true`" as an arbitrary label we can use to target daemonsets to these instances.

The "cas" node pool with label "`workload.sas.com/class=cas`" is also a candidate for local disk.

#### > RWO storage

For AWS, Amazon EBS storage is already "ready-to-use" without explicit provisioning of infrastructure. Other cloud providers have their variations with similar offerings.

### 3. CSI Drivers and Storage classes

Kubernetes needs help to work with physical storage providers. CSI Drivers are the modern approach. They act as plugins to Kubernetes so it can use external storage.

Storage classes are logical resources for dynamic provisioning of storage. A storage class identifies which CSI Driver to use.

#### > RWX storage class

Refer to your IAC selection for RWX storage to identify which CSI driver is desired, then:

Install:

-   NFS CSI Driver
-   Amazon EFS CSI Driver
-   NetApp Trident CSI Driver
-   Or appropriate CSI Driver(s) for shared storage as supported by your cloud provider and site

Some CSI Driver installers might automatically create a storage class for you. If not, then create your own.

> Note: If you elect to do so, the viya4-deployment project can automatically install ***one*** CSI driver for RWX storage based on your IAC selection and define a storage class simply named "`sas`" to use it. 

#### > RWO storage class

An RWO storage class typically relies on block storage in cloud environments.

Install:

-   Amazon EBS CSI Driver

    Amazon EBS offers different kinds of block storage, notably gp3, and io2. Create the storage class definition(s) to access the desired kind of block storage.

-   Or appropriate CSI Driver(s) for block storage as supported by your cloud provider and site.

#### > Local disk storage class

Local disk is fast and relatively inexpensive as used for CAS_DISK_CACHE and SASWORK.

1.  Format and mount

    Locally-attached NVMe SSD drives are not formatted or mounted to the instance by default. That's up to you. One approach we demonstrate is to create a daemonSet (targeting the "`attr.sas.com/local-nvme=true`" label) that will format and mount the physical volume(s). Your site might choose a different approach.

1.  Select a local disk CSI Driver

    There are many to choose from. Recommend a *dynamic* provisioner like Rancher's Local Path Storage, OpenEBS, Portworx, LVM Storage Operator, Azure Container Storage, etc.

1.  Create your a storage class to use that local disk.

    Bonus: installing Rancher's Local Path also creates a storage class named `local-path`. Other CSI create theirs as well.

### 4. Configure Viya's use of storage

The 3SSC provides you with a no-edit, drop-in YAML file that defines patchTransformers which will modify Viya's services to use dynamically-provisioned operational storage with a pre-determined set of storage class names.

Then your site just needs to set up the desired, appropriate storage and define storage classes with names that align with the 3SSC. The recommendation is to create storage classes with generic (or default) names. Your site IT team validates that the storage is working as expected.

When ready, then simply "copy" the desired storage classes and give those copies names that match 3SSC:

- `viya-standard-sc` <<< from `gp3` or `io2`

- `viya-shared-sc` <<< from `nfs`, `efs`, or `ontap`

- `viya-scratch-sc` <<< from `local-path` (or other local disk CSI) ideally, else use performant block storage like `gp3` or `io2`

> These examples refer to Amazon and third-party storage offerings, but the concept applies regardless of your site's actual infrastructure provider.

## Make it your own

Beginning with the Three Starter Storage Classes (one each for RWO, RWX, and local storage), this project shows how to approach storage configuration for SAS Viya.

The intent is for the process to be extensible to suit the needs of any site. So, with a solid understanding of the approach, the examples shown should illustrate the technique for you to make modifications that your site might require.

In other words, Project Mountpoint does *not* provide the *only* storage patterns for SAS Viya. Instead, those patterns are meant as *guides* for you to refine as needed.

## Next

Now that you know how it works, let's try out 3SSC for your SAS Viya platform deployment. Start with the [Prerequisites](/1-Welcome-to-Project-Mountpoint/2-Prerequisites.md) to get going.
