# Validate Three Starter Storage Classes

Some aspects of storage validation might be tricky in places. We can show how to verify storage is being used as intended.

## General

Refer to [3SSC readme](/3SSC-Three-Starter-Storage-Classes/README.md) for the table that breaks down which Viya component is using which storage class. Use the Kubernetes tools to confirm those align with expectations.

## Persistent RWO

In 3SSC, this is the "viya-standard-sc" storage class.

Use `kubectl -n viya get pvc` for a listing of persistent volume claims in Viya's namespace. Each will include the storage class name, capacity, and status - any that are not "Bound" as expected can be investigated with `kubectl describe pvc {{ PVC-NAME }}`.

## Shared RWX

In 3SSC, this is the "viya-shared-sc" storage class.

Use `kubectl -n viya get pvc` for a listing of persistent volume claims in Viya's namespace. Each will include the storage class name and its status - any that are not "BOUND" can be investigated with `kubectl describe pvc {{ PVC-NAME }}`.

## Scratch

In 3SSC, this is the "viya-scratch-sc" storage class.

The use of node-local disk is slightly more complicated because the specified mount location must be validated. So additional confirmation of that is handled below.

### SASWORK and ECE Cache

SASWORK is one of the heaviest I/O throughput consumers in the SAS Viya platform. This often means some of the most costly storage is assigned for use by the SAS Programming Runtime Environment servers, like SAS Batch, SAS Compute, and SAS Connect. Let's make sure their SASWORK volumes are operating as designed.

-   [Validate_RWO_SASWORK.md](/3SSC-Three-Starter-Storage-Classes/Validation-Examples/Validate_RWO_SASWORK.md):
    -   Confirms the use of node-local disk for SASWORK
    -   Confirms the use of node-local disk for ECE Cache

### CAS_DISK_CACHE

CAS_DISK_CACHE is a required backing store for SAS Cloud Analytic Services in-memory data. CAS "pre-deletes" the files on disk in its cache, but keeps an open filehandle to them while they're in use. We confirm those filehandles are indeed for files in the designated volume/disk.

-   [Validate_RWO_CAS_Cache.md](/3SSC-Three-Starter-Storage-Classes/Validation-Examples/Validate_RWO_CAS_Cache.md):
    -   Confirms the use of node-local disk for CAS_DISK_CACHE

## Next

With succesful storage validation, then 3SSC configuration of the SAS Viya platform is complete.
