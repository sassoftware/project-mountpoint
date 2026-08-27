# Deploy SAS Viya to AWS with 3 Starter Storage Classes

Let's get this done. This page provides a streamlined deployment of SAS Viya to AWS. We focus on a "happy path" approach that highlights the concept of 3 Starter Storage Classes as outlined in Project Mountpoint.

> Note: This exercise takes an "upside-down" approach to deployment compared to other GEL deployment workshops. We will:
> - get Viya order assets and configure them *first*
> - *then*, provision infrastructure to match Viya's config
> - *and* deploy SAS Viya
>
> In the TOC below, the deployment aspects where Project Mountpoint contributes significantly are marked with "&#9654; PMP". As you can see, it's just a small part of the larger SAS Viya platform implementation.

Here's the plan:

- [Basis](#basis)
- [Reserve a RACE collection](#reserve-a-race-collection)
- [Logon to RACE host(s)](#logon-to-race-hosts)
- [▶ PMP: Clone Project Mountpoint](#-pmp-clone-project-mountpoint)
- [Get Viya resources and assets](#get-viya-resources-and-assets)
    - [Download Viya order assets](#download-viya-order-assets)
    - [▶ PMP: Configure the Viya assets](#-pmp-configure-the-viya-assets)
    - [▷ Status Check](#-status-check)
- [Infrastructure](#infrastructure)
    - [Set up the AWS CLI](#set-up-the-aws-cli)
    - [Identify yourself to AWS](#identify-yourself-to-aws)
    - [Get the SAS Viya 4 Infrastructure-as-Code project](#get-the-sas-viya-4-infrastructure-as-code-project)
    - [Patch viya4-iac-aws for Amazon FSx, if needed](#patch-viya4-iac-aws-for-amazon-fsx-if-needed)
    - [Build the viya4-iac-aws container](#build-the-viya4-iac-aws-container)
    - [Simplify commands](#simplify-commands)
    - [Setup SSH key](#setup-ssh-key)
    - [Which IAC-provisioned shared (RWX) storage?](#which-iac-provisioned-shared-rwx-storage)
    - [Configure Terraform for desired AWS resources](#configure-terraform-for-desired-aws-resources)
    - [Use Terraform to provision infrastructure](#use-terraform-to-provision-infrastructure)
    - [Get k8s clients set up](#get-k8s-clients-set-up)
    - [Enable SSH communication with the IAC-provided jumpbox in AWS](#enable-ssh-communication-with-the-iac-provided-jumpbox-in-aws)
    - [▷ Status Check](#-status-check-1)
- [▶ PMP: Provision and configure storage in AWS](#-pmp-provision-and-configure-storage-in-aws)
    - [AWS provides a storage class out-of-the-box](#aws-provides-a-storage-class-out-of-the-box)
    - [RWO storage for `viya-standard-sc`: Amazon EBS](#rwo-storage-for-viya-standard-sc-amazon-ebs)
    - [Local storage for `viya-scratch-sc`: Rancher local-path](#local-storage-for-viya-scratch-sc-rancher-local-path)
    - [RWX storage for `viya-shared-sc`: NFS Server](#rwx-storage-for-viya-shared-sc-nfs-server)
    - [▷ Status Check](#-status-check-2)
- [Provision and configure supporting 3rd-party resources](#provision-and-configure-supporting-3rd-party-resources)
    - [Deploy GEL's demo LDAP service](#deploy-gels-demo-ldap-service)
    - [Install OpenSSL as the certificate generator](#install-openssl-as-the-certificate-generator)
    - [Confirm files match configuration](#confirm-files-match-configuration)
    - [Install the Kubernetes Cluster Autoscaler](#install-the-kubernetes-cluster-autoscaler)
    - [Install ingress-nginx](#install-ingress-nginx)
    - [Establish a user-friendly DNS alias](#establish-a-user-friendly-dns-alias)
    - [▷ Status Check](#-status-check-3)
- [Deploy the SAS Viya platform](#deploy-the-sas-viya-platform)
    - [Install the Orchestration tool](#install-the-orchestration-tool)
    - [Deploy SAS Viya](#deploy-sas-viya)
    - [▷ Status Check](#-status-check-4)
- [Monitor the start up of SAS Viya services](#monitor-the-start-up-of-sas-viya-services)
    - [K9s](#k9s)
    - [Monitor sas-readiness pod](#monitor-sas-readiness-pod)
- [Validate the SAS Viya platform](#validate-the-sas-viya-platform)
    - [Get a high-level storage report](#get-a-high-level-storage-report)
    - [Check on specific storage resources in Viya's namespace](#check-on-specific-storage-resources-in-viyas-namespace)
    - [Logon to SAS Viya](#logon-to-sas-viya)
    - [As directed](#as-directed)
    - [▷ Status Check](#-status-check-5)
- [Delete your environment](#delete-your-environment)
    - [Uninstall Viya from Amazon EKS](#uninstall-viya-from-amazon-eks)
    - [Destroy cloud resources](#destroy-cloud-resources)
    - [▷ Status Check](#-status-check-6)

## Basis

The deployment process here is heavily borrowed from the [SAS® Viya®: Deployment on Amazon Elastic Kubernetes Service](https://learn.sas.com/course/view.php?id=6972) (learn.sas.com) workshop.

> Currently optimized for SAS Viya at LTS-2026.03 running on Kubernetes 1.32.x - 1.35.x.



Refer to that for explanations and/or help.



## &#9654; PMP: Clone Project Mountpoint

We need the files from this project to help ease the deployment.

As the `cloud-user` on your Linux host in RACE:

```bash
cd $HOME

# Get Project Mountpoint
git clone https://github.com/sassoftware/project-mountpoint.git

# note where
export PMP_HOME=$HOME/project-mountpoint

# Invoke the Recall-My-State feature
source $PMP_HOME/bin/recall_state.sh

# remember it
add_my_var PMP_HOME
```

## Get Viya resources and assets

Let's get SAS Viya order assets and configure them.

### Download Viya order assets

1.  Figure out what to call things and where to put them:

    ```bash
    # as cloud-user on your Linux host in RACE

    # Find out my unique identifier prefix
    export MY_PREFIX=$(cat ~/MY_PREFIX.txt)

    # Pick the name of the namespace for Viya
    export MY_NS=viya

    # Determine the FQDN we want for Viya urls
    export MY_VIYA_FQDN="${MY_PREFIX}-${MY_NS}.aws.example.com"

    # Remember it for later
    add_my_var MY_NS
    add_my_var MY_PREFIX
    add_my_var MY_VIYA_FQDN

    # create the project folder for our Viya collateral
    mkdir -p ~/project/deploy/${MY_NS}/site-config/storage
    ```

1.  Download the SAS Viya order assets

    ```bash
    # Desired version of SAS Viya
    export MY_CADENCE_NAME='lts'
    export MY_CADENCE_VERSION='2026.03'

    # Remember it
    add_my_var MY_CADENCE_NAME
    add_my_var MY_CADENCE_VERSION

    # Generate the sas-bases assets
    bash /opt/gellow_code/scripts/common/generate_sas_bases.sh \
    --cadence-name ${MY_CADENCE_NAME} \
    --cadence-version ${MY_CADENCE_VERSION} \
    --order-nickname 'simple' \
    --output-folder ~/project/deploy/${MY_NS}
    ```

1.  Let's get the actual order number from the downloaded file and then remember all this for later:

    ```bash
    # Parse the order number from the asset file
    export MY_ORDERNUM=$(echo $(ls ~/project/deploy/${MY_NS}/*tgz) | sed 's/^.*SASViyaV4_/SASViyaV4_/' | cut -d "_" -f 2)

    # Remember it
    add_my_var MY_ORDERNUM

    # Say it
    echo "MY_ORDERNUM:" $MY_ORDERNUM
    ```

    > Note, if the value of `$MY_ORDERNUM` is blank or otherwise incorrect, then fix before proceeding.

1.  Confirm the remembered variables can be recalled

    ```bash
    # Recall the variables we need to remember:
    recall
    ```

    With results similar to:

    ```log
    Recalled current workshop state:
    ---
    MY_CADENCE_NAME=lts
    MY_CADENCE_VERSION=2026.03
    MY_NS=viya
    MY_ORDERNUM=9D1ZB7
    MY_PREFIX=envoy-p41814
    MY_VIYA_FQDN=envoy-p41814-viya.aws.example.com
    ---
    ```

    > Note: Remember the "`recall_state.sh`" script we sourced earlier? That provides the functionality to remember variables (add_my_var) and then *recall* their values for later use (e.g., in a different shell later).

### &#9654; PMP: Configure the Viya assets

Now we need to create the required configuration files that will drive SAS Viya's deployment.

1. Create the initial kustomization.yaml file

    ```bash
    # as cloud-user on your Linux host in RACE

    # provide your Viya namespace
    VIYA_NS="$MY_NS"

    # provide your Viya order directory
    VIYA_ORDER_HOME="$HOME/project/deploy/${VIYA_NS}"

    # provide your Viya expected FQDN
    VIYA_FQDN="$MY_VIYA_FQDN"

    # create the new kustomization.yaml
    cat <<-EOF > $VIYA_ORDER_HOME/kustomization.yaml
    namespace: ${VIYA_NS}
    resources:
      - sas-bases/base
      - sas-bases/overlays/network/networking.k8s.io
      - sas-bases/overlays/cas-server
      - sas-bases/overlays/crunchydata/postgres-operator
      - sas-bases/overlays/postgres/platform-postgres
      - sas-bases/overlays/internal-elasticsearch
      - sas-bases/overlays/update-checker
      - sas-bases/overlays/cas-server/auto-resources
      - sas-bases/overlays/sas-workload-orchestrator/cluster-role
    configurations:
      - sas-bases/overlays/required/kustomizeconfig.yaml
    transformers:
      - sas-bases/overlays/internal-elasticsearch/sysctl-transformer.yaml
      - sas-bases/overlays/required/transformers.yaml
      - sas-bases/overlays/cas-server/auto-resources/remove-resources.yaml
      - sas-bases/overlays/internal-elasticsearch/internal-elasticsearch-transformer.yaml
    components:
      - sas-bases/components/crunchydata/internal-platform-postgres
      - sas-bases/components/security/core/base/full-stack-tls
      - sas-bases/components/security/network/networking.k8s.io/ingress/nginx.ingress.kubernetes.io/full-stack-tls
    configMapGenerator:
      - name: ingress-input
        behavior: merge
        literals:
          - INGRESS_HOST=${VIYA_FQDN}
      - name: sas-shared-config
        behavior: merge
        literals:
          - SAS_SERVICES_URL=https://${VIYA_FQDN}
    EOF
    ```

    > Note: This is basically the [initial kustomization.yaml](https://documentation.sas.com/?cdcId=itopscdc&cdcVersion=default&docsetId=dplyml0phy0dkr&docsetTarget=n0g237aqo6pz1in1t19wjb94j9bi.htm) shown in SAS documentation, but improved slightly:
    > - enables the "`sas-workload-orchestrator`" resources to add clusterrole and -binding
    >
    >   for Viya 2025.12 and later, append "`/cluster-role`"
    >
    > - specifies the fully-qualified domain name for ingress host and the SAS services url
    >
    > Additional configuration to kustomization.yaml is provided later as those related elements are deployed.

1.  Get the patches we want for the 3 Starter Storage Classes implementation:

    ```bash
    # Subdirectory for storage config
    mkdir -p ${VIYA_ORDER_HOME}/site-config/storage

    # Copy the 3SSC configuration to your site-config
    cp $PMP_HOME/3SSC-Three-Starter-Storage-Classes/3SSC-transformers.yaml ${VIYA_ORDER_HOME}/site-config/storage
    ```

1. Update kustomization.yaml to reference the new patch file(s):

    ```bash
    # Insert new storage configuration to kustomization.yaml
    
    cd ${VIYA_ORDER_HOME}

    # backup to be safe
    cp -p kustomization.yaml "kustomization.yaml.bak-$(date +%y%m%d%H%M)"

    # Find the line with "required/transformers.yaml"
    index=$(yq eval '.transformers | to_entries | .[] | select(.value == "sas-bases/overlays/required/transformers.yaml") | .key' kustomization.yaml);

    # Add refererence to 3SSC in site-config to kustomization.yaml
    if [[ -f "${VIYA_ORDER_HOME}/site-config/storage/3SSC-transformers.yaml" ]]; then
        # Insert the reference to 3SSC
        yq eval -i ".transformers |= (.[0:${index}] + [\"site-config/storage/3SSC-transformers.yaml\"] + .[${index}:])" kustomization.yaml
    else
        echo "Error: 3SSC-transformers.yaml is not in \"${VIYA_ORDER_HOME}/site-config/storage\" directory." >&2
    fi

    # Verify the update
    icdiff kustomization.yaml.bak*  kustomization.yaml
    ```

    > Note that the README [explains](https://support.sas.com/documentation/installcenter/viya/SASViyaReadMe.htm#sas_programming_environment_storage_tasks) to insert new storage config before the "required" transformers in the `transformers:` section.

### &#9655; Status Check

We've downloaded the SAS Viya order assets and created the configuration files needed for deployment. Viya services that need storage have been configured to use the [3 Starter Storage Classes](/3SSC-Three-Starter-Storage-Classes/):

- "`viya-standard`": block storage for RWO volumes
- "`viya-shared`": network file storage for RWX volumes
- "`viya-scratch`": local disk storage for SASWORK and CAS Cache

This is the point at which a site should ask, "**What storage technology will I provide to service those storage classes?**"

## Infrastructure

The site is responsible to provide infrastructure. SAS personnel might contribute knowledge and expertise, but the site's IT team must maintain ownership and responsibility for implementation and support over time.

SAS provides the IAC project (and knowledge and expertise) to help sites successfully provision the required infrastructure.

The steps in this Infrastructure section then should be (or become) familiar to your site's IT team.

### Set up the AWS CLI

The AWS command-line interface gives us a powerful utility to administer resources in AWS.

1.  Install the AWS CLI command-line utility

    ```bash
    # as cloud-user on your Linux host in RACE

    # Prepare AWS credentials file for use later
    mkdir -p $HOME/.aws
    touch $HOME/.aws/credentials

    # Download the AWS CLI installer package
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"

    # Unzip it
    unzip awscliv2.zip

    # Install
    sudo ./aws/install
    ```

    > This installs the very latest version of the AWS CLI. It is possible to [install older versions](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-version.html), if needed.

1.  Validate:

    ```bash
    # Get the version of the AWS CLI
    aws --version
    ```

    With results similar to:

    ```log
    aws-cli/2.25.5 Python/3.12.9 Linux/3.10.0-1062.12.1.el7.x86_64 exe/x86_64.centos.7
    ```

### Identify yourself to AWS

Let's configure the AWS CLI to know who you are.

First, let's check your credentials in a web browser:

1.  In a web browser, visit the AWS Identity Center using the SAS federated logon: <https://example.awsapps.com/start#>. **Provide your own site credentials** (if prompted).

    > Note: Each site is responsible to provide their own AWS subscription credentials for a real implementation.


1.  Browse to the **AWS Console** site:

    > Note: Each site is responsible to provide their own AWS subscription credentials for a real implementation.

    

    If that worked okay, then let's get signed in with the AWS CLI...

1.  Configure SSO for token renewal

    If you plan on spending more than an hour using this access to AWS, then setup single-signon.

    -   Initiate configuration of single-signon to the AWS Identity Center:

        ```sh
        # invoke the AWS CLI from the viya4-iac-aws container
        aws configure sso  --use-device-code
        ```

    -   Answer the prompts with the following values:

        | Prompt | Response |
        | ------ | -------- |
        | SSO session name: | `default` |
        | SSO start URL: | `https://example.awsapps.com/start#` |
        | SSO region: | `us-east-1` |
        | SSO registration scopes: | `sso:account:access` |

        > Always specify `us-east-1` as the SSO region.

    -   Next, you'll be prompted to authorize the SSO request by visiting a URL similar to <https://example.awsapps.com/start/#/device>.

        On the resulting web page, enter the 9-character code provided to you in the terminal. Then click to Allow access.

        Once the authentication is complete, you can close that browser window.

    -   The configuration continues with more prompts from the AWS CLI:

        | Prompt | Response |
        | ------ | -------- |
        | Role name: | `Example` |
        | CLI default client region: | `us-east-1` |
        | CLI default output format: | `json` |
        | CLI profile name: | `default` |

    -   When the SSO configuration is complete, the resulting profile definition is stored in `/home/cloud-user/.aws/config`.

1.  Disable the system pager for long AWS CLI output

    ```bash
    # Set the pager value to null
    aws configure set cli_pager ""
    ```

    > Prevents pagination from interrupting info collection. Specify "less" or "more" or any other pager utility, if preferred.

1.  Remember the AWS region specified

    ```bash
    # Which AWS region?
    MY_REGION=$(grep "^region" ~/.aws/config | head -1 | awk '{ print $3 }')

    # Remember it
    add_my_var MY_REGION
    ```

1.  Validate signon

    Confirm that the AWS-CLI has access to your AWS configuration:

    ```sh
    # confirm your identity to AWS
    aws sts get-caller-identity

    # confirm configuration of the AWS CLI
    aws configure list
    ```

    Results similar to:

    ```log
    $ aws sts get-caller-identity
    {
        "UserId": "AROASVxxxxxxAAEJJ3TO4:your.name@site.com",
        "Account": "1826xxx77754",
        "Arn": "arn:aws:sts::1826xxx77754:assumed-role/AWSReservedSSO_Example_2794963200b1xxx/your.name@site.com"
    }

    $ aws configure list
            Name                    Value             Type    Location
            ----                    -----             ----    --------
        profile                <not set>             None    None
    access_key     ****************GVPL              sso
    secret_key     ****************DeSY              sso
        region                us-east-1      config-file    ~/.aws/config
    ```

    More information about [token provider configuration with automatic authentication refresh](https://docs.aws.amazon.com/cli/latest/userguide/sso-configure-profile-token.html) is available in the AWS docs.

At this point, you're signed into AWS with your own credentials. SAS employees are using the SAS-provided subscription with _AWSReservedSSO_ signon.

### Get the SAS Viya 4 Infrastructure-as-Code project

Clone the viya4-iac-aws project and build the Docker container [viya4-iac-aws](https://github.com/sassoftware/viya4-iac-aws/blob/main/docs/user/DockerUsage.md) we'll use:

```bash
# clone the viya4-iac-aws repo
cd ~
git clone https://github.com/sassoftware/viya4-iac-aws

cd ~/viya4-iac-aws

# If needed, pin to a specific version
#git checkout 8.8.0
```

### Patch viya4-iac-aws for Amazon FSx, if needed

> **This is an optional step** - but it is ***required*** if you intend to use the IAC to provision Amazon FSx for NetApp ONTAP resources.

&star; Perform the tasks to [Patch IAC FSx module for IAM Policy](https://your-git-repo.example.com/GEL/workshops/Your_Project_Name-sas-viya-4-deployment-on-amazon-elastic-kubernetes-service/-/blob/main/07-Experimental/07-100-Storage_Patterns/07-110-Provision_Infrastructure/12-Get-viya4-iac-aws.md).

Then return here and continue.

### Build the viya4-iac-aws container

It's a proven practice to build the viya4-iac-aws container to take advantage of its resources operating as known-good versions.

1. Build the viya4-iac-aws container

    ```bash
    # Build the viya4-iac-aws container
    docker build -t viya4-iac-aws .
    ```

    > Note: Building the container will take around a couple of minutes or so to complete.

1.  Try running the viya4-iac-aws container

    ```bash
    # Does it work?
    docker container run --rm -it viya4-iac-aws -version
    ```

    Results similar to:

    ```log
    Terraform v1.10.5
    on linux_amd64
    + provider registry.terraform.io/hashicorp/aws v5.92.0
    + provider registry.terraform.io/hashicorp/cloudinit v2.3.6
    + provider registry.terraform.io/hashicorp/external v2.3.4
    + provider registry.terraform.io/hashicorp/kubernetes v2.36.0
    + provider registry.terraform.io/hashicorp/local v2.5.2
    + provider registry.terraform.io/hashicorp/null v3.2.3
    + provider registry.terraform.io/hashicorp/random v3.7.1
    + provider registry.terraform.io/hashicorp/time v0.13.0
    + provider registry.terraform.io/hashicorp/tls v4.0.6
    ```

    > *Note: Terraform is the default entry point of the container. And because we requested the version, it shows its own version as well as the other components it relies on.*

### Simplify commands

Let's simplify the Docker commands we're going to use to run utilities inside the viya4-iac-aws container.

At this point, you certainly understand we're running Terraform CLI utilities inside of the `viya4-iac-aws` Docker container. That syntax is hard to remember and also difficult to compare to product documentation. Let's define aliases for them instead:

```bash
# Use an alias to reduce the complexity of running inside a container
alias terraform="docker container run --rm --group-add root --user $(id -u):$(id -g) -v $HOME/.aws:/.aws -v $HOME/.ssh:/.ssh -v $HOME/viya4-iac-aws:/workspace --entrypoint terraform viya4-iac-aws"

# Remember it
add_my_alias terraform

# Try it out
terraform --version
```

Results similar to:

```log
$ terraform --version
Terraform v1.10.5
on linux_amd64
+ provider registry.terraform.io/hashicorp/aws v5.92.0
+ provider registry.terraform.io/hashicorp/cloudinit v2.3.6
+ provider registry.terraform.io/hashicorp/external v2.3.4
+ provider registry.terraform.io/hashicorp/kubernetes v2.36.0
+ provider registry.terraform.io/hashicorp/local v2.5.2
+ provider registry.terraform.io/hashicorp/null v3.2.3
+ provider registry.terraform.io/hashicorp/random v3.7.1
+ provider registry.terraform.io/hashicorp/time v0.13.0
+ provider registry.terraform.io/hashicorp/tls v4.0.6
```

> From now on, we'll use the alias for Terraform. But you still need to remember that it's really running *inside* a Docker container.

### Setup SSH key

The IAC will create machines in AWS which can be accessed with cloud-user's default SSH key (`~/.ssh/id_rsa`). So create that now.

```bash
# ensure there is a .ssh dir in $HOME
ansible localhost -m file \
  -a "path=$HOME/.ssh mode=0700 state=directory"

# ensure there is an ssh key that we can use
ansible localhost -m openssh_keypair \
  -a "path=~/.ssh/id_rsa type=rsa size=2048" --diff
```

> *Note: The resulting `~/.ssh/id_rsa` file is referenced by default when `ssh`'ing, unless a different file is specified using the `-i` switch.*

### Which IAC-provisioned shared (RWX) storage?

The viya4-iac-aws project offers [three main options for shared (RWX) storage](https://github.com/sassoftware/viya4-iac-aws/blob/main/docs/CONFIG-VARS.md#storage).

**Select one of the following** and execute the command given to set an environment variable with the appropriate IAC parameters:

-   Basic, no-frills NFS Server   **<<== PICK THIS ONE**

    ```sh
    RWX_STORAGE_PROVIDER=$(cat << 'EOF'
    # Basic NFS Server for RWX volumes
    storage_type             = "standard"
    create_nfs_public_ip     = false
    nfs_vm_admin             = "nfsuser"
    nfs_raid_disk_size       = 128
    nfs_raid_disk_type       = "gp2"     # or io1/2, sc1, st2, standard
    nfs_raid_disk_iops       = 0         # for io1/2 only
    EOF
    )
    ```

    > Note: I haven't added the necessary decisions/actions for the other storage to this exercise yet - but I have thoroughly tested them all. :)

-   Amazon Elastic File Storage (EFS)

    ```sh
    RWX_STORAGE_PROVIDER=$(cat << 'EOF'
    # Amazon EFS for RWX volumes
    storage_type                            = "ha"
    efs_performance_mode                    = "generalPurpose"
    EOF
    )
    ```

-   Amazon FSx for NetApp ONTAP (FSx)

    ```sh
    RWX_STORAGE_PROVIDER=$(cat << 'EOF'
    # Amazon FSx for NetApp ONTAP for RWX volumes
    storage_type                                   = "ha"
    storage_type_backend                           = "ontap"
    aws_fsx_ontap_deployment_type                  = "SINGLE_AZ_1"     # or MULTI_AZ_1
    aws_fsx_ontap_file_system_storage_capacity     = "1024"            # up to 196608
    aws_fsx_ontap_file_system_throughput_capacity  = "512"             # up to 4096
    aws_fsx_ontap_fsxadmin_password                = "ThePowerToKnow123!"
    EOF
    )
    ```

    > Reminder to perform the tasks to [Patch IAC FSx module for IAM Policy](https://your-git-repo.example.com/GEL/workshops/Your_Project_Name-sas-viya-4-deployment-on-amazon-elastic-kubernetes-service/-/blob/main/07-Experimental/07-100-Storage_Patterns/07-110-Provision_Infrastructure/12-Get-viya4-iac-aws.md) (including rebuilding the IAC container) if using FSx storage.

### Configure Terraform for desired AWS resources

The IAC is driven by a terraform variables file that we must create. As shown here, we've made selections that will support the 3 Starter Storage Classes paradigm to provide shared (RWX) storage and local disk storage.

> Note: Block storage (Amazon EBS) is *not* addressed by the IAC project. We will set that up for ourselves that later.

1.  Create the TF Vars file to drive infrastructure:

    ```bash
    K8S_VERSION="1.33"

    # Create the Terraform variables file for the IAC
    cat << EOF > ~/viya4-iac-aws/${MY_PREFIX}.tfvars
    # REQUIRED VARIABLES
    # Necessary for use by the IAC
    # --------------------------------------
    # - Prefix is used for naming resources for easy identification
    # - Location is the geo region where resources will be placed
    #
    prefix                                  = "$MY_PREFIX"
    location                                = "$MY_REGION" 

    # ACCESS, IDENTITY, and AUTHENTICATION
    # Who is doing what where
    # --------------------------------------
    #
    aws_profile                             = "default"            # or whatever you named it
    ssh_public_key                          = "~/.ssh/id_rsa.pub"
    create_static_kubeconfig                = true

    # CIDR
    # Specify public access CIDR to allow ingress traffic to the EKS cluster
    # --------------------------------------
    # - Define access from your clients network IP address range(s)
    #
    default_public_access_cidrs         = ["192.0.2.0.0/16", "198.551.100.102.80/32", "198.551.100.102.81/32"]

    # TAGS
    # Optional metadata associated with AWS resources
    # --------------------------------------
    # - Resourceowner makes it easy to find associated resources
    # - Project_Name and GEL_Project are for tracking
    # - Chronos (old) and Smart Parking (new) are programs to auto-shutdown resources
    #
    tags = { "resourceowner"          = "$MY_PREFIX", 
            "project_name"           = "Your_Project_Name", 
            "gel_project"            = "Your_Project_Name", 
            "disable_chronos"        = "True", 
            "smart_parking_disabled" = "True" 
        }

    # EXTERNAL POSTGRES SERVER
    # --------------------------------------
    # - if defined, creates an External Postgres Server in AWS, else use internal Crunchy
    #
    #postgres_servers = {
    #  default = {},
    #}

    ## Cluster config
    kubernetes_version                      = "$K8S_VERSION"

    default_nodepool_node_count             = 2
    default_nodepool_vm_type                = "m7i-flex.2xlarge"
    default_nodepool_custom_data            = ""

    ## Shared storage provider
    $RWX_STORAGE_PROVIDER

    ## Cluster Node Pools config
    node_pools = {
        cas = {
            "vm_type" = "r6idn.2xlarge"                        # includes local NVMe
            "cpu_type"     = "AL2023_x86_64_STANDARD"
            "os_disk_type" = "gp3"
            "os_disk_size" = 200
            "os_disk_iops" = 0
            "min_nodes" = 4
            "max_nodes" = 5
            "node_taints" = ["workload.sas.com/class=cas:NoSchedule"]
            "node_labels" = {
            "workload.sas.com/class" = "cas"
            "attr.sas.com/local-nvme" = "true"
            }
            "custom_data" = ""
            "metadata_http_endpoint"               = "enabled"
            "metadata_http_tokens"                 = "required"
            "metadata_http_put_response_hop_limit" = 1
        },
        compute = {
            "vm_type" = "r6idn.4xlarge"                        # includes local NVMe
            "cpu_type"     = "AL2023_x86_64_STANDARD"
            "os_disk_type" = "gp3"
            "os_disk_size" = 200
            "os_disk_iops" = 0
            "min_nodes" = 1
            "max_nodes" = 5
            "node_taints" = ["workload.sas.com/class=compute:NoSchedule"]
            "node_labels" = {
            "workload.sas.com/class"        = "compute"
            "launcher.sas.com/prepullImage" = "sas-programming-environment"
            "attr.sas.com/local-nvme" = "true"
            }
            "custom_data" = ""
            "metadata_http_endpoint"               = "enabled"
            "metadata_http_tokens"                 = "required"
            "metadata_http_put_response_hop_limit" = 1
        },
        stateless = {
            "vm_type" = "m7i-flex.4xlarge"
            "cpu_type"     = "AL2023_x86_64_STANDARD"
            "os_disk_type" = "gp3"
            "os_disk_size" = 200
            "os_disk_iops" = 0
            "min_nodes" = 1
            "max_nodes" = 5
            "node_taints" = ["workload.sas.com/class=stateless:NoSchedule"]
            "node_labels" = {
            "workload.sas.com/class" = "stateless"
            }
            "custom_data" = ""
            "metadata_http_endpoint"               = "enabled"
            "metadata_http_tokens"                 = "required"
            "metadata_http_put_response_hop_limit" = 1
        },
        stateful = {
            "vm_type" = "m7i-flex.4xlarge"
            "cpu_type"     = "AL2023_x86_64_STANDARD"
            "os_disk_type" = "gp3"
            "os_disk_size" = 200
            "os_disk_iops" = 0
            "min_nodes" = 1
            "max_nodes" = 3
            "node_taints" = ["workload.sas.com/class=stateful:NoSchedule"]
            "node_labels" = {
            "workload.sas.com/class" = "stateful"
            }
            "custom_data" = ""
            "metadata_http_endpoint"               = "enabled"
            "metadata_http_tokens"                 = "required"
            "metadata_http_put_response_hop_limit" = 1
        }
    }

    # Jump Server
    create_jump_vm                        = true
    jump_vm_admin                         = "jumpuser"
    jump_vm_type                          = "t3.small"
    EOF
    ```

    > Note, this specifies:
    > - 200GB OS disk as `gp3` volumes
    > - Your choice for `RWX_STORAGE_PROVIDER` has been included
    > - Instance types with local disk are specified for CAS and Compute, including labels we can use to identify them.

### Use Terraform to provision infrastructure

With the terraform variables all defined, now we can provision the infrastructure in AWS.

1.  Generate the Terraform plan

    ```sh
    # direct terraform to create a plan, runs in seconds
    terraform plan \
        -input=false \
        -var-file=/workspace/${MY_PREFIX}.tfvars \
        -out /workspace/${MY_PREFIX}.tfplan
    ```

1.  Apply the Terraform plan:

    ```bash
    # direct terraform to apply the plan to provision resources in AWS 
    time terraform apply -state /workspace/${MY_PREFIX}.tfstate "/workspace/${MY_PREFIX}.tfplan"
    ```

    ---

    <details>
    <summary>Terraform failure? Click here.</summary>

    Sometimes Terraform gets hung up in cross-dependencies, failing to generate a kubeconfig file. The workaround is to re-plan at the current state and re-apply. (see [Issue 384](https://github.com/sassoftware/viya4-iac-aws/issues/384))

    Re-`plan` and re-`apply`:

    ```sh
    # re-plan (and include the current state)
    terraform plan \
        -input=false \
        -var-file=/workspace/${MY_PREFIX}.tfvars \
        -state /workspace/${MY_PREFIX}.tfstate \
        -out /workspace/${MY_PREFIX}.tfplan

    # re-apply the updated plan
    terraform apply -state /workspace/${MY_PREFIX}.tfstate "/workspace/${MY_PREFIX}.tfplan"
    ```

    </details>

    ---

It will take 20-30 minutes for Terraform to complete the provisioning of resources in AWS.

### Get k8s clients set up

1.  Use terraform to create a kubeconfig file

    ```bash
    cd ~/viya4-iac-aws

    # direct terraform to create a kubectl configuration file
    terraform output -state /workspace/${MY_PREFIX}.tfstate -raw kube_config > ${MY_PREFIX}.kube.conf

    # Create the .kube directory in your home directory
    mkdir -p ~/.kube

    # Copy kubeconfig to its default location
    cp -p ./${MY_PREFIX}.kube.conf   ~/.kube/config
    chmod 600 ~/.kube/config
    ```

1.  Update kubectl to match the Kubernetes server version

    Kubectl is already installed on your Linux host in RACE, but it's old and not within the [accepted skew range](https://kubernetes.io/releases/version-skew-policy/). Let's update it to match the version running in EKS.

    ```bash
    # Get the Kubernetes version
    MAJOR_EKS_VER=$(aws eks describe-cluster --name ${MY_PREFIX}-eks --query 'cluster.version' --output text)

    FULL_EKS_VER=$(aws eks describe-addon-versions --addon-name kube-proxy --kubernetes-version ${MAJOR_EKS_VER} --query 'addons[0].addonVersions[0].addonVersion' --output text | cut -d'-' -f1)

    echo -e "Kubernetes version = $FULL_EKS_VER\n\n"
    ```

    Install the equivalent version of `kubectl` to run locally:

    ```bash
    # Get kubectl from its home site
    curl -LO https://dl.k8s.io/release/${FULL_EKS_VER}/bin/linux/amd64/kubectl

    # Install the new kubectl binary to the system:
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

    # Verify our new local install of `kubectl` is working:
    kubectl version
    ```

    With results similar to:

    ```log
    Client Version: v1.32.9
    Kustomize Version: v5.5.0
    Server Version: v1.32.9-eks-3025e55
    ```

    > Note: The Client version and Server version numbers should match now.

1.  Install K9s from its [home web site](https://webinstall.dev/k9s/):

    ```bash
    # Execute the installer script
    curl -sS https://webi.sh/k9s | sh

    # Get the K9s environment variables
    source ~/.config/envman/PATH.env
    ```

    ---

    <details>
    <summary>Optional: Modify the k9s color palette</summary>

    For this next step to work, you must launch and quit `k9s` first. That way, the config.yaml file will exist to edit.

    ```sh
    # K9s auto-creates its own config file at first launch
    # timeout 2s k9s

    K9S_SKIN="transparent"

    # Download the skin definition file for a better color palette
    wget https://raw.githubusercontent.com/derailed/k9s/refs/heads/master/skins/${K9S_SKIN}.yaml -O /home/cloud-user/.config/k9s/skins/${K9S_SKIN}.yaml

    # Configure k9s to use it
    yq -i ".k9s.ui.skin = \"${K9S_SKIN}"\" /home/cloud-user/.config/k9s/config.yaml
    ```

    Refer to the [K9s documentation](https://k9scli.io) for more information.

    </details>

    ---

### Enable SSH communication with the IAC-provided jumpbox in AWS

The IAC optionally provides a jumpbox as a touchpoint for working with protected resources in AWS. We cannot SSH to it directly from a RACE host (due to RACE rules), so instead we will [enable Amazon EC2 Instance Connect](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/connect-linux-inst-eic.html) to talk to it.

1.  Provide an Inbound Rule in the security group to allow SSH communication to the jumpbox from the region where the EC2 Instance Connect will run.

    Identify the current AWS security group:

    ```bash
    # IAC names the primary security group with MY_PREFIX
    mySGname="${MY_PREFIX}-sg"

    # Use the sg's name to get its unique id
    # https://docs.aws.amazon.com/cli/latest/reference/ec2/describe-security-groups.html
    mySGid=`aws ec2 describe-security-groups --query "SecurityGroups[*].{GroupName:GroupName,GroupId:GroupId}" --filter "Name=group-name,Values=${mySGname}" | grep GroupId | awk -F\" {'print $4'}`

    # Verify values
    echo "Security group name: $mySGname, Security group id: $mySGid"
    ```

    Determine the IP prefix for EC2 Instance Connect in the current region:

    ```bash
    # list of AWS IP ranges
    URL="https://ip-ranges.amazonaws.com/ip-ranges.json"

    # Name for EC2 Instance Connect service
    SERVICE_NAME="EC2_INSTANCE_CONNECT"

    # Use curl to fetch the JSON content and pipe it to jq for filtering
    ip_prefix=$(curl -s "$URL" | \
    jq -r --arg service_arg "$SERVICE_NAME" --arg region_arg "$MY_REGION" \
        '.prefixes[] | select(.service == $service_arg and .region == $region_arg) | .ip_prefix')

    # Print the found IP prefix
    if [ -n "$ip_prefix" ]; then
        echo -e "\nIP Prefix for $SERVICE_NAME in $MY_REGION: $ip_prefix"
        else
        echo -e "\nNo IP Prefix found for $SERVICE_NAME in $MY_REGION."
    fi
    ```

    Add an inbound rule to allow EC2 Instance Connect in this region:

    ```bash
    # Add inbound rule for EC2 Instance Connect
    # https://docs.aws.amazon.com/cli/latest/reference/ec2/authorize-security-group-ingress.html
    aws ec2 authorize-security-group-ingress \
        --group-id $mySGid \
        --ip-permissions "IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges=[{CidrIp=${ip_prefix},Description=${MY_REGION} EC2 Instance Connect}]"
    ```

### &#9655; Status Check

We've stood up the core infrastructure in AWS in alignment with our planned configuration of SAS Viya. And we've set up Kubernetes clients to give us administration and monitoring. But there's more yet to do...

## &#9654; PMP: Provision and configure storage in AWS

At the risk of repetition, the site is responsible for providing storage that meets Viya's requirements. This section shows an approach where the site has evaluated Viya's use of storage and selected appropriate technologies. We show installing CSI Drivers and such because you need to see it. However, to be clear, the ideal is that the site will do this work, including validating that it's all working properly *before* attempting to use it for Viya's services.

> Note: Project Mountpoint's contribution here is the idea of *copying* storage classes. By giving Viya its own set of storage class names, we abstract Viya's config from the physical implementation. This isn't required - the site is free to use any names for storage classes it wants - but the additional layer of abstraction gives us another aspect of control.

The IAC will setup your choice of supported shared (RWX) storage provider. But we also need CSI drivers and other resources. Some of these would be handled automatically by the DAC project, but we're not using that here.

1.  We will make copies of storage classes. To help aid that task:

    ```bash
    # define the "copysc" function 
    source $HOME/project-mountpoint/bin/copySC.sh
    ```

### AWS provides a storage class out-of-the-box

AWS provides an RWO storage class for immediate use of Amazon Elastic Block Storage.

1. Let's see what's there:

    ```bash
    $ kubectl get sc

    NAME                     PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
    gp2 (default)            kubernetes.io/aws-ebs   Delete          WaitForFirstConsumer   false                   27m
    ```

    > Note that the "`gp2`" storage class relies on the legacy, deprecated in-tree provisioner that's provided by Kubernetes. And it's annotated as "default" not by Amazon, but by the IAC project.

1.  Disable any storage class that's annotated as "default"

    ```bash
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

    > Note: if a PVC doesn't specify a storage class, then Kubernetes will automatically use one that's annotated as a "default". SAS should neither expect nor require the use of a "default" storage class. So, in our test environment, we won't have one. That way, if we somehow miss a storage definition in our config, then it will fail and we can find it to fix it.
    >
    > In the real world, if a site wants to have a "default"-annotated storage class, that's fine.

### RWO storage for `viya-standard-sc`: Amazon EBS

The "viya-standard-sc" storage class is intended for use by [services that need persistent RWO volumes](/3SSC-Three-Starter-Storage-Classes/). SAS Viya services like Crunchy Postgres, RabbitMQ, Redis, Consul, and OpenSearch all need persistent RWO volumes.

[Amazon Elastic Block Store (EBS) offers several storage types](https://docs.aws.amazon.com/ebs/latest/userguide/ebs-volume-types.html) for this, including gp2, gp3, io1, io2 Block Express, st1, sc1, etc. In this section, we will install the Amazon EBS CSI Driver and define a "`gp3`" storage class. You can expand its use with additional storage classes for "`io2`" or others as needed.

1.  Establish attributes we need for EBS CSI driver

    ```bash
    ## AWS: Get Account ID
    export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

    ## AWS: Determine the ARN for my EKS cluster OpenID Connect host
    export OIDC_URL="$(aws eks describe-cluster --name ${MY_PREFIX}-eks --query 'cluster.identity.oidc.issuer' --output text)"
    export OIDC_HOSTNAME="$(echo $OIDC_URL | awk -F/ '{print $5}')"
    export OIDC_REGION="$(echo $OIDC_URL | awk -F. '{print $3}')"
    export OIDC_PROVIDER_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/oidc.eks.${OIDC_REGION}.amazonaws.com/id/${OIDC_HOSTNAME}"

    ## Default values
    export CSI_K8S_SANAME="ebs-csi-controller-sa"
    export CSI_IAM_POLICYARN="arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
    export MY_EBS_CSI_IAM_ROLENAME=${MY_PREFIX}-ebs-csi-controller-role

    # Remember it for later
    ansible localhost -m lineinfile \
        -a "dest=/home/cloud-user/RECALL_MY_STATE \
            regexp='^export MY_EBS_CSI_IAM_ROLENAME' \
            line='export MY_EBS_CSI_IAM_ROLENAME=${MY_EBS_CSI_IAM_ROLENAME}' \
            insertbefore='### END OF MY STATE ###'" \
            --diff
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
            "oidc.eks.${MY_REGION}.amazonaws.com/id/${OIDC_HOSTNAME}:sub": "system:serviceaccount:kube-system:$CSI_K8S_SANAME",
            "oidc.eks.${MY_REGION}.amazonaws.com/id/${OIDC_HOSTNAME}:aud": "sts.amazonaws.com"
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
    --set node.serviceAccount.name="${EBS_CSI_DRIVER_NAME}-node-sa" \
    --wait

    # Verify the list of pods with the aws-ebs-csi-driver labels
    kubectl get pod -n kube-system -l "app.kubernetes.io/name=aws-ebs-csi-driver,app.kubernetes.io/instance=aws-ebs-csi-driver"
    ```

1.  Attach policy to role for each k8s node

    ```bash
    # Attach the AWS-managed `AmazonEBSCSIDriverPolicy` to the IAC-provided Roles associated with the instances by their node groups
    bash $HOME/project-mountpoint/bin/attach-ebscsi-policy.sh
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

    > Note: The **gp3** storage class provides RWO block storage. That will be the basis for the **viya-standard-sc** storage class we configured some Viya services to use in the site-config.

1.  &#9654; PMP: Copy the `gp3` storage class to make `viya-standard-sc`:

    ```bash
    cd ~/project/deploy/$MY_NS

    # Make a copy
    copysc gp3 viya-standard-sc
    ```

1.  Review the resulting file `defineSC_viya-standard-sc.yaml`:

    ```yaml
    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
        name: viya-standard-sc
    parameters:
        fsType: ext4
        iops: "3000"
        throughput: "125"
        type: gp3
    provisioner: ebs.csi.aws.com
    reclaimPolicy: Delete
    volumeBindingMode: WaitForFirstConsumer
    ```

    Edit the file to make any desired changes.

1.  When it's acceptable, then create the viya-standard-sc storage class in the EKS cluster:

    ```bash
    # Apply the storage class definition
    kubectl apply -f defineSC_viya-standard-sc.yaml
    ```

### Local storage for `viya-scratch-sc`: Rancher local-path

The "viya-scratch-sc" storage class is intended for use by [SASWORK and CAS_DISK_CACHE](/3SSC-Three-Starter-Storage-Classes/). SAS Programming Runtime Environment (including SAS Batch, SAS Compute, and SAS Connect Servers) and the SAS Cloud Analytic Services (CAS) rely on this space for low-latency and high-throughput - something local disk in the cloud does well for little additional cost.

There are several ways to provide Kubernetes with access to local disk, but for this effort we want a CSI Driver that can *dynamically* provision volumes on local disk. In this section, we'll set up [Rancher Local Path Provisioner](https://github.com/rancher/local-path-provisioner), but it's just an example. Projects like OpenEBS and Portworx are acceptable, too.

Local disk on a node is not a given. It takes extra steps for a site to format and mount the local disk for use. But it's worth the extra effort.

1.  Create daemonSet to format and mount local NVMe drives

    For the "CAS" and "Compute" node pool definitions, we specified instance types in the IAC that include local NVMe disk. And we gave them special labels `attr.sas.com/local-nvme=true` that are used in the `nodeSelector:` directives to target those nodes.

    ```bash
    # Deploy a daemonSet to format and mount local disk
    bash $HOME/project-mountpoint/bin/deploy-nvme-daemonset.sh
    ```

    With results ending:

    ```log
    NAME           DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR                  AGE
    nvme-mounter   5         5         5       5            5           attr.sas.com/local-nvme=true   10s
    ```

    > Note: We configured Terraform to provide 1 SPRE node and 4 CAS nodes using instance types with local disk. `1+4=5`.

1.  Install the Rancher project local-path-provisioner

    ```bash
    # Install local-path latest
    kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
    ```

    ---

    <details>
    <summary>Click here for alternative to support ESM (step 1 of 2)</summary>

    ESM relies on hostPath to monitor activity in SASWORK. This approach will define a simple, static path to the top-level SASWORK location (not uniquely named for PVC) so ESM can find things.

    ```bash
    # Install local-path v0.0.29
    kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.29/deploy/local-path-storage.yaml
    ```

    > Note the use of v0.0.29 as a workaround so that it doesn't enforce the PVC_ID in the path name for uniqueness.

    </details>

    ---

    The `local-path` SC is automatically defined:

    ```sh
    # Automatically creates the `local-path` SC, too
    kubectl describe sc local-path
    ```

    > Note that the base directory path defaults to `/opt/local-path-provisioner/` on the node.

1. We need a custom path to use `/viya-scratch`. Modify the configMap:

    ```sh
    # Open an editor to local-path CSI driver's configMap
    kubectl edit configmap local-path-config -n local-path-storage
    ```

    Replace the default path "`/opt/local-path-provisioner`" with our new mounted volume "`/viya-scratch`". And save the file.

    Alternatively, here's a single command to patch it:

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

1.  &#9654; PMP: Copy the `local-path` storage class to make `viya-scratch-sc`:

    ```bash
    # Make a copy
    copysc local-path viya-scratch-sc
    ```

1.  Review resulting file `defineSC_viya-scratch-sc.yaml`:

    ```yaml
    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
        name: viya-scratch-sc
    provisioner: rancher.io/local-path
    reclaimPolicy: Delete
    volumeBindingMode: WaitForFirstConsumer
    ```

    Edit the file to make any desired changes.

    ---

    <details>
    <summary>Click here for alternative to support ESM (step 2 of 2)</summary>

    ESM relies on hostPath to monitor activity in SASWORK. This approach will define a simple, static path to the top-level SASWORK location (not uniquely named for PVC) so ESM can find things.

    ```bash
    # In this scenario, we do not want pod termination to trigger
    # the deletion of the directory on-disk.
    yq eval '.reclaimPolicy = "Retain"' -i ./defineSC_viya-scratch-sc.yaml

    # Modify the default on-disk path used for new PV to "saswork"
    # SPRE already guarantees a unique subdir path for SASWORK amd ECE_CACHE
    yq eval '.parameters.pathPattern = "saswork"' -i ./defineSC_viya-scratch-sc.yaml

    # Note the default (implied) value for reference
    yq eval '. head_comment="pathPattern default: ${PVC_UUID}_${PV_NAME}"' -i ./defineSC_viya-scratch-sc.yaml
    ```

    > Note that Rancher local-path default is effectively "`/viya-scratch/{{PVC_UUID}}/{{PVC_NAME}}`". We're changing it to drop the PV identifiers to simply use "`/viya-scratch/saswork`".
    >
    > This change accommodates ESM's expectation that it can monitor SASWORK activity by using a hostPath definition with the same path that SPRE uses for SASWORK. We're using a GeV (not hostPath) for SASWORK but with this static directory naming convention, then ESM using hostPath can find SASWORK files.

    </details>

    ---

1.  When it's acceptable, then apply it:

    ```bash
    # Apply the storage class definition
    kubectl apply -f defineSC_viya-scratch-sc.yaml
    ```

### RWX storage for `viya-shared-sc`: NFS Server

The "viya-shared-sc" storage class is intended for use by [services that need persistent RWX volumes](/3SSC-Three-Starter-Storage-Classes/). SAS Viya services like sas-backup-job, sas-common-files, sas-pyconfig and others all need persistent RWX volumes so that multiple pods running on different nodes can access the same set of shared files.

The IAC for AWS provides three options of RWX storage that it can provide. We'll go with the NFS Server option here for simplicity. But for robust production use, consider using Amazon FSx for NetApp ONTAP or with Amazon Elastic File Storage (EFS) instead.

1.  Install the NFS CSI Driver

    ```bash
    # Install
    curl -skSL https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/v4.11.0/deploy/install-driver.sh | bash -s v4.11.0 --
    ```

1.  Modify the NFS CSI Driver's `Fs Group Policy` attribute from default "`File`" to "`None`":

    ```bash
    # Prevent CSI Driver from changing file permissions
    kubectl patch csidriver nfs.csi.k8s.io -p '{"spec":{"fsGroupPolicy": "None"}}'

    # Verify
    kubectl describe csidriver nfs.csi.k8s.io
    ```

    > Recursive permission changes for the 80,000 files in the `python-volume` can cause timeouts waiting for SAS Programming Runtime servers to start. So, we disable that as an attribute of the CSI driver.
    >
    > For more information, see: microsoft.com &gt; [How to disable recursive group change (fsGroupPolicy) in Azure File CSI Driver on AKS](https://learn.microsoft.com/en-us/answers/questions/2277901/how-to-disable-recursive-group-change-%28fsgrouppoli)

1.  Define storage class "`nfs`"

    ```bash
    # identify my NFS server (from IAC):
    export NFS_IP=`terraform output -state /workspace/${MY_PREFIX}.tfstate -raw rwx_filestore_endpoint`
    echo -e "\n==> NFS_IP = $NFS_IP"

    #NFS_Path="/export/pvs"     # old provisioner
    NFS_Path="/export"          # csi
    NFS_NS="nfs"

    cat << EOF > ~/project/deploy/defineSC_nfs.yaml
    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
        name: ${NFS_NS}
    provisioner: nfs.csi.k8s.io
    parameters:
        server: ${NFS_IP}
        share: ${NFS_Path}
        subDir: "pvs/\${pvc.metadata.namespace}-\${pvc.metadata.name}"   # creates a unique subdir per PVC (resolved by CSI provisioner)
        mountPermissions: "0777"                 # sets permissions on the mount (resolved by CSI provisioner)
    reclaimPolicy: Retain
    volumeBindingMode: WaitForFirstConsumer
    mountOptions:
    #    - vers=4.1
        - noatime
        - nodiratime
        - 'rsize=262144'
        - 'wsize=262144'
        - nolock         # need to get NFS Server set with lock svc?
    EOF

    # Apply to k8s
    kubectl apply -f ~/project/deploy/defineSC_nfs.yaml

    # Validate
    kubectl describe sc nfs
    ```

    > Note that, unlike the local-path-provisioner, the base directory path is defined here in the storage class. We chose a path and naming convention here that matches with the `viya4-deployment` project's approach when using the legacy nfs-subdir-external-provisioner.

1.  &#9654; PMP: Copy the `nfs` storage class to make `viya-shared-sc`:

    ```bash
    # Make a copy
    copysc nfs viya-shared-sc
    ```

1.  Review resulting file `defineSC_viya-shared-sc.yaml`:

    ```yaml
    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
        name: viya-shared-sc
    mountOptions:
        - noatime
        - nodiratime
        - rsize=262144
        - wsize=262144
    parameters:
        mountPermissions: "0777"
        server: ip-123-45-67-8.ec2.internal
        share: /export
        subDir: pvs/${pvc.namespace}-${pvc.name}
    provisioner: nfs.csi.k8s.io
    reclaimPolicy: Retain
    volumeBindingMode: WaitForFirstConsumer
    ```

    Edit the file to make any desired changes.

1.  When it's acceptable, then apply it:

    ```bash
    # Apply the storage class definition
    kubectl apply -f defineSC_viya-shared-sc.yaml
    ```

### &#9655; Status Check

We've done the site's work of installing storage providers for Kubernetes to use. We created some generic storage classes named per their provider. This is a good practice because the site can perform validation testing on their own to ensure that storage is working correctly.

With known good storage, we take advantage of that by making *copies* of those storage classes and giving them names we've configured Viya to use already. 

The result:

```log
$ kubectl get sc

NAME              PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE

gp2               kubernetes.io/aws-ebs   Delete          WaitForFirstConsumer
gp3               ebs.csi.aws.com         Delete          WaitForFirstConsumer
local-path        rancher.io/local-path   Delete          WaitForFirstConsumer
nfs               nfs.csi.k8s.io          Retain          WaitForFirstConsumer

viya-scratch-sc   rancher.io/local-path   Retain          WaitForFirstConsumer
viya-shared-sc    nfs.csi.k8s.io          Retain          WaitForFirstConsumer
viya-standard-sc  ebs.csi.aws.com         Delete          WaitForFirstConsumer
```

> Note: this approach allows us to specify storage for Viya ***without modifying Viya's storage configuration***. Don't want "`local-path`" as the basis for "`viya-scratch-sc`"? Then use "`gp3`" instead.

## Provision and configure supporting 3rd-party resources

Beyond what the IAC project provides, we need more resources that Viya relies on.

### Deploy GEL's demo LDAP service

SAS Viya requires LDAP or Active Directory service for authentication. For this demo environment, we will deploy "[gelldap](https://your-git-repo.example.com/GEL/utilities/gelldap/)" that's [prepopulated with userids](https://your-git-repo.example.com/GEL/utilities/gelldap/-/blob/master/bases/gelldap/Users_and_groups.md?ref_type=heads).

1.  Deploy "gelldap" to provide LDAP service

    ```bash
    # Copy gelldap deployment artifcats
    cp -r ~/payload/gelldap ~/project/deploy

    # Prepare to deploy GELLDAP
    cd ~/project/deploy/gelldap/
    kustomize build ./no_TLS/ -o gelldap-no_TLS.yaml
    kubectl create ns gelldap

    # Deploy gelldap to the EKS cluster
    kubectl -n gelldap apply -f gelldap-no_TLS.yaml

    # Modify the sitedefault to use fqdn to reach gelldap in its ns
    sed -i "s/host: 'gelldap-service'/host: 'gelldap-service.gelldap.svc.cluster.local'/" ~/project/deploy/gelldap/no_TLS/gelldap-sitedefault.yaml

    # This workshop provides the site-config files to enable SAS Viya to use gelldap
    cp ~/project/deploy/gelldap/no_TLS/gelldap-sitedefault.yaml \
       ~/project/deploy/${MY_NS}/site-config/
    
    # Verify gelldap is running
    kubectl -n gelldap get endpoints
    ```

    And update kustomization.yaml to provide the secretGenerator:

    ```bash
    # provide your Viya namespace
    VIYA_NS="$MY_NS"

    # provide your Viya order directory
    VIYA_ORDER_HOME="$HOME/project/deploy/${VIYA_NS}"

    cd ${VIYA_ORDER_HOME}

    # append secretGenerator block for gelldap to end of file
    yq -i '.secretGenerator += [{"name": "sas-consul-config", "behavior": "merge", "files": ["SITEDEFAULT_CONF=site-config/gelldap-sitedefault.yaml"]}]' kustomization.yaml

    # Verify the update
    icdiff kustomization.yaml.bak*  kustomization.yaml
    ```

### Install OpenSSL as the certificate generator

SAS Viya needs the ability to generate encryption certificates on the fly.

1.  Use openSSL as the certificate generator (instead of the legacy "cert-manager" utility).

    Copy the example `openssl-generated-ingress-certificate.yaml` file to our local `site-config/` directory:

    ```bash
    # create a `security` directory for TLS files
    mkdir -p ~/project/deploy/${MY_NS}/site-config/security

    # Copy certs provided from sas-bases to site-config
    cp ~/project/deploy/${MY_NS}/sas-bases/examples/security/openssl-generated-ingress-certificate.yaml ~/project/deploy/${MY_NS}/site-config/security/openssl-generated-ingress-certificate.yaml
    ```

    And update kustomization.yaml to reference the new patch file(s):

    ```bash
    # Add the openssl-generated-ingress-certificate to the resources: in kustomization.yaml
    yq -i '.resources += ["site-config/security/openssl-generated-ingress-certificate.yaml"]' kustomization.yaml

    # Verify the update
    icdiff kustomization.yaml.bak*  kustomization.yaml
    ```

### Confirm files match configuration

We've added several services with matching configuration files in `$deploy/site-config`. Make sure the path to those files matches what's specified in kustomization.yaml.

1.  Confirm we have the expected site-config files for Viya deployment as referenced in kustomziation.yaml:

    ```bash
    # Get a list of files in site-config
    tree ~/project/deploy/${MY_NS}/site-config
    ```

    With results similar to:

    ```log
    /home/cloud-user/project/deploy/viya/site-config
    ├── gelldap-sitedefault.yaml
    ├── security
    │   └── openssl-generated-ingress-certificate.yaml
    └── storage
        └── 3SSC-transformers.yaml
    ```

### Install the Kubernetes Cluster Autoscaler

Amazon does not include the [Kubernetes Cluster Autoscaler](https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler) with EKS. So, we can install it, if desired.

1.  Install the Cluster Autoscaler

    The IAC project sets up the pre-reqs for the CA, but doesn't actually install it in AWS. The DAC project will install the CA, but we're not using that here. So, we will install the CA and reference the pre-req items the IAC has provided.

    ```bash
    # Set cluster autoscaler parameters from environment variables
    CHART_VERSION=9.48.0
    CLUSTER_NAME="${MY_PREFIX}-eks"
    AWS_REGION="${MY_REGION}"
    IAM_ROLE_ARN="arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/${MY_PREFIX}-cluster-autoscaler"

    echo "Installing Cluster Autoscaler with:"
    echo "  Helm chart: ${CHART_VERSION}"
    echo "  Cluster: ${CLUSTER_NAME}"
    echo "  Region: ${AWS_REGION}"
    echo "  IAM Role: ${IAM_ROLE_ARN}"
    echo ""

    # Add helm repository
    echo "Adding autoscaler helm repository..."
    helm repo add autoscaler https://kubernetes.github.io/autoscaler
    helm repo update

    # Install cluster autoscaler
    echo "Installing cluster autoscaler..."
    helm install cluster-autoscaler autoscaler/cluster-autoscaler \
    --namespace kube-system \
    --version ${CHART_VERSION} \
    --set autoDiscovery.clusterName=${CLUSTER_NAME} \
    --set awsRegion=${AWS_REGION} \
    --set rbac.serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=${IAM_ROLE_ARN} \
    --set rbac.serviceAccount.name=cluster-autoscaler \
    --wait

    # Check cluster autoscaler status
    kubectl get pods -n kube-system -l "app.kubernetes.io/name=aws-cluster-autoscaler"
    ```

    > Note: Matching the `viya4-deployment` project's default to pin the Helm chart version `9.48.0` (see [CONFIG_VARS](https://github.com/sassoftware/viya4-deployment/blob/main/docs/CONFIG-VARS.md#cluster-autoscaler)).

### Install ingress-nginx

SAS Viya requires [ingress-nginx](https://github.com/kubernetes/ingress-nginx) as the ingress controller.

1.  Install the Ingress NGINX Controller

    ```bash
    # Get the Cloud NAT IP
    export NATIP=$(terraform output -state /workspace/${MY_PREFIX}.tfstate -raw nat_ip)

    # Create the NGNIX namespace
    kubectl delete ns ingress-nginx  --ignore-not-found=true
    kubectl create ns ingress-nginx

    # Install the Helm repo
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo update

    # Install Nginx ingress controller
    # - HA with 2-5 replicas
    # - Allow SAS network CIDR ranges (use Direct-to-Cary VPN)
    # - Specify Amazon Network lb, not Classic lb
    # - Helm chart:
    #        4.13.3 ==> Nginx v1.13.3 (latest 30-SEP-2025)
    #        4.12.7 ==> Nginx v1.12.7 (last 1.12.x)
    #        4.12.1 ==> Nginx v1.12.1 (min reqd Viya 25.09)
    helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
        --namespace ingress-nginx \
        --version 4.12.7 \
        --set controller.service.externalTrafficPolicy=Local \
        --set controller.service.sessionAffinity=None \
        --set controller.service.loadBalancerSourceRanges="{10.244.0.0/16,192.0.2.0.0/16,198.551.100.102.80/31}" \
        --set controller.config.use-forwarded-headers="true" \
        --set controller.autoscaling.enabled=true \
        --set controller.autoscaling.minReplicas=2 \
        --set controller.autoscaling.maxReplicas=5 \
        --set controller.resources.requests.cpu=100m \
        --set controller.resources.requests.memory=500Mi \
        --set controller.autoscaling.targetCPUUtilizationPercentage=90 \
        --set controller.autoscaling.targetMemoryUtilizationPercentage=90 \
        --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-type"="nlb" \
        --wait

    # Validate by getting the service endpoints for Nginx
    kubectl get svc -n ingress-nginx
    ```

1. Patch the Ingress NGINX Controller configuration [as required](https://documentation.sas.com/?cdcId=itopscdc&cdcVersion=v_068&docsetId=dplyml0phy0dkr&docsetTarget=p1deewvd9xtqiyn168adq6fu9msv.htm):

    ```bash
    # Patch the configMap to set annotations-risk-level
    kubectl patch cm ingress-nginx-controller -n ingress-nginx -p '{"data":{"annotations-risk-level":"Critical"}}';

    # Patch the configMap to enable block list
    # See CVE-2021-25742
    kubectl patch cm ingress-nginx-controller -n ingress-nginx -p \
    '{"data":{"allow-snippet-annotations":"true","annotation-value-word-blocklist":"load_module,lua_package,_by_lua,location,root,proxy_pass,serviceaccount,{,},\\"}}'
    ```

    > Note: NGINX watches for changes to its configMaps and picks them up automatically.
    >
    > [Read more information](https://github.com/kubernetes/kubernetes/issues/126811) about CVE-2021-25742.

### Establish a user-friendly DNS alias

Amazon in particular provides FQDN for external load balancers that are highly randomized for uniqueness. Other cloud providers might only provide an IP address. Either way, let's set up a DNS alias on our local network that will make sense to the end users.

1.  Note the external IP address of the load balancer in Kubernetes used by the ingress controller:

    ```bash
    # Identify the endpoint of our Elastic Load Balancer for Nginx
    LBIP=$(kubectl get service -n ingress-nginx | grep LoadBalancer | awk '{print $4}')

    echo -e "\n==> LoadBalancer IP = $LBIP"
    ```

    The public IP/DNS allows access to the SAS Viya applications from outside the cloud (like from the Internet or an associated corporate intranet).

1. Determine the URL we want for Viya

    ```bash
    # The root url for accessing SAS Viya from outside EKS
    export MY_VIYA_FQDN="${MY_PREFIX}-${MY_NS}.aws.example.com"

    # Remember it
    add_my_var MY_VIYA_FQDN

    # Announce
    echo -e "\n==> FQDN we want to reach Viya = $MY_VIYA_FQDN"
    ```



### &#9655; Status Check

We've rounded out the remaining items needed for deploying the SAS Viya platform.

## Deploy the SAS Viya platform

We'll use the SAS Orchestration Utility to deploy the SAS Viya platform to EKS.

### Install the Orchestration tool

The official instructions are available in the README; see section "[Using Kubernetes Tools from the sas-orchestration Image](https://support.sas.com/documentation/installcenter/viya/SASViyaReadMe.htm#using_kubernetes_tools_from_the_sas-orchestration_image)".

-   Retrieve the `sas-orchestration` image from the SAS Registry (cr.sas.com).

    ```bash
    # Parse the sas-orchestration image version from the DepOp README
    IMAGE_VERSION=$(cat ~/project/deploy/${MY_NS}/sas-bases/examples/kubernetes-tools/README.md | grep "docker tag cr.sas.com/viya-4-x64_oci_linux_2-docker/sas-orchestration:" | sed 's/^.*sas-orchestration:/sas-orchestration:/' | cut -d " " -f 1 | cut -d ":"  -f 2)
    echo "image version:" $IMAGE_VERSION

    # Pull the sas-orchestration image from cr.sas.com
    docker pull cr.sas.com/viya-4-x64_oci_linux_2-docker/sas-orchestration:${IMAGE_VERSION}
    ```

-   Replace the image tag for ease of use.

    Replace '`cr.sas.com/viya-4-x64_oci_linux_2-docker/sas-orchestration:x.xx.x-yyymmdd.xxxxxxxxxxxxx`' with a local tag for ease of use. Then we can refer to the container simply as '`sas-orch`'.

    ```bash
    # Rename to something easy
    docker tag cr.sas.com/viya-4-x64_oci_linux_2-docker/sas-orchestration:${IMAGE_VERSION} sas-orch

    # Validate: looks for "sas-orch" in the list of containers
    docker image list | grep sas-orch

    # Confirm we can use the container as its named
    docker run --rm sas-orch deploy --help
    ```

-   You are now all set to start using the `sas-orchestration` tool to deploy SAS Viya.

### Deploy SAS Viya

1. Create the Kubernetes namespace for Viya

    ```bash
    # Create the namespace 
    kubectl create ns ${MY_NS}
    ```

1.  Run the `sas-orch`estration utility to deploy SAS Viya

    ```bash
    cd ~/project/deploy

    # Run the sas-orchestration with all deployment parameters
    docker run --rm \
    -v $(pwd):/workingdir/ \
    -v ~/.kube/config:/kube/config \
    -e "KUBECONFIG=/kube/config" \
    --user $(id -u):$(id -g) \
    sas-orch \
    deploy \
    --namespace ${MY_NS} \
    --deployment-data /workingdir/${MY_NS}/SASViyaV4_${MY_ORDERNUM}_certs.zip \
    --license /workingdir/${MY_NS}/SASViyaV4_${MY_ORDERNUM}_license.jwt \
    --user-content /workingdir/${MY_NS} \
    --cadence-name ${MY_CADENCE_NAME} \
    --cadence-version ${MY_CADENCE_VERSION}
    ```

    ---

    <details>
    <summary>Click Here for alternative command that enables Debug output</summary>

    ```sh
    # Include directives to show Debug output
    docker run --rm \
    -v $(pwd):/workingdir/ \
    -v ~/.kube/config:/kube/config \
    -e "KUBECONFIG=/kube/config" \
    -e DEBUG_LOG_LOCATION=stderr \
    --user $(id -u):$(id -g) \
    sas-orch --verbose \
    deploy \
    --namespace ${MY_NS} \
    --deployment-data /workingdir/${MY_NS}/SASViyaV4_${MY_ORDERNUM}_certs.zip \
    --license /workingdir/${MY_NS}/SASViyaV4_${MY_ORDERNUM}_license.jwt \
    --user-content /workingdir/${MY_NS} \
    --cadence-name ${MY_CADENCE_NAME} \
    --cadence-version ${MY_CADENCE_VERSION}
    ```

    </details>

    ---

    With results similar to:

    ```log
    The deploy command started
    Generating deployment artifacts
    Generating deployment artifacts complete
    Generating kustomizations
    Generating kustomizations complete
    Generating manifests
    Generating manifests complete
    Applying manifests
    > start_leading gel-viya

    I0110 17:39:48.672683       1 leaderelection.go:248] attempting to acquire leader lease gel-viya/sas-lifecycle-leader...
    I0110 17:39:48.752099       1 leaderelection.go:258] successfully acquired lease gel-viya/sas-lifecycle-leader
    > kubectl delete --namespace gel-viya --wait --timeout 7200s --ignore-not-found configmap sas-deploy-lifecycle-operation-variables

    > kubectl create --namespace gel-viya configmap sas-deploy-lifecycle-operation-variables

    configmap/sas-deploy-lifecycle-operation-variables created

    > run deploy-assess --namespace gel-viya --deploymentDir /work/deploy/resources/generation --timeout 7200s --serviceAccountName  --manifest /work/deploy/manifest.yaml
    ...
    ...
    ```

    Ending with:

    ```log
    ...
    ...
    Applying manifests complete
    The deploy command completed successfully
    ```

    > If nothing happens after the "`deploy command started`" message or if you see a failure/error message, then simply try re-running the `deploy` again. Often that's all it needs. Beyond that, try the Debug option (above) and resolve.

### &#9655; Status Check

You've kicked off the deployment SAS Viya software to the AWS infrastructure using the SAS Orchestration utility.

After the SAS Orchestration utility says it's "completed successfully", Kubernetes will continue the work as directed by the site manifest to retrieve containers and startup Viya services. It will take another 10-20 minutes for Viya to achieve readiness.

## Monitor the start up of SAS Viya services

There are many tools to monitor the activity of the SAS Viya platform and how it progresses through the startup process. 

### K9s

If you've used the commerical [Lens](https://lenshq.io/products/lens-k8s-ide) app or open-source spinoffs [OpenLens](https://github.com/MuhammedKalkan/OpenLens) (now defunct) or [FreeLens](https://freelensapp.github.io), then you're already familiar with the kind of utility that [K9s](https://k9scli.io) provides. However, where Lens provides a point-and-click interface driven by your mouse pointer, K9s is instead driven by your keyboard. With a little practice, it provides easy access to powerful insights about the status of your Kubernetes cluster.

-   Open up the K9s app installed earlier

    ```bash
    # launch K9s
    k9s
    ```

-   Type `:ns` to bring up a list of namespaces

-   Use the arrow keys to select the "viya" namespace and hit `[Enter]`. This shows a list of pods in the "viya" namespace

-   Type `[Ctrl]-A` to sort the list of pods by Age (newest to oldest). You can watch as pods progress through their lifecycles. New pods will be added to the top.

-   Type `:pods` to return to the list of pods. Re-sort again if needed.

-   For more detail on a selected item, hit the `[Enter]` key. Depending on what you're looking at, you will see the "Describe" output or, if it's a hierarchical item, then K9s will take you down to the next level. For example, namespaces > pods > containers > logs.

-   To reverse back, hit the `[Escape]` key. For example, if you're viewing a container's log > containers > pods > namespace.

    Or use another colon-command (starting  with "`:`") to jump elsewhere.

-   For help on key actions, refer to the reference list at the top of the screen, or hit "`?`" for the help screen (and `[Escape]` to exit it)

-   Type `:q` to quit K9s and return to the Linux command line

### Monitor sas-readiness pod

The `sas-readiness` pod keeps track of the pods as they come online and mark themselves as Ready. When nearly all of them have reached that state, then the `sas-readiness` pod will mark itself as Ready, too. So, that's a pretty good indicator to monitor:

```bash
# Watch the "Ready" state of the sas-readiness pod
kubectl -n $MY_NS get pod -l app.kubernetes.io/name=sas-readiness --watch
```

When the READY column shows `1/1`, then it's "ready":

```log
NAME                             READY   STATUS     RESTARTS  AGE
sas-readiness-5b75b79f57-txkzx   0/1     Pending    0         0s
sas-readiness-5b75b79f57-txkzx   0/1     Init:0/2   0         4s
sas-readiness-5b75b79f57-txkzx   0/1     Init:1/2   0         10s
sas-readiness-5b75b79f57-txkzx   0/1     Running    0         37s
sas-readiness-5b75b79f57-txkzx   1/1     Running    0         20m
```

> Note how a new line is added for each change of state to the "sas-readiness" pod. Finally, the READY status is updated to "`1/1`" when SAS Viya's overall readiness is achieved (meaning most pods are Ready for work).

Expect to wait 15-20 minutes to reach this milestone. Hit `[Ctrl]-C` to break out of the watch command.

At steady state, fully started but with no user activity, expect to see around 120 pods or so running. (And note we did not enable high-availability features for the stateless services.)

## Validate the SAS Viya platform

Before exploring storage use in the SAS Viya platform, let's perform some cursory checks to ensure that apps and services are functioning as expected.

### Get a high-level storage report

This project includes the [K8s Volume Report utility](/9-Appendix/Kubernetes/k8s-volume-report.md) to for storage exploration.

-   Create a high-level overview of volumes in the "viya" namespace

    ```bash
    # Get a namespace summary volume report
    bash $PMP_HOME/bin/k8s-volume-report.sh -n viya
    ```

    With results similar to:

    ```log
    Fetching data from namespace 'viya'...

    Volume Summary — namespace: viya  (110 pods)
    ─────────────────────────────────────────────────────────────────────────────────────────────────────────
    TYPE            COUNT  PODS W/TYPE  DETAILS
    ─────────────────────────────────────────────────────────────────────────────────────────────────────────
    emptyDir          304          109  4 w/ sizeLimit  |  3 w/ Memory medium
    hostPath            0            0  (none)
    PVC                31           18  18 unique claims  |  StorageClasses: viya-shared-sc, viya-standard-sc
    GeV                 3            3  viya-scratch-sc: 50Gi×3
    ─────────────────────────────────────────────────────────────────────────────────────────────────────────
    ```

-   Refer to the [K8s Volume Report utility](/9-Appendix/Kubernetes/k8s-volume-report.md) page for additional reporting options.

### Check on specific storage resources in Viya's namespace

1.  Launch `k9s`
1.  Enter `:ns` and select the `viya` namespace
1.  Enter `:pvc` to get a list of PVC defined for Viya pods in the namespace

    Confirm none are stuck `Pending` due to error. "Waiting for first consumer" is okay and expected as the system comes online.

    Confirm each are using the expected storage class.

1.  Continue to monitor and evaluate. Watch for new pods (like `sas-compute-server`) which are started on-demand and then define new PV.

### Logon to SAS Viya

Take SAS Viya for a quick spin to see it working.

1.  Generate the URL to access your SAS Viya deployment

    ```sh
    # Display the URL to access Viya

    echo -e "\n>>> The landing page for your SAS Viya platform is: \n\n    https://${MY_VIYA_FQDN}/SASLanding/\n"
    ```

    Copy and paste the provided URL to your web browser.

    > Note: If your browser warns that the connection isn't private, click through to advance.
    >
    > Setting up proper TLS certification authority is explained in *SAS® Viya® Platform Administration* > Security > Encryption > Data in Motion > [Certificate Trust and CA Certificates](https://documentation.sas.com/?cdcId=sasadmincdc&cdcVersion=default&docsetId=calencryptmotion&docsetTarget=p07i4iwkl3huj3n16jan24mw8apq.htm#p1pyyictlnri54n1svcvq8iys49t).

1.  Logon to SAS Viya with the desired id/role

    The `gelldap` server provides sample user credentials:

    | Role               | Userid       | Password      |
    | ------------------ | ------------ | ------------- |
    | Regular user       | `alex`       | `lnxsas` |
    | Regular admin      | `sasadm`     | `lnxsas` |
    | Unrestricted admin<br>(cannot run Compute or CAS jobs) | `sasboot`    | `lnxsas`  |

### As directed

The remaining validation exercises primarily rely on a few SAS Viya apps to validate storage is being used as designed:

-   **SAS Studio** ("Develop Code and Flows"): launch SAS Compute Servers and user CAS sessions
-   **SAS Environment Manager** ("Manage Environment"): configure and monitor the SAS Viya platform
-   **sas-viya CLI**: command-line interface to interact with the SAS Viya platform, notably to submit batch jobs

### &#9655; Status Check

You're able to logon to the SAS Viya environment using LDAP-provided user credentials (not just `sasboot`). User interfaces and basic operation are operating normally.

From here, continue with additional validation for storage use.

---
---
---

## Delete your environment

This is an important step - some of [these resources cost money](https://calculator.aws/#/) just by existing! When you're done with this workshop, please ensure all of your resources have been destroyed.

### Uninstall Viya from Amazon EKS

1.  [If needed] Unset sas-viya CLI SSL env vars

    ```bash
    # ensure AWS CLI and Azure CLI can use their encrypted comm
    unset SSL_CERT_FILE REQUESTS_CA_BUNDLE
    ```

1.  Uninstall the SAS Viya platform

    ```bash
    # Find existing Viya namespace(s)
    VIYA_NS=$(kubectl get ns | grep 'viya\|sasoperator' | awk '{ print $1 }')

    if [ "$VIYA_NS" != "" ]
    then
        for VNS in $VIYA_NS
        do
            # Announce
            echo -e "\n---\n$(kubectl get ns $VNS)\n"

            # Uninstall the Viya deployment (2 steps)
            kubectl -n $VNS delete postgresclusters --selector="sas.com/deployment=sas-viya"

            kubectl delete ns $VNS --ignore-not-found=true
        done
    else
        echo -e "\n---\nNo Viya namespaces to delete."
    fi
    ```

### Destroy cloud resources

1.  Delete the DNS aliases

    There's no automatic approach (yet) to clean up orphaned DNS alias records in our environment. So, we need you to delete your records. Here's a script to make it easy:

    ```bash
    # execute this script to delete your DNS alias records

    bash $HOME/project-mountpoint/bin/gel_dns-deleteAlias.sh
    ```

1.  Remove the IAM Roles we created to support the CSI Drivers for AWS resources

    ```bash
    ### EBS -----------------------------
    if aws iam get-role --role-name $MY_EBS_CSI_IAM_ROLENAME &>/dev/null; then
        echo "Found EBS CSI IAM Role \"$MY_EBS_CSI_IAM_ROLENAME\""

        aws iam detach-role-policy --role-name $MY_EBS_CSI_IAM_ROLENAME --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy

        echo "Detached \"AmazonEBSCSIDriverPolicy\" from role"

        aws iam delete-role --role-name $MY_EBS_CSI_IAM_ROLENAME
        echo "Deleted role \"$MY_EBS_CSI_IAM_ROLENAME\""
    else
        echo "No EBS CSI IAM Role to delete"
    fi

    ### EFS -----------------------------
    if aws iam get-role --role-name $MY_EFS_CSI_IAM_ROLENAME &>/dev/null; then
        echo "Found EFS CSI IAM Role \"$MY_EFS_CSI_IAM_ROLENAME\""

        aws iam detach-role-policy --role-name $MY_EFS_CSI_IAM_ROLENAME --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy

        echo "Detached \"AmazonEFSCSIDriverPolicy\" from role"

        aws iam delete-role --role-name $MY_EFS_CSI_IAM_ROLENAME
        echo "Deleted role \"$MY_EFS_CSI_IAM_ROLENAME\""
    else
        echo "No EFS CSI IAM Role to delete"
    fi

    ### FSx -----------------------------
    if aws iam get-role --role-name $MY_TRIDENT_CSI_IAM_ROLENAME &>/dev/null; then
        echo "Found Trident CSI IAM Role \"$MY_TRIDENT_CSI_IAM_ROLENAME\""

        MY_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

        aws iam detach-role-policy --role-name $MY_TRIDENT_CSI_IAM_ROLENAME --policy-arn arn:aws:iam::${MY_ACCOUNT}:policy/${MY_PREFIX}-trident-fsx-policy

        echo "Detached \"${MY_PREFIX}-trident-fsx-policy\" from role"

        aws iam delete-role --role-name $MY_TRIDENT_CSI_IAM_ROLENAME
        echo "Deleted role \"$MY_TRIDENT_CSI_IAM_ROLENAME\""
    else
        echo "No Trident CSI IAM Role to delete"
    fi
    ```

    > Remember, Terraform didn't create the the IAM Roles. We did that manually in a couple of exercises in preparation for deploying SAS Viya.

1.  Destroy the AWS infrastructure defined by the IAC using Terraform

    ```bash
    cd ~/viya4-iac-aws

    # terraform destroy
    terraform destroy -auto-approve \
        -var-file /workspace/${MY_PREFIX}.tfvars \
        -state /workspace/${MY_PREFIX}.tfstate
    ```

    > Note: Sometimes AWS is slow to destroy resources and Terraform might timeout when waiting. Usually a second run of the `terraform destroy` command will work.

### &#9655; Status Check

All resources in AWS created for these exercises have been deleted.
