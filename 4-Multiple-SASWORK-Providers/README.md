# ![pmp icon](/images/pmp-icon-40x40.png) Configure SAS Viya platform to use multiple storage providers for SASWORK

SASWORK is a critical I/O resource to configure properly. For side-by-side testing of different storage technologies to determine the best fit, we can configure the SAS Viya platform to utilize multiple storage providers for SASWORK.

There are multiple abstraction layers that create a chain in this effort:

![PMP Multiwork Relationships](/images/pmp-multiwork-relationships.png)

> {{ User Choice - SAS Batch/Compute/Connect Context — SAS Launcher Context — Pod Template — Volume Type/Storage Class - Storage Provider }}

Note that this is not meant to replace I/O throughput testing directly at the infrastructure layer. That's an important step to validate on its own before the SAS Viya platform is deployed. However, the testing here - which illustrates [focused use of SASWORK](/bin/test-saswork-io.sas) - is helpful to understand just how much the SPRE can be constrained in its data I/O operations by storage architecture.

## Caveats

**Pod templates**

This process relies on making copies of pod templates. We choose to do that with the Kubernetes resources that already exist. We *could* elect to copy the original `sas-bases` resources and modify them to achieve the same end instead.

The thing is, both approaches exist in a gray area for SAS support of cadence updates. The `sas-bases` resources are *not* "overlays" or "examples". So, a later software update could redefine the pod templates in meaningful ways.

To help make that clear, we copy the pod templates after they exist in Kubernetes. After updating Viya with a newer cadence release, then it should be required to recreate the new pod templates again to be safe. The context definitions should be safe for Viya updates, but they could be recreated, too, if needed.

**Examples shown**

Some results shown here as examples make occasional reference to Amazon Web Services infrastructure. However, all steps shown rely on generalized `kubectl` and `sas-viya` CLI commands, so they will work in any cloud provider or on-prem environment.

## Prerequisites

A few things are required before beginning this effort:

-   SAS Viya platform is deployed and operational
-   The kubectl CLI specifies the Kubernetes cluster with sufficient permissions
-   The sas-viya CLI is installed with all plugins and user authenticated
- Env var `$PMP_HOME` is set to the cloned location of Project Mountpoint files

Also:

-   If it's desired to test different kinds of local disk (or really, any difference in the instances themselves), then additional steps to configure host types in SAS Workload Orchestrator will be necessary.

Note for the examples shown:

-   Project Mountpoint Three Starter Storage Classes are implemented
    - SPRE pods are configured to use GeV specifying `viya-scratch-sc` for SASWORK
-   To use this at your own site, adjust as needed for your own storage configuration.

## SAS Viya provides initial resources

First of all, let's get a list of the relevant pod templates that Viya gives us to start with:

```sh
# Simple command
#kubectl get podtemplates -n $MY_NS | grep sas-programming

# Fancy command to show only the pod templates and info we want
kubectl get podtemplates -n $MY_NS -o json | jq -r '.items[] | select(.template.spec.containers[].name == "sas-programming-environment") | [.metadata.name, (.template.spec.containers[].name), (.template.metadata.labels | to_entries | map("\(.key):\(.value)") | join(","))] | @tsv' | column -t -s $'\t' -N "NAME,CONTAINERS,POD_LABELS"
```

Returning 4 Viya pod templates:

```log
NAME                             CONTAINERS                   POD_LABELS
sas-batch-pod-template           sas-programming-environment  launcher.sas.com/job-type:sas-batch-job,sas.com/deployment:sas-viya
sas-compute-job-config           sas-programming-environment  launcher.sas.com/job-type:compute-server,sas.com/deployment:sas-viya
sas-connect-pod-template         sas-programming-environment  launcher.sas.com/job-type:sas-connect-server,sas.com/deployment:sas-viya
sas-launcher-job-config          sas-programming-environment  launcher.sas.com/job-type:sas-launcher-job,sas.com/deployment:sas-viya
```

> For this exercise (and in general), ignore the `sas-launcher-job-config` podTemplate.

And those are referenced by the primary SPRE contexts:

