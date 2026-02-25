# Validate RWX Storage for Checkpoint-Restart

Some aspects of storage validation might be tricky in places. We can show how to verify storage is being used as intended.

## SASWORK

SASWORK is one of the heaviest I/O throughput consumers in the SAS Viya platform. This often means some of the most costly storage is assigned for use by the SAS Programming Runtime Environment servers, like SAS Batch, SAS Compute, and SAS Connect. Let's make sure their SASWORK volumes are operating as designed.

-   [Validate_RWX_SASWORK.md](/5-RWX-Storage-for-Checkpoint-Restart/Validation-Examples/Validate_RWX_SASWORK.md):
    -   Confirms the use of shared disk for SASWORK of the SAS Batch Server allows for Checkpoint-Restart operations

