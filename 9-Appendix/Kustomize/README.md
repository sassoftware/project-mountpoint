# Initial `kustomization.yaml`

The *[SAS® Viya® Platform Operations](https://documentation.sas.com/?cdcId=itopscdc&cdcVersion=default&docsetId=dplyml0phy0dkr&docsetTarget=n0g237aqo6pz1in1t19wjb94j9bi.htm)* document provides us with an Initial `kustomization.yaml` file.

## Needs some tweaks

Honestly, it could use a little tidying up in general, but there is one thing in particular we need to address for Project Mountpoint. It includes this section:

```yaml
patches:
- path: site-config/storageclass.yaml
  target:
    kind: PersistentVolumeClaim
    annotationSelector: sas.com/component-name in (sas-backup-job,sas-data-quality-services,sas-commonfiles,sas-cas-operator,sas-pyconfig,sas-risk-cirrus-core,sas-risk-modeling-core,sas-event-stream-processing-studio-app)
```

This is syntactically correct and it works.

But, it's also inconsistent with how we approach the use of patchTransformers in combination with the "`site-config`" directory.

## Make it work for Project Mountpoint

The storage patterns defined in Project Mountpoint create a patchTransformer file and it has one section that already handles the above:

```yaml
---
# Configures the PersistentVolumeClaims of selected Viya services to use the "viya-shared-sc " storage class
apiVersion: builtin 
kind: PatchTransformer
metadata:
  name: patch-pvc-SC
patch: |-
  - op: replace
    path: /spec/storageClassName
    value: viya-shared-sc 
target:
  kind: PersistentVolumeClaim
  annotationSelector: |
    sas.com/component-name in (
      sas-backup-job,
      sas-commonfiles,
      sas-cas-operator,
      sas-data-quality-services,
      sas-event-stream-processing-studio-app,
      sas-pyconfig,
      sas-risk-cirrus-search,
      sas-risk-modeling-core
    )
```

So, we don't need that patch in the initial `kustomization.yaml` as shown in the *Operations* doc.

## Alternative initial `kustomization.yaml` for Project Mountpoint

If you need an "initial" `kustomization.yaml`, use this instead:

```bash
# provide your Viya namespace
VIYA_NS="viya"

# provide your Viya's expected FQDN
VIYA_FQDN="ingress-host.viya.site.com"


# create the new kustomization.yaml
cat <<-EOF > ./kustomization.yaml
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

> Ensure this file is placed with your site's Viya order assets alongside subdirectory named `site-config`.
>
> The main change here is that the problematic half-patch has been removed. Don't worry, when you implement Project Mountpoint's storage pattern later, that configuration will be included.

Of course, you can modify this `kustomization.yaml` as directed by the deployment instructions provided by SAS. 

If they make sense for your site, you can also add other items like integration with a local "GELLDAP" server:

```bash
cat <<-EOF >> ./kustomization.yaml

secretGenerator:
    - name: sas-consul-config 
      behavior: merge
      files:
        - SITEDEFAULT_CONF=site-config/gelldap-sitedefault.yaml
EOF
```

And clusterrole and -binding definitions for SAS Workload Orchestrator:

```bash
# Insert the clusterrole and -binding definitions for SWO
yq -i '.resources += ["sas-bases/overlays/sas-workload-orchestrator/cluster-role"]' kustomization.yaml
```

> Useful because one of our storage patterns is specific to that functionality.

And Ingress TLS certs:

```bash
# Insert the resource definition for Ingress TLS certs
yq -i '.resources += ["site-config/security/openssl-generated-ingress-certificate.yaml"]' kustomization.yaml
```

## Takeaway

The `kustomization.yaml` is a fluid and powerful configuration element for deploying the SAS Viya platform. Take care to ensure it includes everything you need and nothing you don't.
