# Install CSI Driver for AWS Elastic File Storage volumes

This page provides general guidance about installing the Amazon EFS CSI Driver to your EKS cluster. It will:

- define a new IAM role for the driver to use
- create a k8s service account and link it to the IAM role
- use a Helm chart to deploy the Amazon EFS CSI Driver
- attach the IAM policy for EFS to the EKS nodes (so they can use the driver)
- demonstrate how to create storage classes for EFS storage

## Assumes

These instructions assume:

- the site's EKS cluster has been provisioned already
- the AWS CLI is installed and that the user is logged in
- the kubectl CLI is installed and user has cluster-admin privileges

And finally, the user is expected to have the skillset to modify and debug these steps as needed for their site.

## Prerequisites

This exericse requires the existence of an EFS file system with a known id. The IAC project can provision this for you when [configured](https://github.com/sassoftware/viya4-iac-aws/blob/main/docs/CONFIG-VARS.md#aws-elastic-file-system-efs) with:
> - `storage_type=ha`
> - `storage_type_backend=efs`

Else, here's a simple script to stand up an ad-hoc Elastic File System and access point:

```bash
# Create an ad-hoc EFS
bash ${PMP_HOME}/bin/create-efs.sh
```

Either way, confirm the existing EFS file system:

```bash
# List file systems in EFS
aws efs describe-file-systems --no-cli-pager --query 'FileSystems[].[FileSystemId, Name, LifeCycleState, PerformanceMode, ThroughputMode, Tags[?Key==`resourceowner`].Value | [0]]' --output table
```

> Note the first column provides the `FileSystemId` value we need to reference later.

## Steps

1.  Local environment variables

    ```bash
    # Provide info about this site

    ## Project Mountpoint home
    export PMP_HOME=${PMP_HOME:-"$HOME/project/deploy/project-mountpoint"}
    # keeps existing value if PMP_HOME is already defined, else takes new value

    ## AWS: Get Account ID
    export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

    ## EKS Cluster Name
    export CLUSTER_NAME="$(kubectl config view -o jsonpath='{.contexts[0].name}')"
    # assumes only 1 context is defined in kubeconfig

    ## My Prefix (useful for naming things in AWS)
    export MY_PREFIX=${MY_PREFIX:-"YOUR_PREFIX_HERE"}
    # keeps existing value if MY_PREFIX is already defined, else takes new value
    ```

1.  Establish attributes we need for EFS CSI driver

    ```bash
    ## AWS: Determine the ARN for my EKS cluster OpenID Connect host
    export OIDC_URL="$(aws eks describe-cluster --name $CLUSTER_NAME --query 'cluster.identity.oidc.issuer' --output text)"
    export OIDC_HOSTNAME="$(echo $OIDC_URL | awk -F/ '{print $5}')"
    export OIDC_REGION="$(echo $OIDC_URL | awk -F. '{print $3}')"
    export OIDC_PROVIDER_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/oidc.eks.${OIDC_REGION}.amazonaws.com/id/${OIDC_HOSTNAME}"

    ## Default values
    export CSI_K8S_SANAME="efs-csi-controller-sa"
    export CSI_IAM_POLICYARN="arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
    export MY_EFS_CSI_IAM_ROLENAME=${MY_PREFIX}-efs-csi-controller-role
    ```

1.  Create the new IAM role for the CSI driver

    ```bash
    ## Create the role for EFS CSI driver
    aws iam create-role --role-name ${MY_EFS_CSI_IAM_ROLENAME} --assume-role-policy-document "$(cat <<EOF
    {
    "Version": "2012-10-17",
    "Statement": [
        {
        "Effect": "Allow",
        "Principal": {
            "Federated": "$OIDC_PROVIDER_ARN"
        },
        "Action": "sts:AssumeRoleWithWebIdentity",
        "Condition": {
            "StringEquals": {
            "oidc.eks.${OIDC_REGION}.amazonaws.com/id/${OIDC_HOSTNAME}:sub": "system:serviceaccount:kube-system:$CSI_K8S_SANAME",
            "oidc.eks.${OIDC_REGION}.amazonaws.com/id/${OIDC_HOSTNAME}:aud": "sts.amazonaws.com"
            }
        }
        }
    ]
    }
    EOF
    )"

    # AWS: Attach the AWS EFS CSI driver policy to the role
    aws iam attach-role-policy --role-name "$MY_EFS_CSI_IAM_ROLENAME" --policy-arn "$CSI_IAM_POLICYARN"

    # AWS: Validate the policy is attached to role
    aws iam list-attached-role-policies --role-name "$MY_EFS_CSI_IAM_ROLENAME"
    ```

1.  Create a new service account in Kubernetes that links to the new IAM role with necessary permissions provided.

    ```bash
    # AWS: Get the ARN of the role just created
    CSI_IAM_ROLEARN=$(aws iam get-role --role-name $MY_EFS_CSI_IAM_ROLENAME --output text --query 'Role.Arn')

    # K8s: Create the service account for EFS CSI driver
    kubectl create serviceaccount -n kube-system $CSI_K8S_SANAME

    # K8s: Annotate the service account so it links to the new role
    kubectl annotate serviceaccount -n kube-system $CSI_K8S_SANAME eks.amazonaws.com/role-arn="$CSI_IAM_ROLEARN"
    ```

1.  Helm: deploy aws-efs-csi-driver to Kubernetes

    ```bash
    # add the AWS EFS CSI Driver repo to Helm
    helm repo add aws-efs-csi-driver https://kubernetes-sigs.github.io/aws-efs-csi-driver

    # Update Helms local cache
    helm repo update

    # Initialize
    export EFS_CSI_DRIVER_ENABLED="true"
    export EFS_CSI_DRIVER_NAME="aws-efs-csi-driver"
    export EFS_CSI_DRIVER_NAMESPACE="kube-system"
    export EFS_CSI_DRIVER_CHART_NAME="aws-efs-csi-driver"
    export EFS_CSI_DRIVER_CHART_URL="https://kubernetes-sigs.github.io/aws-efs-csi-driver"
    export EFS_CSI_DRIVER_CHART_VERSION="3.1.2"
    export EFS_CSI_DRIVER_ACCOUNT="$CSI_K8S_SANAME"  # SA created above
    export EFS_CSI_DRIVER_ROLEARN="$CSI_IAM_ROLEARN" # Role created above
    export EFS_CSI_DRIVER_LOCATION="$OIDC_REGION"    # Region of EKS determined above

    # Install the Amazon EFS CSI driver and associate with role
    helm upgrade --install "${EFS_CSI_DRIVER_NAME}" \
    "${EFS_CSI_DRIVER_NAME}/${EFS_CSI_DRIVER_NAME}" \
    --namespace "${EFS_CSI_DRIVER_NAMESPACE}" \
    --version "${EFS_CSI_DRIVER_CHART_VERSION}" \
    --set controller.serviceAccount.create=false \
    --set controller.serviceAccount.name="${EFS_CSI_DRIVER_ACCOUNT}" \
    --set controller.serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${EFS_CSI_DRIVER_ROLEARN}" \
    --set node.serviceAccount.create=true \
    --set node.serviceAccount.name="${EFS_CSI_DRIVER_NAME}-node-sa"
    ```

1.  Validate the aws-efs-csi-driver is running on all nodes:

    ```bash
    # K8s: get the list of pods with the aws-efs-csi-driver labels
    kubectl get pod -n kube-system -l "app.kubernetes.io/name=aws-efs-csi-driver,app.kubernetes.io/instance=aws-efs-csi-driver"
    ```

1.  Attach policy to role for each k8s node

    ```bash
    # Attach the AWS-managed `AmazonEFSCSIDriverPolicy` to the IAC-provided Roles associated with the instances by their node groups
    bash ${PMP_HOME}/bin/attach-efscsi-policy.sh
    ```

1.  Identify which EFS file system to use

    ```bash
    # Grabbing the first listed file system, else you need to set manually
    export MY_EFS_ID=$(aws efs describe-file-systems --no-cli-pager --query 'FileSystems[].[FileSystemId]' --output text | head -1)
    ```

1.  Define the `efs` storage class

    ```bash
    mkdir -p ~/project/deploy/

    # define the efs storage class
    cat << EOF > ~/project/deploy/defineSC_efs.yaml
    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
        name: efs
    provisioner: efs.csi.aws.com
    parameters:
        provisioningMode: efs-ap
        fileSystemId: ${MY_EFS_ID}
        directoryPerms: "0777"
        gidRangeStart: "1000"
        gidRangeEnd: "2000"
        basePath: "/dynamic_provisioning"
    volumeBindingMode: WaitForFirstConsumer
    reclaimPolicy: Delete
    EOF

    # Apply the manifest to define efs storage class
    kubectl apply -f ~/project/deploy/defineSC_efs.yaml

    # review
    kubectl describe sc efs
    ```

    > Note:
    > - The EFS CSI Driver supports both static and dynamic provisioning
    > - For dynamic provisioning, the driver creates EFS Access Points automatically
    > - EFS volumes can be shared across multiple pods and nodes (ReadWriteMany)
    > - Consider performance mode and throughput mode settings based on your workload requirements
    > - EFS supports both Regional (default) and One Zone storage classes for cost optimization
    > - You can have multiple storage classes pointing to different EFS file systems

## Additional tasks

There's more that could be done beyond the bare minimums above.

### > Cleanup

If the Amazon EFS CSI Driver is removed from the cluster (or even if the EKS cluster is terminated), we still need to clean up other items left behind.

Delete the EFS file system:

```bash
# Delete our ad-hoc EFS
bash ${PMP_HOME}/bin/delete-efs.sh
```

> Attention: this is only necessary if you manually provisioned an ad-hoc Elastic File System. **Skip this and move on to delete the IAM role** if you configured the IAC with:
>
> - `storage_type=ha`
> - `storage_type_backend=efs`
>
> For IAC-provisioned EFS, then the `terraform destroy` command below will handle deleting the Elastic File System.

Delete the IAM role for EFS:

```bash
# Delete IAM role used by Amazon EFS CSI Driver

# IAM Policies must be detached from Roles first
aws iam detach-role-policy --role-name $MY_EFS_CSI_IAM_ROLENAME --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy

# Then delete the IAM Role
aws iam delete-role --role-name $MY_EFS_CSI_IAM_ROLENAME
```

> This is just housekeeping. There is no cost associated with the role's continued existence.
