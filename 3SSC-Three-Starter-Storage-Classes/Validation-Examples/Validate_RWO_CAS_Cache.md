# Validate CAS_DISK_CACHE

Generally speaking, we can validate the storage that Viya is using by referring to the PVC and storage classes.

But for SASWORK and CAS_DISK_CACHE, it can be good to take extra steps to show that the storage is being utilized as designed.

In this exercise, we demonstrate three different viewpoints from which to confirm the physical storage behind CAS_DISK_CACHE.

## RWO CAS_DISK_CACHE files for SAS Cloud Analytics Service

Let's check on the configuration for CAS_DISK_CACHE storage for `sas-cas-server-default` pod(s).

### > From SAS Compute Server

Check where SAS reports the CAS disk cache to be.

In SAS Studio, submit the following program:

```sas
* Start a CAS session;
cas sess1;
 
* Show information about CAS cache;
proc cas;
    session sess1;
    accessControl.assumeRole / adminRole="superuser";
    builtins.getCacheInfo result=results;
    print results.diskCacheInfo;
run;
quit;

cas sess1 clear;
```

With results similar to:

| Node | File System | Capacity | Free_Mem | %_Used | NodePath |
| ---- | ----------- | -------- | -------- | ------ | -------- |
controller.sas-cas-server-default.viya-vol.svc.cluster.local | /dev/nvme0n1p1 | 199 GB | 182 GB | 9.0 | `/cas/cache-scratch` |

> The value in NodePath should match the patchTransformer we define in site-config to setup a generic ephemeral volume for CAS_DISK_CACHE, specifically in two places: `volumeMounts` and `env`ironment variables.
>
> ```yaml
> - op: add
>     path: /spec/controllerTemplate/spec/containers/0/volumeMounts/-
>     value:
>         name: cas-cache-gev
>         mountPath: /cas/cache-scratch
> - op: add
>     path: /spec/controllerTemplate/spec/containers/0/env/-
>     value:
>         name: CASENV_CAS_DISK_CACHE
>         value: "/cas/cache-scratch"
> ```

### > From the `sas-cas-default-{controller,worker}` pod

It's possible to exec into the CAS pod and survey open file handles to find the memory-mapped files in CAS Disk Cache. We provide a script to make it easy:

```sh
# Identify the Kubernetes namespace for SAS Viya
export VIYA_NS="viya"

# analyze the how CAS cache is used
bash ${PMP_HOME}/bin/cas-cache-analyzer.sh $VIYA_NS concise
```

> Besides "`concise`", you can specify "`full`" or "`simple`" for different output.

With results similar to:

```log
Analyzing pod: sas-cas-server-default-controller (SMP)

PID OWNER       DIRECTORY                 SIZE (MB)       CHUNKS     TYPE      
=============== ========================= =============== ========== ==========
2333            /cas/cache-scratch        946.33          2          ACTIVE    

Summary (grouped by PID owner):
--------------------------------
PIDs with cache: 1
Total cache size: 946.33 MB (0.92 GB)
```

> Again, note that the value in the directory column shows CAS is creating memory-mapped files in the location we configured. That location is not hard-coded in the analyzer, but is determined dynamically by locating (pre-)deleted files owned by CAS processes with open file handles.

### > From the node running the CAS pod

We've got a simple script that looks for the newest `sas-cas-server-default-controller` pod and it provides commands to exec into the host node.

```sh
# generate command to exec into node
bash ${PMP_HOME}/bin/find-cas-controller.sh
```

With results similar to:

```log
🔍 Finding newest sas-cas-server-default-controller pod...
✅ Found pod: sas-cas-server-default-controller (namespace: viya-vol, node: ip-192-168-14-86.ec2.internal)

🚀 ACCESS COMMANDS:

# Interactive shell on node:
-----------------------------------------------------------------
kubectl debug node/ip-192-168-14-86.ec2.internal -it --image=busybox -- chroot /host
-----------------------------------------------------------------
# Alternative: kubectl debug node/ip-192-168-14-86.ec2.internal -it --image=nicolaka/netshoot -- chroot /host

# CAS Disk Cache volumes:
cd /viya-scratch

# EmptyDir volumes:
cd /var/lib/kubelet/pods/92f4604c-a788-44e3-8a23-6698b4e55470/volumes/kubernetes.io~empty-dir

# Clean up debug pods:
kubectl get pods | grep node-debugger | awk '{print $1}' | xargs kubectl delete pod
```

Use the interactive shell command provided to get a root-user prompt on the node, like:

```log
[root@ip-192-168-14-86 /]#
```

Recall from our `viya-scratch` storage class definition that it's using the `local-path` CSI driver with default configuration. So, new persistent volumes are created on the node at path `/viya-scratch`. We can find the CAS Controller's cache volume there:

```sh
# List the local-path volumes on this node
cd /viya-scratch
ls -l
```

With results like:

```log
drwxrwxrwx 2 root root 20 Aug 11 20:30 pvc-3d1462fb-c5fd-4a3f-9ad7-4ae047ce1f7b_viya-vol_sas-cas-server-default-controller-cas-cache-scratch
```

If you look in there right now, you'll find zero files, even if you have several large tables loaded into CAS memory. That's because CAS marks these files as "deleted" when it creates them and holds on to the open file handle. So let's prove this directory really is used for CAS cache in a slightly different way.

**Use a new, different terminal window** to launch K9s and find the `sas-cas-server-default-controller` pod. Select it and hit Enter to see its containers. Select the `sas-cas-server` container and then hit the letter `s` so that K9s will provide a shell inside that container.

K9s should place you in a shell as the "sas" user at the root-level directory. We know from our tests above that CAS is using the `/cas/cache-scratch` directory as it exists in the container for CAS_DISK_CACHE. Create an empty file there:

```sh
# at the "sas@controller" prompt shell in sas-cas-server in K9s 
touch /cas/cache-scratch/Test-File
```

**Return to your previous terminal window** showing the PV for CAS cache on the host node. Get a directory listing of files in there.

Your test file should be visible here, too:

```log
[root@ip-192-168-14-86 /]# ls -l /viya-scratch/pvc-3d1462fb-c5fd-4a3f-9ad7-4ae047ce1f7b_viya-vol_sas-cas-server-default-controller-cas-cache-scratch

-rw------- 1 1001 1001 0 Aug 11 20:48 Test-File
```

This confirms that the CAS Server is configured to place CAS_DISK_CACHE in generic ephemeral volumes referencing the viya-scratch storage class using the Rancher local-path provisioner CSI driver.

## Status

The CAS Server's cache location is valid at three independent levels: 

1. from SAS runtime view,
1. from the `sas-cas-server` container's view, and 
1. from the host node's view.

> Just fyi that CAS took an extra level because it "pre-deletes" files in its cache. So, we snuck in and made one.
