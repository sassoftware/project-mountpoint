# ![pmp icon](/images/pmp-icon-40x40.png) Project Mountpoint Prerequisites

Let's make sure your Kubernetes infrastructure is ready.

We'll mostly approach this from the implementation of [Three Starter Storage Classes](/3SSC-Three-Starter-Storage-Classes/) (3SSC) which is intended for new deployments (or fresh re-deployment) of the SAS Viya platform.

Essentially, we should be at a point between two major milestones: all Kubernetes infrastructure should be deployed and validated - and you're ready to get SAS Viya up and running.

## Kubectl

You should have the `kubectl` CLI installed on your local system configured to use a `kubeconfig` file that provides you with **cluster-admin** privileges.

Try it out:

```bash
# see if kubectl works

kubectl get nodes
```

You should get back a list of Kubernetes nodes.

Now let's see if you actually have cluster-admin privileges:

```bash
# see if we have cluster-admin

kubectl auth can-i '*' '*' --all-namespaces
```

> Checks if I can "`*`" (all verbs) to "`*`" (all resources) in all namespaces.

You should get back "`YES`" if you have cluster-admin privileges. Otherwise, if you get back "`NO`", then you might not be able to complete all steps here needed to configure and deploy SAS Viya.

## Original Storage Classes

You should already have at least three storage classes defined in your Kubernetes cluster:

-   **Persistent RWO storage**: in the cloud, this is usually block storage.

    For example, Amazon EBS CSI Driver supports "`gp3`" and "`io2`" storage classes (and others). Your site might have other storage class(es) for this, especially in a different cloud environment.

-   **Persistent RWX storage**: in the cloud, this is usually shared file storage.

    For example, if the viya4-iac-project is configured to provide "standard" storage, then it sets up a basic, no-frills NFS server machine. You can then install the NFS CSI Driver and define a storage class to use it named "`nfs`".

    Alternatively, Amazon EFS CSI Driver can be used with an "`efs`" storage class.

    Amazon FSx for NetApp ONTAP uses the Trident CSI driver and provides the "`ontap-nas`" storage class.

    Again, adjust as needed for your site's choice here.

-   **Ephemeral Local Disk storage**: this usually requires provisioning an instance type that includes local disk. And further, that local disk must be formatted and mounted.

    For example, the Kubernetes static local provisioner might be referred to by a storage class named "`local-disk`" (or similar).

    If dynamic provisioning is possible (preferred!), then Rancher's Local Path provisioner might use "`local-path`".

    OpenEBS, Portworx or other 3rd-party local disk provisioners could also be employed. Azure Container Storage is an excellent choice, too.

The point is that storage providers will vary from cloud-to-cloud and even site-to-site. For this project, we expect that site IT understands Viya's requirements and usage to set up the appropriate storage classes.

Get a listing of storage classes on hand now:

```bash
# get a list of storage classes

kubectl get sc
```

With results similar to:

```text
NAME            PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION
efs             efs.csi.aws.com         Delete          WaitForFirstConsumer   false  
gp2 (default)   kubernetes.io/aws-ebs   Delete          WaitForFirstConsumer   false               
gp3             ebs.csi.aws.com         Delete          WaitForFirstConsumer   false               
local-path      rancher.io/local-path   Delete          WaitForFirstConsumer   false               
nfs             nfs.csi.k8s.io          Retain          WaitForFirstConsumer   false               
ontap-nas       csi.trident.netapp.io   Delete          WaitForFirstConsumer   true                
```

> Notice in this example, the "`gp2`" storage class is annotated as the "default".
>
> If no storage class is mentioned by a PVC, then Kubernetes will look for a storage class annotated as "`default`" and use that.

## Managing "default" storage class

SAS Viya components should not be left un-configured so that they use a "default" storage class.

**[Optional]:** De-annotate the "default" storage class

> If a site has their own reasons to use a "default" storage class, that's fine. We just don't want SAS to dictate to a site what the "default" storage class should be.

```sh
# remove the "default" storage class annotation
hasDefaultSC=$(kubectl get sc | grep "(default)")

if [[ "$hasDefaultSC" != "" ]]; then

    # found the default storage class
    defaultSC=$(echo $hasDefaultSC | awk -F'(' '{print $1}')

    echo -e "\n--\nFound default storage class \"$defaultSC\" - disabling it..."

    # patch it false
    kubectl patch storageclass $defaultSC -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'

fi
```

> Contrary to logic, Kubernetes allows for *multiple* storage classes to be annotated as "default". So, make sure *all* such annotations have been removed.

## Next

If everything is ready, then move on to [configure SAS Viya](/1-Welcome-to-Project-Mountpoint/3-Configure-SAS-Viya.md) to what it takes to get storage configured as you want it in SAS Viya.
