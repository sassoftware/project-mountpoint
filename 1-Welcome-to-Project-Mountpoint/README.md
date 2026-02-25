# ![pmp icon](/images/pmp-icon-40x40.png) Welcome to Project Mountpoint

Project Mountpoint aims to make the task of identifying, planning, defining, configuring, and successfully using storage for SAS Viya much easier.

If you want to jump right in, then check out the [Three Starter Storage Classes](/3SSC-Three-Starter-Storage-Classes/) (3SSC). They modify the SAS Viya platform to effectively use the appropriate storage that your site provides. On the Viya side, configuration is simple with a drop-in, no-edit configuration file that works in all environments. This is then mapped to your site's storage offerings through storage class definitions - simple text files easy for Kubernetes administrators to update and manage.

We invite you to explore the [Axioms](/1-Welcome-to-Project-Mountpoint/0-Axioms.md), [Overview](/1-Welcome-to-Project-Mountpoint/1-Overview.md), [Prerequisites](/1-Welcome-to-Project-Mountpoint/2-Prerequisites.md), and [Configuration](/1-Welcome-to-Project-Mountpoint/3-Configure-SAS-Viya.md) documents as well. They provide a lot of the background and reasoning behind the approaches you'll see employed throughout Project Mountpoint.

And finally, we offer additional storage configuration for other use cases beyond initial deployment, such as:

-   [Multiple SASWORK Providers](/4-Multiple-SASWORK-Providers/): configure the Viya platform to use different backend storage for SASWORK. You can then perform comparison testing to see what works best for your workloads. Non-destructive and does not require a service outage.

-   [RWX Storage for Checkpoint Restart](/5-RWX-Storage-for-Checkpoint-Restart/): Checkpoint-Restart is a nifty feature that allows for pre-empted batch jobs to resume at the point where they left off. Great for ETL and other long-running processes that might be interrupted by higher-priority workloads or if a Kubernetes node goes offline unexpectedly. This requires a specialized implementation of SASWORK so that those files can persist from one run to the next.

Have fun!
