# ![pmp icon](/images/pmp-icon-40x40.png) Project Mountpoint Axioms

These are the fundamental axioms that guide Project Mountpoint. Additional opinions that inform some examples are given as well.

## № 1 - Make it straight-forward, discoverable, and customizable

The storage available for the SAS Viya platform will differ significantly from site-to-site, even when running in the same cloud infrastructure. Project Mountpoint provides drop-in, no-edit configuration files to get started along with sample code, and hands-on exercises. All resources are self-documenting and provide links to backend documentation sources for reference. This enables the Viya deployment team to understand the configuration of storage and enables them to modify and extend it to suit their needs.



## № 2 - Avoid Kubernetes Builtin Storage

Kubernetes offers several builtin storage types. We'll focus on three to avoid:

-   `emptyDir`: provides an *ephemeral* volume on the node's root volume.

    Implemented as the default storage type for SASWORK and ECE Cache in the SPRE servers' podTemplates. And for CAS_DISK_CACHE in the SAS Cloud Analytics Service definition.

    > SAS documentation suggests to avoid it. The risk is filling up the root volume and crashing the entire node.

-   `nfs`: provides access to a *persistent* volume to a server using the NFS protocol.

    Used to provide simple access to static NFS-based volumes.

    > Like other Kubernetes built-in volume types, this is considered legacy and is deprecated.

-   `hostPath`: provides access to a *persistent*<sup>&ast;</sup> volume on the node's local disk.

    Often implemented when trying to avoid `emptyDir` and still have access to local disk for SASWORK, ECE Cache, and CAS_DISK_CACHE.

    > Kubernetes documentation recommends to [avoid it](https://kubernetes.io/docs/concepts/storage/volumes/#hostpath). The risk is full privilege escalation in Kubernetes and its underlying host machines. SAS documentation [suggests](https://documentation.sas.com/?cdcId=itopscdc&cdcVersion=default&docsetId=itopssr&docsetTarget=n0ampbltwqgkjkn1j3qogztsbbu0.htm#p0vz40hestth2wn11gbcd8jez48f) only using it if fully cognizant of the risks.

    > <sup>**&ast;**</sup>Note: The `hostPath` volume type is often described as *ephemeral* instead of *persistent* - but *persistent* it is. It's considered to be "effectively ephemeral" because pods starting up on a different nodes won't have access to the same files at the same path... but even so, whatever files your pod writes out to the hostPath will remain until they're intentionally deleted.



## № 3 - Storage classes are "free"

SAS system requirements put the burden of infrastructure provisioning and management on the site's IT team. SAS does provide guidance in the form of the IAC projects (see *SAS® Viya® Platform Operations* > [Help with Cluster Setup](https://go.documentation.sas.com/doc/en/itopscdc/v_071/itopssr/n1ika6zxghgsoqn1mq4bck9dx695.htm#n1olvuvfn9c4ctn1xfu73enqva1s)), consulting, technical support, and so on - but always with the understanding the the customer is *responsible* for infrastructure.

That is an approach fully supported by Project Mountpoint.

The site's IT team is free to stand up Kubernetes and supporting storage architecture as suits their processes and accepted practices - and in alignment with SAS Viya [Hardware and Resource Requirements](https://documentation.sas.com/?cdcId=itopscdc&cdcVersion=default&docsetId=itopssr&docsetTarget=n0ampbltwqgkjkn1j3qogztsbbu0.htm). This includes defining storage classes for dynamic volume provisioning. After setup, configuration, and validation of the storage infrastructure is complete, then the original storage classes - whatever they're called - are in a known-good state.

From there, Project Mountpoint recommends literally *copying* the original storage class definitions to create new ones in alignment with 3SSC (or whatever scheme you want). This is "free" - storage classes cost nothing. They're just YAML. And this provides a very useful abstraction layer that helps manage Viya's configuration independently of the underlying storage infrastructure.

Want to change Viya's use of persistent volumes in Amazon EBS from "gp3" to "io2"? Then *copy* the original, tested "io2" storage class to redefine the 3SSC "viya-standard-sc" storage class. [Caveat: this is not a *migration* recommendation, but an example that's useful for new (re-)deployments.] No additional change is needed to Viya's internal configuration - you're just mapping "viya-standard-sc" to use "io2" instead of "gp3" now. This approach works in any cloud-provider or on-prem infrastructure.

### Opinions:

-   **SAS Viya should not rely on storage classes with "default" annotation**

    If a persistent volume claim doesn't specify a storage class by name, then Kubernetes will look at its list of storage classes to see if any have the ["default" annotation](https://kubernetes.io/docs/tasks/administer-cluster/change-default-storage-class/) and use that if found. This is lazy and problematic.

    Project Mountpoint provides optional steps to remove the "default" annotation from any storage classes it finds. This ensures that when the SAS Viya platform is deployed, then all persistent volume claims it uses must explicitly specify a storage class name or they will fail. If they fail, we fix them.

    In the real world, if your site's IT team prefers to have a storage class annotated as "default", then that's okay. Just make sure you're confident that none of the persistent volume claims used by SAS Viya rely on that "default" behavior.

## № 4 - CAS Cache, SASWORK, and ECE Cache require architectural storage

By "architectural storage", we mean an explicit solution to target these volumes. Project Mountpoint provides straight-forward techniques to systematically configure Viya to use Kubernetes generic ephemeral volumes (GeV) for this purpose. GeV are a perfect fit for the lifecycle demands. And they can be pointed at *any* storage provider with storage class configuration. Local disk is preferred, but any target can be used that meets I/O requirements.

A word about [Checkpoint-Restart](https://documentation.sas.com/?cdcId=sasadmincdc&cdcVersion=default&docsetId=wrkldmgmt&docsetTarget=n08kwxkduvcw1an1sk3lsri96liq.htm). This feature of SAS Viya Workload Management (inherited from SAS 9 Grid Manager) requires a static persistent volume in RWX shared storage - a GeV is not suitable for this purpose. Project Mountpoint provides [guidance for this use-case](/5-RWX-Storage-for-Checkpoint-Restart/README.md) as well.



## Next

Ready to learn more about Project Mountpoint? Proceed to the [Overview](/1-Welcome-to-Project-Mountpoint/1-Overview.md).