| SPRE B/C/C Context Name                  | Type       | Pod Template Name
| ---------------------------------------- | ---------- | ------------- 
| **default**                              | Batch      | `sas-batch-pod-template`
| **SAS Studio Compute context**           | Compute    | `sas-compute-job-config`
| **SAS/CONNECT service launcher context** | Connect    | `sas-connect-pod-template`

> Note this is not a comprehensive list of SPRE contexts - but should be sufficient for SASWORK testing and to provide an example to follow for other situations.

These are the building blocks from which we will create additional configuration resources.

## The plan

In this scenario, Project Mountpoint was already implented to provide scratch space for SASWORK with the 3SSC:

-  `viya-scratch-sc` - used by GeV to dynamically provision space on local disk

In addition to that, let's also implement two more alternative storage providers for SASWORK:

-   `emptyDir` - back to Viya's out-of-the-box default to use OS root volume
-   `viya-shared-sc` - RWX storage

    > The goal is comparative performance testing - not production use. For example, we will keep ephemeral volumes for SASWORK. If a site really wants to employ RWX storage for SASWORK to support Checkpoint-Restart functionality, then a static Persistent Volume (not dynamic GeV) is required.

Each alternative storage provider we want must be reflected in new pod template definitions:

| New PT Name | Service | Volume Type | Backend |
|-----------------------|---------|-------------|---------|
| `pmp-batch-saswork-emptydir-pt` | Batch | emptyDir | emptyDir: OS root vol |
| `pmp-batch-saswork-rwx-pt` | Batch | RWX | GeV: viya-shared-sc |
| `pmp-compute-saswork-emptydir-pt` | Compute | emptyDir | emptyDir: OS root vol |
| `pmp-compute-saswork-rwx-pt` | Compute | RWX | GeV: viya-shared-sc |
| `pmp-connect-saswork-emptydir-pt` | Connect | emptyDir | emptyDir: OS root vol |
| `pmp-connect-saswork-rwx-pt` | Connect | RWX | GeV: viya-shared-sc |

Each new pod template must be called from a new SAS Launcher Context:

| New LC Name | Description | References Pod Template |
|-------------|-------------|------------------------|
| `pmp-batch-saswork-emptydir-lc` | PMP Batch launcher context using emptyDir for SASWORK | pmp-batch-saswork-emptydir-pt |
| `pmp-batch-saswork-rwx-lc` | PMP Batch launcher context using RWX storage for SASWORK | pmp-batch-saswork-rwx-pt |
| `pmp-compute-saswork-emptydir-lc` | PMP Studio launcher context using emptyDir for SASWORK | pmp-compute-saswork-emptydir-pt |
| `pmp-compute-saswork-rwx-lc` | PMP Studio launcher context using RWX storage for SASWORK | pmp-compute-saswork-rwx-pt |
| `pmp-connect-saswork-emptydir-lc` | PMP CONNECT launcher context using emptyDir for SASWORK | pmp-connect-saswork-emptydir-pt |
| `pmp-connect-saswork-rwx-lc` | PMP CONNECT launcher context using RWX storage for SASWORK | pmp-connect-saswork-rwx-pt |

And each new Launcher Context must be called from a new SAS Batch/Compute/Connect Context (as appropriate):

| New B/C/C Name | Description | References Launcher Context |
|----------------|-------------|-----------------------------|
| `pmp-batch-saswork-emptydir-bc` | PMP Batch context using emptyDir for SASWORK | pmp-batch-saswork-emptydir-lc |
| `pmp-batch-saswork-rwx-bc` | PMP Batch context using RWX storage for SASWORK | pmp-batch-saswork-rwx-lc |
| `pmp-compute-saswork-emptydir-cc` | PMP Studio compute context using emptyDir for SASWORK | pmp-compute-saswork-emptydir-lc |
| `pmp-compute-saswork-rwx-cc` | PMP Studio compute context using RWX storage for SASWORK | pmp-compute-saswork-rwx-lc |
| `pmp-connect-saswork-emptydir-cc` | PMP connect context using emptyDir for SASWORK | pmp-connect-saswork-emptydir-lc |
| `pmp-connect-saswork-rwx-cc` | PMP connect context using RWX storage for SASWORK | pmp-connect-saswork-rwx-lc |
> Note that we must manually create new Connect Contexts using EVM (not with the sas-viya CLI).

