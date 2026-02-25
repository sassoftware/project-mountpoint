# Validate SASWORK on RWX volume

Generally speaking, we can validate the storage that Viya is using by referring to the PVC and storage classes.

But for SASWORK and CAS_DISK_CACHE, it can be good to take extra steps to show that the storage is being utilized as designed.

In this exercise, we demonstrate the Checkpoint-Restart functionality offered by SAS Workload Management for SAS Batch Servers as a means to validate the use of RWX (shared storage) volume for SASWORK.

**For AWS environments, this exercise only works when an RWX volume from a static PVC referring to the NFS or FSx-based storage is used for the SAS Batch Server's `/viya` volume.** (Reminder, Amazon EFS is not a supported RWX storage provider for SASWORK... yet.)

## Get the sas-viya CLI

We need the sas-viya CLI to submit batch jobs. [Perform these instructions](/9-Appendix/Viya/install-sas-viya-cli.md) before continuing here.

## RWX SASWORK files for SAS Batch Server

Let's check on the configuration for SASWORK storage for `sas-batch-server` pods.

Checkpoint-Restart functionality is only available for batch SAS jobs that are submitted using the `sas-viya` CLI with either `--restart-label` or `--restart-datastep` options and specifying a SAS Workload Management queue that has "Restart Jobs" enabled.

### Configure SAS Workload Manager

