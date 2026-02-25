# Validate SASWORK on RWO volumes

Generally speaking, we can validate the storage that Viya is using by referring to the PVC and storage classes.

But for SASWORK and CAS_DISK_CACHE, it can be good to take extra steps to show that the storage is being utilized as designed.

In this exercise, we demonstrate two different viewpoints from which to confirm the physical storage behind SASWORK.

The SAS runtime has an equivalent to CAS_DISK_CACHE. So we also demonstrate validation of the ECE Cache as well that accommodate its operation.

## RWO SASWORK files for SAS Compute Server

Let's check on the configuration for SASWORK storage for `sas-compute-server` pods.

> This exercise only works when the Rancher `local-path` provisioner CSI Driver is employed by the storage class for the SAS Compute Server's `viya` volume.

### > From SAS Compute Server

Check where SAS reports its SASWORK library to be.

In SAS Studio, submit the following program:

```sas
* Copy a table into SASWORK;
data work.BASEBALL;
  set sashelp.BASEBALL;
run;

* Get the physical path for the SASWORK libref;
%let workpath = %sysfunc(pathname(work));

* Print the path to the SAS log;
%put The physical path of the SASWORK library is: &workpath;
```

In the log output, you should see:

```log
The physical path of the SASWORK library is: 
/opt/sas/viya/config/var/tmp/compsrv/default/c2e1f389-bd5f-4b6f-becc-c8db6e4564bf/SAS_work07EE000001D7_sas-compute-server-8e39c438-4a0f-40b8-81b1-53c19236a793-14
```

> That's the path to SASWORK that SAS sees _inside_ its container.

### > From the node running the `sas-compute-server` pod

We've got a simple script that looks for the newest `sas-compute-server` pod (assuming it's yours) and it provides commands to exec into the host node.

```sh
# Identify the Kubernetes namespace for SAS Viya
export VIYA_NS="viya"

# generate command to exec into node
bash ${PMP_HOME}/bin/find-sas-compute.sh
```

With results similar to:

```log
🔍 Finding newest sas-compute-server pod...
✅ Found pod: sas-compute-server-a8b6ce13-9484-4e72-8cf7-48e1078f9da3-17 (namespace: viya-vol, node: ip-192-168-23-188.ec2.internal)

🚀 ACCESS COMMANDS:

# Interactive shell on node:
-----------------------------------------------------------------
kubectl debug node/ip-192-168-23-188.ec2.internal -it --image=busybox -- chroot /host
-----------------------------------------------------------------
# Alternative: kubectl debug node/ip-192-168-23-188.ec2.internal -it --image=nicolaka/netshoot -- chroot /host

# Local-path volumes (contains /tmp and /viya subdirectories):
cd /viya-scratch

# EmptyDir volumes:
cd /var/lib/kubelet/pods/e893e55d-2906-429d-85f9-ccd14d75a519/volumes/kubernetes.io~empty-dir

# Clean up debug pods:
kubectl get pods | grep node-debugger | awk '{print $1}' | xargs kubectl delete pod
```

Use the interactive shell command provided to get a root-user prompt on the node, like:

```log
[root@ip-192-168-23-188 /]#
```

Recall from our `viya-scratch` storage class definition that it's using the `local-path` CSI driver with default configuration. So, new persistent volumes are created on the node at path `/viya-scratch`. We can find the CAS Controller's cache volume there:

```sh
# List the local-path volumes on this node
cd /viya-scratch/
ls -l
```

With results like:

```log
drwxrwxrwx 6 root root 52 Aug 11 20:25 pvc-4cec6616-3732-475e-8071-9e68bb9a2c90_viya-vol_sas-compute-server-8e39c438-4a0f-40b8-81b1-53c19236a793-14-viya

drwxrwxrwx 2 root root  6 Aug 11 20:25 pvc-bfd1bebc-af53-4503-8e5a-796471b6a2b7_viya-vol_sas-compute-server-8e39c438-4a0f-40b8-81b1-53c19236a793-14-tmp
```

> The volume name ending with "`-viya`" is the top-level location of SASWORK and related files.

Now we know where to start, because we need to dig in deeper to get to the actual SASWORK folder used by your current SAS Compute Server session.

Use `cd` and `ls` commands to navigate down the directory structure inside the "`-viya`" volume:

- `/viya-scratch/`: Where all `local-path` volumes are placed

- `pvc-[[uuid]]_viya-vol_sas-compute-server-[[uuid]]]-viya/`: top-level for this instance of SAS runtime

- `tmp/compsrv/default/`: path into tmp files for SAS Compute

- `[[uuid]]/`: another unique named subdir

- `SAS_work07EE000001D7_sas-compute-server-[[uuid]]/`: Your current SASWORK folder.

If you look in there right now, you'll find several SAS catalogs (.sas7bcat), SAS item stores (.sas7bitm), and other nominally hidden files. And you should also see that baseball table we copied in, `baseball.sas7bdat`.

