# Fix: sas-logon-app CrashLoopBackOff — Missing Hostname in JWT Issuer URI

## Symptom

`sas-logon-app` pod is in `CrashLoopBackOff`. Logs show:

```
java.lang.IllegalArgumentException: [https:///SASLogon] is not a valid HTTP URL
```

The Spring context fails to initialize the `identityZoneResolvingFilter` bean because
the JWT issuer URI in Consul has an empty hostname.

## Root Cause

During deployment bootstrap, Consul KV keys for the JWT issuer URI are written before
`SAS_SERVICES_URL` is set, leaving the hostname blank. Spring Cloud Consul Config takes
precedence over environment variables, so the broken value wins at runtime.

There are **two** Consul paths where this value can live. Spring Cloud Consul Config
checks them in this order (most specific wins):

1. `config/SASLogon/sas.logon.jwt/issuer.uri` — service-specific, **checked first**
2. `config/application/sas.logon.jwt/issuer.uri` — shared fallback

Both may be broken; both must be fixed.

## Diagnosis

Get the correct hostname from the shared ConfigMap:

```bash
kubectl get configmap -n ${MY_NS} -l sas.com/admin=cluster-local \
  -o jsonpath='{range .items[*]}{.data.SAS_SERVICES_URL}{"\n"}{end}' | grep -v '^$'
```

Check both Consul keys:

```bash
kubectl exec -n ${MY_NS} sas-consul-server-0 -- sh -c \
  'CONSUL_HTTP_TOKEN=$(cat /opt/sas/viya/config/etc/SASSecurityCertificateFramework/tokens/consul/default/management.token) \
   CONSUL_CACERT=/opt/sas/viya/config/etc/SASSecurityCertificateFramework/cacerts/trustedcerts.pem \
   CONSUL_HTTP_ADDR=https://127.0.0.1:8500 \
   consul kv get config/SASLogon/sas.logon.jwt/issuer.uri'

kubectl exec -n ${MY_NS} sas-consul-server-0 -- sh -c \
  'CONSUL_HTTP_TOKEN=$(cat /opt/sas/viya/config/etc/SASSecurityCertificateFramework/tokens/consul/default/management.token) \
   CONSUL_CACERT=/opt/sas/viya/config/etc/SASSecurityCertificateFramework/cacerts/trustedcerts.pem \
   CONSUL_HTTP_ADDR=https://127.0.0.1:8500 \
   consul kv get config/application/sas.logon.jwt/issuer.uri'
```

Expected bad output from either: `https:///SASLogon`

## Fix

1. **Update both Consul KV keys** (replace `<SAS_SERVICES_URL>` with the hostname from above):

```bash
for KEY in config/SASLogon/sas.logon.jwt/issuer.uri config/application/sas.logon.jwt/issuer.uri; do
  kubectl exec -n ${MY_NS} sas-consul-server-0 -- sh -c \
    "CONSUL_HTTP_TOKEN=\$(cat /opt/sas/viya/config/etc/SASSecurityCertificateFramework/tokens/consul/default/management.token) \
     CONSUL_CACERT=/opt/sas/viya/config/etc/SASSecurityCertificateFramework/cacerts/trustedcerts.pem \
     CONSUL_HTTP_ADDR=https://127.0.0.1:8500 \
     consul kv put \$KEY 'https://${MY_VIYA_FQDN}/SASLogon'"
done
```

2. **Restart the pod:**

```bash
kubectl delete pod -n ${MY_NS} -l app=sas-logon-app
```

3. **Verify recovery:**

```bash
kubectl get pods -n ${MY_NS} -l app=sas-logon-app
```

Pod should reach `1/1 Running` with 0 restarts.

## Prevention

Ensure `SAS_SERVICES_URL` is populated in the `sas-shared-config` ConfigMap **before** running deployment bootstrap jobs. The bootstrap process reads this value when writing the issuer URI to Consul.
