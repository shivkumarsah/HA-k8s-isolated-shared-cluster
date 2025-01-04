#!/bin/bash

NAMESPACE_NAME=$1
USER=$2

cat <<EOF >./ns-$NAMESPACE_NAME.yml
kind: Namespace
apiVersion: v1
metadata:
  name: $NAMESPACE_NAME

---

apiVersion: v1
kind: ResourceQuota
metadata:
  name: compute-resources
  namespace: $NAMESPACE_NAME
spec:
  hard:
    requests.cpu: "6"
    requests.memory: 8Gi
    limits.cpu: "12"
    limits.memory: 12Gi
    requests.nvidia.com/gpu: 0
    requests.storage: "40Gi"

---
apiVersion: v1
kind: LimitRange
metadata:
  name: mem-limit-range
  namespace: $NAMESPACE_NAME
spec:
  limits:
  - default:
      memory: 512Mi
      cpu: "2"
    defaultRequest:
      memory: 256Mi
      cpu: "1"
    type: Container

---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: $USER-admin
  namespace: $NAMESPACE_NAME

---
apiVersion: v1
kind: Secret
metadata:
  name: $USER-admin-secret
  namespace: $NAMESPACE_NAME
  annotations:
    kubernetes.io/service-account.name: $USER-admin
type: kubernetes.io/service-account-token

---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: $USER-role
  namespace: $NAMESPACE_NAME
rules:
  - apiGroups: ["*"]
    resources: ["*"]
    verbs: ["*"]
  
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: $USER-rolebinding
  namespace: $NAMESPACE_NAME
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: $USER-role
subjects:
- namespace: $NAMESPACE_NAME
  kind: ServiceAccount
  name: $USER-admin
EOF

# Create namespace, ResourceQuota, LimitRange
kubectl create -f ns-$NAMESPACE_NAME.yml

export SA_SECRET_TOKEN=$(kubectl -n $NAMESPACE_NAME get secret/$USER-admin-secret -o=go-template='{{.data.token}}' | base64 --decode)
export CLUSTER_NAME=$(kubectl config current-context)
export CURRENT_CLUSTER=$(kubectl config view --raw -o=go-template='{{range .contexts}}{{if eq .name "'''${CLUSTER_NAME}'''"}}{{ index .context "cluster" }}{{end}}{{end}}')

cat << EOF > kc_$NAMESPACE_NAME.kubeconfig
apiVersion: v1
kind: Config
current-context: ${CLUSTER_NAME}
contexts:
- name: ${CLUSTER_NAME}
  context:
    cluster: ${CLUSTER_NAME}
    user: ${USER}-admin
    namespace: ${NAMESPACE_NAME}
clusters:
- name: ${CLUSTER_NAME}
  cluster:
    server: https://ats-k8s-stg-apiserver.corp.adobe.com
    insecure-skip-tls-verify: true
users:
- name: ${USER}-admin
  user:
    token: ${SA_SECRET_TOKEN}
EOF
