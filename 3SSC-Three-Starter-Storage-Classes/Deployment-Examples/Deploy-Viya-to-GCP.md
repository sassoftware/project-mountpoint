# Deploy SAS Viya to Google Cloud with 3 Starter Storage Classes

Let's get this done. This page provides a streamlined deployment of SAS Viya to Google Cloud. We focus on a "happy path" approach that highlights the concept of 3 Starter Storage Classes as outlined in Project Mountpoint.

> Note: This exercise takes an "upside-down" approach to deployment compared to other GEL deployment workshops. We will:
> - get Viya order assets and configure them *first*
> - *then*, provision infrastructure to match Viya's config
> - *and* deploy SAS Viya
>
> In the TOC below, the deployment aspects where Project Mountpoint contributes significantly are marked with "&#9654; PMP". As you can see, it's just a small part of the larger SAS Viya platform implementation.

Here's the plan:

- [Deploy SAS Viya to Google Cloud with 3 Starter Storage Classes](#deploy-sas-viya-to-google-cloud-with-3-starter-storage-classes)
    - [Basis](#basis)
    - [Reserve a RACE collection](#reserve-a-race-collection)
    - [Logon to RACE host(s)](#logon-to-race-hosts)
    - [▶ PMP: Clone Project Mountpoint](#-pmp-clone-project-mountpoint)
    - [Get Viya resources and assets](#get-viya-resources-and-assets)
        - [Download Viya order assets](#download-viya-order-assets)
        - [▶ PMP: Configure the Viya assets](#-pmp-configure-the-viya-assets)
        - [▷ Status Check](#-status-check)
    - [Infrastructure](#infrastructure)
        - [Setup the gcloud CLI](#setup-the-gcloud-cli)
        - [Identify yourself to Google Cloud](#identify-yourself-to-google-cloud)
        - [Install and Configure Terraform](#install-and-configure-terraform)
        - [Setup SSH key](#setup-ssh-key)
        - [Which IAC-provisioned shared (RWX) storage?](#which-iac-provisioned-shared-rwx-storage)
        - [Configure Terraform for desired Google Cloud resources](#configure-terraform-for-desired-google-cloud-resources)
        - [Use Terraform to provision infrastructure](#use-terraform-to-provision-infrastructure)
        - [Get k8s clients set up](#get-k8s-clients-set-up)
        - [▷ Status Check](#-status-check-1)
    - [▶ PMP: Provision and configure storage in Google Cloud](#-pmp-provision-and-configure-storage-in-google-cloud)
        - [Google Cloud provides storage classes out-of-the-box](#google-cloud-provides-storage-classes-out-of-the-box)
        - [RWO storage for `viya-standard-sc`: Google persistent disk](#rwo-storage-for-viya-standard-sc-google-persistent-disk)
        - [Local storage for `viya-scratch-sc`: Rancher local-path](#local-storage-for-viya-scratch-sc-rancher-local-path)
        - [RWX storage for `viya-shared-sc`: NFS to Google Filestore](#rwx-storage-for-viya-shared-sc-nfs-to-google-filestore)
        - [▷ Status Check](#-status-check-2)
    - [Provision and configure supporting 3rd-party resources](#provision-and-configure-supporting-3rd-party-resources)
        - [Install OpenSSL as the certificate generator](#install-openssl-as-the-certificate-generator)
        - [Deploy GEL's demo LDAP service](#deploy-gels-demo-ldap-service)
        - [Confirm files match configuration](#confirm-files-match-configuration)
        - [Install ingress-nginx](#install-ingress-nginx)
        - [Establish a user-friendly DNS alias](#establish-a-user-friendly-dns-alias)
    - [Deploy the SAS Viya platform](#deploy-the-sas-viya-platform)
        - [Install the Orchestration tool](#install-the-orchestration-tool)
        - [Deploy SAS Viya](#deploy-sas-viya)
        - [▷ Status Check](#-status-check-3)
    - [Validate the SAS Viya platform](#validate-the-sas-viya-platform)
        - [Review storage resources in Viya's namespace](#review-storage-resources-in-viyas-namespace)
        - [Logon to SAS Viya](#logon-to-sas-viya)
        - [As directed](#as-directed)
        - [▷ Status Check](#-status-check-4)
    - [Delete your environment](#delete-your-environment)
        - [Uninstall Viya from Google Kubernetes Engine](#uninstall-viya-from-google-kubernetes-engine)
        - [Destroy cloud resources](#destroy-cloud-resources)
        - [▷ Status Check](#-status-check-5)

## Basis

The deployment process here is heavily borrowed from the [SAS® Viya®: Deployment on Google Kubernetes Engine](https://learn.sas.com/course/view.php?id=7115) (learn.sas.com) workshop.



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
    export MY_VIYA_FQDN="${MY_PREFIX}-${MY_NS}.gcp.example.com"

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
    export MY_CADENCE_VERSION='2025.09'

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
    MY_CADENCE_VERSION=2025.09
    MY_NS=viya
    MY_ORDERNUM=9D1ZB7
    MY_PREFIX=envoy-p41814
    MY_VIYA_FQDN=envoy-p41814-viya.gcp.example.com
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
      - sas-bases/overlays/sas-workload-orchestrator
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
        exit 1
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

### Setup the gcloud CLI

The gcloud command-line interface gives us a powerful utility to administer resources in Google Cloud.

1.  Identify what and where in GCP

    ```bash
    # Specify project name, region, and zone
    MY_GCPPROJECT=${MY_GCPPROJECT:-sas-gelsandbox}
    MY_GCPREGION=${MY_GCPREGION:-us-east1}
    MY_GCPZONE=${MY_GCPZONE:-us-east1-b}

    # Remember them
    add_my_var MY_GCPPROJECT
    add_my_var MY_GCPREGION
    add_my_var MY_GCPZONE
    ```

1.  Install the gcloud CLI utility

    ```bash
    # save the gcloud CLI executable to my home directory
    cd $HOME

    # pin to a known-good version
    GCP_CLI_VERSION="428.0.0"

    # download the install archive
    curl -O https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-sdk-${GCP_CLI_VERSION}-linux-x86_64.tar.gz

    # unpack the archive
    tar -xf google-cloud-sdk-${GCP_CLI_VERSION}-linux-x86_64.tar.gz

    # run the installer
    ./google-cloud-sdk/install.sh --quiet

    # complete the install
    echo "source $HOME/google-cloud-sdk/path.bash.inc"       >> $HOME/.bashrc
    echo "source $HOME/google-cloud-sdk/completion.bash.inc" >> $HOME/.bashrc

    # pickup env changes
    source $HOME/.bashrc

    # validate 
    gcloud --version
    ```

### Identify yourself to Google Cloud

Let's configure the gcloud CLI to know who you are.

First, let's check your credentials in a web browser:

1.  In a web browser, visit the Google Console using the SAS federated logon: <https://console.cloud.google.com/>. **Provide your own site credentials** (if prompted).

    > Note: Each site is responsible to provide their own Google subscription credentials for a real implementation.

    If that worked okay, then let's get signed in with the gcloud CLI...

1.  Initial gcloud and sign in

    ```sh
    ## Initialize gcloud
    gcloud init --project=${MY_GCPPROJECT} --console-only
    ```

1.  You'll be prompted to logon. Follow the instructions to open a new browser with a signon link. After authenticating with your sas.com credentials, you'll be provided with a long verification code to paste back into the terminal window to complete signing on with the gcloud CLI.

    In the final output, you should see values confirming the project name, region, and zone as established above.

1.  Validate:

    ```bash
    # List the current config
    gcloud config list
    ```

    With results like:

    ```log
    [compute]
    region = us-east1
    zone = us-east1-b
    [core]
    account = your.name@sas.com
    disable_usage_reporting = True
    project = sas-gelsandbox
    ```

At this point, you're signed into Google Cloud with your own credentials. SAS employees are using the SAS-provided subscription.

### Install and Configure Terraform

Install and configure terraform using the assets from viya4-iac-gcp project.

1.  Install the Terraform YUM repository

    ```bash
    ## Install yum-config-manager to manage your repositories.
    sudo yum install -y yum-utils
    
    # Use yum-config-manager to add the official HashiCorp Linux repository.
    # Centos/RHEL7 is EOL
    sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
    ```

1.  Pin our Terraform version to the version [required](https://github.com/sassoftware/viya4-iac-gcp) by the "SAS Viya 4 IaC for GCP" tool.

    ```bash
    # Specify the version that is recommended by viya4-iac-gcp
    TFVERSION="1.10.5"

    # Install that version of terraform
    sudo yum install terraform-${TFVERSION} -y

    # Validate
    terraform -version
    ```

    > Note you can ignore the "Terraform is out of date" message. We installed the specific version supported by the viya4-iac-gcp project.

1.  Download the viya4-iac-gcp project from `github.com/sassoftware` to get the Terraform templates that SAS maintains to provision infrastructure in the Google Cloud.

    ```bash
    # clean slate
    rm -Rf ~/project/gcp/viya4-iac-gcp
    mkdir -p ~/project/gcp/
    cd ~/project/gcp/

    # Clone the IAC for GCP project
    git clone https://github.com/sassoftware/viya4-iac-gcp.git
    cd ~/project/gcp/viya4-iac-gcp/

    # Instead of being at the mercy of the latest changes, we pin to a specific version
    # v7.6.2 fix for "ubuntu-os-cloud/ubuntu-2004-lts"
    IAC_GCP_TAG=v7.6.2
    git checkout tags/${IAC_GCP_TAG}
    ```

1.  Identify yourself

    ```bash
    # Get the email address associated with your Google Cloud identity
    MY_EMAIL=$(gcloud auth list --filter=status:ACTIVE --format="value(account)")
    add_my_var MY_EMAIL

    # Create a username from your email address
    MY_NAME=$(echo $MY_EMAIL | awk -F "[.@]" '{print substr($1,1,4) substr($2,1,6)}')
    add_my_var MY_NAME

    # Validate
    recall
    ```

1.  Fetch GCP credentials for the sas-installer service account

    For infrastructure provisioning we will use a service account named "`sas-installer`".

    ```bash
    # Fetch "sas-installer" credentials provided by this workshop
    curl -sk https://gelweb.example.com/scripts/gcp/users/gel-sas-installer@sas-gelsandbox.iam.gserviceaccount.com.json > $HOME/.gel-sas-installer.json
    ```

1.  Prepare the environment for terraform to operate: initialize backend configuration and install additional plugins and providers.

    ```bash
    cd ~/project/gcp/viya4-iac-gcp
    
    # Initialize
    terraform init
    ```

    Expect to see:

    ```log
    Terraform has been successfully initialized!

    You may now begin working with Terraform. Try running "terraform plan" to see any changes that are required for your infrastructure. All Terraform commands should now work.
    ```

### Setup SSH key

The IAC will create machines in Google Cloud which can be accessed with cloud-user's default SSH key (`~/.ssh/id_rsa`). So create that now.

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

The viya4-iac-gcp project offers [three main options for shared (RWX) storage](https://github.com/sassoftware/viya4-iac-gcp/blob/main/docs/CONFIG-VARS.md#storage).

**Select one of the following** and execute the command given to set an environment variable with the appropriate IAC parameters:

-   Google Cloud Filestore  **<<== PICK THIS ONE**

    ```sh
    RWX_STORAGE_PROVIDER=$(cat << 'EOF'
    storage_type                            = "ha"
    storage_type_backend                    = "filestore"
    EOF
    )
    ```

    > Note that other storage options should work fine - but I haven't created the alternative instructions to manage them in this exercise yet.

-   Basic, no-frills NFS Server

    ```sh
    RWX_STORAGE_PROVIDER=$(cat << 'EOF'
    storage_type                            = "standard"
    EOF
    )
    ```

### Configure Terraform for desired Google Cloud resources

The IAC is driven by a terraform variables file that we must create. As shown here, we've made selections that will support the 3 Starter Storage Classes paradigm to provide shared (RWX) storage and local disk storage.

1.  Create the TF Vars file to drive infrastructure:

    ```bash
    K8S_VERSION="1.31"
    SA_KEY_FILE="$HOME/.gel-sas-installer.json"

    # Start the Terraform variables file for the IAC
    cat << EOF > $HOME/project/gcp/viya4-iac-gcp/${MY_PREFIX}.tfvars
    # REQUIRED VARIABLES
    # Necessary for use by the IAC
    # --------------------------------------
    # - Prefix is used for naming resources for easy identification
    # - Location is the geo region where resources will be placed
    #
    prefix                  = "$MY_PREFIX"
    location                = "$MY_GCPZONE"
    project                 = "$MY_GCPPROJECT"
    service_account_keyfile = "$SA_KEY_FILE"


    # ACCESS, IDENTITY, and AUTHENTICATION
    # Who is doing what where
    # --------------------------------------
    #
    ssh_public_key                          = "$HOME/.ssh/id_rsa.pub"
    create_static_kubeconfig                = true

    # CIDR
    # Specify public access CIDR to allow ingress traffic to the EKS cluster
    # --------------------------------------
    # - Define access from RACE VMWARE and RACE Azure clients networks
    #
    default_public_access_cidrs         = ["192.0.2.0.0/16", "198.551.100.102.80/32", "198.551.100.102.81/32"]

    # TAGS
    # Optional metadata associated with GCP resources
    # --------------------------------------
    # - Resourceowner makes it easy to find associated resources
    # - Project_Name and GEL_Project are for tracking
    #
    tags = { "resourceowner"  = "$MY_NAME",
             "prefix"         = "$MY_PREFIX", 
             "gel_project"    = "$MY_GCPPROJECT"
        }

    # EXTERNAL POSTGRES SERVER
    # --------------------------------------
    # - if defined, creates an External Postgres Server, else use internal Crunchy
    #
    #postgres_servers = {
    #  default = {},
    #}

    ## Cluster config
    kubernetes_version                      = "$K8S_VERSION"

    default_nodepool_min_nodes = 1
    default_nodepool_max_nodes = 2
    default_nodepool_vm_type   = "e2-standard-4"

    ## Shared storage provider
    $RWX_STORAGE_PROVIDER

    ## Cluster Node Pools config
    node_pools = {
        cas = {
            "vm_type"           = "n1-highmem-4"
            "os_disk_size"      = 200
            "min_nodes"         = 1
            "max_nodes"         = 5
            "node_taints"       = ["workload.sas.com/class=cas:NoSchedule"]
            "node_labels"       = { 
            "workload.sas.com/class" = "cas" 
            "attr.sas.com/local-nvme" = "true"
            }
            "local_ssd_count"   = 1
            "accelerator_count" = 0
            "accelerator_type"  = ""
        },
        compute = {
            "vm_type"           = "n1-highmem-4"
            "os_disk_size"      = 200
            "min_nodes"         = 1
            "max_nodes"         = 3
            "node_taints"       = ["workload.sas.com/class=compute:NoSchedule"]
            "node_labels"       = {
            "workload.sas.com/class" = "compute" 
            "attr.sas.com/local-nvme" = "true"
            }
            "local_ssd_count"   = 1
            "accelerator_count" = 0
            "accelerator_type"  = ""
        },
        stateless = {
            "vm_type"         = "n2-standard-16"
            "os_disk_size"    = 200
            "min_nodes"       = 2
            "max_nodes"       = 2
            "node_taints"     = ["workload.sas.com/class=stateless:NoSchedule"]
            "node_labels"     = {
            "workload.sas.com/class" = "stateless"
            }
            "local_ssd_count"   = 0
            "accelerator_count" = 0
            "accelerator_type"  = ""
        },
        stateful = {
            "vm_type"         = "n2-standard-8"
            "os_disk_size"    = 200
            "min_nodes"       = 2
            "max_nodes"       = 3
            "node_taints"     = ["workload.sas.com/class=stateful:NoSchedule"]
            "node_labels"     = {
            "workload.sas.com/class" = "stateful"
            }
            "local_ssd_count"   = 0
            "accelerator_count" = 0
            "accelerator_type"  = ""
        }
    }

    # Jump Server
    create_jump_vm                        = true
    jump_vm_admin                         = "jumpuser"
    jump_vm_type                          = "e2-standard-2"

    # NFS Server
    # only used when storage_type is "standard" to create NFS Server VM
    create_nfs_public_ip                  = false
    nfs_vm_admin                          = "nfsuser"
    nfs_vm_type                           = "c3-standard-4"
    EOF
    ```

    > Note, this specifies:
    > - 200GB OS disk volumes
    > - Your choice for `RWX_STORAGE_PROVIDER` has been included
    > - Instance types with local disk are specified for CAS and Compute and include scripts to automatically format and mount the disks. Labels to identify them are added, too.

### Use Terraform to provision infrastructure

With the terraform variables all defined, now we can provision the infrastructure in Google Cloud.

1.  Generate the Terraform plan

    ```sh
    cd $HOME/project/gcp/viya4-iac-gcp

    # direct terraform to create a plan, runs in seconds
    terraform plan \
        -input=false \
        -var-file=./${MY_PREFIX}.tfvars \
        -out ./${MY_PREFIX}.tfplan
    ```

1.  Apply the Terraform plan:

    ```bash
    # direct terraform to apply the plan to provision resources in Google Cloud 
    time terraform apply -state ./${MY_PREFIX}.tfstate "./${MY_PREFIX}.tfplan"
    ```

    ---

    <details>
    <summary>Terraform failure? Click here.</summary>

    Sometimes Terraform gets hung up in cross-dependencies, failing to generate a kubeconfig file. The workaround is to re-plan at the current state and re-apply. (see [Issue 384](https://github.com/sassoftware/viya4-iac-aws/issues/384))

    Re-`plan` and re-`apply`:

    ```sh
    cd $HOME/project/gcp/viya4-iac-gcp

    # re-plan (and include the current state)
    terraform plan \
        -input=false \
        -var-file=./${MY_PREFIX}.tfvars \
        -state ./${MY_PREFIX}.tfstate \
        -out ./${MY_PREFIX}.tfplan

    # re-apply the updated plan
    terraform apply -state ./${MY_PREFIX}.tfstate "./${MY_PREFIX}.tfplan"
    ```

    </details>

    ---

It will take 8-10 minutes for Terraform to complete the provisioning of resources in Google Cloud.


### Get k8s clients set up

1.  Use terraform to create a kubeconfig file

    ```bash
    cd $HOME/project/gcp/viya4-iac-gcp

    # direct terraform to create a kubectl configuration file
    terraform output -state ./${MY_PREFIX}.tfstate -raw kube_config > ./${MY_PREFIX}.kube.conf

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
    export GKE_FULL_VER=$(gcloud container clusters describe ${MY_PREFIX}-gke --region=$MY_GCPREGION --format="value(currentMasterVersion)" | cut -d'-' -f1) && echo -e "Kubernetes version = $GKE_FULL_VER\n\n"
    ```

    Install the equivalent version of `kubectl` to run locally:

    ```bash
    # Get kubectl from its home site
    curl -LO https://dl.k8s.io/release/v${GKE_FULL_VER}/bin/linux/amd64/kubectl

    # Install the new kubectl binary to the system:
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

    # Verify our new local install of `kubectl` is working:
    kubectl version
    ```

    With results similar to:

    ```log
    Client Version: v1.31.14
    Kustomize Version: v5.4.0
    Server Version: v1.31.14-gke.1081000
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

### &#9655; Status Check

We've stood up the core infrastructure in Google Cloud in alignment with our planned configuration of SAS Viya. And we've set up Kubernetes clients to give us administration and monitoring. But there's more yet to do...

## &#9654; PMP: Provision and configure storage in Google Cloud

At the risk of repetition, the site is responsible for providing storage that meets Viya's requirements. This section shows an approach where the site has evaluated Viya's use of storage and selected appropriate technologies. We show installing CSI Drivers and such because you need to see it. However, to be clear, the ideal is that the site will do this work, including validating that it's all working properly *before* attempting to use it for Viya's services.

> Note: Project Mountpoint's contribution here is the idea of *copying* storage classes. By giving Viya its own set of storage class names, we abstract Viya's config from the physical implementation. This isn't required - the site is free to use any names for storage classes it wants - but the additional layer of abstraction gives us another aspect of control.

The IAC will setup your choice of supported shared (RWX) storage provider. But we also need CSI drivers and other resources. Some of these would be handled automatically by the DAC project, but we're not using that here.

1.  We will make copies of storage classes. To help aid that task:

    ```bash
    # define the "copysc" function 
    source $HOME/project-mountpoint/bin/copySC.sh
    ```

### Google Cloud provides storage classes out-of-the-box

Google Cloud provides several storage classes for immediate use.

1. Let's see what's there:

    ```bash
    $ kubectl get sc

    NAME                     PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
    premium-rwo              pd.csi.storage.gke.io   Delete          WaitForFirstConsumer   true                   27m
    standard                 kubernetes.io/gce-pd    Delete          Immediate              true                   27m
    standard-rwo (default)   pd.csi.storage.gke.io   Delete          WaitForFirstConsumer   true                   27m
    ```

1.  Disable any storage class that's annotated as "default"

    ```bash
    # disable the k8s default SC, if there is one 
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

### RWO storage for `viya-standard-sc`: Google persistent disk

The "viya-standard-sc" storage class is intended for use by [services that need persistent RWO volumes](/3SSC-Three-Starter-Storage-Classes/). SAS Viya services like Crunchy Postgres, RabbitMQ, Redis, Consul, and OpenSearch all need persistent RWO volumes.

The `pd.csi.storage.gke.io` driver to use [Google persistent disk](https://docs.cloud.google.com/compute/docs/disks/persistent-disks) is already installed and associated storage classes with different levels of performance have been defined for our use.

1.  &#9654; PMP: Copy the `premium-rwo` storage class to make `viya-standard-sc`:

    ```bash
    cd ~/project/deploy/$MY_NS

    # Make a copy
    copysc premium-rwo viya-standard-sc
    ```

    > Note that "`premium-rwo`" provides SSD-backed persistent disk where as "`standard-rwo`" provides HDD-backed persistent disk.

1.  Review the resulting file `defineSC_viya-standard-sc.yaml`:

    ```yaml
    allowVolumeExpansion: true
    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
    labels:
        addonmanager.kubernetes.io/mode: EnsureExists
        k8s-app: gcp-compute-persistent-disk-csi-driver
    name: viya-standard-sc
    parameters:
    type: pd-ssd
    provisioner: pd.csi.storage.gke.io
    reclaimPolicy: Delete
    volumeBindingMode: WaitForFirstConsumer
    ```

    Edit the file to make any desired changes.

1.  When it's acceptable, then create the viya-standard-sc storage class in the AKS cluster:

    ```bash
    # Apply the storage class definition
    kubectl apply -f defineSC_viya-standard-sc.yaml
    ```

### Local storage for `viya-scratch-sc`: Rancher local-path

The "viya-scratch-sc" storage class is intended for use by [SASWORK and CAS_DISK_CACHE](/3SSC-Three-Starter-Storage-Classes/). SAS Programming Runtime Environment (including SAS Batch, SAS Compute, and SAS Connect Servers) and the SAS Cloud Analytic Services (CAS) rely on this space for low-latency and high-throughput - something local disk in the cloud does well for little additional cost.

There are several ways to provide Kubernetes with access to local disk, but for this effort we want a CSI Driver that can *dynamically* provision volumes on local disk. In this section, we'll set up [Rancher Local Path Provisioner](https://github.com/rancher/local-path-provisioner), but it's just an example. Projects like OpenEBS and Portworx are acceptable, too.

Local disk on a node is not a given. It takes extra steps for a site to format and mount the local disk for use. But it's worth the extra effort.

1.  Format and mount additional local disk drives

    > ALREADY DONE. Google Cloud's [Container-Optimized OS](https://docs.cloud.google.com/container-optimized-os/docs/concepts/disks-and-filesystem) does this for us automatically. The extra node-local disk `ssd0` is mounted at `/host/mnt/disks` by default. We will configure the local-path-provisioner to use it.
    >
    > ```log
    > NAME    MOUNTPOINT                     SIZE TYPE
    > sda     /mnt/disks/ssd0                375G disk
    > sdb                                    200G disk
    > |-sdb1  /mnt/stateful_partition      195.8G part
    > |-sdb2                                  16M part
    > |-sdb3                                   2G part
    > |-sdb4                                  16M part
    > |-sdb5                                   2G part
    > |-sdb6                                 512B part
    > |-sdb7                                 512B part
    > |-sdb8  /usr/share/oem                  16M part
    > |-sdb9                                 512B part
    > |-sdb10                                512B part
    > |-sdb11                                  8M part
    > `-sdb12                                 32M part
    > ```
    >
    > FYI:
    > - `/` (root volume): located on `sdb` (on 200G disk)
    > - `/mnt/disks/ssd0` (addtl volume): located on `sda` (on 375G disk)

1.  Install the Rancher project local-path-provisioner

    ```bash
    # Install local-path
    kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
    ```

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

    Replace the default path "`/opt/local-path-provisioner`" with our new mounted volume "`/mnt/disks/ssd0`". And save the file.

    Alternatively, here's a single command to patch it:

    ```bash
    # Configure to use /viya-scratch
    kubectl get configmap local-path-config -n local-path-storage -o json \
    | jq '.data["config.json"] |= (fromjson | .nodePathMap[0].paths = ["/mnt/disks/ssd0/viya-scratch"] | tojson)' \
    | kubectl apply -f -

    # Remove `priorityClassName: system-node-critical` from the helper pod spec
    kubectl patch configmap local-path-config -n local-path-storage --type merge -p '{
    "data": {
        "helperPod.yaml": "apiVersion: v1\nkind: Pod\nmetadata:\n  name: helper-pod\nspec:\n  tolerations:\n    - key: node.kubernetes.io/disk-pressure\n      operator: Exists\n      effect: NoSchedule\n  containers:\n  - name: helper-pod\n    image: busybox\n    imagePullPolicy: IfNotPresent"
    }
    }'
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

1.  When it's acceptable, then apply it:

    ```bash
    # Apply the storage class definition
    kubectl apply -f defineSC_viya-scratch-sc.yaml
    ```

### RWX storage for `viya-shared-sc`: NFS to Google Filestore

The "viya-shared-sc" storage class is intended for use by [services that need persistent RWX volumes](/3SSC-Three-Starter-Storage-Classes/). SAS Viya services like sas-backup-job, sas-common-files, sas-pyconfig and others all need persistent RWX volumes so that multiple pods running on different nodes can access the same set of shared files.

The IAC for Google Cloud provides two options of RWX storage that it can provide. Earlier, we suggested choosing Google Filestore so the IAC created a 1Ti volume for us. We can use the NFS CSI Driver to work with it.

> Note that 1Ti is the smallest Filestore volume possible for Basic HDD service tier (@ ~$205/mo.). If we chose Premium SSD instead, it would be at least 2.5Ti in size. 
> 
> Keep this in mind - we don't want individual RWX volumes for each set of pods sharing disk... as that could easily exceed 20Ti in short order.

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

1.  Define storage class "`nfs`"

    ```bash
    # identify my NFS server (from IAC):
    export NFS_IP=`terraform output -state $HOME/project/gcp/viya4-iac-gcp/${MY_PREFIX}.tfstate -raw rwx_filestore_endpoint`
    echo -e "\n==> NFS_IP = $NFS_IP"

    #NFS_Path="/export/pvs"     # old provisioner
    NFS_Path="/volumes"         # csi
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
    allowVolumeExpansion: true
    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
      labels:
        addonmanager.kubernetes.io/mode: EnsureExists
        k8s-app: gcp-filestore-csi-driver
      name: viya-shared-sc
    parameters:
      tier: standard
    provisioner: filestore.csi.storage.gke.io
    reclaimPolicy: Delete
    volumeBindingMode: WaitForFirstConsumer
    ```

1.  Edit the file to make any desired changes. In this case, we need to tell Google Cloud to create Filestore instances in our VPC (not the Default VPC):

    ```bash
    # Specify our VPC
    yq eval ".parameters.network = \"${MY_PREFIX}-vpc\"" -i defineSC_viya-shared-sc.yaml
    ```

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

NAME                        PROVISIONER                    RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION
premium-rwo                 pd.csi.storage.gke.io          Delete          WaitForFirstConsumer   true                
standard                    kubernetes.io/gce-pd           Delete          Immediate              true                
standard-rwo                pd.csi.storage.gke.io          Delete          WaitForFirstConsumer   true                

local-path                  rancher.io/local-path          Delete          WaitForFirstConsumer   false               
nfs                         nfs.csi.k8s.io                 Retain          WaitForFirstConsumer   false                  

viya-scratch-sc             rancher.io/local-path          Delete          WaitForFirstConsumer   false               
viya-shared-sc              nfs.csi.k8s.io                 Delete          WaitForFirstConsumer   true                
viya-standard-sc            pd.csi.storage.gke.io          Delete          WaitForFirstConsumer   true                
```

> Note: this approach allows us to specify storage for Viya ***without modifying Viya's storage configuration***. Don't want "`local-path`" as the basis for "`viya-scratch-sc`"? Then use "`premium-rwo`" instead.

## Provision and configure supporting 3rd-party resources

Beyond what the IAC project provides, we need more resources that Viya relies on.

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

### Confirm files match configuration

We've added several services with matching configuration files in `$deploy/site-config`. Make sure the path to those files matches what's specified in kustomization.yaml.

1.  Confirm we have the expected site-config files for Viya deployment as referenced in kustomization.yaml:

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

### Install ingress-nginx

SAS Viya requires [ingress-nginx](https://github.com/kubernetes/ingress-nginx) as the ingress controller.

1.  Install the Ingress NGINX Controller

    ```bash
    # Get the Cloud NAT IP
    export NATIP=$(terraform output -state $HOME/project/gcp/viya4-iac-gcp/${MY_PREFIX}.tfstate -raw nat_ip)

    # Create the NGNIX namespace
    kubectl delete ns ingress-nginx  --ignore-not-found=true
    kubectl create ns ingress-nginx

    # Install the Helm repo
    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm repo update

    # Install Nginx ingress controller
    # - HA with 2-5 replicas
    # - Allow SAS network CIDR ranges (use Direct-to-Cary VPN)
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
    export MY_VIYA_FQDN="${MY_PREFIX}-${MY_NS}.gcp.example.com"

    # Remember it
    add_my_var MY_VIYA_FQDN

    # Announce
    echo -e "\n==> FQDN we want to reach Viya = $MY_VIYA_FQDN"
    ```



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

You've kicked off the deployment SAS Viya software to the Google Cloud infrastructure using the SAS Orchestration utility.

After the SAS Orchestration utility says it's "completed successfully", Kubernetes will continue the work as directed by the site manifest to retrieve containers and startup Viya services. It will take another 10-20 minutes for Viya to achieve readiness.

## Validate the SAS Viya platform

Before exploring storage use in the SAS Viya platform, let's perform some cursory checks to ensure that apps and services are functioning as expected.

### Review storage resources in Viya's namespace

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

This is an important step - some of [these resources cost money](https://cloud.google.com/products/calculator) just by existing! When you're done with this workshop, please ensure all of your resources have been destroyed.

### Uninstall Viya from Google Kubernetes Engine

1.  [If needed] Unset sas-viya CLI SSL env vars

    ```bash
    # ensure gcloud CLI and Azure CLI can use their encrypted comm
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

1.  Destroy the Google Cloud infrastructure defined by the IAC using Terraform

    ```bash
    cd ~/project/gcp/viya4-iac-gcp

    # terraform destroy
    terraform destroy -auto-approve \
        -var-file ./${MY_PREFIX}.tfvars \
        -state ./${MY_PREFIX}.tfstate
    ```

    > Note: Sometimes Google Cloud is slow to destroy resources and Terraform might timeout when waiting. Usually a second run of the `terraform destroy` command will work.

### &#9655; Status Check

All resources in Google Cloud created for these exercises have been deleted.
