# ![pmp icon](/images/pmp-icon-40x40.png) Project Mountpoint: Three Starter Storage Classes (3SSC)

This document provides a straightforward, drop-in, no-edit configuration that enables SAS Viya platform operations with three starter storage classes for dynamically-provisioned volumes.

It's easy:

1. Add the `3SSC-transformers.yaml` file to your `$deploy/site-config` to provide Kustomize transformers that configure SAS Viya services to refer to the 3SSC names.

1.  Provision storage that meets Viya's requirements in your infrastructure and define storage classes in Kubernetes with names that match the 3SSC.

1.  Install the SAS Viya platform software as usual.

The steps below explain the process. To see where they're implemented in real world deployments, look to the [Deployment Examples](/3SSC-Three-Starter-Storage-Classes/Deployment-Examples/).

> Note the 3SSC are intended for new deployments of the SAS Viya platform. They should not be implemented for an existing deployment because no guidance is provided here for migrating existing data from old storage to new.
>
> While migration of data from one storage provisioner to another is possible, that's beyond the scope of this section.


## Objective

For this pattern, we want storage classes named for their purpose, similar to:

```log
NAME               PROVISIONER   RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION
viya-scratch-sc    tbd           Delete          WaitForFirstConsumer   false               
viya-shared-sc     tbd           Retain          WaitForFirstConsumer   false               
viya-standard-sc   tbd           Delete          WaitForFirstConsumer   false               
```

Your site's "PROVISIONER" is yet to be determined. Let's look at how we expect Viya to use storage.

We will provide configuration files in `$deploy/site-config` that direct SAS Viya to use **the three starter storage classes**, resulting in:

| Storage Class | Viya purpose   | New mount            | New type     | Original mount | Original type |
| --------------| ------------   | --------------       | ------------ | ---------      | --------      |
| viya-scratch-sc | SASWORK<sup>1</sup><br />*all SPRE servers*        | `/viya`              | GeV on local disk          | `/viya`        | emptyDir      |
| viya-scratch-sc | ECE cache<sup>2</sup><br />*all SPRE servers*      | `/tmp`               | GeV on local disk          | `/tmp`         | emptyDir      |
| viya-scratch-sc | CAS_DISK_CACHE<sup>3</sup> | `/cas/cache-scratch` | GeV on local disk          | `/cas/cache`   | emptyDir      |
| viya-shared-sc  | sas-backup-job | PVC                   | RWX PV           |                 |            |
| viya-shared-sc  | sas-commonfiles| PVC                   | RWX PV           |                 |            |
| viya-shared-sc  | sas-pyconfig   | PVC                   | RWX PV           |                 |            |
| viya-shared-sc  | _addt'l microsvcs_ | PVC               | RWX PV           |                 |            |
| viya-standard-sc | OpenSearch     | PVC                  | RWO PV           |                 |            |
| viya-standard-sc | Crunchy PG     | PVC                  | RWO PV           |                 |            |
| viya-standard-sc | Crunchy PG bkup| PVC                  | RWO PV           |                 |            |
| viya-standard-sc | Consul         | PVC                  | RWO PV           |                 |            |
| viya-standard-sc | Rabbit MQ      | PVC                  | RWO PV           |                 |            |
| viya-standard-sc | Redis          | PVC                  | RWO PV           |                 |            |

> Notes:
>
> Most Viya volumes that are intended for site configuration are set up to use Persistent Volume Claims that reference a storage class.
>
> <sup>1</sup> In the SPRE, the container mount for SASWORK is `/viya` as an emptyDir. Converting that to a Generic Ephemeral Volume with Kustomize requires the use of a strategic merge patch.
>
> <sup>2</sup> In the SPRE, the Enhanced Compute Engine brings CAS in-memory operations to the SAS runtime. The ECE equivalent of the CAS cache mounts at `/tmp` as an emptyDir.
>
> <sup>3</sup> CAS accepts an environment variable to configure the location of CAS_DISK_CACHE. This makes it easy to mount a new volume of the desired type and then update the env var with the new mount point.

## Implementation

Now let's get it done. We will employ an approach that uses some scripting to edit the `kustomization.yaml` to refer to the `3SSC-transformers.yaml` which provides drop-in, no-edit configuration for Viya to employ Three Starter Storage Classes.

### Identify the location of SAS Viya order assets

Identify where the SAS Viya order assets reside on your host system.

This should be the directory path that corresponds to the "`$deploy`" reference in SAS documentation. The children directores should include "`sas-bases`" and "`site-config`".

```bash
# remember where to find the Viya order assets

# update this value for your site
export VIYA_ORDER_HOME="${HOME}/project/deploy/viya"
```

Then validate with a directory listing:

```bash
# What's there?

cd $VIYA_ORDER_HOME

ls -lh
```

With results similar to:

