# Deploy SAS Viya to OpenShift Container Platform with 3 Starter Storage Classes

Let's get this done. This page provides a streamlined deployment of SAS Viya to Red Hat OpenShift Container Platform. We focus on a "happy path" approach that highlights the concept of 3 Starter Storage Classes as outlined in Project Mountpoint.

> Note: This exercise takes an "upside-down" approach to deployment compared to other GEL deployment workshops. We will:
> - get Viya order assets and configure them *first*
> - *then*, provision infrastructure to match Viya's config
> - *and* deploy SAS Viya
>
> In the TOC below, the deployment aspects where Project Mountpoint contributes significantly are marked with "&#9654; PMP". As you can see, it's just a small part of the larger SAS Viya platform implementation.

Here's the plan:

- [Deploy SAS Viya to OpenShift Container Platform with 3 Starter Storage Classes](#deploy-sas-viya-to-openshift-container-platform-with-3-starter-storage-classes)
    - [Basis](#basis)
    - [Reserve a RACE collection](#reserve-a-race-collection)
    - [Logon to RACE host(s)](#logon-to-race-hosts)
    - [▶ PMP: Clone Project Mountpoint](#-pmp-clone-project-mountpoint)
    - [Get Viya resources and assets](#get-viya-resources-and-assets)
        - [Download Viya order assets](#download-viya-order-assets)
        - [▶ PMP: Configure the Viya assets](#-pmp-configure-the-viya-assets)
        - [▷ Status Check](#-status-check)
    - [Infrastructure](#infrastructure)
        - [Setup the Kubernetes clients](#setup-the-kubernetes-clients)
        - [Label for Compute workloads](#label-for-compute-workloads)
        - [Install Cert Utils Operator](#install-cert-utils-operator)
        - [Initialize the OpenShift project for SAS Viya](#initialize-the-openshift-project-for-sas-viya)
    - [Additional site configuration](#additional-site-configuration)
        - [Configure Viya's resources for OpenShift](#configure-viyas-resources-for-openshift)
        - [Confirm files match configuration](#confirm-files-match-configuration)
        - [▷ Status Check](#-status-check-1)
    - [▶ PMP: Provision and configure storage in OCP](#-pmp-provision-and-configure-storage-in-ocp)
        - [OCP provides storage classes out-of-the-box](#ocp-provides-storage-classes-out-of-the-box)
        - [RWO storage for `viya-standard-sc`: Azure managed disk](#rwo-storage-for-viya-standard-sc-azure-managed-disk)
        - [Local storage for `viya-scratch-sc`: LVM Storage Operator](#local-storage-for-viya-scratch-sc-lvm-storage-operator)
        - [RWX storage for `viya-shared-sc`: Azure Files](#rwx-storage-for-viya-shared-sc-azure-files)
        - [▷ Status Check](#-status-check-2)
    - [Provision and configure supporting 3rd-party resources](#provision-and-configure-supporting-3rd-party-resources)
        - [Create a sitedefault file for user authentication with gel-adds](#create-a-sitedefault-file-for-user-authentication-with-gel-adds)
        - [Install OpenSSL as the certificate generator](#install-openssl-as-the-certificate-generator)
        - [Configure Viya for "routes" instead of "ingresses"](#configure-viya-for-routes-instead-of-ingresses)
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
        - [Uninstall Viya from OpenShift Container Platform](#uninstall-viya-from-openshift-container-platform)
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

    # Remember it for later
    add_my_var MY_NS
    add_my_var MY_PREFIX

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
          - INGRESS_HOST={{viya_fqdn}}
      - name: sas-shared-config
        behavior: merge
        literals:
          - SAS_SERVICES_URL={{viya_fqdn}}
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

For this exercise, the OpenShift Container Platform is already deployed for you.

### Setup the Kubernetes clients

The oc command-line interface gives us a powerful utility to administer resources in the OpenShift Container Platform.

1.  Get the location of OpenShift in our environment

    ```bash
    # get the url to OCP API server
    OCP_API_URL=$(grep API_URL ~/OCPurls.txt | cut -d= -f2)

    # verify it is reachable
    curl -k ${OCP_API_URL}/version
    ```

    With results like:

    ```log
    {
    "major": "1",
    "minor": "31",
    "gitVersion": "v1.31.11",
    "gitCommit": "a6cd3cbaf3baffa7179cfe4d7143a8a3bbf51c67",
    "gitTreeState": "clean",
    "buildDate": "2025-08-05T21:32:08Z",
    "goVersion": "go1.22.12 (Red Hat 1.22.12-3.el9_5) X:strictfipsruntime",
    "compiler": "gc",
    "platform": "linux/amd64"
    }
    ```

1.  Get your administrator credentials

    ```bash
    # get Ahmed's generated password
    echo "Ahmed's password is: $(get_password Ahmed)"
    ```

    With results like:

    ```log
    Ahmed's password is: •••••••••••••••••
    ```

    > Note that we have already established user credentials in LDAP and configured OpenShift and the SAS Viya platform to use it.

1.  Configure the oc CLI for the environment

    ```bash
    # Connect oc to the Kubernetes backend
    oc login --server $OCP_API_URL -u Ahmed
    ```

    When prompted:

    - to "use insecure connections", respond "`y`".

    - for Ahmed's password, enter the value returned from the command above.

    Success will show:

    ```log
    Login successful.

    You have access to 73 projects, the list has been suppressed. You can list all projects with 'oc projects'

    Using project "default".
    Welcome! See 'oc help' to get started.
    ```

    > Note that this action will automatically create the `$HOME/.kube/config` file for use by other Kubernetes clients like kubectl and k9s.

1.  Get the address of the OCP web console

    ```bash
    # Request url
    oc whoami --show-console
    ```

    Resulting url similar to:

    ```log
    https://console-openshift-console.apps.xxxxxx#####.example.com
    ```

1.  Connect to the OCP web console

    -   Open the url provided for the OCP web console in your web browser.
    -   Accept the browser warnings about the insecure connection. 
    -   When prompted to select an authentication service, choose: "`gelenable-adds`".
    -   When prompted to log in to your account, provide:
        -  Username: **Ahmed**
        -  Password: *as noted above*

    And confirm that:

    -   you see the **Overview** page (title),
    -   logged in as **Ahmed** (top right),
    -   with the **Administrator** perspective (top left).


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

### Label for Compute workloads

We currently have a plain, out-of-the-box deployment. For Viya workloads, we can use labels (and taints) to direct which hosts pods get scheduled to.

1.  Get a list of host nodes for your OCP cluster

    ```bash
    # show OCP nodes
    oc get nodes
    ```

    With results like:

    ```log
    NAME                          STATUS   ROLES                  AGE     VERSION
    blitz-p41603-controlplane-0   Ready    control-plane,master   6h16m   v1.31.14
    blitz-p41603-controlplane-1   Ready    control-plane,master   6h16m   v1.31.14
    blitz-p41603-controlplane-2   Ready    control-plane,master   6h16m   v1.31.14
    blitz-p41603-worker-1         Ready    worker                 5h57m   v1.31.14
    blitz-p41603-worker-2         Ready    worker                 5h57m   v1.31.14
    blitz-p41603-worker-3         Ready    worker                 5h57m   v1.31.14
    blitz-p41603-worker-4         Ready    worker                 5h57m   v1.31.14
    blitz-p41603-worker-5         Ready    worker                 5h57m   v1.31.14
    ```

1.  Label nodes for use by SAS Programming Runtime Environment

    ```bash
    # Label worker-1 and -2 for "compute" workloads
    oc label nodes $(oc get nodes | grep worker-[1,2] | awk '{print $1}' | tr '\n' ' ') workload.sas.com/class=compute
    ```

    Results:

    ```log
    node/blitz-p41603-worker-1 labeled
    node/blitz-p41603-worker-2 labeled
    ```

### Install Cert Utils Operator

The cert-utils-operator manages the TLS certficates needed for encrypted communication with services in the OpenShift cluster.

1. Deploy the Cert Utils Operator

    ```bash
    # Create the cert-utils-operator namespace
    oc new-project cert-utils-operator

    # Create OperatorGroup with cluster-wide scope
    oc apply -f - <<EOF
    apiVersion: operators.coreos.com/v1
    kind: OperatorGroup
    metadata:
      name: cert-utils-operator
      namespace: cert-utils-operator
    spec: {}
    EOF

    # Create Subscription to install the operator
    oc apply -f - <<EOF
    apiVersion: operators.coreos.com/v1alpha1
    kind: Subscription
    metadata:
      name: cert-utils-operator
      namespace: cert-utils-operator
    spec:
      channel: alpha
      installPlanApproval: Automatic
      name: cert-utils-operator
      source: community-operators
      sourceNamespace: openshift-marketplace
    EOF

    echo "Pause for operator installation..."
    sleep 30

    # Wait for operator to be ready
    oc wait --for=jsonpath='{.status.phase}'=Succeeded csv -l operators.coreos.com/cert-utils-operator.cert-utils-operator -n cert-utils-operator --timeout=300s

    # Verify installation
    oc get csv -n cert-utils-operator
    oc get pods -n cert-utils-operator
    ```

### Initialize the OpenShift project for SAS Viya

1.  Create an OCP Project for your SAS Viya deployment

    ```bash
    # creates the Kubernetes namespace called "viya", too
    oc new-project $MY_NS
    ```

    Success includes:

    ```log
    Now using project "viya" on server "https://api.pdcesx41603.example.com:443".
    ```

1.  Identify your OCP cluster FQDN

    ```bash
    # get the domain of my OCP cluster
    APPS_DOMAIN=$(oc get ingresscontroller.operator.openshift.io -n openshift-ingress-operator -o jsonpath='{.items[].status.domain}')

    # Determine the FQDN we want for Viya urls
    export MY_VIYA_FQDN="${MY_NS}.${APPS_DOMAIN}"

    # Remember it for later
    add_my_var MY_VIYA_FQDN
    ```

    And specify that in the kustomization.yaml:

    ```bash
    # Provide ingress endpoint and url
    sed -i "s/{{viya_fqdn}}/$MY_VIYA_FQDN/g" $HOME/project/deploy/$MY_NS/kustomization.yaml

    # Verify the update
    icdiff kustomization.yaml.bak*  kustomization.yaml
    ```

1.  SAS provides Security Context Constraints definitions for use with the Viya platform:

    ```bash
    cd $HOME/project/deploy/$MY_NS

    # show all the SCC manifests provides with your Viya order assets
    find ./sas-bases -name "*scc*yaml"
    ```

    > OpenShift uses SCC to provide additional permission configuration for pods. If we don't provide the required SCC for a pod that needs it, then it will get OpenShift's more restrictive permissions and likely won't function properly.

1.  Create a new manifest with updated kernel settings for OpenSearch

    ```bash
    # Modify OpenSearch settings before installation
    yq4 eval '
        .allowPrivilegeEscalation = true |
        .allowPrivilegedContainer = true |
        .runAsUser.type = "RunAsAny"' \
        ./sas-bases/examples/configure-elasticsearch/internal/openshift/sas-opendistro-scc.yaml > ./site-config/sas-opendistro-scc.yaml
    ```

1.  Apply all the required SCC definition files provided by SAS

    ```bash
    # verify we are logged in as the cluster administrator, Ahmed
    oc whoami

    # CAS: pick only one of cas-server-scc.yaml or cas-server-scc-host-launch.yaml
    oc apply -f ./sas-bases/examples/cas/configure/cas-server-scc.yaml
    # SAS Watchdog - includes SPRE, too
    oc apply -f ./sas-bases/examples/sas-programming-environment/watchdog/sas-watchdog-scc.yaml
    # MAS
    oc apply -f ./sas-bases/overlays/sas-microanalytic-score/service-account/sas-microanalytic-score-scc.yaml
    # Model Publish Service
    oc apply -f ./sas-bases/overlays/sas-model-publish/service-account/sas-model-publish-scc.yaml
    # Model Repository Service
    oc apply -f ./sas-bases/overlays/sas-model-repository/service-account/sas-model-repository-scc.yaml
    # SAS Decisions Runtime Builder Service Buildkit
    oc apply -f ./sas-bases/overlays/sas-decisions-runtime-builder/buildkit/service-account/buildkit-scc.yaml
    # OpenSearch
    oc apply -f ./site-config/sas-opendistro-scc.yaml
    # SAS Configurator for Open Source
    oc apply -f sas-bases/examples/sas-pyconfig/pyconfig-scc.yaml
    ```

    > Note that we're applying the `./site-config/sas-opendistro-scc.yaml` file now. So, you will *not* see a reference to it later in kustomization.yaml.

1.  Bind the new SCC to their appropriate service accounts

    ```bash
    # Add service accounts for Viya SCC
    oc -n $MY_NS adm policy add-scc-to-user sas-cas-server -z sas-cas-server
    oc -n $MY_NS adm policy add-scc-to-user sas-opendistro -z sas-opendistro
    oc -n $MY_NS adm policy add-scc-to-user sas-microanalytic-score -z sas-microanalytic-score
    oc -n $MY_NS adm policy add-scc-to-user sas-model-repository -z sas-model-repository
    oc -n $MY_NS adm policy add-scc-to-user sas-buildkit -z sas-buildkit

    # As described in its README, Model Publish uses different service accounts to perform different actions
    oc -n $MY_NS adm policy add-scc-to-user sas-model-publish -z sas-model-publish-buildkit
    oc -n $MY_NS adm policy add-scc-to-user sas-model-publish -z sas-decisions-runtime-builder-buildkit
    oc -n $MY_NS adm policy add-scc-to-user sas-model-publish -z default 

    # SAS Progamming environment
    oc -n $MY_NS adm policy add-scc-to-user sas-watchdog -z sas-programming-environment
    oc -n $MY_NS adm policy add-scc-to-user sas-pyconfig -z sas-pyconfig

    # Add permission for ephemeral volumes
    # to CAS
    oc get scc sas-cas-server -o json | jq '.volumes += ["ephemeral"]' | oc apply -f -
    # to SPRE
    oc get scc sas-watchdog -o json | jq '.volumes += ["ephemeral"]' | oc apply -f -
    ```

    > Reminder:
    > - 3SSC = 3 Starter Storage Classes
    > - SCC = Security Context Constraint
    >
    > Note that "3SSC" patches CAS to use a Generic Ephemeral Volume (GeV) for CAS_DISK_CACHE and patches the SPRE containers to use GeV for SASWORK and ECE_Cache. The SCC definition files (cas-server-scc and sas-watchdog-scc) provided by SAS don't include the permission for ephemeral volumes. So, we add those on the fly in the example here. Alternatively, you could modify those files first like we did for sas-opendistro-scc above.
    >
    > Note that we haven't deployed the SAS Viya platform yet and so none of the named service account users above actually exist at this point. But, that's okay... these definitions will get picked up appropriately later.

## Additional site configuration

There's more to do for Viya to run in the OCP cluster.

### Configure Viya's resources for OpenShift

1.  Update the fsGroup in targeted manifests with the correct GID value

    ```bash
    cd ~/project/deploy/$MY_NS

    # place for security manifests to configure Viya
    mkdir -p site-config/security

    # get the ID from OpenShift
    NS_GROUP_ID=$(oc get project ${MY_NS} -o jsonpath='{.metadata.annotations.openshift\.io/sa\.scc\.supplemental-groups}' | cut -f1 -d / )

    echo -e "\n>>> The supplemental group ID for the ${MY_NS} namespace is: ${NS_GROUP_ID}\n"

    # Replace the placeholder token with the GID value
    sed -e "s|{{ FSGROUP_VALUE }}|${NS_GROUP_ID}|g" \
        ./sas-bases/examples/security/container-security/configmap-inputs.yaml > ./site-config/security/configmap-inputs.yaml
    ```

    And reference the new files in kustomization.yaml:

    ```bash
    # Insert the config-map inputs to the resources:
    yq eval '.resources += ["site-config/security/configmap-inputs.yaml"]' -i kustomization.yaml

    # Add update-fsgroup to the transformers:
    yq eval '.transformers += ["sas-bases/overlays/security/container-security/update-fsgroup.yaml"]' -i ./kustomization.yaml

    # Verify the update
    icdiff kustomization.yaml.bak*  kustomization.yaml
    ```

    > Note that these two files work together. The configmap-inputs specifies the fsGroup to use. And the update-fsgroup transformer overlay ensures that the Viya services use it.

1.  Add transformer to remove Secure Computing Mode (seccomp) settings

    ```bash
    # Add the remove-seccomp-transformer to the transformers:
    yq eval '.transformers += ["sas-bases/overlays/security/container-security/remove-seccomp-transformer.yaml"]' -i ./kustomization.yaml

    # Verify the update
    icdiff kustomization.yaml.bak*  kustomization.yaml
    ```

1. Configure CAS as MPP, specifying resources and limits

    ```bash
    # DISABLE CAS AUTO-RESOURCES
    # ------------------------------------
    # Comment out auto-resources in kustomization.yaml:
    sed -i 's|^\(\s*\)- sas-bases/overlays/cas-server/auto-resources|\1# - sas-bases/overlays/cas-server/auto-resources|' kustomization.yaml

    # SPECIFY REQUESTS AND LIMITS FOR CAS
    # ------------------------------------
    # Set the CPU and RAM
    CAS_CPU_=1
    CAS_MEMORY=2Gi

    # Copy the sample PatchTransformer and configure the desired number of workers
    sed -e "s/{{ AMOUNT-OF-RAM }}/${CAS_MEMORY}/g" \
        -e "s/{{ NUMBER-OF-CORES }}/${CAS_CPU_}/g" \
       ./sas-bases/examples/cas/configure/cas-manage-cpu-and-memory.yaml \
        > ./site-config/cas-manage-cpu-and-memory.yaml

    # Add CPU and Memory for CAS to kustomization.yaml:
    yq eval '.transformers += ["site-config/cas-manage-cpu-and-memory.yaml"]' -i kustomization.yaml

    # MULTI-MACHINE CAS
    # ------------------------------------
    # Deploy CAS as MPP with 2 worker nodes
    CAS_WORKERS=2

    # Copy the sample PatchTransformer and configure the desired number of workers
    sed -e "s/{{ NUMBER-OF-WORKERS }}/${CAS_WORKERS}/g" \
        ./sas-bases/examples/cas/configure/cas-manage-workers.yaml \
        > ./site-config/cas-manage-workers.yaml

    # Add MPP CAS workers to kustomization.yaml:
    yq eval '.transformers += ["site-config/cas-manage-workers.yaml"]' -i kustomization.yaml

    # VALIDATE
    # -------------------------------------
    # Verify 3 more changes to kustomization.yaml
    icdiff kustomization.yaml.bak*  kustomization.yaml
    ```

    > Note that these `yq` commands are not idempotent - only run them once, else you might end up with duplicate entries in kustomization.yaml that will derail your Viya install later.

### Confirm files match configuration
We've added several services with matching configuration files in `$deploy/site-config`. Make sure the path to those files matches what's specified in kustomization.yaml.

1.  Confirm we have the expected site-config files for Viya deployment as referenced in kustomization.yaml:

    ```bash
    # Get a list of files in site-config
    tree ~/project/deploy/${MY_NS}/site-config
    ```

    With results similar to:

    ```log
    /home/cloud-user/project/deploy/viya/site-config/
    ├── cas-manage-cpu-and-memory.yaml
    ├── cas-manage-workers.yaml
    ├── sas-opendistro-scc.yaml
    ├── security
    │   └── configmap-inputs.yaml
    └── storage
        └── 3SSC-transformers.yaml
    ```

### &#9655; Status Check

The core infrastructure for the OpenShift Container Platform has already been deployed to run in Microsoft Azure. We've set up general Kubernetes clients as well as OpenShift clients to give us administration and monitoring. But there's more yet to do...

## &#9654; PMP: Provision and configure storage in OCP

At the risk of repetition, the site is responsible for providing storage that meets Viya's requirements. This section shows an approach where the site has evaluated Viya's use of storage and selected appropriate technologies. We show installing CSI Drivers and such because you need to see it. However, to be clear, the ideal is that the site will do this work, including validating that it's all working properly *before* attempting to use it for Viya's services.

> Note: Project Mountpoint's contribution here is the idea of *copying* storage classes. By giving Viya its own set of storage class names, we abstract Viya's config from the physical implementation. This isn't required - the site is free to use any names for storage classes it wants - but the additional layer of abstraction gives us another aspect of control.

The IAC will setup your choice of supported shared (RWX) storage provider. But we also need CSI drivers and other resources. Some of these would be handled automatically by the DAC project, but we're not using that here.

1.  We will make copies of storage classes. To help aid that task:

    ```bash
    # define the "copysc" function 
    source $HOME/project-mountpoint/bin/copySC.sh
    ```

### OCP provides storage classes out-of-the-box

OCP provides several storage classes for immediate use.

1. Let's see what's there:

    ```bash
    $ oc get storageclasses

    NAME                    PROVISIONER           RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
    azurefile-csi           file.csi.azure.com    Delete          Immediate              true                   92m
    managed-csi (default)   disk.csi.azure.com    Delete          WaitForFirstConsumer   true                   92m
    sas-azurefile           file.csi.azure.com    Delete          Immediate              true                   64m
    ```

1.  Disable any storage class that's annotated as "default"

    ```bash
    # disable the k8s default SC, if there is one 
    hasDefaultSC=$(oc get storageclasses| grep "(default)")

    if [[ "$hasDefaultSC" != "" ]]; then
        # found the default storage class
        defaultSC=$(echo $hasDefaultSC | awk -F'(' '{print $1}')

        echo -e "\n--\nFound default storage class \"$defaultSC\" - disabling it..."

        # patch it false
        oc patch storageclass $defaultSC -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
    fi
    ```

    > Note: if a PVC doesn't specify a storage class, then Kubernetes will automatically use one that's annotated as a "default". SAS should neither expect nor require the use of a "default" storage class. So, in our test environment, we won't have one. That way, if we somehow miss a storage definition in our config, then it will fail and we can find it to fix it.
    >
    > In the real world, if a site wants to have a "default"-annotated storage class, that's fine.

### RWO storage for `viya-standard-sc`: Azure managed disk

The "viya-standard-sc" storage class is intended for use by [services that need persistent RWO volumes](/3SSC-Three-Starter-Storage-Classes/). SAS Viya services like Crunchy Postgres, RabbitMQ, Redis, Consul, and OpenSearch all need persistent RWO volumes.

The `disk.csi.azure.com` driver to use [Azure Managed Files](https://learn.microsoft.com/en-us/azure/aks/concepts-storage) is already installed and associated storage classes with different levels of performance have been defined for our use.

1.  &#9654; PMP: Copy the `managed-csi` storage class to make `viya-standard-sc`:

    ```bash
    cd ~/project/deploy/$MY_NS

    # Make a copy
    copysc managed-csi viya-standard-sc
    ```

1.  Review the resulting file `defineSC_viya-standard-sc.yaml`:

    ```yaml
    allowVolumeExpansion: true
    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
      name: viya-standard-sc
    parameters:
      skuname: Premium_LRS
    provisioner: disk.csi.azure.com
    reclaimPolicy: Delete
    volumeBindingMode: WaitForFirstConsumer
    ```

    Edit the file to make any desired changes.

1.  When it's acceptable, then create the viya-standard-sc storage class in the OCP cluster:

    ```bash
    # Apply the storage class definition
    oc apply -f defineSC_viya-standard-sc.yaml
    ```
### Local storage for `viya-scratch-sc`: LVM Storage Operator

The "viya-scratch-sc" storage class is intended for use by [SASWORK and CAS_DISK_CACHE](/3SSC-Three-Starter-Storage-Classes/). SAS Programming Runtime Environment (including SAS Batch, SAS Compute, and SAS Connect Servers) and the SAS Cloud Analytic Services (CAS) rely on this space for low-latency and high-throughput - something local disk in the cloud does well for little additional cost.

There are several ways to provide Kubernetes with access to local disk, but for this effort we want a CSI Driver that can *dynamically* provision volumes on local disk. In this section, we'll set up [LVM Storage Operator](https://github.com/openshift/lvm-operator/blob/main/README.md), but it's just an example. Your site might prefer a different utility. Or opt for static volumes instead.

Local disk on a node is not a given. It takes extra steps for a site to format and mount the local disk for use. But it's worth the extra effort.

1.  Identify local disk drives

    > Note that our OpenShift Container Platform cluster is running in Azure and that our worker nodes already have local disk attached.

    A quick survey shows:

     ```log
     # lsblk -o NAME,MOUNTPOINT,SIZE,TYPE,FSTYPE,LABEL

     NAME   MOUNTPOINT   SIZE TYPE FSTYPE LABEL
     sda                 300G disk        
     `-sda1              300G part ntfs   Temporary Storage
     sdb                 128G disk        
     |-sdb1                1M part        
     |-sdb2              127M part vfat   EFI-SYSTEM
     |-sdb3 /boot        384M part ext4   boot
     `-sdb4 /sysroot   127.5G part xfs    root
     ```

     FYI:
     - `sdb` (OS disk): 127G `/sysroot` partition on 128G disk
     - `sda` (addtl volume): 300G disk, formatted NTFS
  
    > Note that the assignment of "`sda`" or "`sdb`" is not fixed and is arbitrarily assigned per host. Some of your OCP workers will have "`sdb`" as the temporary disk.

1.  Wipe the "temporary disk" for LVMS

    Use an oc debug container to run on each worker node and wipe the full "temporary disk" to create a fresh guid partition table for LVMS to claim.

    ```bash
    # Prep "temporary disk" on all worker nodes for LVMS
    AZURE_TMP_DEV=/host/dev/disk/azure/resource

    for _NODE in $(oc get nodes -l node-role.kubernetes.io/worker -o name); do
    echo "=== Processing ${_NODE} ==="
    oc debug -q ${_NODE} -- bash -c "\
        # Wipe any existing filesystems and partition table
        wipefs -a ${AZURE_TMP_DEV}-part1 2>/dev/null || true;\
        wipefs -a ${AZURE_TMP_DEV};\
        \
        # Create single partition for LVM
        parted ${AZURE_TMP_DEV} --script -- \
        mklabel gpt \
        mkpart primary 1MiB 100%;\
        \
        # Wait for partition to settle
        sleep 5;\
        partprobe ${AZURE_TMP_DEV};\
        \
        # Set GPT partition name (label) to viya-scratch
        parted ${AZURE_TMP_DEV} --script -- name 1 viya-scratch;\
        \
        # Verify
        lsblk ${AZURE_TMP_DEV};\
        parted ${AZURE_TMP_DEV} print
    "
    echo ""
    done
    ```

    After reformatting, the temporary disk ("`sda`" or "`sdb`" per host) now has no file system and the updated partition label is "viya-scratch".

    ```log
     NAME   MOUNTPOINT   SIZE TYPE FSTYPE LABEL
     sda                 300G disk        
     `-sda1              300G part        viya-scratch
     ```

1.  Install the Local Volume Manager Storage Operator

    ```bash
    # Create namespace for LVMS
    cat <<EOF | oc apply -f -
    apiVersion: v1
    kind: Namespace
    metadata:
      name: openshift-storage
      labels:
        openshift.io/cluster-monitoring: "true"
    EOF

    # Create OperatorGroup
    cat <<EOF | oc apply -f -
    apiVersion: operators.coreos.com/v1
    kind: OperatorGroup
    metadata:
      name: openshift-storage-operatorgroup
      namespace: openshift-storage
    spec:
      targetNamespaces:
      - openshift-storage
    EOF

    # Create Subscription to install LVMS Operator
    cat <<EOF | oc apply -f -
    apiVersion: operators.coreos.com/v1alpha1
    kind: Subscription
    metadata:
      name: lvms-operator
      namespace: openshift-storage
    spec:
      channel: stable-4.18
      name: lvms-operator
      source: redhat-operators
      sourceNamespace: openshift-marketplace
      installPlanApproval: Automatic
    EOF

    # Wait for the deployment to be created
    echo "Waiting for lvms-operator deployment to be created..."
    until oc get deployment lvms-operator -n openshift-storage &>/dev/null; do
        echo -n "."
        sleep 5
    done

    echo ">>> lvms-operator deployment found!"

    # Wait for operator to be ready
    echo "Waiting for LVMS operator to install..."
    oc wait --for=condition=Available --timeout=300s \
       deployment/lvms-operator -n openshift-storage

    # Verify installation
    oc get csv -n openshift-storage
    oc get pods -n openshift-storage
    ```

    At the end, you should details about the LVMS Operator like:

    ```log
    NAME                    DISPLAY       VERSION   REPLACES   PHASE
    lvms-operator.v4.18.4   LVM Storage   4.18.4               Succeeded

    NAME                            READY   STATUS    RESTARTS   AGE
    lvms-operator-d4bd9b7c9-ww6jb   1/1     Running   0          64s
    ```

1. Create the LVMCluster custom resource definition

    ```bash
    # Apply the LVMCluster custom resource definition
    cat <<EOF | oc apply -f -
    apiVersion: lvm.topolvm.io/v1alpha1
    kind: LVMCluster
    metadata:
      name: lvmcluster
      namespace: openshift-storage
    spec:
      storage:
        deviceClasses:
        - name: local-disk
          thinPoolConfig:
            name: thin-pool-1
            sizePercent: 80
            overprovisionRatio: 2
          deviceSelector:
            paths:
            - /dev/disk/azure/resource-part1
          fstype: xfs
        nodeSelector:
          nodeSelectorTerms:
            - matchExpressions:
              - key: node-role.kubernetes.io/worker
                operator: Exists
    EOF

    echo "Waiting for LVMCluster to be ready..."
    until oc get lvmcluster lvmcluster -n openshift-storage -o jsonpath='{.status.ready}' 2>/dev/null | grep -q "true"; do
        echo -n "."
        sleep 5
    done

    echo ">>> LVMCluster is ready!"
    ```

    > Note this CR will:
    > - claim the "viya-scratch" disks we created
    > - create an LVM volume group
    > - generate the "lvms-local-disk" storage class ("lvms-" is prepended by the LVM Storage operator)
    >
    > And that the storage class will:
    > - use XFS file system
    > - LVM thin pool up to 80% total disk usage
    > - overprovision the physical space at 2x ratio


1.  &#9654; PMP: Copy the `lvms-disk` storage class to make `viya-scratch-sc`:

    ```bash
    # Make a copy
    copysc lvms-local-disk viya-scratch-sc
    ```

1.  Review resulting file `defineSC_viya-scratch-sc.yaml`:

    ```yaml
    allowVolumeExpansion: true
    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
      labels:
        owned-by.topolvm.io/group: lvm.topolvm.io
        owned-by.topolvm.io/kind: LVMCluster
        owned-by.topolvm.io/name: lvmcluster
        owned-by.topolvm.io/namespace: openshift-storage
        owned-by.topolvm.io/uid: 5d7f2d0c-7b64-4cfb-8b82-935ca4b6367d
        owned-by.topolvm.io/version: v1alpha1
      name: viya-scratch-sc
    parameters:
      csi.storage.k8s.io/fstype: xfs
      topolvm.io/device-class: lvms-disk
    provisioner: topolvm.io
    reclaimPolicy: Delete
    volumeBindingMode: WaitForFirstConsumer
    ```

    Edit the file to make any desired changes.

1.  When it's acceptable, then apply it:

    ```bash
    # Apply the storage class definition
    oc apply -f defineSC_viya-scratch-sc.yaml
    ```

### RWX storage for `viya-shared-sc`: Azure Files

The "viya-shared-sc" storage class is intended for use by [services that need persistent RWX volumes](/3SSC-Three-Starter-Storage-Classes/). SAS Viya services like sas-backup-job, sas-common-files, sas-pyconfig and others all need persistent RWX volumes so that multiple pods running on different nodes can access the same set of shared files.

This environment has already set up a storage class named "sas-azurefile" for our use.

We will follow the pattern established to copy that storage class to create "viya-shared-sc" which we have configured Viya to use.

1.  &#9654; PMP: Copy the `sas-azurefile` storage class to make `viya-shared-sc`:

    ```bash
    # Make a copy
    copysc sas-azurefile viya-shared-sc
    ```

1.  Review resulting file `defineSC_viya-shared-sc.yaml`:

    ```yaml
    allowVolumeExpansion: true
    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
      name: viya-shared-sc
    mountOptions:
      - nconnect=4
    parameters:
      protocol: nfs
      storageAccount: pdcesx41692viya
    provisioner: file.csi.azure.com
    reclaimPolicy: Delete
    volumeBindingMode: Immediate
    ```

    Edit the file to make any desired changes.

1.  When it's acceptable, then apply it:

    ```bash
    # Apply the storage class definition
    oc apply -f defineSC_viya-shared-sc.yaml
    ```

### &#9655; Status Check

This exercise included some storage providers for Kubernetes to use. And we created a generic storage class using the LVM Storage operator. This is a good practice because the site can perform validation testing on their own to ensure that storage is working correctly.

With known good storage, we take advantage of that by making *copies* of those storage classes and giving them names we've configured Viya to use already.

The result:

```log
$ oc get storageclasses

NAME               PROVISIONER          RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION
azurefile-csi      file.csi.azure.com   Delete          Immediate              true               
managed-csi        disk.csi.azure.com   Delete          WaitForFirstConsumer   true               

sas-azurefile      file.csi.azure.com   Delete          Immediate              true               

lvms-local-disk    topolvm.io           Delete          WaitForFirstConsumer   true                

viya-scratch-sc    topolvm.io           Delete          WaitForFirstConsumer   true                
viya-shared-sc     file.csi.azure.com   Delete          Immediate              true                
viya-standard-sc   disk.csi.azure.com   Delete          WaitForFirstConsumer   true               
```

> Note: this approach allows us to specify storage for Viya ***without modifying Viya's storage configuration***. Don't want LVMS as the basis for "`viya-scratch-sc`"? Then use "`managed-csi`" instead.

## Provision and configure supporting 3rd-party resources

Beyond what the environment has initially provided, we need more resources that Viya relies on.

### Create a sitedefault file for user authentication with gel-adds

Some configuration settings can be pre-loaded using a sitedefault.yaml file. To simplify user management for this workshop, we provide a file already configured to connect to this workshop's Azure Active Directory - the same used by the OpenShift cluster.

1.  Copy the provided file in the proper location with the following command:

    ```bash
    # Copy the provided site-default file to Viya's site-config directory
    cp /opt/gellow_code/scripts/loop/gelenable/gelenable_site-config/gelenable-sitedefault.yaml \
    ~/project/deploy/${MY_NS}/site-config/
    ```

1.  Starting from SAS Viya release 2024.12, you must configure the SAS Logon service property `issuer.uri` to point to the full external URI of that service. Let's find the URI for this cluster, then update the value in the sitedefault.yaml file that we just copied.

    ```bash
    # build the URI for SASLogon
    SASLOGON_URI="https://${MY_FQDN}/SASLogon"
    echo "The SAS Logon external URI is: ${SASLOGON_URI}"

    # Update sitedefault.yaml
    sed -i "s|https://MYRESOURCEGROUP.example.com/SASLogon|${SASLOGON_URI}|g" \
        $HOME/project/deploy/${MY_NS}/site-config/gelenable-sitedefault.yaml
    ```

1.  Reference the site-default.yaml in kustomization.yaml

    ```bash
    # append secretGenerator block
    yq -i '.secretGenerator += [{"name": "sas-consul-config", "behavior": "merge", "files": ["SITEDEFAULT_CONF=site-config/gelenable-sitedefault.yaml"]}]' kustomization.yaml

    # Verify the update
    icdiff kustomization.yaml.bak*  kustomization.yaml
    ```

### Install OpenSSL as the certificate generator

SAS Viya needs the ability to generate encryption certificates on the fly.

1.  Use openSSL as the certificate generator (instead of the legacy "cert-manager" utility).

    Copy the example `openssl-generated-ingress-certificate.yaml` file to our local `site-config/` directory:

    ```bash
    cd $HOME/project/deploy/${MY_NS}

    # create a `security` directory for TLS files
    mkdir -p $HOME/project/deploy/${MY_NS}/site-config/security

    # Copy certs provided from sas-bases to site-config
    cp $HOME/project/deploy/${MY_NS}/sas-bases/examples/security/openssl-generated-ingress-certificate.yaml \
    $HOME/project/deploy/${MY_NS}/site-config/security/openssl-generated-ingress-certificate.yaml
    ```

    And update kustomization.yaml to reference the new patch file(s):

    ```bash
    # Add the openssl-generated-ingress-certificate to the resources: in kustomization.yaml
    yq -i '.resources += ["site-config/security/openssl-generated-ingress-certificate.yaml"]' kustomization.yaml

    # Verify the update
    icdiff kustomization.yaml.bak*  kustomization.yaml
    ```

### Configure Viya for "routes" instead of "ingresses"

OpenShift uses *routes* for its ingress controllers to expose services within the cluster to the outside world. The initial kustomization.yaml file that is described in the official documentation does not account for routes, so you must change a couple of lines.

1. Modify kustomization.yaml for routes

    ```bash
    cd $HOME/project/deploy/$MY_NS

    # Specify OpenShift routes instead of Kubernetes ingresses
    sed -i 's|sas-bases/overlays/network/networking\.k8s\.io|sas-bases/overlays/network/route.openshift.io|g' ./kustomization.yaml

    # Specify full-stack TLS for OpenShift routes
    sed -i 's|sas-bases/components/security/network/networking\.k8s\.io/ingress/nginx\.ingress\.kubernetes\.io/full-stack-tls|sas-bases/components/security/network/route.openshift.io/route/full-stack-tls|g' ./kustomization.yaml

    # verify
    icdiff ./kustomization.yaml.bak* ./kustomization.yaml
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

    Replace '`cr.sas.com/viya-4-x64_oci_linux_2-docker/sas-orchestration:x.xx.x-yyymmdd.xxxxxxxxxxxxx`' with a local tag for ease of use. Then we can refer to the container simply as '`sas-orchestration`'.

    ```bash
    # Rename to something easy
    docker tag cr.sas.com/viya-4-x64_oci_linux_2-docker/sas-orchestration:${IMAGE_VERSION} sas-orchestration

    # Validate: looks for "sas-orchestration" in the list of containers
    docker image list | grep sas-orchestration

    # Confirm we can use the container as its named
    docker run --rm sas-orchestration deploy --help
    ```

-   You are now all set to start using the `sas-orchestration` tool to deploy SAS Viya.

### Deploy SAS Viya

1.  Run the `sas-orchestration` utility to deploy SAS Viya

    ```bash
    cd ~/project/deploy

    # Confirm namespace for Viya exists
    if ! kubectl get namespace "$MY_NS" >/dev/null 2>&1; then

        echo -e "\n>>> ERROR: Namespace '$MY_NS' does not exist.\n           Refer to \"Initialize the OpenShift project\" instructions to set it up.\n"

    else

        # Run the sas-orchestration with all deployment parameters
        docker run --rm \
        -v $(pwd):/workingdir/ \
        -v ~/.kube/config:/kube/config \
        -e "KUBECONFIG=/kube/config" \
        --user $(id -u):$(id -g) \
        sas-orchestration \
        deploy \
        --namespace ${MY_NS} \
        --deployment-data /workingdir/${MY_NS}/SASViyaV4_${MY_ORDERNUM}_certs.zip \
        --license /workingdir/${MY_NS}/SASViyaV4_${MY_ORDERNUM}_license.jwt \
        --user-content /workingdir/${MY_NS} \
        --cadence-name ${MY_CADENCE_NAME} \
        --cadence-version ${MY_CADENCE_VERSION}

    fi
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

    This workshop's "gelenable-adds" server provides sample user credentials:

    | Role               | Userid       | Password       |
    | ------------------ | ------------ | -------------  |
    | Regular user       | `Ahmed`      | (query needed) |
    | Regular admin      | `sasadm`     | (query needed) |
    | Unrestricted admin<br>(cannot run Compute or CAS jobs) | `sasboot`    | `lnxsas`  |

    For "(query needed)" passwords, use the function call:

    ```bash
    # To get sasadm password:
    echo "sasadm's password is: $(get_password sasadm)"
    ```

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

### Uninstall Viya from OpenShift Container Platform

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
            echo -e "\n---\n$(oc get namespace $VNS)\n"

            # Uninstall the Viya deployment (2 steps)
            oc -n $VNS delete postgresclusters --selector="sas.com/deployment=sas-viya"

            oc delete namespace $VNS --ignore-not-found=true
        done
    else
        echo -e "\n---\nNo Viya namespaces to delete."
    fi
    ```

### Destroy cloud resources

The openshift-install CLI can delete the OpenShift cluster, the Azure resource group it belongs to, and all related cloud artifacts. This requires access to the original directory used to deploy the cluster which contains the files that define it and grant full administrative access. For this workshop, these files are owned by root, so we'll have to switch user first.

1.  Destroy the Azure infrastructure used by OCP

    Become root:

    ```bash
    #become root
    sudo su -
    ```

    Destroy the cluster:

    ```bash
    #move to the OCP deployment directory
    cd /home/cloud-user/project/clusterconfig/

    #destroy the cluster and related Azure resources
    openshift-install destroy cluster
    ```

### &#9655; Status Check

All resources in Azure created for these exercises have been deleted.