After creating these 18 resources, then SAS Viya is able to present the end-user with the Batch/Compute/Connect Context names for selection when starting their next SAS job.

## Get the sas-viya CLI

We need the sas-viya CLI to perform the configurations shown here. [Perform these instructions](/9-Appendix/Viya/install-sas-viya-cli.md) before continuing.

## Let's do it

It's tedious to step through the creation of all those resources. So we've created an automated script to do the job: `multi-saswork-tool.sh`.

Referring to the diagram above, it will create copies of the specified B/C/C Context, associated Launcher Context, and associated Pod Template to specify the volume type or storage class name (or PVC name) you indicate. This saves you a lot of manual effort and tracking of esoteric resources.

1.  Show the help text:

    ```text
    $ bash $PMP_HOME/bin/multi-saswork-tool.sh

    Usage: ./multi-saswork-tool.sh ROOTNAME STORAGE CONTEXT-TYPE CONTEXT-NAME
      ROOTNAME: Base name for new resources
      STORAGE: 'emptyDir', 'sc:storage-class-name', or 'pvc:pvc-name'
      CONTEXT-TYPE: 'compute', 'batch', 'connect', or 'launcher'
      CONTEXT-NAME: Name of existing context to clone from
    ```

1.  Create a new Compute Context to configure SASWORK to use emptyDir

    ```sh
    # Create a new Compute Context (and dependencies) to use emptydir
    bash $PMP_HOME/bin/multi-saswork-tool.sh pmp-compute-saswork-emptydir emptyDir compute "SAS Studio compute context"
    ```

    With results like:

    ```log
    ==========================================
    ✓ Successfully created new SASWORK configuration
    Pod Template: pmp-compute-saswork-emptydir-pt
    Launcher Context: pmp-compute-saswork-emptydir-lc
    Compute Context: pmp-compute-saswork-emptydir-cc
    ==========================================
    ```

1.  If that looks good, then repeat for Batch.

    ```sh
    # Create a new Batch Context (and dependencies) to use emptydir
    $PMP_HOME/bin/multi-saswork-tool.sh pmp-batch-saswork-emptydir emptyDir batch "default"
    ```

1.  And again for Connect, but this one works differently.

    ```sh
    # Create a new Connect Context (and dependencies) to use emptydir
    $PMP_HOME/bin/multi-saswork-tool.sh pmp-connect-saswork-emptydir emptyDir connect "SAS/CONNECT service launcher context"
    ```

    After the success message indicates the new pod template and new launcher context have been created, then you will be given additional instructions. You must perform these *manually* in the SAS Environment Manager UI to create the actual Connect Context. There's no plugin for the sas-viya CLI to do this.

1. Now that you've got the hang of it, let's also create resources to use RWX shared storage for SASWORK as well. All together now:

    ```sh
    # Create a new Compute Context (and dependencies) to use RWX shared storage
    $PMP_HOME/bin/multi-saswork-tool.sh pmp-compute-saswork-rwx sc:viya-shared-sc compute "SAS Studio compute context"

    # Create a new Batch Context (and dependencies) to use RWX shared storage
    $PMP_HOME/bin/multi-saswork-tool.sh pmp-batch-saswork-rwx sc:viya-shared-sc batch "default"

    # Create a new Connect Context (and dependencies) to use RWX shared storage
    $PMP_HOME/bin/multi-saswork-tool.sh pmp-connect-saswork-rwx sc:viya-shared-sc connect "SAS/CONNECT service launcher context"
    ```

## Try it out

All we've done so far is define some optional resources in Kubernetes and SAS Viya. To actually use them, SAS jobs must specify the appropriate B/C/C context name for the desired service and SASWORK storage type.

Project Mountpoint provides a sample SAS program to test SASWORK I/O: [test-saswork-io.sas](/bin/test-saswork-io.sas):

- Very simple SAS program
- Generates 1M rows of random data (=1 GB file size) in a SASWORK table
- Sorts the data multiple times

To run your own test interactively, logon to SAS Studio, **select the desired Compute Context**, and submit some SASWORK-heavy test code and compare times. Copy-and-paste the example program code we provide - or use your own - and look at the SAS log.