```log
-rw-r--r--. 1 user group    2133 Nov  7 10:35 kustomization.yaml
drwxr-xr-x. 8 user group     140 Nov  7 10:33 sas-bases
-rw-r--r--. 1 user group    4207 Nov  7 10:33 SASViyaV4_9xyzB7_certs.zip
-rw-r--r--. 1 user group   29227 Nov  7 10:33 SASViyaV4_9xyzB7_license.jwt
-rw-r--r--. 1 user group 1132013 Nov  7 10:33 SASViyaV4_9xyzB7_stable_2025.09_20251106.1762462075222_deploymentAssets_1762473402241.tgz
drwxr-xr-x. 2 user group       6 Nov  7 10:33 site-config
```

> The plan is to create files in the `site-config` directory and add references to them in the `kustomization.yaml` file.

### Clone Project Mountpoint

We have some files you'll want to use. We'll place them alongside your order assets, but you can save it elsewhere if preferred.

```bash
# Fetch useful files

cd $VIYA_ORDER_HOME/..   # parent dir of Viya order

# clone the Project Mountpoint git repo
git clone https://github.com/sassoftware/project-mountpoint.git

# Remember where they are
export PMP_HOME="${PWD}/project-mountpoint"

cd $PMP_HOME

# Match PMP to your Viya release
git checkout 2026.01            # or whatever you're at
```

