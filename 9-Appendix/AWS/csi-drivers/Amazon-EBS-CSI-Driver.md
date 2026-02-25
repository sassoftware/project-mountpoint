# Install CSI Driver for AWS Elastic Block Storage volumes (gp3, io2)

This page provides general guidance about installing the Amazon EBS CSI Driver to your EKS cluster. It will:

- define a new IAM role for the driver to use
- create a k8s service account and link it to the IAM role
- use a Helm chart to deploy the Amazon EBS CSI Driver
- attach the IAM policy for EBS to the EKS nodes (so they can use the driver)
- demonstrate how to create storage classes for different EBS storage

## Assumes

These instructions assume:

- the site's EKS cluster has been provisioned already
- the AWS CLI is installed and that the user is logged in
- the kubectl CLI is installed and user has cluster-admin privileges

And finally, the user is expected to have the skillset to modify and debug these steps as needed for their site.

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

1.  Establish attributes we need for EBS CSI driver

    ```bash
    ## AWS: Determine the ARN for my EKS cluster OpenID Connect host
    export OIDC_URL="$(aws eks describe-cluster --name $CLUSTER_NAME --query 'cluster.identity.oidc.issuer' --output text)"
    export OIDC_HOSTNAME="$(echo $OIDC_URL | awk -F/ '{print $5}')"
    export OIDC_REGION="$(echo $OIDC_URL | awk -F. '{print $3}')"
    export OIDC_PROVIDER_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/oidc.eks.${OIDC_REGION}.amazonaws.com/id/${OIDC_HOSTNAME}"

    ## Default values
    export CSI_K8S_SANAME="ebs-csi-controller-sa"
    export CSI_IAM_POLICYARN="arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
    export MY_EBS_CSI_IAM_ROLENAME=${MY_PREFIX}-ebs-csi-controller-role
    ```

1.  Create the new IAM role for the CSI driver

    ```bash
    ## Create the role for EBS CSI driver
    aws iam create-role --role-name ${MY_EBS_CSI_IAM_ROLENAME} --assume-role-policy-document "$(cat <<EOF
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

    # AWS: Attach the AWS EBS CSI driver policy to the role
    aws iam attach-role-policy --role-name "$MY_EBS_CSI_IAM_ROLENAME" --policy-arn "$CSI_IAM_POLICYARN"

    # AWS: Validate the policy is attached to role
    aws iam list-attached-role-policies --role-name "$MY_EBS_CSI_IAM_ROLENAME"
    ```

1.  Create a new service account in Kubernetes that links to the new IAM role with necessary permissions provided.

    ```bash
    # AWS: Get the ARN of the role just created
    CSI_IAM_ROLEARN=$(aws iam get-role --role-name $MY_EBS_CSI_IAM_ROLENAME --output text --query 'Role.Arn')

    # K8s: Create the service account for EBS CSI driver
    kubectl create serviceaccount -n kube-system $CSI_K8S_SANAME

    # K8s: Annotate the service account so it links to the new role
    kubectl annotate serviceaccount -n kube-system $CSI_K8S_SANAME eks.amazonaws.com/role-arn="$CSI_IAM_ROLEARN"
    ```

1.  Helm: deploy aws-ebs-csi-driver to Kubernetes

    ```bash
    # add the AWS EBS CSI Driver repo to Helm
    helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver

    # Update Helms local cache
    helm repo update

    # Initialize
    export EBS_CSI_DRIVER_ENABLED="true"
    export EBS_CSI_DRIVER_NAME="aws-ebs-csi-driver"
    export EBS_CSI_DRIVER_NAMESPACE="kube-system"
    export EBS_CSI_DRIVER_CHART_NAME="aws-ebs-csi-driver"
    export EBS_CSI_DRIVER_CHART_URL="https://kubernetes-sigs.github.io/aws-ebs-csi-driver"
    export EBS_CSI_DRIVER_CHART_VERSION="2.38.1"
    export EBS_CSI_DRIVER_ACCOUNT="$CSI_K8S_SANAME"  # SA created above
    export EBS_CSI_DRIVER_ROLEARN="$CSI_IAM_ROLEARN" # Role created above
    export EBS_CSI_DRIVER_LOCATION="$OIDC_REGION"    # Region of EKS determined above

    # Install the Amazon EBS CSI driver and associate with role
    helm upgrade --install "${EBS_CSI_DRIVER_NAME}" \
    "${EBS_CSI_DRIVER_NAME}/${EBS_CSI_DRIVER_NAME}" \
    --namespace "${EBS_CSI_DRIVER_NAMESPACE}" \
    --version "${EBS_CSI_DRIVER_CHART_VERSION}" \
    --set controller.k8sTagClusterId="${CLUSTER_NAME}" \
    --set controller.region="${EBS_CSI_DRIVER_LOCATION}" \
    --set controller.serviceAccount.create=false \
    --set controller.serviceAccount.name="${EBS_CSI_DRIVER_ACCOUNT}" \
    --set controller.serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${EBS_CSI_DRIVER_ROLEARN}" \
    --set node.serviceAccount.create=true \
    --set node.serviceAccount.name="${EBS_CSI_DRIVER_NAME}-node-sa"
    ```

