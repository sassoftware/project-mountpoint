# Deploy SAS Viya to Azure with 3 Starter Storage Classes (ACSv2)

> Note this exercise specifies Azure Container Storage v2 to use the node-local NVMe disk for SASWORK and CAS_DISK_CACHE.

Let's get this done. This page provides a streamlined deployment of SAS Viya to Microsoft Azure. We focus on a "happy path" approach that highlights the concept of 3 Starter Storage Classes as outlined in Project Mountpoint.

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
- [Initialize the workshop environment](#initialize-the-workshop-environment)
- [Get Viya resources and assets](#get-viya-resources-and-assets)
    - [Download the order assets for SAS Viya](#download-the-order-assets-for-sas-viya)
    - [▶ PMP: Configure the Viya assets](#-pmp-configure-the-viya-assets)
    - [▷ Status Check](#-status-check)
- [Infrastructure](#infrastructure)
    - [Setup SSH key](#setup-ssh-key)
    - [Set up Terraform](#set-up-terraform)
    - [Obtain the Terraform templates](#obtain-the-terraform-templates)
    - [Set-up the Terraform and initialize the configuration](#set-up-the-terraform-and-initialize-the-configuration)
    - [Configure Terraform for desired Azure resources](#configure-terraform-for-desired-azure-resources)
    - [Use Terraform to provision infrastructure](#use-terraform-to-provision-infrastructure)
    - [Get k8s clients set up](#get-k8s-clients-set-up)
    - [▷ Status Check](#-status-check-1)
- [▶ PMP: Provision and configure storage in Azure](#-pmp-provision-and-configure-storage-in-azure)
    - [Azure provides storage classes out-of-the-box](#azure-provides-storage-classes-out-of-the-box)
    - [RWO storage for `viya-standard-sc`: Azure managed disk](#rwo-storage-for-viya-standard-sc-azure-managed-disk)
    - [Local storage for `viya-scratch-sc`: Azure Container Storage v2 (for NVMe)](#local-storage-for-viya-scratch-sc-azure-container-storage-v2-for-nvme)
    - [RWX storage for `viya-shared-sc`: NFS Server](#rwx-storage-for-viya-shared-sc-nfs-server)
    - [▷ Status Check](#-status-check-2)
- [Provision and configure supporting 3rd-party resources](#provision-and-configure-supporting-3rd-party-resources)
    - [Deploy GEL's demo LDAP service](#deploy-gels-demo-ldap-service)
    - [Install OpenSSL as the certificate generator](#install-openssl-as-the-certificate-generator)
    - [Confirm files match configuration](#confirm-files-match-configuration)
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
    - [Uninstall Viya from Azure](#uninstall-viya-from-azure)
    - [Destroy cloud resources](#destroy-cloud-resources)
    - [▷ Status Check](#-status-check-6)

## Basis

The deployment process here is heavily borrowed from the [SAS® Viya®: Deployment on Azure Kubernetes Service](https://learn.sas.com/course/view.php?id=6419) (learn.sas.com) workshop.

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

### Download the order assets for SAS Viya

1.  Figure out what to call things and where to put them:

    ```bash
    # as cloud-user on your Linux host in RACE

    # Local variables to configure Viya deployment
    iac_dir=$HOME/project/aks/viya4-iac-azure
    Tenant=$(cat ~/project/vars/.aztf_creds | grep TF_VAR_tenant_id | awk -F'=' '{print $2}')
    Workshop_Sub=$(cat ~/project/vars/.aztf_creds | grep TF_VAR_subscription_id | awk -F'=' '{print $2}')
    myPrefix=$(cat ~/MY_PREFIX.txt)
    myLocation=$(cat ~/azureregion.txt )
    myTags=$(cat ~/MY_TAGS.txt)", \"gel_project\" = \"PSGEL298 Track-A\" "
    
    # Set the K8s general configuration (version pinning)
    source $HOME/workshop_assets/platform/build-vars.txt

    # Pick the name of the namespace for Viya
    export MY_NS=viya

    # create the project folder for our Viya collateral
    mkdir -p ~/project/deploy/${MY_NS}/site-config/storage
    ```

1.  Download the SAS Viya order assets

    ```bash
    # Desired version of SAS Viya
    export MY_CADENCE_NAME='lts'
    export MY_CADENCE_VERSION='2026.03'

    # Remember it
    #add_my_var MY_CADENCE_NAME
    #add_my_var MY_CADENCE_VERSION

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
    #add_my_var MY_ORDERNUM

    # Say it
    echo "MY_ORDERNUM:" $MY_ORDERNUM
    ```

    > Note, if the value of `$MY_ORDERNUM` is blank or otherwise incorrect, then fix before proceeding.

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
    #VIYA_FQDN="$MY_VIYA_FQDN"

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
          - INGRESS_HOST={{viya_fqdn}}
      - name: sas-shared-config
        behavior: merge
        literals:
          - SAS_SERVICES_URL=https://{{viya_fqdn}}
    EOF
    ```

    > Note: This is basically the [initial kustomization.yaml](https://documentation.sas.com/?cdcId=itopscdc&cdcVersion=default&docsetId=dplyml0phy0dkr&docsetTarget=n0g237aqo6pz1in1t19wjb94j9bi.htm) shown in SAS documentation, but improved slightly:
    > - enables the "`sas-workload-orchestrator`" resources to add clusterrole and -binding
    >
    >   for Viya 2025.12 and later, append "`/cluster-role`"
    >
    > - specifies the fully-qualified domain name for ingress host and the SAS services url
    >
    > Additional configuration to kustomization.yaml is provided later as those related elements are deployed. The placeholder for the Viya's ingress FQDN will be modified later, too.

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

### Setup SSH key

The IAC will create machines in Azure which can be accessed with cloud-user's default SSH key (`~/.ssh/id_rsa`). So create that now.

```bash
# ensure there is a .ssh dir in $HOME
ansible localhost -m file \
  -a "path=$HOME/.ssh mode=0700 state=directory"

# ensure there is an ssh key that we can use
ansible localhost -m openssh_keypair \
  -a "path=~/.ssh/id_rsa type=rsa size=2048" --diff
```

> *Note: The resulting `~/.ssh/id_rsa` file is referenced by default when `ssh`'ing, unless a different file is specified using the `-i` switch.*

### Set up Terraform

1. Install the Terraform YUM repository

    ```bash
    ## Install yum-config-manager to manage your repositories.
    sudo yum install -y yum-utils
    ## Use yum-config-manager to add the official HashiCorp Linux repository.
    #sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
    # Use an alternative repo
    sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
    ```

    *Note: you may see some warning messages due to the Centos image that is being used. You can ignore these.*

1. We want to pin our Terraform version to the version required by the "SAS Viya 4 IaC" tool.

    ```bash
    ## List available releases
    yum --showduplicate list terraform -y

    ## Use a version that is supported by the viya4-iac project
    source $HOME/workshop_assets/platform/build-vars.txt

    ## install
    sudo yum install -y terraform-${TERRAFORM_VERSION}
    ```

### Obtain the Terraform templates

The Terraform templates that we need comes from this <a href="https://github.com/sassoftware/viya4-iac-azure" target="_blank">project</a>.
Since they are public, they are not included in the payload tarball.

1. Get the Terraform artifacts from GitHub and checkout a specific version

    ```bash
    rm -Rf ~/project/aks/viya4-iac-azure
    mkdir -p ~/project/aks/
    cd ~/project/aks/

    # Download the IAC project
    git clone https://github.com/sassoftware/viya4-iac-azure.git

    # Instead of being at the mercy of the latest changes, we pin to a specific version
    cd ~/project/aks/viya4-iac-azure/
    git fetch --all

    source $HOME/workshop_assets/platform/build-vars.txt
    git checkout tags/${IAC_AZURE_TAG}
    ```

### Set-up the Terraform and initialize the configuration

As you will be using Terraform interactively we will use the workshop SP Azure credentials when running Terraform from the Azure CLI.

1. Run this command to initialize terraform in our environment.

    ```bash
    cd ~/project/aks/viya4-iac-azure

    # Initialize terraform environment
    terraform init
    ```

    Success will be shown as:

    ```log
    Terraform has been successfully initialized!

    You may now begin working with Terraform. Try running "terraform plan" to see any changes that are required for your infrastructure. All Terraform commands should now work.
    ```

### Configure Terraform for desired Azure resources

Let's create our Terraform variables file (gel-vars.tfvars) with multiple node pools: cas node pool, compute node pool, stateless and stateful node pool.

To avoid having to cut and paste a large code block a template has been set-up. We need to update this for your environment.

1.  Get the template for the 'tfvars' file.

    ```bash
    iac_dir=$HOME/project/aks/viya4-iac-azure
    cd $iac_dir

    # Copy and rename the template
    cp $HOME/workshop_assets/gelenable_tfvars/track_a_gel-vars.tfvars \
    ./gel-vars.tfvars

    # Make a backup copy for comparison
    cp ./gel-vars.tfvars ./gel-vars.tfvars.bak
    ```

1.  Update the template for your environment.

    The template needs to be updated for your environment. This includes setting the right prefix and tags for your resources.

    ```bash
    # Update tenant and subscription
    sed -i 's/{{tfvars_tenant}}/'"${Tenant}"'/' ${iac_dir}/gel-vars.tfvars
    sed -i 's/{{tfvars_subscription}}/'"${Workshop_Sub}"'/' ${iac_dir}/gel-vars.tfvars
    
    # Update the prefix
    sed -i 's/{{tfvars_prefix}}/'"${myPrefix}"'/' ${iac_dir}/gel-vars.tfvars
    
    # Update the location
    sed -i 's/{{tfvars_location}}/'"${myLocation}"'/' ${iac_dir}/gel-vars.tfvars
    
    # Set K8s version and tier
    sed -i 's/{{tfvars_k8s_version}}/'"${k8s_version}"'/' ${iac_dir}/gel-vars.tfvars
    sed -i 's/{{tfvars_aks_sku_tier}}/'"${aks_cluster_sku_tier}"'/' ${iac_dir}/gel-vars.tfvars
    sed -i 's/{{tfvars_aks_support_tier}}/'"${cluster_support_tier}"'/' ${iac_dir}/gel-vars.tfvars
    
    # Update the tags
    sed -i 's/{{tfvars_tags}}/'"${myTags}"'/' ${iac_dir}/gel-vars.tfvars
    
    # Verify token replacement
    icdiff gel-vars.tfvars.bak gel-vars.tfvars
    ```

    > Note if the right side of the `icdiff` output shows empty/null values for the "`{{ tokens }}`", then ensure you've executed the following command in the current terminal:
    >
    > `source $HOME/workshop_assets/platform/build-vars.txt`

1.  Postgres configuration

    The original workshop specifies the use of an external Postgres server. That's not needed here. So let's remove those directives and then the IAC will default to use internal Crunchy Postgres. 

    ```bash
    # Remove the postgres_servers block definition - and make a backup of the original file
    sed -i.bak '/^postgres_servers = {/,/^}/d' gel-vars.tfvars

    # Verify the removal of external Postgres directives
    icdiff gel-vars.tfvars.bak gel-vars.tfvars
    ```

    ---
    
    <details>
    <summary>Alternative: click here for instructions to keep the use of external Postges instead</summary>
    
    Update the template for the external Postgres parameters.

    When the RACE collection was created a random password was generated for the Postgres admin user. This is stored in the file: $HOME/SIDS_Admin_PASS.txt

    ```bash
    source $HOME/workshop_assets/platform/build-vars.txt

    iac_dir=$HOME/project/aks/viya4-iac-azure
    tfvars_pguser=pgadmin
    tfvars_pgpass=$(cat $HOME/SIDS_Admin_PASS.txt)

    # Update the template
    sed -i 's/{{tfvars_pguser}}/'"${tfvars_pguser}"'/' ${iac_dir}/gel-vars.tfvars
    sed -i 's/{{tfvars_pgpass}}/'"${tfvars_pgpass}"'/' ${iac_dir}/gel-vars.tfvars
    sed -i 's/{{tfvars_pgversion}}/'"${tfvars_pgversion}"'/' ${iac_dir}/gel-vars.tfvars
    ```
    </details>

    ---

1.  Update the Azure VM OS type

    The final change we will make is to update the OS for the Jump Host and NFS Server virtual machines. This is perhaps a non-standard change, but illustrates how to override the IaC defaults.

    There are two variables to update in the `/modules/azurerm_vm/variables.tf` file. The `os_offer` and `os_sku` need to be updated.

    ```bash
    cd ~/project/aks/viya4-iac-azure

    # Update for IaC 10.4.0 and later
    # Update the os_offer
    sed -i 's/0001-com-ubuntu-server-jammy/ubuntu-24_04-lts/g' ./modules/azurerm_vm/variables.tf
    
    # Update the OS SKU
    sed -i 's/22_04-lts/server/g' ./modules/azurerm_vm/variables.tf
    ```

1.  Modify the machine types for CAS and Compute to support Azure Container Storage for local NVMe and add the required labels

    ```bash
    # Modify the node pool definitions for CAS and Compute
    sed -i \
    -e '/^  cas = {/,/^  },/ s|^    "machine_type" = "Standard_E4ds_v4".*|    #"machine_type" = "Standard_E4ds_v4"         # 4x32 w 150GiB SSD\n    "machine_type" = "Standard_L8s_v3"|' \
    -e '/^  compute = {/,/^  },/ s|^    #"machine_type" = "Standard_L8s_v2".*|    #"machine_type" = "Standard_L8s_v2"         # 8x64 w 80GBSSD 1.9TB NVMe|' \
    -e '/^  compute = {/,/^  },/ s|^    "machine_type" = "Standard_E8ds_v4".*|    #"machine_type" = "Standard_E8ds_v4"         # 8x64 w 300GiB SSD\n    "machine_type" = "Standard_L8s_v3"|' \
    -e '/^  cas = {/,/^  },/ s|"workload.sas.com/class" = "cas"|"workload.sas.com/class" = "cas"\n      "acstor.azure.com/io-engine" = "acstor"|' \
    -e '/^  compute = {/,/^  },/ s|"launcher.sas.com/prepullImage" = "sas-programming-environment"|"launcher.sas.com/prepullImage" = "sas-programming-environment"\n      "acstor.azure.com/io-engine" = "acstor"|' \
    gel-vars.tfvars

    # If needed, pick an AZ ("1", "2", or "3") with more ready capacity
    sed -i 's/^default_nodepool_availability_zones.*$/default_nodepool_availability_zones  = ["2"]/' gel-vars.tfvars
    sed -i 's/^node_pools_availability_zone.*$/node_pools_availability_zone         = "2"/' gel-vars.tfvars

    # Verify new machine types and labels
    icdiff gel-vars.tfvars.bak gel-vars.tfvars
    ```

    > Note this sed action comments out the previous machine type and adds a new one that support Azure Container Storage with the local NVMe disk. ACS requires those nodes to have the "`acstor`" label as well.

### Use Terraform to provision infrastructure

With the terraform variables all defined, now we can provision the infrastructure in Azure.

1.  Generate the Terraform plan

    ```bash
    cd ~/project/aks/viya4-iac-azure

    # direct terraform to create a plan, runs in seconds
    terraform plan \
        -input=false \
        -var-file=./gel-vars.tfvars \
        -out ./${myPrefix}.tfplan
    ```

1.  Apply the Terraform plan:

    ```bash
    # direct terraform to apply the plan to provision resources in Azure 
    time terraform apply -state ./${myPrefix}.tfstate "./${myPrefix}.tfplan"
    ```

    It only takes 10-15 minutes for Terraform to complete the provisioning of resources in Azure.

1.  Quick verification of Azure resources

    ```bash
    # symlink for expected filename (hardcoded)
    ln -s $myPrefix.tfplan my-aks.plan

    # Basic health check
    bash $HOME/workshop_scripts/utils/GEL.Infrastructure.HealthCheck.sh track-a
    ```

    With results expected like:

    ```log
    Starting environment checks...

    Testing the AKS node pools
    Node Pool: cas Passed
    Node Pool: compute Passed
    Node Pool: stateless Passed
    Node Pool: stateful Passed
    Testing Postgres
    Testing the NFS Server
    Testing the Jump Server


    Summary of environment check results

    The environment test: Passed

    AKS cluster:              Passed
    NFS Server:               Passed
    Jump Server:              Passed
    Postgres Flexible Server: Posgres not configured
    ```

    ---

    <details>
    <summary>Health check failure? Click here.</summary>

    If one of the resources shows Failed above, then try provisioning again.

    Re-`plan` and re-`apply`:

    ```sh
    cd ~/project/aks/viya4-iac-azure

    # re-plan (and include the current state)
    terraform plan \
        -input=false \
        -var-file=./gel-vars.tfvars \
        -state ./${myPrefix}.tfstate \
        -out ./${myPrefix}.tfplan

    # re-apply the updated plan
    terraform apply -state ./${myPrefix}.tfstate "./${myPrefix}.tfplan"
    ```

    </details>

    ---

1.  Remember the current state

    There are a number of configuration variables that are needed for the lab exercises. Now that the AKS cluster has been provisioned let's collect them and save them to a file for later use.

    ```bash
    # Query terraform to create a variables.txt file for later use

    VARS_DIR=$HOME/project/vars
    rm -f ${VARS_DIR}/variables.txt

    cd ~/project/aks/viya4-iac-azure/

    echo "subscription::"$(cat ${VARS_DIR}/.aztf_creds | grep subscription | awk -F'=' '{print $2}') | tee -a ${VARS_DIR}/variables.txt
    echo "tenant::"$(cat ${VARS_DIR}/.aztf_creds | grep tenant | awk -F'=' '{print $2}') | tee -a ${VARS_DIR}/variables.txt
    echo "cluster-name::"$(terraform output -state $myPrefix.tfstate -raw cluster_name) | tee -a ${VARS_DIR}/variables.txt
    echo "resource-group::"$(terraform output -state $myPrefix.tfstate -raw prefix)"-rg" | tee -a ${VARS_DIR}/variables.txt
    echo "node-res-group::MC_"$(terraform output -state $myPrefix.tfstate -raw prefix)"-rg_"$(terraform output -state $myPrefix.tfstate -raw cluster_name)"_"$(terraform output -state $myPrefix.tfstate -raw location) | tee -a ${VARS_DIR}/variables.txt
    echo "prefix::"$(terraform output -state $myPrefix.tfstate -raw prefix) | tee -a ${VARS_DIR}/variables.txt
    echo "location::"$(terraform output -state $myPrefix.tfstate -raw location) | tee -a ${VARS_DIR}/variables.txt
    echo "postgres-server::"$(terraform output -state $myPrefix.tfstate postgres_servers | grep fqdn | awk -F'= "' '{print $2}' | sed 's/"//g') | tee -a ${VARS_DIR}/variables.txt
    echo "postgres-admin::"$(terraform output -state $myPrefix.tfstate postgres_servers | grep admin | awk -F'= "' '{print $2}' | sed 's/"//g') | tee -a ${VARS_DIR}/variables.txt
    echo "postgres-pass::"$(cat $HOME/SIDS_Admin_PASS.txt) | tee -a ${VARS_DIR}/variables.txt
    echo "postgres-port::"$(terraform output -state $myPrefix.tfstate postgres_servers | grep server_port | awk -F'= "' '{print $2}' | sed 's/"//g') | tee -a ${VARS_DIR}/variables.txt
    echo "nfs-ip::"$(terraform output -state $myPrefix.tfstate -raw rwx_filestore_endpoint) | tee -a ${VARS_DIR}/variables.txt
    echo "nfs-path::"$(terraform output -state $myPrefix.tfstate -raw rwx_filestore_path) | tee -a ${VARS_DIR}/variables.txt
    echo "nfs-admin::"$(terraform output -state $myPrefix.tfstate -raw nfs_admin_username) | tee -a ${VARS_DIR}/variables.txt
    echo "jump-admin::"$(terraform output -state $myPrefix.tfstate -raw jump_admin_username) | tee -a ${VARS_DIR}/variables.txt
    printf "\nYour environment varables\n-------------------------\n$(cat ${VARS_DIR}/variables.txt) \n\n"
    ```

1.  Create a file to source the values as variables.

    ```bash
    # Create a variables file that can be sourced rather than searched

    VARS_DIR=$HOME/project/vars
    rm -f ${VARS_DIR}/env-vars.txt
    
    while read line; do
      var_name=$(echo $line | awk -F'::' '{print $1}' | sed 's/-/_/g')
      var_value=$(echo $line | awk -F'::' '{print $2}')
      echo "${var_name}='${var_value}'" | tee -a ${VARS_DIR}/env-vars.txt
    done < ${VARS_DIR}/variables.txt
    ```

    With results like:

    ```log
    subscription='e8d9e6ad-9325-4c8d-a301-4e6xxx40fc8b'
    tenant='a708xxx9-1d96-416a-ad34-72fa07ff196d'
    cluster_name='cadet-p41744-aks'
    resource_group='cadet-p41744-rg'
    node_res_group='MC_cadet-p41744-rg_cadet-p41744-aks_westus3'
    prefix='cadet-p41744'
    location='westus3'
    postgres_server=''
    postgres_admin=''
    postgres_pass='AaxxxxaNFQQrZRF'
    postgres_port=''
    nfs_ip='192.168.2.4'
    nfs_path='/export'
    nfs_admin='nfsuser'
    jump_admin='jumpuser'
    ```

    > Note that we didn't direct the creation of an external Postgres server - so Terraform has no information about that to share.

### Get k8s clients set up

1.  Use terraform to create a kubeconfig file

    ```bash
    cd ~/project/aks/viya4-iac-azure

    # direct terraform to create a kubectl configuration file
    terraform output -state ./${myPrefix}.tfstate -raw kube_config > ${myPrefix}.kube.conf

    # Create the .kube directory in your home directory
    mkdir -p ~/.kube

    # Copy kubeconfig to its default location
    cp -p ./${myPrefix}.kube.conf   ~/.kube/config
    chmod 600 ~/.kube/config
    ```

1.  Update kubectl to match the Kubernetes server version

    Kubectl is already installed on your Linux host in RACE, but it's old and not within the [accepted skew range](https://kubernetes.io/releases/version-skew-policy/). Let's update it to match the version running in AKS.

    ```bash
    # Identify the AKS version and install kubectl to match
    VARS_DIR=$HOME/project/vars
    RG=$(cat ${VARS_DIR}/variables.txt | grep resource-group | awk -F'::' '{print $2}')
    AKS_NAME=$(cat ${VARS_DIR}/variables.txt | grep cluster-name | awk -F'::' '{print $2}')
    
    # Get the Kubernetes version
    AKS_VER_FULL=$(az aks show --resource-group $RG --name $AKS_NAME --query "currentKubernetesVersion" -o tsv)
    printf "\nKubernetes version:  ${AKS_VER_FULL}\n\n"
    
    # Install the version of the CLI to match the AKS version
    sudo curl -L "https://dl.k8s.io/release/v${AKS_VER_FULL}/bin/linux/amd64/kubectl" -o /usr/local/bin/kubectl
    sudo chmod +x /usr/local/bin/kubectl

    # Verify our new local install of `kubectl` is working:
    kubectl version
    ```

    With results similar to:

    ```log
    Client Version: v1.34.9
    Kustomize Version: v5.7.1
    Server Version: v1.34.9
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
    wget https://raw.githubusercontent.com/derailed/k9s/refs/heads/master/skins/${K9S_SKIN}.yaml -O $HOME/.config/k9s/skins/${K9S_SKIN}.yaml

    # Configure k9s to use it
    yq -i ".k9s.ui.skin = \"${K9S_SKIN}"\" $HOME/.config/k9s/config.yaml
    ```

    Refer to the [K9s documentation](https://k9scli.io) for more information.

    </details>

    ---

### &#9655; Status Check

We've stood up the core infrastructure in Azure in alignment with our planned configuration of SAS Viya. And we've set up Kubernetes clients to give us administration and monitoring. But there's more yet to do...

## &#9654; PMP: Provision and configure storage in Azure

At the risk of repetition, the site is responsible for providing storage that meets Viya's requirements. This section shows an approach where the site has evaluated Viya's use of storage and selected appropriate technologies. We show installing CSI Drivers and such because you need to see it. However, to be clear, the ideal is that the site will do this work, including validating that it's all working properly *before* attempting to use it for Viya's services.

> Note: Project Mountpoint's contribution here is the idea of *copying* storage classes. By giving Viya its own set of storage class names, we abstract Viya's config from the physical implementation. This isn't required - the site is free to use any names for storage classes it wants - but the additional layer of abstraction gives us another aspect of control.

The IAC will setup your choice of supported shared (RWX) storage provider. But we also need CSI drivers and other resources. Some of these would be handled automatically by the DAC project, but we're not using that here.

-   We will make copies of storage classes. To help aid that task:

    ```bash
    # define the "copysc" function 
    source $HOME/project-mountpoint/bin/copySC.sh
    ```

### Azure provides storage classes out-of-the-box

Azure provides several storage classes for immediate use.

1. Let's see what's there:

    ```bash
    $ kubectl get sc

    NAME                    PROVISIONER          RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
    azurefile               file.csi.azure.com   Delete          Immediate              true                   79m
    azurefile-csi           file.csi.azure.com   Delete          Immediate              true                   79m
    azurefile-csi-premium   file.csi.azure.com   Delete          Immediate              true                   79m
    azurefile-premium       file.csi.azure.com   Delete          Immediate              true                   79m
    default (default)       disk.csi.azure.com   Delete          WaitForFirstConsumer   true                   79m
    managed                 disk.csi.azure.com   Delete          WaitForFirstConsumer   true                   79m
    managed-csi             disk.csi.azure.com   Delete          WaitForFirstConsumer   true                   79m
    managed-csi-premium     disk.csi.azure.com   Delete          WaitForFirstConsumer   true                   79m
    managed-premium         disk.csi.azure.com   Delete          WaitForFirstConsumer   true                   79m
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

### RWO storage for `viya-standard-sc`: Azure managed disk

The "viya-standard-sc" storage class is intended for use by [services that need persistent RWO volumes](/3SSC-Three-Starter-Storage-Classes/). SAS Viya services like Crunchy Postgres, RabbitMQ, Redis, Consul, and OpenSearch all need persistent RWO volumes.

The `disk.csi.azure.com` driver to use [Azure Managed Files](https://learn.microsoft.com/en-us/azure/aks/concepts-storage) is already installed and associated storage classes with different levels of performance have been defined for our use.

1.  &#9654; PMP: Copy the `managed` storage class to make `viya-standard-sc`:

    ```bash
    cd ~/project/deploy/$MY_NS

    # Make a copy
    copysc managed viya-standard-sc
    ```

1.  Review the resulting file `defineSC_viya-standard-sc.yaml`:

    ```yaml
    allowVolumeExpansion: true
    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
      labels:
        addonmanager.kubernetes.io/mode: EnsureExists
        kubernetes.io/cluster-service: "true"
      name: viya-standard-sc
    parameters:
      cachingmode: ReadOnly
      kind: Managed
      storageaccounttype: StandardSSD_ZRS
    provisioner: disk.csi.azure.com
    reclaimPolicy: Delete
    volumeBindingMode: WaitForFirstConsumer
    ```

    Edit the file to make any desired changes.

1.  When it's acceptable, then create the viya-standard-sc storage class in the AKS cluster:

    ```bash
    # Apply the storage class definition
    kubectl apply -f defineSC_viya-standard-sc.yaml
    ```

### Local storage for `viya-scratch-sc`: Azure Container Storage v2 (for NVMe)

The "viya-scratch-sc" storage class is intended for use by [SASWORK and CAS_DISK_CACHE](/3SSC-Three-Starter-Storage-Classes/). SAS Programming Runtime Environment (including SAS Batch, SAS Compute, and SAS Connect Servers) and the SAS Cloud Analytic Services (CAS) rely on this space for low-latency and high-throughput - something local disk in the cloud does well for little additional cost.

There are several ways to provide Kubernetes with access to local disk, but for this effort we want a CSI Driver that can *dynamically* provision volumes on local disk. In this section, we'll set up [Azure Container Storage v2](https://blog.aks.azure.com/2025/09/15/acstor-v2-ga).

Local disk on a node is not a given. It takes extra steps for a site to format and mount the local disk for use. But it's worth the extra effort.

1.  Format and mount additional local disk drives

    > NOT NEEDED YET. We'll set up Azure Container Storage to do this for us automatically. The extra node-local NVMe disk will be formatted and mounted soon.
    >
    > ```log
    >  NAME      SIZE TYPE FSTYPE MOUNTPOINT
    > sda       200G disk        
    > |-sda1  199.9G part ext4   /
    > |-sda14     4M part        
    > `-sda15   106M part vfat   /boot/efi
    > sdb        80G disk        
    > `-sdb1     80G part ext4   /mnt
    > sr0       760K rom         
    > nvme0n1   1.7T disk        
    > ```
    >
    > FYI:
    > - `/` (root volume): located on `sda1` (199G partition on 200G disk)
    > - (addtl disk): located on `nvme0n1` (1.7T unmounted NVMe disk)

1.  Enable Azure Container Storage v2 (not v1)

    We've already labeled the CAS and Compute nodes for ACS. Now we can enable it to use them.

    ```bash
    # add the k8s extension to aks cli
    az extension add -n k8s-extension

    # Update the AKS cluster to enable ACS to use local NVMe
    az k8s-extension create \
        --cluster-type managedClusters \
        --cluster-name ${myPrefix}-aks \
        --resource-group ${myPrefix}-rg \
        --name azurecontainerstorage \
        --extension-type microsoft.azurecontainerstoragev2 \
        --configuration-settings enable-azure-container-storage=true
    ```

    > Note that warnings about "Python" and "KubernetesConfiguration" are okay. It might take a few moments before the "`Running ..`" indicator appears. And for about 5-10 minutes to pass before it all completes.
    >
    > This process registers the extension with the AKS cluster. Then it deploys ACS IO Engine container images to the nodes with the "`acstor`" label. Once those ACS pods are running, they'll scan the PCIe bus to find the raw NVMe devices to claim them, initializing them with format and striping.

1.  Create the "`acstor-nvme`" storage class:

    ```bash
    cat << EOF > ~/project/deploy/defineSC_acstor-nvme.yaml
    allowVolumeExpansion: true
    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
      name: acstor-nvme
    provisioner: localdisk.csi.acstor.io
    reclaimPolicy: Delete
    volumeBindingMode: WaitForFirstConsumer
    EOF

    # Apply to k8s
    kubectl apply -f ~/project/deploy/defineSC_acstor-nvme.yaml

    # Validate
    kubectl describe sc acstor-nvme
    ```

1.  &#9654; PMP: Copy the `acstor-nvme` storage class to make `viya-scratch-sc`:

    ```bash
    # Make a copy
    copysc acstor-nvme viya-scratch-sc
    ```

1.  Review resulting file `defineSC_viya-scratch-sc.yaml`:

    ```yaml
    allowVolumeExpansion: true
    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
      name: viya-scratch-sc
    provisioner: localdisk.csi.acstor.io
    reclaimPolicy: Delete
    volumeBindingMode: WaitForFirstConsumer
    ```

    Edit the file to make any desired changes.

1.  When it's acceptable, then apply it:

    ```bash
    # Apply the storage class definition
    kubectl apply -f defineSC_viya-scratch-sc.yaml
    ```

### RWX storage for `viya-shared-sc`: NFS Server

The "viya-shared-sc" storage class is intended for use by [services that need persistent RWX volumes](/3SSC-Three-Starter-Storage-Classes/). SAS Viya services like sas-backup-job, sas-common-files, sas-pyconfig and others all need persistent RWX volumes so that multiple pods running on different nodes can access the same set of shared files.

The IAC for Azure provides two options of RWX storage that it can provide. We'll go with the NFS Server option here for simplicity. But for robust production use, consider using Azure NetApp Files instead.

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
    export NFS_IP=`terraform output -state $HOME/project/aks/viya4-iac-azure/${myPrefix}.tfstate -raw rwx_filestore_endpoint`
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

    > Note that the base directory path is defined here in the storage class. We chose a path and naming convention here that matches with the `viya4-deployment` project's approach when using the legacy nfs-subdir-external-provisioner.

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
        server: 123.45.67.8
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

NAME                    PROVISIONER               RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION
acstor-nvme             localdisk.csi.acstor.io   Delete          WaitForFirstConsumer   true

azurefile               file.csi.azure.com        Delete          Immediate              true
azurefile-csi           file.csi.azure.com        Delete          Immediate              true
azurefile-csi-premium   file.csi.azure.com        Delete          Immediate              true
azurefile-premium       file.csi.azure.com        Delete          Immediate              true
default                 disk.csi.azure.com        Delete          WaitForFirstConsumer   true
managed                 disk.csi.azure.com        Delete          WaitForFirstConsumer   true
managed-csi             disk.csi.azure.com        Delete          WaitForFirstConsumer   true
managed-csi-premium     disk.csi.azure.com        Delete          WaitForFirstConsumer   true
managed-premium         disk.csi.azure.com        Delete          WaitForFirstConsumer   true

nfs                     nfs.csi.k8s.io            Retain          WaitForFirstConsumer   false

viya-scratch-sc         localdisk.csi.acstor.io   Delete          WaitForFirstConsumer   true
viya-shared-sc          nfs.csi.k8s.io            Retain          WaitForFirstConsumer   false 
viya-standard-sc        disk.csi.azure.com        Delete          WaitForFirstConsumer   true
```

> Note: this approach allows us to specify storage for Viya ***without modifying Viya's storage configuration***. Don't want "`acstor-nvme`" as the basis for "`viya-scratch-sc`"? Then use "`managed-premium`" instead - it's a lot slower and costs a bit more, but it will function.

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

    # Deploy gelldap to the AKS cluster
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

### Install ingress-nginx

SAS Viya requires [ingress-nginx](https://github.com/kubernetes/ingress-nginx) as the ingress controller.

1.  Install the Ingress NGINX Controller

    ```bash
    # Get the Cloud NAT IP
    export NATIP=$(terraform output -state $HOME/project/aks/viya4-iac-azure/${myPrefix}.tfstate -raw nat_ip)

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

Let's use the Azure CLI to associate the DNS to the newly created Public IP address.

1.  First we need to get the LB Public IP id (as defined in the Azure Cloud).

    ```bash
    VARS_DIR=$HOME/project/vars
    node_res_group=$(cat ${VARS_DIR}/variables.txt | grep node-res-group | awk -F'::' '{print $2}')
    # get the LB Public IP id (as defined in the Azure Cloud)
    PublicIPId=$(az network lb show \
      -g ${node_res_group} -n kubernetes \
      --query "frontendIPConfigurations[].publicIPAddress.id" \
      --out table | grep kubernetes\
      )
    echo $PublicIPId
    ```

1.  Now,  we use the Public IP Id to create and associate a DNS alias:

    ```bash
    VARS_DIR=$HOME/project/vars
    RG=$(cat ${VARS_DIR}/variables.txt | grep resource-group | awk -F'::' '{print $2}')
    # Use the Id to associate a DNS alias
    az network public-ip update \
        -g ${node_res_group} \
        --ids $PublicIPId --dns-name ${RG} -o yaml
    ```

1.  Validate that the DNS name is working using nslookup

    ```bash
    #get the FQDN
    FQDN=$(az network public-ip show --ids "${PublicIPId}" --query "{ fqdn: dnsSettings.fqdn }" --out tsv)
    echo $FQDN

    # Use nslookup for the FQDN
    nslookup $FQDN
    ```

    You should see output referencing your Prefix similar to:

    ```log
    Server:		192.0.2.206.166
    Address:	192.0.2.206.166#53

    Non-authoritative answer:
    Name:	cadet-p41744-rg.westus3.cloudapp.azure.com
    Address: 4.249.85.12
    ```

1. Update the kustomization.yaml to use the new FQDN

    ```bash
    # Provide ingress endpoint and url
    sed -i "s/{{viya_fqdn}}/$FQDN/g" $HOME/project/deploy/$MY_NS/kustomization.yaml

    # verify
    icdiff $HOME/project/deploy/$MY_NS/kustomization.yaml.bak* $HOME/project/deploy/$MY_NS/kustomization.yaml
    ```

### &#9655; Status Check

We've rounded out the remaining items needed for deploying the SAS Viya platform. 

## Deploy the SAS Viya platform

We'll use the SAS Orchestration Utility to deploy the SAS Viya platform to AKS.

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

You've kicked off the deployment SAS Viya software to the Azure infrastructure using the SAS Orchestration utility.

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

    echo -e "\n>>> The landing page for your SAS Viya platform is: \n\n    https://${FQDN}/SASLanding/\n"
    ```

    Copy and paste the provided URL to your web browser.

    > Note: If you browser warns that the connection isn't private, click through to advance.
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

This is an important step - some of [these resources cost money](https://azure.microsoft.com/en-us/pricing/calculator) just by existing! When you're done with this workshop, please ensure all of your resources have been destroyed.

### Uninstall Viya from Azure

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

1.  Run the workshop script to delete AKS resources

    ```sh
    bash $HOME/workshop_scripts/utils/GEL.400.Delete.Environment.sh
    ```

    You can use the following command to check for the existance of the resource group.

    ```sh
    RG=$(cat ~/MY_PREFIX.txt)-rg
    rgExists=$(az group exists --name ${RG})
    
    if [ $rgExists = "false" ]; then
      printf "\n\nIt is safe to proceed / restart the AKS environment build.\n\n"
    else
      printf "\n\nThe Resource Group exists.\n\n"
    fi
    ```

### &#9655; Status Check

All resources in Azure created for these exercises have been deleted.