```log
[root@ip-192-168-23-188 ~]# ls -l /viya-scratch/pvc-4cec6616-3732-475e-8071-9e68bb9a2c90_viya-vol_sas-compute-server-8e39c438-4a0f-40b8-81b1-53c19236a793-14-viya/tmp/compsrv/default/c2e1f389-bd5f-4b6f-becc-c8db6e4564bf/SAS_work07EE000001D7_sas-compute-server-8e39c438-4a0f-40b8-81b1-53c19236a793-14

-rw-r--r-- 1 518005308 518005308 196608 Aug 11 21:09 baseball.sas7bdat
-rw-r--r-- 1 518005308 518005308  12288 Aug 11 20:25 profile.sas7bcat
-rw-r--r-- 1 518005308 518005308  32768 Aug 11 20:25 regstry.sas7bitm
-rw-r--r-- 1 518005308 518005308  12288 Aug 11 20:25 sasgopt.sas7bcat
-rw-r--r-- 1 518005308 518005308      0 Aug 11 20:25 sas.lck
-rw-r--r-- 1 518005308 518005308  20480 Aug 11 21:09 sasmac3.sas7bcat
-rw-r--r-- 1 518005308 518005308 163840 Aug 11 21:09 sasmacr.sas7bcat
-rw-r--r-- 1 518005308 518005308 131072 Aug 11 21:09 sastmp-000000004.sas7butl
-rw-r--r-- 1 518005308 518005308 103424 Aug 11 20:25 sastmp-000000005.sas7bitm
```

We can use `tree` to visualize this a bit better:

```text
/viya-scratch/pvc-4cec6616-3732-475e-8071-9e68bb9a2c90_viya-vol_sas-compute-server-8e39c438-4a0f-40b8-81b1-53c19236a793-14-viya/
├── log
├── run
├── spool
└── tmp
    ├── batch
    ├── compsrv
    │   └── default
    │       └── c2e1f389-bd5f-4b6f-becc-c8db6e4564bf
    │           └── SAS_work07EE000001D7_sas-compute-server-8e39c438-4a0f-40b8-81b1-53c19236a793-14
    │               ├── baseball.sas7bdat
    │               ├── profile.sas7bcat
    │               ├── regstry.sas7bitm
    │               ├── sasgopt.sas7bcat
    │               ├── sas.lck
    │               ├── sasmac3.sas7bcat
    │               ├── sasmacr.sas7bcat
    │               ├── sastmp-000000004.sas7butl
    │               └── sastmp-000000005.sas7bitm
    └── connectserver
```

This confirms that the SAS runtime is configured to place SASWORK in generic ephemeral volumes referencing the viya-scratch storage class using the Rancher local-path provisioner CSI driver.

## RWO ECE Cache Files for SAS Compute Server

SAS Viya introduced the Enhanced Compute Engine as an improvement to the SAS Programming Runtime Environment. Essentially, it provides a local instance of CAS inside the SAS Compute Server. As such, it has its own equivalent of cache files that are placed in the `/tmp` mount point of the "sas-programming-environment" container.

### > From SAS Compute Server

Generate enough data activity in ECE to produce memory-mapped files.

In SAS Studio, submit the following program:

```sas
* Generate a large enough data set to work on;
data work.huge_data;
    do i = 1 to 1000000;  /* 1 million observations */
        x1 = ranuni(1);
        x2 = ranuni(2); 
        x3 = ranuni(3);
        x4 = ranuni(4);
        x5 = ranuni(5);
        category = ceil(ranuni(6) * 100);
        output;
    end;
    drop i;
run;

* Analyze using ECE, not standalone CAS;
proc treesplit data=work.huge_data SEED=12345 maxdepth=10 leafsize=1000;
    input x1 x2 x3 x4 x5 / level=interval;
    target category / level=nominal;    
run;
```

> Note that this SAS program will probably run for about 90 seconds. **Proceed to run the analyze script below during this window.** Re-run as needed.

### > From the `sas-compute-server` pod

It's possible to exec into the SAS Compute Server pod and survey open file handles to find the memory-mapped files in ECE's cache in /tmp. We provide a script to make it easy:

```sh
# analyze the how CAS cache is used
bash ${PMP_HOME}/bin/ece-cache-analyzer.sh $VIYA_NS concise
```

> Besides "`concise`", you can specify "`full`" or "`simple`" for different output.

With results similar to:

```log
Analyzing pod: sas-compute-server-df6086a1-c3b1-4d4f-abbc-318746fa53b4-15 (Enhanced Compute Engine)

PID OWNER       DIRECTORY                 SIZE (MB)       CHUNKS     TYPE      
=============== ========================= =============== ========== ==========
499             /tmp                      30.00           2          ACTIVE    

Summary (grouped by PID owner):
--------------------------------
PIDs with ECE cache: 1
Total ECE cache size: 30.00 MB (0.03 GB)
```

> **If no results are found, then try again while the SAS program provided above is still actively running.**
>
> Again, note that the value in the directory column shows the ECE is creating memory-mapped files in the location we configured. That location is determined dynamically by locating (pre-)deleted files owned by the Compute ECE process with open file handles.

## Status

The SAS runtime's SASWORK location is valid at two independent levels: 

1. from SAS runtime view, and
1. from the host node's view.

The SAS runtime's ECE cache location is valid from the sas-compute-server pod's view. It's left to the reader to further validate following established examples. :)