1.  Validate the aws-ebs-csi-driver is running on all nodes:

    ```bash
    # K8s: get the list of pods with the aws-ebs-csi-driver labels
    kubectl get pod -n kube-system -l "app.kubernetes.io/name=aws-ebs-csi-driver,app.kubernetes.io/instance=aws-ebs-csi-driver"
    ```

1.  Attach policy to role for each k8s node

    ```bash
    # Attach the AWS-managed `AmazonEBSCSIDriverPolicy` to the IAC-provided Roles associated with the instances by their node groups
    bash ${PMP_HOME}/bin/attach-ebscsi-policy.sh
    ```

1.  Define the `gp3` storage class

    ```bash
    mkdir -p ~/project/deploy/

    # define the gp3 storage class - better and cheaper than gp2
    cat << EOF > ~/project/deploy/defineSC_gp3.yaml
    ---
    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
        name: gp3
    provisioner: ebs.csi.aws.com
    volumeBindingMode: WaitForFirstConsumer
    parameters:
        type: gp3
        fsType: ext4
        iops: "3000"      # Match gp2 default peak
        throughput: "250" # Match gp2 default peak
    EOF

    # Apply the manifest to define gp3 storage class
    kubectl apply -f ~/project/deploy/defineSC_gp3.yaml

    # review
    kubectl describe sc gp3
    ```

## Additional tasks

There's more that could be done beyond the bare minimums above.

### > Storage class for `io2` volumes in Amazon EBS

**[Optional:]** Define an `io2` storage class for EBS (faster and more expensive)

A manifest for an `io2` storage class would look nearly identical to the `gp3` one above with different values provided for:
- **name**: `io2` (or your preference)
- **type**: `io2` (required since this is what AWS calls it)
- **iops**: up to 64,000 IOPS
- **throughput**: up to 1,000 MiB/s

### > Managing "default" storage class

If no storage class is mentioned by a PVC, then Kubernetes will look for a storage class annotated as "`default`" and use that.

**[Optional]:** De-annotate the "default" storage class

```sh
# disable the k8s default SC, if there is one 
# (EKS 1.30+ does not define a default, but IAC might)
hasDefaultSC=$(kubectl get sc | grep "(default)")

if [[ "$hasDefaultSC" != "" ]]; then
# found the default storage class
defaultSC=$(echo $hasDefaultSC | awk -F'(' '{print $1}')

echo -e "\n--\nFound default storage class \"$defaultSC\" - disabling it..."

# patch it false
kubectl patch storageclass $defaultSC -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
fi
```

**[Optional]:** Annotate "gp3" as the "default" storage class

You should avoid relying on "default" storage classes. But if you're gonna have one, then "gp3" is better than "gp2".

```sh
# Make gp3 the default
echo -e "\n--\nSetting storage class \"gp3\" as the default..."
kubectl patch storageclass gp3 -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

### > Cleanup

If the Amazon EBS CSI Driver is removed from the cluster (or even if the EKS cluster is terminated), we still need to clean up the IAM role left behind.

```bash
# Delete IAM role used by Amazon EBS CSI Driver

## IAM Policies must be detached from Roles first
aws iam detach-role-policy --role-name $MY_EBS_CSI_IAM_ROLENAME --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy

## Then delete the IAM Role
aws iam delete-role --role-name $MY_EBS_CSI_IAM_ROLENAME
```

> This is just housekeeping. There is no cost associated with the role's continued existence.
