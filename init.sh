#!/bin/bash

set -e
export title="app-monitoring-webhook"
export namespace="kube-system"

[ -z ${title} ] && title=app-monitoring-webhook
[ -z ${namespace} ] && namespace=aks-webhook-ns

if [ ! -x "$(command -v openssl)" ]; then
    echo "openssl not found"
    exit 1
fi

csrName=${title}.${namespace}
tmpdir=$(mktemp -d)
#tmpdir=tmpdir
#mkdir tmpdir
echo "creating certs in tmpdir ${tmpdir} "

cat <<EOF >> ${tmpdir}/csr.conf
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
[req_distinguished_name]
[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
[alt_names]
DNS.1 = ${title}
DNS.2 = ${title}.${namespace}
DNS.3 = ${title}.${namespace}.svc
DNS.4 = ${namespace}.svc
EOF

openssl genrsa -out ${tmpdir}/server-key.pem 2048
openssl req -new -key ${tmpdir}/server-key.pem -subj "/CN=${title}.${namespace}.svc" -out ${tmpdir}/server.csr -config ${tmpdir}/csr.conf

# clean-up any previously created CSR for our service. Ignore errors if not present.
echo "delete previous csr certs if they exist"
kubectl config set-context  myJavaOnAKS
kubectl delete csr ${csrName} 2>/dev/null || true

# create server cert/key CSR and send to k8s API
echo "create server cert/key CSR and send to k8s API"
cat <<EOF | kubectl create --validate=false -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: ${csrName}
spec:
  groups:
  - system:authenticated
  request: $(cat ${tmpdir}/server.csr | base64 | tr -d '\n')
  signerName: kubernetes.io/kubelet-serving
  usages:
  - digital signature
  - key encipherment
  - server auth
EOF

cat <<EOF | kubectl create --validate=false -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: ${csrName}
spec:
  request: $(cat ${tmpdir}/server.csr | base64 | tr -d '\n')
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400
  usages:
  - digital signature
  - key encipherment
  - client auth
EOF

# verify CSR has been created
echo "verify CSR has been created"
while true; do
    kubectl get csr ${csrName}
    if [ "$?" -eq 0 ]; then
        break
    fi
done

# approve and fetch the signed certificate
echo "approve and fetch the signed certificate"
kubectl certificate approve ${csrName}
# verify certificate has been signed

for x in $(seq 10); do
    serverCert=$(kubectl get csr ${csrName} -o jsonpath='{.status.certificate}')
    if [[ ${serverCert} != '' ]]; then
        break
    fi
    sleep 1
done
if [[ ${serverCert} == '' ]]; then
    echo "ERROR: After approving csr ${csrName}, the signed certificate did not appear on the resource. Giving up after 10 attempts." >&2
    exit 1
fi
echo ${serverCert} | openssl base64 -d -A -out ${tmpdir}/server-cert.pem

# create the secret with CA cert and server cert/key
echo "create the secret with CA cert and server cert/key"
kubectl create secret generic ${title} \
        --from-file=key.pem=${tmpdir}/server-key.pem \
        --from-file=cert.pem=${tmpdir}/server-cert.pem \
        --dry-run=client -o yaml |
    kubectl -n ${namespace} apply -f -

export CA_BUNDLE=$(kubectl get configmap -n kube-system extension-apiserver-authentication -o=jsonpath='{.data.client-ca-file}' | base64 | tr -d '\n')
#cat ./values._aml | envsubst > ./values.yaml

kVer=`kubectl version --short=true`
kVer="${kVer#*\Server Version: v}"
part1="${kVer%.*}"
kVerMajor="${part1%.*}"
kVerMinor="${part1#*\.}"
kVerRev="${kVer#*\.}"
kVerRev="${kVerRev#*\.}"
echo "found kubernetes server version ${kVer} "

cat <<EOF >> ./values.yaml
app:
  iKey: "<target ikey>" # instrumentation key of Application Insights resource to send telemetry to
  kVerMajor: "${kVerMajor}"
  kVerMinor: "${kVerMinor}"
  kVerRev: "${kVerRev}"
  caBundle: "${CA_BUNDLE}"
EOF

cat values.yaml

helm install ./appmonitoring-0.9.2.tgz -f values.yaml --generate-name

## Deploy Piggymetrics to Azure Kubernetes Service
## Build and push container images for micro service apps
## Build Java apps, container images and push images to Azure Container Registry using Maven and Jib:


## Login to ACR First before running the maven builds.
az acr login -n ${CONTAINER_REGISTRY}

cd config
mvn compile jib:build \
    -Djib.container.environment=CONFIG_SERVICE_PASSWORD=${CONFIG_SERVICE_PASSWORD}

cd ../registry
mvn compile jib:build

cd ../gateway
mvn compile jib:build

cd ../auth-service
mvn compile jib:build

cd ../account-service
mvn compile jib:build \
    -Djib.container.environment=ACCOUNT_SERVICE_PASSWORD=${ACCOUNT_SERVICE_PASSWORD}

cd ../statistics-service
mvn compile jib:build \
    -Djib.container.environment=STATISTICS_SERVICE_PASSWORD=${STATISTICS_SERVICE_PASSWORD}

cd ../notification-service
mvn compile jib:build \
    -Djib.container.environment=NOTIFICATION_SERVICE_PASSWORD=${NOTIFICATION_SERVICE_PASSWORD}

## Prepare Kubernetes manifest files
## Prepare Kubernetes manifest files using the supplied bash script:

# cd to kubernetes folder
cd ../kubernetes
source ../.scripts/prepare-kubernetes-manifest-files.sh

## Create Secrets in K8S
kubectl apply -f deploy/0-secrets.yaml

# you can view Secrets in Kubernetes using:
kubectl get secret piggymetrics -o yaml

## Deploy Spring Cloud Config Server
## You can deploy the Spring Cloud Config Server to Kubernetes:

kubectl apply -f deploy/1-config.yaml

##Deploy Spring Cloud Service Registry
## You can deploy the Spring Cloud Service Registry to Kubernetes:

kubectl apply -f deploy/2-registry.yaml

##You can validate that a Spring Cloud Config Server is up and running by invoking its REST API.
##
##The Spring Cloud Config Server REST API has resources in the following form:
##
##/{application}/{profile}[/{label}]
##/{application}-{profile}.yml
##/{label}/{application}-{profile}.yml
##/{application}-{profile}.properties
##/{label}/{application}-{profile}.properties
##You can get IP addresses of Spring Cloud Config Server and Spring Cloud Service Registry using kubectl
kubectl get services

## Try: 
open http://20.118.121.5:8888/gateway/profile
open http://20.118.121.5:8888/account-service/profile
open http://20.118.121.5:8888/statistics-service/profile
open http://20.118.121.5:8888/notification-service/profile
...
open http://20.118.121.5:8888/notification-service/profile/development
...
## You can validate that a Spring Cloud Service Registry is up and running by opening the Service Registry Dashboard:
open http://20.118.121.5:8761/registry
open http://20.118.121.5:8761

## Deploy Spring Cloud Gateway
## You can deploy the Spring Cloud Gateway to Kubernetes:

kubectl apply -f deploy/3-gateway.yaml

## Deploy 4 Spring Cloud micro service apps
# You can deploy Spring Cloud micro service apps to Kubernetes:

kubectl apply -f deploy/4-auth-service.yaml
kubectl apply -f deploy/5-account-service.yaml
kubectl apply -f deploy/6-statistics-service.yaml
kubectl apply -f deploy/7-notification-service.yaml

## Validate services are running
kubectl get services

## You can also validate that by opening the Spring Cloud Service Registry Dashboard

open http://20.118.125.44:8761/

## Open Spring Cloud micro service apps running on Kubernetes
## Open the Piggymetrics landing page by using thegateway app's EXTERNAL-IP.

open http://13.66.89.144/

## Stream logs from micro service apps in cloud to development machines
# You can stream logs from micro service apps running on Kubernetes to your development machine using kubectl, like:

# Stream logs from Spring Cloud Config Server
kubectl logs -f --timestamps=true -l app=config

# Stream logs from Spring Cloud Service Registry
kubectl logs -f --timestamps=true -l app=registry

# Stream logs from Spring Cloud Gateway
kubectl logs -f --timestamps=true -l app=gateway

# Stream logs from Spring Cloud micro service apps
kubectl logs -f --timestamps=true -l app=auth-service
kubectl logs -f --timestamps=true -l app=account-service
kubectl logs -f --timestamps=true -l app=statistics-service
kubectl logs -f --timestamps=true -l app=notification-service

## Turn on monitoring for the AKS CLuster
az aks enable-addons -a monitoring -n myJavaOnAKS -g rgJavaOnAKS