> The `main` branch is always the latest release - but it might not be compatible with older releases.
>
> SAS Viya versioning specifies a cadence (`LTS` or `Stable`) and a release (`YYYY.MM`) - examples `lts-2025.09` and `stable-2026.01`. We try to keep Project Mountpoint examples in sync with SAS Viya per the release number. Be sure to refer to the [Releases page](https://github.com/sassoftware/project-mountpoint/releases) in case of patch updates.

### Configure Viya to use 3SSC

1.  Copy the `3SSC-transformers.yaml` file to your `site-config`

    ```bash
    # Copy the Project Mountpoint pattern files to site-config
    
    # Create a storage config subdir
    mkdir -p ${VIYA_ORDER_HOME}/site-config/storage

    cp -p ${PMP_HOME}/3SSC-Three-Starter-Storage-Classes/3SSC-transformers.yaml  \
              ${VIYA_ORDER_HOME}/site-config/storage
    ```

1.  Update your `kustomization.yaml` file to use the 3SSC file

    You can, of course, manually edit `kustomization.yaml` with the text editor of your choice and insert the reference to the 3SSC configuration to the `transformers:` section.

    Or use this automation:

    > Note that the README [explains](https://support.sas.com/documentation/installcenter/viya/SASViyaReadMe.htm#sas_programming_environment_storage_tasks) to insert new storage config *before* the "required transformers".

    ```bash
    # Use yq to insert new storage configuration to kustomization.yaml
    
    cd ${VIYA_ORDER_HOME}

    # backup to be safe
    cp -p kustomization.yaml "kustomization.yaml.bak-$(date +%y%m%d%H%M)"

    # Find the line with "required/transformers.yaml" 
    index=$(yq eval '.transformers | to_entries | .[] | select(.value == "sas-bases/overlays/required/transformers.yaml") | .key' kustomization.yaml);

    # Insert the reference to 3SSC file 
    yq eval -i ".transformers |= (.[0:${index}] + [\"site-config/storage/3SSC-transformers.yaml\"] + .[${index}:])" kustomization.yaml
    ```

### Configure your site to meet 3SSC definitions

Now we can make the necessary changes to the Kubernetes environment so it can match that goal.

It's pretty simple really. We assume that your site IT team has already defined storage classes to meet the Viya platform requirements. And we expect those storage classes to have their conventional names, like "azurefile-csi", or "gp3", or "standard", or "nfs".

Those storage clas definitions are just plain-text YAML files. There's no specific cost or weight to them.

So, **we will just copy them** to create new storage class names that match those defined by 3SSC that Viya is configured to look for.

### Help to copy your site's original storage classes

Your site provides the original storage classes (whatever they're called). We want to copy them to create duplicates using the "`viya-`" names expected by the storage patterns.

To help aid that task:

```bash
# define the "copysc" function 
source ${PMP_HOME}/bin/copySC.sh
```

> Note the `copysc` function will get the target storage class definition and save it out to a YAML file. It automatically re-names the duplicate storage class to the new name provided, but it leaves the other attributes untouched. **You must modify them as needed.**

#### What you know

Now we assume you know:

- what original storage classes identify the storage providers your site has installed for Viya's use
- the capabilities and attributes of those original storage classes

And Project Mountpoint provides information so you also know:

- the capabilities and attributes the "`viya-`"-named storage classes expect
- how to copy the original storage classes to create those for your select Viya storage pattern

#### Scenario

To drive this last step home, here's detailed example:

-   The site used the **viya4-iac-aws** project to provision a Kubernetes cluster in AWS and configured it to:
    -   stand up a basic NFS server for hosting shared files.
    -   specify instance types with local disk for the "cas" and "compute" node groups.

-   The site IT team has already set up the original storage:
    - **Amazon EBS** provides persistent RWO volumes through the Amazon EBS CSI Driver using original storage class named `gp3`.
    - The **NFS server** provides persistent RWX volumes through the NFS CSI Driver using original storage class named `nfs`.
    - **Local disk** on the "cas" and "compute" instances that's been formatted xfs and mounted. That disk is accessed through the Rancher Local-Path CSI Driver and using original storage class named `local-path`.

-   Looking at the original storage classes at this point:

    ```log
    $ kubectl get sc
    
    NAME             PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE
    gp2              kubernetes.io/aws-ebs   Delete          WaitForFirstConsumer
    gp3              ebs.csi.aws.com         Delete          WaitForFirstConsumer
    local-path       rancher.io/local-path   Delete          WaitForFirstConsumer
    nfs              nfs.csi.k8s.io          Retain          WaitForFirstConsumer
    ```

    > Note that the "`gp2`" storage class is often provided in Amazon EKS. But we will not use it for SAS Viya.

### What you will do

The patchTransformers in the 3SSC site-config file specify three "`viya-`"-named storage classes. With an understanding of the kinds of storage each of those "`viya-`"-named storage classes are intended to use, we must map those the original set of storage classes provided by the site.

For the example so far, here's the mapping we will refer to:

| VIYA SC            | EXPECTS    | MAPS TO ORIGINAL SC | USING BACKEND    |
| ------------------ | ---------  | ----------------    | ---------------- |
| `viya-standard-sc` | RWO block  | `gp3`               | Amazon EBS       |
| `viya-shared-sc`   | RWX files  | `nfs`               | Basic NFS host   |
| `viya-scratch-sc`  | local disk | `local-path`        | Local NVMe SSD   |

**This is an exercise you must do on your own.** To be clear:

- Be familiar with the original storage technology provided by the site. These should have been selected in line with SAS Viya's system requirements in the first place.
- Be familiar with the Project Mountpoint storage pattern. The pattern provides a pre-defined set of patchTransformers that configure "`viya-`"-named storage classes depending on how the specified software components are expected to use storage.
- Be prepared to map out which original storage class capabilities are aligned with the storage pattern's "`viya-`"-named storage classes.

Now, let's try it out...

***Attention: this is just an illustration - your site will be different***

```sh
# EXAMPLE SCENARIO: Create Viya storage classes

cd $VIYA_ORDER_HOME

## Copy the original storage classes
copysc gp3        viya-standard-sc
copysc nfs        viya-shared-sc
copysc local-path viya-scratch-sc
```

Each of those `copysc` commands will output similar to:

```log
---
  Created: defineSC_viya-standard-sc.yaml

To deploy: kubectl apply -f defineSC_viya-standard-sc.yaml
---
```

The "`copysc`" function outputs a YAML file. You're expected to review each YAML file's content and, if needed, edit it to modify the attributes of the "`viya-`"-named storage classes to suit your needs.

When the new storage class definitions are ready, then apply them to Kubernetes:

```sh
## Apply the new storage classes
kubectl apply -f defineSC_viya-standard-sc.yaml
kubectl apply -f defineSC_viya-shared-sc.yaml
kubectl apply -f defineSC_viya-scratch-sc.yaml
```

Confirm with a list of available storage classes now in your cluster:

```sh
## show all storage classes now available
kubectl get sc
```

With results showing your original storage classes plus new ones for 3SSC:

```log
NAME             PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE
gp2              kubernetes.io/aws-ebs   Delete          WaitForFirstConsumer

gp3              ebs.csi.aws.com         Delete          WaitForFirstConsumer
local-path       rancher.io/local-path   Delete          WaitForFirstConsumer
nfs              nfs.csi.k8s.io          Retain          WaitForFirstConsumer

viya-scratch-sc  rancher.io/local-path   Delete          WaitForFirstConsumer
viya-shared-sc   nfs.csi.k8s.io          Retain          WaitForFirstConsumer
viya-standard-sc ebs.csi.aws.com         Delete          WaitForFirstConsumer
```

> Note that the "`gp2`" storage class was not copied. We're not using that type of storage for SAS Viya here.

Of course, your site is likely using a different set of original storage classes. So, **apply as appropriate for your site**.

## Make it your own

We can't describe the details at your site right now. The example above is meant to illustrate how **you can implement the proper approach** for 3SSC at your site with the storage providers you have.

For more low-level details, look at the [Deployment Examples](/3SSC-Three-Starter-Storage-Classes/Deployment-Examples/).

## Next

Ensure that your site's IT team has installed and validated the necessary backend storage provisioners (and/or CSI drivers) in Kubernetes. And that the appropriate storage classes referring to the desired provisioners have been "copied" to create the 3SSC names that Viya is configured to use.

Continue with the usual steps for a SAS Viya deployment. After installation is complete, refer to the [Validation Examples](/3SSC-Three-Starter-Storage-Classes/Validation-Examples/) for guidance to ensure storage for the SAS Viya platform is operating as intended.