Or, to run your test in batch, use the sas-viya CLI to submit some SASWORK-heavy test code **to the different Batch Contexts** and compare times from the log results. Here's how:

1.  Submit the I/O test as a batch job

    ```sh
    # Submit the SAS program to run in Batch Context pmp-batch-saswork-rwx-bc
    # (specifies the RWX storage class "viya-shared-sc" backed by NFS or similar)
    sas-viya batch jobs submit-pgm --context pmp-batch-saswork-rwx-bc --pgm $PMP_HOME/bin/test-saswork-io.sas --wait

    # repeat for "`default`" and for "`pmp-batch-saswork-emptydir-bc`" Batch Contexts.
    ```

    The sas-viya CLI provides status:

    ```log
    >>> The file set "JOB_20260210_203913_063_1" was created.
    >>>   Uploading "test-saswork-io.sas".
    >>> The job was submitted. ID: "a503dd5d-4729-4be6-9c9d-78933dea5951"  Workload Orchestrator job ID: "28"
    >>> Waiting for the job to complete...
    >>> Job started.
    <<< Job ended.
    ```

1.  Get the results of the batch program

    ```sh
    # Fetch the results of that job
    sas-viya batch jobs get-results --job-id a503dd5d-4729-4be6-9c9d-78933dea5951 --results-dir /tmp/batch-results
    ```

    The sas-viya CLI provides status:

    ```log
    {
        "items": [
            {
                "createdBy": "sasadm",
                "endedTimeStamp": "2026-02-10T20:40:00Z",
                "id": "a503dd5d-4729-4be6-9c9d-78933dea5951",
                "name": "test-saswork-io",
                "returnCode": 0,
                "startedTimeStamp": "2026-02-10T20:39:13Z",
                "state": "completed",
                "submittedTimeStamp": "2026-02-10T20:39:13Z",
                "workloadJobId": "28"
            }
        ]
    }
    <<<   Downloading the files in the file set to the following path: "/tmp/batch-results/JOB_20260210_203913_063_1".
    <<<   Downloading "test-saswork-io.log".
    <<<   Downloading "test-saswork-io.lst".
    <<<   Downloading "test-saswork-io.sas".
    ```

1.  And then look at the log output

    ```sh
    # view the log content
    less /tmp/batch-results/JOB_20260210_203913_063_1/test-saswork-io.log
    ```

After submitting the programs, then review the "`real time`" for the processing steps across runs using different SPRE contexts (specifying different backend storage for SASWORK) to see the impact of storage technology on SASWORK efficiency. Just looking at the total runtime captured at the very end of the log:

| Local disk (`viya-scratch-sc`) | RWX shared (`viya-shared-sc`) | EmptyDir (in AWS backed by gp3) |
| ------------------------------ | ------------------------------ | -------------- |
| NOTE: The SAS System used:<br />**real time 14.02 seconds**<br />cpu time 11.99 seconds | NOTE: The SAS System used:<br />**real time 32.75 seconds**<br />cpu time 14.74 seconds | NOTE: The SAS System used:<br />**real time 1:36.19**<br />cpu time 12.42 seconds |

> Note that these are the results from ***my*** run in ***my*** env with ***my*** storage choices. You should expect to see substantially different results if your tests make alternative choices.

## Bonus round

We used emptyDir volume above for testing of block storage. However, you might prefer to use the "`viya-standard-sc`" storage class for that instead. Create more resources to address this storage provider:

```sh
# Create a new Compute Context (and dependencies) to use persistent block storage
$PMP_HOME/bin/multi-saswork-tool.sh pmp-compute-saswork-block sc:viya-standard-sc compute "SAS Studio compute context"

# Create a new Batch Context (and dependencies) to use persistent block storage
$PMP_HOME/bin/multi-saswork-tool.sh pmp-batch-saswork-block sc:viya-standard-sc batch "default"

# Create a new Connect Context (and dependencies) to use persistent block storage
$PMP_HOME/bin/multi-saswork-tool.sh pmp-connect-saswork-block sc:viya-standard-sc connect "SAS/CONNECT service launcher context"
```

And test as shown above.
