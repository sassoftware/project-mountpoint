# Install Rancher's Local Path Provisioner

This page provides general guidance about installing the Rancher Local Path Provisioner to your EKS cluster. It will:

- Install the Rancher Local Path Provisioner using provided script
- Configure local-path to use a custom directory
- Identify the storage class for dyamic volumes on local-disk

## Assumes

These instructions assume:

- the kubectl CLI is installed and user has cluster-admin privileges
- instance types provided that have local disk attached, formatted, and mounted ([see example](/9-Appendix/Kubernetes/local-disk/daemonset-format-mount-local-disk.md))

The user is expected to have the skillset to modify and debug these steps as needed for their site.

## Steps

1.  Install the Rancher project local-path-provisioner

    ```bash
    # Install local-path
    kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
    ```

1.  The `local-path` storage class is automatically defined:

    ```sh
    # Automatically creates the `local-path` SC, too
    kubectl describe sc local-path
    ```

    > Note that the base directory path defaults to `/opt/local-path-provisioner/` on the node.

1.  We need a custom path to use the mounted local disk. For this exercise, that is mounted on the node at `/viya-scratch`.

    Manually modify the configMap:

    ```sh
    # Open an editor to local-path CSI driver's configMap
    kubectl edit configmap local-path-config -n local-path-storage
    ```

    Replace the default path "`/opt/local-path-provisioner`" with our new mounted volume "`/viya-scratch`". And save the file.

    ---

    Or, here's a script to patch it:

    ```bash
    # Configure to use /viya-scratch
    kubectl get configmap local-path-config -n local-path-storage -o json \
    | jq '.data["config.json"] |= (fromjson | .nodePathMap[0].paths = ["/viya-scratch"] | tojson)' \
    | kubectl apply -f -
    ```

1. Rollout the change gracefully

    ```bash
    # Restart the local-path provisioner
    kubectl rollout restart deployment local-path-provisioner -n local-path-storage
    ```

## Status

The `rancher.io/local-path` CSI driver has been installed for local disk volumes and an example storage class named "local-path" defined to use the "`/viya-scratch`" mount point.