> The user is expected to be familiar with [basic functionality of SAS Viya Workload Manager](https://documentation.sas.com/?cdcId=sasadmincdc&cdcVersion=default&docsetId=wrkldmgmt&docsetTarget=n08kwxkduvcw1an1sk3lsri96liq.htm), including preemption and priority.

1. Configure the existing Queue named "default" to enable "[Restart Jobs](https://documentation.sas.com/?cdcId=sasadmincdc&cdcVersion=default&docsetId=wrkldmgmt&docsetTarget=n1xug8bvp3fnv0n1nrxtofezcxv1.htm#p0w3agj0iqexcmn1dhn1htnkihui)".

1. Create a new Queue with a "[Priority](https://documentation.sas.com/?cdcId=sasadmincdc&cdcVersion=default&docsetId=wrkldmgmt&docsetTarget=n1xug8bvp3fnv0n1nrxtofezcxv1.htm#p0w3agj0iqexcmn1dhn1htnkihui)" value of `20`. (The "default" queue's priority is set to `10`)

1. Configure the high priority Queue to [preempt](https://documentation.sas.com/?cdcId=sasadmincdc&cdcVersion=default&docsetId=wrkldmgmt&docsetTarget=p0qs2l4ukvbeddn1qx6zw8eyox7x.htm#n06tked1obpgecn1o5elop1lzxci) the "default" Queue.

1. Configure the "default" Host Type with a "[Maximum jobs allowed](https://documentation.sas.com/?cdcId=sasadmincdc&cdcVersion=default&docsetId=wrkldmgmt&docsetTarget=n1xug8bvp3fnv0n1nrxtofezcxv1.htm#p0hr1bbpk7kon4n11dqfxurb6a11)" value of `1`.

Preemption and the host "disappearing" are the **only** triggers for the "-restart" side of Checkpoint-Restart functionality (simple job failure isn't sufficient). The configuration here sets up the simplest test environment.

> Note that these are not production-level settings. Instead, we are ratcheting the envrionment down to make tracing batch job actions as simple as possible.

### Validate Checkpoint-Restart

To validate Checkpoint-Restart, we need 1) a job with checkpoint labels, 2) for that job to be preempted, and 3) for that job to be restarted such that it resumes where it left off.

1.  The SAS program we'll use for testing:

    ```bash
    cat << EOF > ~/checkpoint-test.sas
    /* Checkpoint-Restart Demo Program */
    /* This program demonstrates checkpoint-restart capability in SAS Viya WLM */

    /* Step 1: Create a test table from SASHELP data */
    %put NOTE: Starting Step 1 - Creating test table;
    %put NOTE: Current time: %sysfunc(datetime(), datetime20.);

    label_begin:
    data work.test_table;
        set sashelp.cars;
        random_id = ranuni(12345);
    run;

    %put NOTE: Step 1 completed at %sysfunc(datetime(), datetime20.);

    label_batchbaseball:
    data work.baseball2;
        set sashelp.baseball;
    run;

    /* Create a checkpoint after table creation */
    label_after_table_creation:
    %put NOTE: Checkpoint created: after_table_creation;

    /* Step 2: Sleep for 5 minutes to allow manual intervention */
    %put NOTE: Starting Step 2 - Sleeping for 5 minutes;
    %put NOTE: This is where you can delete the pod to test checkpoint-restart;

    label_30s:
    data _null_;
        start = datetime();
        call sleep(30000);
        finish = datetime();
        put "NOTE: Sleep started at " start datetime20.;
        put "NOTE: Sleep finished at " finish datetime20.;
    run;

    label_60s:
    data _null_;
        start = datetime();
        call sleep(30000);
        finish = datetime();
        put "NOTE: Sleep started at " start datetime20.;
        put "NOTE: Sleep finished at " finish datetime20.;
    run;

    label_90s:
    data _null_;
        start = datetime();
        call sleep(30000);
        finish = datetime();
        put "NOTE: Sleep started at " start datetime20.;
        put "NOTE: Sleep finished at " finish datetime20.;
    run;

    label_120s:
    data _null_;
        start = datetime();
        call sleep(30000);
        finish = datetime();
        put "NOTE: Sleep started at " start datetime20.;
        put "NOTE: Sleep finished at " finish datetime20.;
    run;

    /* Create another checkpoint after sleep */
    label_after_sleep:
    %put NOTE: Checkpoint created: after_sleep;

    /* Step 3: Perform analysis on the table */
    %put NOTE: Starting Step 3 - Performing analysis;
    %put NOTE: Analysis started at %sysfunc(datetime(), datetime20.);

    /* PROC CONTENTS to show table structure */
    proc contents data=work.test_table varnum;
        title 'Contents of Test Table After Checkpoint-Restart';
    run;

    /* Some basic statistics */
    proc means data=work.test_table n mean std min max;
        var mpg_highway msrp;
        title 'Statistics for Test Table';
    run;

    /* Frequency analysis */
    proc freq data=work.test_table;
        tables mpg_highway * msrp / nocol norow nopercent;
        title 'Cross-tabulation of MPG and Price Categories';
    run;

    %put NOTE: Analysis completed at %sysfunc(datetime(), datetime20.);

    /* Step 4: Cleanup */
    %put NOTE: Starting Step 4 - Cleanup;

    proc delete data=work.test_table;
    run;

    %put NOTE: Cleanup completed at %sysfunc(datetime(), datetime20.);
    %put NOTE: Checkpoint-Restart Demo Program completed successfully!;
    EOF
    ```

    > Notes:
    >
    > This program is pretty simple. It creates a couple of tables in SASWORK, goes to sleep for a few minutes, and then does a few more things.
    >
    > Along the way, it creates checkpoint labels that will be used to determine where to restart the job if it fails midway through.

1.  Submit the 1st test job:

    ```bash
    # Use the sas-viya CLI to submit a batch program with checkpoint labels enabled
    sas-viya batch jobs submit-pgm --context pmp-batch-saswork-pvc-bc --queue default --pgm ~/checkpoint-test.sas --restart-label --jobname jobrestart_default
    ```

    > Note that we're referring to Batch Context "`pmp-batch-saswork-pvc-bc`" which we setup to reference a static PVC to RWX shared storage. If you prefer a different Batch Context, then specify it.

    Results similar to:

    ```log
    >>> The file set "JOB_20250905_213303_323_1" was created.
    >>>   Uploading "checkpoint-test.sas".
    >>> The job was submitted. ID: "1d4a22da-4a3c-4a22-b9a8-2aae483083be"  Workload Orchestrator job ID: "22"
    ```

    > The `--restart-label` parameter is crucial to ensure checkpoint-restart functionality is enabled.
    >
    > Alternatives are `--restart-datastep` and `--restart-job` (restarting the entire job isn't really "checkpoint" though).

1.  Monitor job status:

    ```sh
    # Keep this running in its own terminal window
    watch "sas-viya -y --output text workload-orchestrator jobs list | tail -10"
    ```

    It's also a good idea to have K9s running in another terminal window, too.

1.  Repeat the process above to **submit a 2nd test job to the higher-priority queue** (note the `--queue` parameter) to cause preemption of the first job in the middle of its run.

    > The SAS Workload Orchestrator will determine that the second job in the higher-priority queue should _preempt_ the first job. So, it kills the first job and reverts its status from "RUNNING" to "PENDING".

1.  Wait for the 2nd test job to complete. Then **continue monitoring the 1st test job** as it is re-submitted to run to completion.

    > The second job should complete in just over 2 minutes. Then the SAS Workload Orchestrator will resubmit the first job. With Checkpoint-Restart enabled, the SAS Batch Server will find its old SASWORK in the shared (RWX) storage configured and determine where to resume.

1.  Get the jobs' log files:

    ```sh
    # Use the sas-viya CLI to fetch job output, including the log
    sas-viya batch jobs get-results
    ```

    > Files are organized by "`JOB`" directories that include timestamps in the name.

    This command fetches all results that haven't been retrieved before. Expect to get a set of files back for each job:

    - the 2nd test job that ran in the higher priority queue
    - the 1st test job that was preempted and then restarted to run to completion.

1.  Look at the "`JOB`" directory name to determine which is newest and then review the log file in there. You should see checkpoint activity that resumes execution midway through the SAS program to complete the steps that the first "failed" job didn't get to.

    Look near the top of the log for processing to resume at one of the middle labels, similar to:

    ```log
    NOTE: Begin CHECKPOINT (at label) execution mode.
    NOTE: Begin CHECKPOINT-RESTART(at label: label_90s) execution mode.
    ```

    > The test job contains these labeled checkpoints:
    > - `label_begin`
    > - `label_batchbaseball`
    > - `label_after_table_creation`
    > - `label_30s`
    > - `label_60s`
    > - `label_90s`
    > - `label_120s`
    > - `label_after_sleep`
    >
    > Restart picks up *after* the last ***un***interrupted label block.

## Status

Shared (RWX) storage is used to support Checkpoint-Restart functionality for batch-submitted jobs.

## Next

With succcesful storage validation, then RWX Storage for Checkpoint-Restart is complete.