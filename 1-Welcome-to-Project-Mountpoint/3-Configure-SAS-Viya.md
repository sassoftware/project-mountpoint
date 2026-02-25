# ![pmp icon](/images/pmp-icon-40x40.png) Project Mountpoint SAS Viya Configuration

In general, [configuration of the SAS Viya platform deployment](https://documentation.sas.com/?cdcId=itopscdc&cdcVersion=default&docsetId=dplyml0phy0dkr&docsetTarget=n0g237aqo6pz1in1t19wjb94j9bi.htm) is managed by using Kustomize to make changes to the SAS Viya order assets. The resulting site manifest describing Viya's deployment to Kubernetes is then executed with `kubectl`.

For Project Mountpoint, we will rely on a mix of the examples and overlays provided by the SAS Viya order assets in combination with appropriate references in the `kustomization.yaml` document.

## Identify the location of SAS Viya order assets

It'll help with scripting below for you to identify where the SAS Viya order assets reside on your host system.

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

From here, you should be familiar with the documented approaches to [configure](https://documentation.sas.com/?cdcId=itopscdc&cdcVersion=default&docsetId=dplyml0phy0dkr&docsetTarget=n08u2yg8tdkb4jn18u8zsi6yfv3d.htm) and [deploy](https://documentation.sas.com/?cdcId=itopscdc&cdcVersion=v_073&docsetId=dplyml0phy0dkr&docsetTarget=p127f6y30iimr6n17x2xe9vlt54q.htm) the SAS Viya platform.

## Clone Project Mountpoint

We have some files you'll want to use. We'll place them alongside your order assets, but you can save it elsewhere if preferred.

```bash
# Fetch useful files

cd $VIYA_ORDER_HOME/..   # parent dir of Viya order

# clone the Project Mountpoint git repo
git clone https://your-git-repo.example.com/GEL/utilities/project-mountpoint.git

# Remember where they are
export PMP_HOME="${PWD}/project-mountpoint"
```

> Cloning Project Mountpoint to your site is not required - just helpful.

And match to your release of SAS Viya:

```bash
cd $PMP_HOME

# Specify the release tag to match SAS Viya
git checkout 2026.01            # or 2026.01.patch01 if exists
```

> The `main` branch is always the latest release - but it might not be compatible with older releases.
>
> SAS Viya versioning specifies a cadence (`LTS` or `Stable`) and a release (`YYYY.MM`) - examples `lts-2025.09` and `stable-2026.01`. We try to keep Project Mountpoint examples in sync with SAS Viya per the release number. Be sure to refer to the [Releases page](https://github.com/sassoftware/project-mountpoint/releases) in case of patch updates.

## Dynamically Provisioned Volumes for Operational Storage

There are practically an infinite number of ways to configure storage for the SAS Viya platform. This project will supply some representative examples with the goal of illustrating how to extend as needed for your site.

> As a reminder, "operational" storage refers to the backend storage relied on by the SAS components. Typically, this is unknown to end users. It includes storage for stateful services like Postgres, Redis, etc., SAS analytic engines use of SASWORK and CAS_DISK_CACHE, and so on.
>
> On the other hand, "functional" storage refers places that the end users are aware of, including data mart locations, user home directories, and so on.

### Three Starter Storage Classes

Provides a great setup of with drop-in, no-edit configuration that achieves full capabilities with three starter storage classes.

Refer to the [3SSC - Three Starter Storage Classes](/3SSC-Three-Starter-Storage-Classes/) for the steps to implement.

### Additional Storage Enhancements

Project Mountpoint will continue to add guidance for other storage enhancements. Depending on the needs of your site, you might consider:

-   [Multiple SASWORK Providers](/4-Multiple-SASWORK-Providers/): demonstrates a technique to provide multiple storage technologies for SASWORK - useful for side-by-side comparison testing in a live environment that's non-destructive and without service interruption.
  
-   [RWX Storage for Checkpoint-Restart](/5-RWX-Storage-for-Checkpoint-Restart/): If your site requires Checkpoint-Restart functionality to recover interrupted long-running SAS Batch Server jobs, then ephemeral scratch space for SASWORK is not sufficient - you need a static, persistent volume in RWX shared storage instead.

-   More to come.

## Next

From here, add [3SSC](/3SSC-Three-Starter-Storage-Classes/) to your new Viya deployment. It provides guidance for initial configuration, additional customization, implementation, and validation.

Notably, 3SSC also includes detailed step-by-step implementation exercises for four different infrastructure providers. The primary goal of those exercises is to show that 3SSC is indeed drop-in, no-edit configuration - that all of those different cloud sites still use the same Viya configuration files *without modification* and yet utilize very different storage providers in each scenario.

As you'll see, storage configuration - and Project Mountpoint's contributions - are a small part that play an oversized role in the SAS Viya platform deployment process.
