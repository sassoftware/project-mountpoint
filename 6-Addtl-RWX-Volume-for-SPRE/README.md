# ![pmp icon](/images/pmp-icon-40x40.png) Additional RWX volumes for SPRE

Out of the box, the SPRE pods - that is, SAS Batch, SAS Compute, and SAS Connect servers - only define the minimum storage volumes for initial operations. But it is common to mount additional volumes to those pods so that they can access data they need, such as:

- **Data mart**: A file system where SAS data sets, indexes, catalogs and other file types like CSV, Parquet, DuckDB files, and more can be found, accessed, and updated, if needed.

- **Gridwork**: Gridwork was originally [defined](https://go.documentation.sas.com/api/docsets/gridref/9.4/content/gridref.pdf?locale=en) in SAS 9.4 as a "shared directory that the job uses to store the program, output, and job information". It's not formally defined for [batch submitting jobs](https://documentation.sas.com/?cdcId=pgmsascdc&cdcVersion=default&docsetId=gsub&docsetTarget=p10gm7sg1m9k8dn1lvh0an2cic08.htm) in SAS Viya, but we can use the idea of a shared space where discrete SAS programs can handoff intermediate data sets to each other. This is helpful in a parallel processing in the environment.

- **Database Drivers**: There's no need to install database drivers to every container that needs them in Viya. Instead we can place the drivers we need into one shared volume and mount it as needed.

- **User home directories**: Provide space on a shared volume with subdirectories dedicated for each user's private files.

This exercise will set up datamart and gridwork volumes for the SPRE pods.

## Configure SPRE for more volumes

To create additional volumes for SPRE, we need three things.

### 1. RWX shared storage provider

RWX storage is a Kubernetes term for shared file system. It means that pods running on different hosts of your Kubernetes cluster can access data in the same physical location with read-write access. (Read-only is referred to as ROX).

There are many approaches to provide RWX shared storage. That's up to your site IT team to manage in alignment with SAS Viya's storage requirements.

What must be identified is the Kubernetes access to that storage. Since we're in Project Mountpoint, we will assume the `viya-shared-sc` [storage class](/3SSC-Three-Starter-Storage-Classes/README.md) will be used. Your site could use a different storage class name, or perhaps something more directly and statically defined.

### 2. PVC

&star; Refer to [rwx-volumes-spre-resouces.yaml](/6-Addtl-RWX-Volume-for-SPRE/rwx-volumes-spre-resouces.yaml)

---

Because this storage is for files that exist independent of any pod's lifecycle, then we need it to be persistent. This means defining a Persistent Volume Claim. Our PVC will refer to the `viya-shared-sc` storage class so that it dynamically creates the Persistent Volume in the RWX storage provider.

Once the PV exists, then it can be loaded with files that will remain until they're intentionally deleted.

For this effort, we will create two PVC for different purposes:

-   `name: spre-rwx-datamart-pvc`

    This will be a data mart location so that SPRE servers can access and work with the same analytics data.

-   `name: spre-rwx-gridwork-pvc`

    For SAS programs using MP CONNECT (and/or PROC SCAPROC)

### 3. Pod volume mount

&star; Refer to [rwx-volumes-spre-transformers.yaml](/6-Addtl-RWX-Volume-for-SPRE/rwx-volumes-spre-transformers.yaml)

---

With the PVC available, then we need to define a volume mount so that containers in the pod can access it. For SAS Viya, the volume mounts for the SPRE are defined in the pod templates for SAS Batch, SAS Compute, and SAS Connect servers.

For SAS Viya, we use Kustomize to modify those resources. And so Project Mountpoint therefore provides the necessary Kustomize Patch Transformers to get the job done. 

We provide two patch transformers:

-   `name: add-spre-rwx-pvc-1`: for datamart
-   `name: add-spre-rwx-pvc-2`: for gridwork

Each transformer contains two patches:

1.  Identify the PVC by its name:

    -   `claimName: spre-rwx-datamart-pvc`
    -   `claimName: spre-rwx-gridwork-pvc`

    > *Note this name must match the PVC resources created above.*

1.  Specify where it mounts in the container:

    -   `mountPath: /data/datamart`
    -   `mountPath: /data/gridwork`

    > *Note this path is automatically created inside the targeted containers by Kubernetes.*

## And then use the volumes

The SAS Programming Runtime (SPRE) acceses data through the use of librefs and other files with filerefs. You just need to provide the path.

Example:

```sas
/* Library references */
libname datamart "/data/datamart";

libname gridwork "/data/gridwork";

/* File reference */
filename myinput "/data/datamart/input_file.csv";

/* Import CSV using fileref - save out to gridwork */
proc import datafile="myinput"
            out=gridwork.myoutput 
            dbms=csv 
            replace;
run;
```

It's really that simple. Once the various resources are defined to find each other, then we can use the resulting storage in any SAS program code.
