# Lab Solution: Multi-Team Access Control with RBAC

## Overview

This comprehensive solution guides you through implementing production-ready RBAC with certificate-based authentication for multiple teams in a shared Kubernetes cluster.

> **Journey:** Shared Admin Access → Individual Certificates → Namespace Isolation → Cross-Namespace Avccess → Elevated Operations

**Important:** This lab teaches you the complete authentication and authorization flow used in production Kubernetes clusters.

---

## Phase 1: Environment Setup and Current State Analysis (10-15 minutes)

### Step 1: Create Namespace Structure

**Create three namespaces for the teams:**

```shell
# Create frontend namespace
kubectl create namespace frontend

# Create backend namespace
kubectl create namespace backend

# Create monitoring namespace
kubectl create namespace monitoring

# Verify namespaces created
kubectl get namespaces
```

**Add labels to namespaces for organization:**

```shell
# Label namespaces
kubectl label namespace frontend team=frontend
kubectl label namespace backend team=backend
kubectl label namespace monitoring team=monitoring

# Verify labels
kubectl get namespaces --show-labels
```

---

### Step 2: Deploy Sample Applications

**Deploy application in frontend namespace:**

```yaml
# manifests/frontend/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend-deployment
  namespace: frontend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      securityContext:
        fsGroup: 0
        seccompProfile:
          type: "RuntimeDefault"
      containers:
        - name: frontend
          image: nginxinc/nginx-unprivileged
          ports:
            - containerPort: 8080
          resources:
            requests:
              cpu: 250m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 512Mi
          securityContext:
            runAsNonRoot: true
            readOnlyRootFilesystem: true
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL
          volumeMounts:
            - name: tmp
              mountPath: /tmp
      volumes:
        - name: tmp
          emptyDir: {}

---
# manifests/frontend/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: frontend-service
  namespace: frontend
spec:
  selector:
    app: frontend
  ports:
    - name: http
      port: 8080
      targetPort: 8080
      protocol: TCP
  type: ClusterIP
  sessionAffinity: ClientIP

---
# manifests/frontend/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: frontend
  namespace: frontend
  labels:
    app.kubernetes.io/name: frontend
  annotations:
    kubernetes.io/ingress.class: nginx
spec:
  ingressClassName: nginx
  rules:
    - host: frontend.k3s.test.local
      http:
        paths:
          - pathType: Prefix
            path: "/"
            backend:
              service:
                name: frontend-service
                port:
                  number: 8080
```

```shell
# Deploy frontend application
kubectl apply -f manifests/frontend

# Verify resources
kubectl get all -n frontend
```

**Deploy application in backend namespace:**

```yaml
# manifests/backend/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend-deployment
  namespace: backend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
    spec:
      securityContext:
        fsGroup: 0
        seccompProfile:
          type: "RuntimeDefault"
      containers:
        - name: backend
          image: nginxinc/nginx-unprivileged
          ports:
            - containerPort: 8080
          resources:
            requests:
              cpu: 250m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 512Mi
          securityContext:
            runAsNonRoot: true
            readOnlyRootFilesystem: true
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL
          volumeMounts:
            - name: tmp
              mountPath: /tmp
      volumes:
        - name: tmp
          emptyDir: {}

---
# manifests/backend/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: backend-service
  namespace: backend
spec:
  selector:
    app: backend
  ports:
    - name: http
      port: 8080
      targetPort: 8080
      protocol: TCP
  type: ClusterIP
  sessionAffinity: ClientIP

---
# manifests/backend/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: backend
  namespace: backend
  labels:
    app.kubernetes.io/name: backend
  annotations:
    kubernetes.io/ingress.class: nginx
spec:
  ingressClassName: nginx
  rules:
    - host: backend.k3s.test.local
      http:
        paths:
          - pathType: Prefix
            path: "/"
            backend:
              service:
                name: backend-service
                port:
                  number: 8080
```

```shell
# Deploy backend application
kubectl apply -f  manifests/backend

# Verify resources
kubectl get all -n backend
```

---

### Step 3: Analyze Current Admin Access

**Check current permissions:**

```shell
# Check what your current user can do
kubectl auth can-i --list

# Check access to frontend namespace
kubectl auth can-i get pods -n frontend
kubectl auth can-i delete deployments -n frontend

# Check access to backend namespace
kubectl auth can-i get pods -n backend

# Check cluster-level access
kubectl auth can-i create namespaces
kubectl auth can-i get nodes

# View all resources across namespaces
kubectl get pods -A
kubectl get deployments -A
```

**Document current state:**

```plaintext
Current Access Analysis:
========================
Current User: kubernetes-admin (from default kubeconfig)
Access Level: cluster-admin

Permissions:
✓ Full access to all namespaces
✓ Can create, read, update, delete any resource
✓ Can manage RBAC rules
✓ Can access nodes and cluster resources
✓ No audit trail (everyone uses same kubeconfig)

Problem: This violates principle of least privilege
```

---

## Phase 2: Frontend Team - Certificate-Based Authentication (20-25 minutes)

### Step 1: Generate Private Key and CSR

**Create directory for certificates:**

```shell
# Create directory to organize certificates
mkdir -p certs
```

**Generate private key:**

```shell
# Generate RSA private key (2048 bit)
openssl genrsa -out certs/frontend-user.key 2048

# Verify key was created
ls -lh certs/frontend-user.key
```

**Generate Certificate Signing Request (CSR):**

```shell
# Generate CSR with CN and O fields
# CN (Common Name) = username in Kubernetes
# O (Organization) = group membership in Kubernetes

openssl req -new \
  -key certs/frontend-user.key \
  -out certs/frontend-user.csr \
  -subj "/CN=frontend-user/O=frontend-team"

# Verify CSR was created
ls -lh certs/frontend-user.csr

# View CSR contents (optional)
openssl req -in certs/frontend-user.csr -noout -text
```

**Understanding the CSR fields:**

```plaintext
Certificate Fields Explained:
==============================
CN=frontend-user     → Becomes username "frontend-user" in Kubernetes
O=frontend-team      → Becomes group "frontend-team" in Kubernetes

When RBAC evaluates permissions:
- User: "frontend-user"
- Groups: ["frontend-team", "system:authenticated"]
```

---

### Step 2: Create Kubernetes CertificateSigningRequest Object

**Read and encode the CSR:**

```shell
# Base64 encode the CSR (required for Kubernetes)
cat certs/frontend-user.csr | base64
```

**Create CertificateSigningRequest YAML:**

```shell
# Create CSR from template file
USER_NAME="frontend-user"
MANIFEST_DIR="frontend"
CSR_CONTENT=$(cat certs/$USER_NAME.csr | base64 | tr -d '\n')

sed -e "s|<B64_ENCODED_CSR>|$CSR_CONTENT|" \
    -e "s|<USER>|$USER_NAME|" \
    manifests/global/template-csr.yaml > manifests/$MANIFEST_DIR/csr-user.yaml
```

**Create CertificateSigningRequest YAML:**

```shell
kubectl apply -f manifests/frontend/csr-user.yaml
```

**Verify CSR was created:**

```shell
# Check CSR status
kubectl get csr

# Should show:
# NAME            AGE   SIGNERNAME                            REQUESTOR          CONDITION
# frontend-user   5s    kubernetes.io/kube-apiserver-client   kubernetes-admin   Pending

# View detailed CSR information
kubectl describe csr frontend-user
```

---

### Step 3: Approve CSR and Extract Certificate

**Approve the CSR:**

```shell
# Approve the certificate signing request
kubectl certificate approve frontend-user

# Verify approval
kubectl get csr frontend-user

# Should show CONDITION: Approved,Issued
```

**Extract the signed certificate:**

```shell
# Extract certificate from Kubernetes
kubectl get csr frontend-user -o jsonpath='{.status.certificate}' | base64 -d > certs/frontend-user.crt

# Verify certificate file created
ls -lh certs/frontend-user.crt

# View certificate details (optional)
openssl x509 -in certs/frontend-user.crt -noout -text

# Check certificate subject
openssl x509 -in certs/frontend-user.crt -noout -subject
# Should show: subject=CN = certs/frontend-user, O = frontend-team
```

---

### Step 4: Build Kubeconfig File

**Get cluster information:**

```shell
# Get cluster server URL
kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'

# Get cluster CA certificate
kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > certs/ca.crt

# Save these for kubeconfig creation
```

**Method 1: Build kubeconfig manually (educational):**

```yaml
# configs/frontend-user
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: <base64-encoded-ca-cert>
    server: https://127.0.0.1:6443  # Your cluster server URL
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: frontend-user
    namespace: frontend
  name: frontend-user@kubernetes
current-context: frontend-user@kubernetes
users:
- name: frontend-user
  user:
    client-certificate-data: <base64-encoded-client-cert>
    client-key-data: <base64-encoded-client-key>
```

**Method 2: Build kubeconfig using kubectl (recommended):**

```shell
# Get cluster details from current config
CLUSTER_SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
CLUSTER_CA=$(kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

# Create new kubeconfig file
KUBECONFIG=configs/frontend-user kubectl config set-cluster kubernetes \
  --server=$CLUSTER_SERVER \
  --certificate-authority=certs/ca.crt \
  --embed-certs=true

# Add user credentials
KUBECONFIG=configs/frontend-user kubectl config set-credentials frontend-user \
  --client-certificate=certs/frontend-user.crt \
  --client-key=certs/frontend-user.key \
  --embed-certs=true

# Create context
KUBECONFIG=configs/frontend-user kubectl config set-context frontend-user@kubernetes \
  --cluster=kubernetes \
  --user=frontend-user \
  --namespace=frontend

# Set current context
KUBECONFIG=configs/frontend-user kubectl config use-context frontend-user@kubernetes

# Verify kubeconfig structure
KUBECONFIG=configs/frontend-user kubectl config view
```

---

### Step 5: Test Authentication

**Test with new kubeconfig:**

```shell
# Try to get pods (will fail with "forbidden" - this is expected)
kubectl --kubeconfig=configs/frontend-user get pods -n frontend

# Expected error:
# Error from server (Forbidden): pods is forbidden: User "frontend-user"
# cannot list resource "pods" in API group "" in the namespace "frontend"

# This confirms:
# ✓ Authentication WORKS (certificate is trusted)
# ✗ Authorization FAILS (no RBAC rules yet)
```

**Verify identity:**

```shell
# Check who you are with this kubeconfig
kubectl --kubeconfig=configs/frontend-user auth whoami

# Should show:
# Username: frontend-user
# Groups: [frontend-team system:authenticated]
```

**Understanding the result:**

```plaintext
Authentication vs Authorization:
================================

Authentication (Who are you?):
✓ PASSED - Kubernetes trusts the certificate
✓ Identity: frontend-user
✓ Groups: frontend-team, system:authenticated

Authorization (What can you do?):
✗ FAILED - No RBAC rules grant permissions yet
✗ Need to create Role and RoleBinding

Next step: Create RBAC configuration
```

---

## Phase 3: Frontend Team - RBAC Configuration (15-20 minutes)

### Step 1: Create Role for Developers

**Create Role with developer permissions:**

```yaml
# manifests/frontend/role-developer.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: developer
  namespace: frontend
rules:
# Allow managing core resources (in namespace)
- apiGroups: [""]
  resources: ["pods", "services", "persistentvolumeclaims", "configmaps"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

# Allow managing deployments and replicasets
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets", "statefulsets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

# Allow viewing logs (for debugging)
- apiGroups: [""]
  resources: ["pods/log"]
  verbs: ["get", "list"]

# Allow exec into pods (for debugging)
- apiGroups: [""]
  resources: ["pods/exec"]
  verbs: ["create"]

# Allow viewing events
- apiGroups: [""]
  resources: ["events"]
  verbs: ["get", "list", "watch"]
```

```shell
# Apply the Role
kubectl apply -f manifests/frontend/role-developer.yaml

# Verify Role created
kubectl get role -n frontend
kubectl describe role developer -n frontend
```

**Understanding the Role:**

```plaintext
Role Configuration Explained:
==============================

apiGroups:
- "" (empty string) = core API group (pods, services, configmaps)
- "apps" = apps API group (deployments, replicasets, statefulsets)

Resources:
- pods, services, deployments, etc.
- pods/log = subresource for viewing logs
- pods/exec = subresource for executing commands in pods

Verbs:
- get = retrieve single resource
- list = retrieve all resources of type
- watch = watch for changes
- create = create new resources
- update = update entire resource
- patch = modify parts of resource
- delete = delete resources

Namespace Scope:
- This Role only grants permissions in "frontend" namespace
- Cannot be used in other namespaces
```

---

### Step 2: Create RoleBinding

**Create RoleBinding to grant permissions:**

```yaml
# manifests/frontend/rolebinding-developer.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: frontend-team
  namespace: frontend
subjects:
# Bind to GROUP, not individual user
- kind: Group
  name: frontend-team           # Matches O field in certificate
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: developer               # References the Role we created
  apiGroup: rbac.authorization.k8s.io
```

```shell
# Apply the RoleBinding
kubectl apply -f manifests/frontend/rolebinding-developer.yaml

# Verify RoleBinding created
kubectl get rolebinding -n frontend
kubectl describe rolebinding frontend-team -n frontend
```

**Why bind to Group instead of User:**

```plaintext
Group-Based RBAC Benefits:
===========================

Using Group (O field from certificate):
✓ Scale: Add new users by issuing certificates with same O field
✓ Management: One binding covers all team members
✓ Flexibility: Users can be in multiple groups

Example:
- User 1: CN=alice, O=frontend-team
- User 2: CN=bob, O=frontend-team
- User 3: CN=charlie, O=frontend-team
→ All three automatically get frontend-team permissions

Compare to User-Based:
✗ Need separate RoleBinding for each user
✗ Doesn't scale well
✗ More maintenance overhead
```

---

### Step 3: Test Permissions

**Test allowed operations:**

```shell
# Should work: List pods in frontend namespace
kubectl --kubeconfig=configs/frontend-user get pods -n frontend

# Should work: Get detailed pod information
kubectl --kubeconfig=configs/frontend-user describe pods -n frontend

# Should work: View logs
kubectl --kubeconfig=configs/frontend-user logs -n frontend -l app=frontend

# Should work: Get deployments
kubectl --kubeconfig=configs/frontend-user get deployments -n frontend

# Should work: Create deployment
kubectl --kubeconfig=configs/frontend-user create deployment test \
  --image=nginx:alpine -n frontend

# Should work: Delete deployment
kubectl --kubeconfig=configs/frontend-user delete deployment test -n frontend
```

**Test denied operations:**

```shell
# Should FAIL: Access backend namespace
kubectl --kubeconfig=configs/frontend-user get pods -n backend
# Error: pods is forbidden: User "frontend-user" cannot list resource "pods"
#        in API group "" in the namespace "backend"

# Should FAIL: Delete namespace
kubectl --kubeconfig=configs/frontend-user delete namespace frontend
# Error: namespaces "frontend" is forbidden: User "frontend-user" cannot delete
#        resource "namespaces" in API group "" at the cluster scope

# Should FAIL: View nodes
kubectl --kubeconfig=configs/frontend-user get nodes
# Error: nodes is forbidden: User "frontend-user" cannot list resource "nodes"
#        in API group "" at the cluster scope

# Should FAIL: Create Role (no RBAC management)
kubectl --kubeconfig=configs/frontend-user create role test -n frontend --verb=get --resource=pods
# Error: roles.rbac.authorization.k8s.io is forbidden
```

---

### Step 4: Use kubectl auth can-i for Validation

**Validate permissions systematically:**

```shell
# Test as the frontend user (from admin kubeconfig)
# Using --as flag simulates being that user

# Should return "yes" - allowed in frontend namespace
kubectl auth can-i get pods -n frontend --as=frontend-user --as-group=frontend-team

kubectl auth can-i create deployments -n frontend --as=frontend-user --as-group=frontend-team

kubectl auth can-i delete services -n frontend --as=frontend-user --as-group=frontend-team

# Should return "no" - denied in backend namespace
kubectl auth can-i get pods -n backend --as=frontend-user --as-group=frontend-team

# Should return "no" - denied at cluster level
kubectl auth can-i get nodes --as=frontend-user --as-group=frontend-team

kubectl auth can-i create namespaces --as=frontend-user --as-group=frontend-team

# Should return "no" - cannot manage RBAC
kubectl auth can-i create roles -n frontend --as=frontend-user --as-group=frontend-team

# List all permissions frontend-user has in frontend namespace
kubectl auth can-i --list -n frontend --as=frontend-user --as-group=frontend-team
```

**Alternative: Test from frontend-user kubeconfig:**

```shell
# Check permissions directly with frontend-user kubeconfig
kubectl --kubeconfig=configs/frontend-user auth can-i get pods -n frontend

kubectl --kubeconfig=configs/frontend-user auth can-i get pods -n backend

kubectl --kubeconfig=configs/frontend-user auth can-i create namespaces

# List all permissions
kubectl --kubeconfig=configs/frontend-user auth can-i --list -n frontend
```

---

### Step 5: Verify Namespace Isolation

**Complete isolation test:**

```shell
# Create test resources in frontend namespace (should work)
kubectl --kubeconfig=configs/frontend-user run test-pod --image=nginx:alpine -n frontend

kubectl --kubeconfig=configs/frontend-user get pods -n frontend

# Try to access backend namespace (should fail)
kubectl --kubeconfig=configs/frontend-user get pods -n backend

kubectl --kubeconfig=configs/frontend-user run test-pod --image=nginx:alpine -n backend

# Cleanup
kubectl --kubeconfig=configs/frontend-user delete pod test-pod -n frontend
```

**Document findings:**

```plaintext
Frontend Team Permissions Summary:
===================================

ALLOWED in frontend namespace:
✓ View all resources (pods, services, deployments, etc.)
✓ Create, update, delete resources
✓ View logs and events
✓ Execute commands in pods

DENIED:
✗ Access to backend namespace
✗ Access to monitoring namespace
✗ Access to cluster resources (nodes, PVs, etc.)
✗ Manage RBAC (create roles, rolebindings)
✗ Delete or modify the frontend namespace itself
✗ Access secrets in other namespaces

Security Boundary: Complete namespace isolation achieved
```

---

## Phase 4: Backend Team - Rapid Implementation (10-15 minutes)

### Step 1: Create Backend Team Certificate

**Generate certificate (same process as frontend):**

```shell
# Generate private key
openssl genrsa -out certs/backend-user.key 2048

# Generate CSR with backend team identity
openssl req -new \
  -key certs/backend-user.key \
  -out certs/backend-user.csr \
  -subj "/CN=backend-user/O=backend-team"


# Create CSR from template file
USER_NAME="backend-user"
MANIFEST_DIR="backend"
CSR_CONTENT=$(cat certs/$USER_NAME.csr | base64 | tr -d '\n')

sed -e "s|<B64_ENCODED_CSR>|$CSR_CONTENT|" \
    -e "s|<USER>|$USER_NAME|" \
    manifests/global/template-csr.yaml > manifests/$MANIFEST_DIR/csr-user.yaml
```

```shell
# Apply changes
kubectl apply -f manifests/backend

# Approve CSR
kubectl certificate approve backend-user

# Extract certificate
kubectl get csr backend-user -o jsonpath='{.status.certificate}' | base64 -d > certs/backend-user.crt

# Build kubeconfig
KUBECONFIG=configs/backend-user kubectl config set-cluster kubernetes \
  --server=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}') \
  --certificate-authority=certs/ca.crt \
  --embed-certs=true

KUBECONFIG=configs/backend-user kubectl config set-credentials backend-user \
  --client-certificate=certs/backend-user.crt \
  --client-key=certs/backend-user.key \
  --embed-certs=true

KUBECONFIG=configs/backend-user kubectl config set-context backend-user@kubernetes \
  --cluster=kubernetes \
  --user=backend-user \
  --namespace=backend

KUBECONFIG=configs/backend-user kubectl config use-context backend-user@kubernetes

```

---

### Step 2: Implement Backend Team RBAC

**Option 1: Create separate Role (simple):**

```yaml
# manifests/backend/role-developer.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: developer
  namespace: backend
rules:
- apiGroups: [""]
  resources: ["pods", "services", "persistentvolumeclaims", "configmaps"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets", "statefulsets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: [""]
  resources: ["pods/log"]
  verbs: ["get", "list"]
- apiGroups: [""]
  resources: ["pods/exec"]
  verbs: ["create"]
- apiGroups: [""]
  resources: ["events"]
  verbs: ["get", "list", "watch"]
---
# manifests/backend/rolebinding-developer.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: backend-team-binding
  namespace: backend
subjects:
- kind: Group
  name: backend-team
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: developer
  apiGroup: rbac.authorization.k8s.io
```

```shell
kubectl apply -f manifests/backend/role-developer.yaml
```

**Option 2: Use ClusterRole for reusability (better approach):**

```yaml
# manifests/global/clusterrole-developer.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: developer
rules:
- apiGroups: [""]
  resources: ["pods", "services", "persistentvolumeclaims", "configmaps"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets", "statefulsets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: [""]
  resources: ["pods/log"]
  verbs: ["get", "list"]
- apiGroups: [""]
  resources: ["pods/exec"]
  verbs: ["create"]
- apiGroups: [""]
  resources: ["events"]
  verbs: ["get", "list", "watch"]
---

# manifests/frontend/rolebinding-developer.yaml
# Update frontend to use ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: frontend-team-binding
  namespace: frontend
subjects:
- kind: Group
  name: frontend-team
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole      # Changed from Role to ClusterRole
  name: developer
  apiGroup: rbac.authorization.k8s.io
---
# Backend uses same ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: backend-team-binding
  namespace: backend
subjects:
- kind: Group
  name: backend-team
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole      # References ClusterRole
  name: developer
  apiGroup: rbac.authorization.k8s.io
```

```shell
# Apply ClusterRole and RoleBindings
kubectl apply -f manifests/global/clusterrole-developer.yaml

# Delete old namespace-specific Roles if using ClusterRole approach
kubectl delete role developer -n frontend
kubectl delete role developer -n backend
```

**Understanding ClusterRole + RoleBinding pattern:**

```plaintext
ClusterRole + RoleBinding Pattern:
===================================

ClusterRole "developer":
- Defined once at cluster level
- Contains reusable permission rules
- NOT cluster-wide permissions (just the definition)

RoleBinding in frontend namespace:
- References ClusterRole "developer"
- Grants permissions to "frontend-team" group
- Scoped to frontend namespace only

RoleBinding in backend namespace:
- References same ClusterRole "developer"
- Grants permissions to "backend-team" group
- Scoped to backend namespace only

Benefits:
✓ Define permissions once, use in multiple namespaces
✓ Consistent permissions across teams
✓ Update ClusterRole once, affects all namespaces
✓ Reduces duplication and errors

Result:
- Frontend team: developer permissions in frontend namespace only
- Backend team: developer permissions in backend namespace only
- Still complete isolation between teams
```

---

### Step 3: Test Cross-Namespace Isolation

**Test backend team access:**

```shell
# Should work: Backend namespace
kubectl --kubeconfig=configs/backend-user get pods -n backend
kubectl --kubeconfig=configs/backend-user get deployments -n backend
kubectl --kubeconfig=configs/backend-user logs -n backend -l app=backend

# Should FAIL: Frontend namespace
kubectl --kubeconfig=configs/backend-user get pods -n frontend
# Error: pods is forbidden in namespace "frontend"

# Should FAIL: Monitoring namespace
kubectl --kubeconfig=configs/backend-user get pods -n monitoring

# Should FAIL: Cluster resources
kubectl --kubeconfig=configs/backend-user get nodes
```

**Test frontend team still works:**

```shell
# Should work: Frontend namespace
kubectl --kubeconfig=configs/frontend-user get pods -n frontend

# Should FAIL: Backend namespace
kubectl --kubeconfig=configs/frontend-user get pods -n backend
```

**Verify complete isolation:**

```shell
# Use auth can-i to verify permissions
kubectl auth can-i get pods -n backend --as=backend-user --as-group=backend-team
# yes

kubectl auth can-i get pods -n frontend --as=backend-user --as-group=backend-team
# no

kubectl auth can-i get pods -n frontend --as=frontend-user --as-group=frontend-team
# yes

kubectl auth can-i get pods -n backend --as=frontend-user --as-group=frontend-team
# no
```

**Document isolation:**

```plaintext
Namespace Isolation Verified:
==============================

Frontend Team:
✓ Full access to frontend namespace
✗ No access to backend namespace
✗ No access to monitoring namespace

Backend Team:
✓ Full access to backend namespace
✗ No access to frontend namespace
✗ No access to monitoring namespace

Security Boundary:
✓ Complete isolation achieved
✓ Teams cannot interfere with each other
✓ Principle of least privilege enforced
```

---

## Phase 5: Monitoring Team - Cross-Namespace Read-Only Access (15-20 minutes)

### Step 1: Create Monitoring Team Certificate

**Generate certificate:**

```shell
# Generate private key

# Generate CSR

# Create Kubernetes CSR

# Approve and extract certificate

# Build kubeconfig
```

---

### Step 2: Create ClusterRole for Read-Only Access

**Create ClusterRole with read permissions:**

```yaml
# manifests/global/clusterrole-cluster-reader.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cluster-reader
rules:
# Read access to core resources
- apiGroups: [""]
  resources:
  - pods
  - services
  - endpoints
  - persistentvolumeclaims
  - configmaps
  - namespaces
  verbs: ["get", "list", "watch"]

# Read access to apps resources
- apiGroups: ["apps"]
  resources:
  - deployments
  - replicasets
  - statefulsets
  - daemonsets
  verbs: ["get", "list", "watch"]

# Read access to networking resources
- apiGroups: ["networking.k8s.io"]
  resources:
  - ingresses
  - networkpolicies
  verbs: ["get", "list", "watch"]

# IMPORTANT: Allow viewing logs
- apiGroups: [""]
  resources: ["pods/log"]
  verbs: ["get", "list"]

# Allow viewing events for troubleshooting
- apiGroups: [""]
  resources: ["events"]
  verbs: ["get", "list", "watch"]

# Explicitly EXCLUDE secrets and configmaps with sensitive data
# Note: configmaps are included above for read but monitor team
# should use this responsibly and not access sensitive configs
```

```shell
# Apply ClusterRole
kubectl apply -f cluster-reader-clusterrole.yaml

# Verify ClusterRole created
kubectl get clusterrole cluster-reader
kubectl describe clusterrole cluster-reader
```

**Understanding the ClusterRole scope:**

```plaintext
ClusterRole for Read-Only Access:
==================================

Why ClusterRole (not Role)?
- Needs access to resources in ALL namespaces
- Role would only work in one namespace
- ClusterRole can be used with ClusterRoleBinding for cluster-wide access

What's included:
✓ Pods, services, deployments (view only)
✓ Namespaces (to list and see all namespaces)
✓ pods/log (view application logs)
✓ Events (troubleshooting)

What's excluded:
✗ Secrets (sensitive data)
✗ Write operations (create, update, delete, patch)
✗ RBAC resources (roles, rolebindings)
✗ Cluster resources (nodes, PVs - can add if needed)

Result: Safe read-only monitoring access
```

---

### Step 3: Create ClusterRoleBinding

**Create ClusterRoleBinding for cluster-wide access:**

```yaml
# monitoring-team-clusterrolebinding.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: monitoring-team-binding
subjects:
- kind: Group
  name: monitoring-team       # Matches O field in certificate
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: cluster-reader        # References our ClusterRole
  apiGroup: rbac.authorization.k8s.io
```

```shell
# Apply ClusterRoleBinding
kubectl apply -f monitoring-team-clusterrolebinding.yaml

# Verify ClusterRoleBinding created
kubectl get clusterrolebinding monitoring-team-binding
kubectl describe clusterrolebinding monitoring-team-binding
```

**Understanding ClusterRoleBinding:**

```plaintext
ClusterRoleBinding Explained:
==============================

ClusterRoleBinding:
- Grants permissions at cluster scope
- Not limited to one namespace
- Affects ALL namespaces

Subject: Group "monitoring-team"
- Any user with O=monitoring-team in certificate
- Gets permissions defined in ClusterRole

RoleRef: ClusterRole "cluster-reader"
- The permissions to grant
- Read-only access to resources

Result:
✓ Monitoring team can view resources in ALL namespaces
✓ Cannot modify anything
✓ Cannot access secrets
✓ Can view logs across all namespaces
```

---

### Step 4: Test Cross-Namespace Read Access

**Test viewing resources across namespaces:**

```shell
# Should work: View pods in all namespaces
kubectl --kubeconfig=configs/monitoring-user get pods -A

# Should work: View pods in frontend namespace
kubectl --kubeconfig=configs/monitoring-user get pods -n frontend

# Should work: View pods in backend namespace
kubectl --kubeconfig=configs/monitoring-user get pods -n backend

# Should work: View pods in monitoring namespace
kubectl --kubeconfig=configs/monitoring-user get pods -n monitoring

# Should work: View deployments across namespaces
kubectl --kubeconfig=configs/monitoring-user get deployments -A

# Should work: View services across namespaces
kubectl --kubeconfig=configs/monitoring-user get services -A

# Should work: List all namespaces
kubectl --kubeconfig=configs/monitoring-user get namespaces
```

**Test log access:**

```shell
# Should work: View logs in frontend namespace
kubectl --kubeconfig=configs/monitoring-user logs -n frontend -l app=frontend

# Should work: View logs in backend namespace
kubectl --kubeconfig=configs/monitoring-user logs -n backend -l app=backend

# Should work: View logs with follow
kubectl --kubeconfig=configs/monitoring-user logs -n frontend -l app=frontend -f
# Press Ctrl+C to stop
```

---

### Step 5: Test Read-Only Enforcement

**Verify write operations are denied:**

```shell
# Should FAIL: Create deployment
kubectl --kubeconfig=configs/monitoring-user create deployment test \
  --image=nginx:alpine -n monitoring
# Error: deployments.apps is forbidden: User "monitoring-user" cannot create resource

# Should FAIL: Delete pod
kubectl --kubeconfig=configs/monitoring-user delete pod -n frontend -l app=frontend
# Error: pods is forbidden: User "monitoring-user" cannot delete resource

# Should FAIL: Update deployment
kubectl --kubeconfig=configs/monitoring-user scale deployment frontend-app \
  --replicas=5 -n frontend
# Error: deployments.apps/scale is forbidden: User "monitoring-user" cannot update resource

# Should FAIL: Create namespace
kubectl --kubeconfig=configs/monitoring-user create namespace test
# Error: namespaces is forbidden: User "monitoring-user" cannot create resource
```

**Verify secrets are protected:**

```shell
# Create test secret (using admin kubeconfig)
kubectl create secret generic test-secret \
  --from-literal=password=secret123 -n frontend

# Should FAIL: View secrets
kubectl --kubeconfig=configs/monitoring-user get secrets -n frontend
# Error: secrets is forbidden: User "monitoring-user" cannot list resource

kubectl --kubeconfig=configs/monitoring-user get secret test-secret -n frontend
# Error: secrets "test-secret" is forbidden: User "monitoring-user" cannot get resource
```

**Test exec access (not included in permissions):**

```shell
# Should FAIL: Exec into pod
kubectl --kubeconfig=configs/monitoring-user exec -it -n frontend \
  deployment/frontend-app -- /bin/sh
# Error: pods/exec is forbidden: User "monitoring-user" cannot create resource
```

---

### Step 6: Validate with kubectl auth can-i

**Systematically validate permissions:**

```shell
# Should return "yes" - read operations allowed
kubectl auth can-i get pods -A --as=monitoring-user --as-group=monitoring-team

kubectl auth can-i list deployments -n frontend --as=monitoring-user --as-group=monitoring-team

kubectl auth can-i get pods/log -n backend --as=monitoring-user --as-group=monitoring-team

# Should return "no" - write operations denied
kubectl auth can-i create pods -n frontend --as=monitoring-user --as-group=monitoring-team

kubectl auth can-i delete deployments -n backend --as=monitoring-user --as-group=monitoring-team

kubectl auth can-i patch services -n monitoring --as=monitoring-user --as-group=monitoring-team

# Should return "no" - secrets access denied
kubectl auth can-i get secrets -n frontend --as=monitoring-user --as-group=monitoring-team

# Should return "no" - exec access denied
kubectl auth can-i create pods/exec -n frontend --as=monitoring-user --as-group=monitoring-team

# List all permissions monitoring user has
kubectl auth can-i --list --as=monitoring-user --as-group=monitoring-team
```

**Document findings:**

```plaintext
Monitoring Team Permissions Summary:
=====================================

ALLOWED across ALL namespaces:
✓ View pods, services, deployments, replicasets, statefulsets
✓ View namespaces
✓ View ingresses and network policies
✓ View logs (pods/log)
✓ View events

DENIED everywhere:
✗ Create, update, delete any resources
✗ View secrets or sensitive configmaps
✗ Exec into pods
✗ Manage RBAC
✗ Access cluster resources (nodes, PVs)

Security Boundary:
✓ Read-only access enforced
✓ Can monitor applications across namespaces
✓ Cannot access sensitive data
✓ Cannot interfere with operations
✓ Suitable for monitoring and troubleshooting
```

---

## Phase 6: Platform Team - Elevated But Limited Access (15-20 minutes)

### Step 1: Create Platform Team Certificate

**Generate certificate:**

```shell
# Generate private key

# Generate CSR

# Create Kubernetes CSR

# Build kubeconfig

```

---

### Step 2: Create ClusterRole for Platform Operations

**Create ClusterRole with elevated permissions:**

```yaml
# manifests/global/clusterrole-platform-admin.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: platform-admin
rules:
# Manage namespaces
- apiGroups: [""]
  resources: ["namespaces"]
  verbs: ["get", "list", "watch", "create", "delete", "update", "patch"]

# View nodes (read-only for troubleshooting)
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["get", "list", "watch"]

# Manage PersistentVolumes (cluster-scoped)
- apiGroups: [""]
  resources: ["persistentvolumes"]
  verbs: ["get", "list", "watch", "create", "delete", "update", "patch"]

# Manage StorageClasses
- apiGroups: ["storage.k8s.io"]
  resources: ["storageclasses"]
  verbs: ["get", "list", "watch", "create", "delete", "update", "patch"]

# View all pods for cluster overview
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]

# View all events for cluster troubleshooting
- apiGroups: [""]
  resources: ["events"]
  verbs: ["get", "list", "watch"]
```

```shell
# Apply ClusterRole
kubectl apply -f manifests/global/clusterrole-platform-admin.yaml
```

**Create additional RoleBinding for monitoring namespace:**

```yaml
# manifests/monitoring/rolebinding-platform-monitoring.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: platform-admin-binding
  namespace: monitoring
subjects:
- kind: Group
  name: platform-team
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: admin              # Built-in admin role for full namespace access
  apiGroup: rbac.authorization.k8s.io
```

```shell
# Apply RoleBinding
kubectl apply -f platform-monitoring-rolebinding.yaml
```

---

### Step 3: Create ClusterRoleBinding

**Create ClusterRoleBinding:**

```yaml
# manifests/global/clusterrolebinding-platform-team.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: platform-team-binding
subjects:
- kind: Group
  name: platform-team
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: platform-admin
  apiGroup: rbac.authorization.k8s.io
```

```shell
# Apply ClusterRoleBinding
kubectl apply -f manifests/global/clusterrolebinding-platform-team.yaml
```

**Understanding platform team permissions:**

```plaintext
Platform Team Permission Design:
=================================

ClusterRole "platform-admin" + ClusterRoleBinding:
- Manage namespaces (create/delete for new teams)
- View nodes (troubleshooting, capacity planning)
- Manage PersistentVolumes (storage administration)
- Manage StorageClasses (storage configuration)
- View pods cluster-wide (operational overview)

RoleBinding in monitoring namespace:
- Full admin access to monitoring namespace
- Deploy and manage monitoring tools
- Configure dashboards and alerts

NOT included (still denied):
✗ Access to secrets in application namespaces
✗ Modify resources in frontend/backend namespaces
✗ Create or modify RBAC in other namespaces
✗ Delete or modify nodes
✗ cluster-admin level access

Result: Elevated operations without superuser access
```

---

### Step 4: Test Platform Operations

**Test namespace management:**

```shell
# Should work: List all namespaces
kubectl --kubeconfig=configs/platform-admin get namespaces

# Should work: Create new namespace
kubectl --kubeconfig=configs/platform-admin create namespace test-team

# Should work: Label namespace
kubectl --kubeconfig=configs/platform-admin label namespace test-team team=test

# Should work: Delete namespace
kubectl --kubeconfig=configs/platform-admin delete namespace test-team
```

**Test node viewing:**

```shell
# Should work: View nodes
kubectl --kubeconfig=configs/platform-admin get nodes

kubectl --kubeconfig=configs/platform-admin describe nodes

# Should work: View node metrics (if metrics-server installed)
kubectl --kubeconfig=configs/platform-admin top nodes
```

**Test storage management:**

```shell
# Should work: View PersistentVolumes
kubectl --kubeconfig=configs/platform-admin get pv

# Should work: View StorageClasses
kubectl --kubeconfig=configs/platform-admin get storageclass

# Should work: Create StorageClass (example)
cat <<EOF | kubectl --kubeconfig=configs/platform-admin apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: test-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
EOF

# Cleanup
kubectl --kubeconfig=configs/platform-admin delete storageclass test-storage
```

**Test monitoring namespace access:**

```shell
# Should work: Full access in monitoring namespace
kubectl --kubeconfig=configs/platform-admin get all -n monitoring

kubectl --kubeconfig=configs/platform-admin create deployment test \
  --image=nginx:alpine -n monitoring

kubectl --kubeconfig=configs/platform-admin delete deployment test -n monitoring
```

---

### Step 5: Verify Security Boundaries

**Test that application namespace access is denied:**

```shell
# Should work: View pods (read-only from ClusterRole)
kubectl --kubeconfig=configs/platform-admin get pods -n frontend
kubectl --kubeconfig=configs/platform-admin get pods -n backend

# Should FAIL: Modify resources in application namespaces
kubectl --kubeconfig=configs/platform-admin delete deployment frontend-app -n frontend
# Error: deployments.apps "frontend-app" is forbidden

kubectl --kubeconfig=configs/platform-admin scale deployment backend-app \
  --replicas=5 -n backend
# Error: deployments.apps/scale "backend-app" is forbidden

# Should FAIL: Access secrets in application namespaces
kubectl --kubeconfig=configs/platform-admin get secrets -n frontend
# Error: secrets is forbidden

kubectl --kubeconfig=configs/platform-admin get secrets -n backend
# Error: secrets is forbidden
```

**Test that RBAC management is restricted:**

```shell
# Should FAIL: Create Role in application namespace
kubectl --kubeconfig=configs/platform-admin create role test \
  -n frontend --verb=get --resource=pods
# Error: roles.rbac.authorization.k8s.io is forbidden

# Should FAIL: Create ClusterRole
kubectl --kubeconfig=configs/platform-admin create clusterrole test \
  --verb=get --resource=pods
# Error: clusterroles.rbac.authorization.k8s.io is forbidden

# Should work: Full RBAC access in monitoring namespace
kubectl --kubeconfig=configs/platform-admin create role test \
  -n monitoring --verb=get --resource=pods

kubectl --kubeconfig=configs/platform-admin delete role test -n monitoring
```

**Test node management is restricted:**

```shell
# Should FAIL: Cordon node
kubectl --kubeconfig=configs/platform-admin cordon <node-name>
# Error: nodes is forbidden: User "platform-admin" cannot update resource

# Should FAIL: Delete node
kubectl --kubeconfig=configs/platform-admin delete node <node-name>
# Error: nodes is forbidden: User "platform-admin" cannot delete resource
```

---

### Step 6: Validate with kubectl auth can-i

**Validate platform team permissions:**

```shell
# Should return "yes" - cluster operations allowed
kubectl auth can-i create namespaces --as=platform-admin --as-group=platform-team

kubectl auth can-i delete namespaces --as=platform-admin --as-group=platform-team

kubectl auth can-i get nodes --as=platform-admin --as-group=platform-team

kubectl auth can-i get pv --as=platform-admin --as-group=platform-team

# Should return "yes" - monitoring namespace full access
kubectl auth can-i create deployments -n monitoring --as=platform-admin --as-group=platform-team

kubectl auth can-i delete pods -n monitoring --as=platform-admin --as-group=platform-team

# Should return "no" - application namespace modifications denied
kubectl auth can-i delete deployments -n frontend --as=platform-admin --as-group=platform-team

kubectl auth can-i create pods -n backend --as=platform-admin --as-group=platform-team

# Should return "no" - secrets access denied
kubectl auth can-i get secrets -n frontend --as=platform-admin --as-group=platform-team

# Should return "no" - node modifications denied
kubectl auth can-i cordon nodes --as=platform-admin --as-group=platform-team

kubectl auth can-i delete nodes --as=platform-admin --as-group=platform-team
```

**Document platform team permissions:**

```plaintext
Platform Team Permissions Summary:
===================================

ALLOWED at cluster level:
✓ Create, delete, manage namespaces
✓ View nodes (read-only)
✓ Manage PersistentVolumes
✓ Manage StorageClasses
✓ View all pods (read-only overview)

ALLOWED in monitoring namespace:
✓ Full admin access (create, update, delete all resources)
✓ Manage RBAC within monitoring namespace
✓ Deploy monitoring tools and dashboards

DENIED:
✗ Modify resources in frontend/backend namespaces
✗ Access secrets in application namespaces
✗ Create/modify RBAC in other namespaces
✗ Modify nodes (cordon, drain, delete)
✗ cluster-admin level access

Security Boundary:
✓ Elevated operational access without superuser permissions
✓ Can manage infrastructure (namespaces, storage)
✓ Cannot interfere with application teams
✓ Cannot access sensitive application data
✓ Principle of least privilege for platform operations
```

---

## Phase 7: Validation and Permission Testing (10-15 minutes)

### Step 1: Create Permission Matrix

**Document complete permission model:**

```plaintext
RBAC Permission Matrix:
=======================

| Team/User       | Frontend NS | Backend NS | Monitoring NS | Cluster Resources      |
|-----------------|-------------|------------|---------------|------------------------|
| Frontend Team   | Full RW     | None       | None          | None                   |
| Backend Team    | None        | Full RW    | None          | None                   |
| Monitoring Team | Read-only   | Read-only  | Read-only     | Read-only (pods, etc.) |
| Platform Team   | Read pods   | Read pods  | Full RW       | Manage NS, View nodes  |

Legend:
- Full RW: Create, read, update, delete all resources
- Read-only: Get, list, watch resources; view logs
- None: No access
- Manage NS: Create/delete namespaces
- View nodes: Read-only node information

Key:
✓ = Allowed
✗ = Denied
R = Read-only
W = Read-Write
```

---

### Step 2: Systematic Permission Testing

**Create comprehensive test script:**

```shell
#!/bin/bash
# rbac-validation.sh - Comprehensive RBAC testing

echo "=== RBAC Validation Test Suite ==="
echo

# Test 1: Frontend team permissions
echo "Test 1: Frontend Team"
echo "  Frontend namespace access (should succeed):"
kubectl auth can-i create deployments -n frontend --as=frontend-user --as-group=frontend-team
echo "  Backend namespace access (should fail):"
kubectl auth can-i get pods -n backend --as=frontend-user --as-group=frontend-team
echo

# Test 2: Backend team permissions
echo "Test 2: Backend Team"
echo "  Backend namespace access (should succeed):"
kubectl auth can-i create deployments -n backend --as=backend-user --as-group=backend-team
echo "  Frontend namespace access (should fail):"
kubectl auth can-i get pods -n frontend --as=backend-user --as-group=backend-team
echo

# Test 3: Monitoring team cross-namespace access
echo "Test 3: Monitoring Team"
echo "  View pods in frontend (should succeed):"
kubectl auth can-i get pods -n frontend --as=monitoring-user --as-group=monitoring-team
echo "  View pods in backend (should succeed):"
kubectl auth can-i get pods -n backend --as=monitoring-user --as-group=monitoring-team
echo "  Delete pods in frontend (should fail):"
kubectl auth can-i delete pods -n frontend --as=monitoring-user --as-group=monitoring-team
echo "  View secrets (should fail):"
kubectl auth can-i get secrets -n frontend --as=monitoring-user --as-group=monitoring-team
echo

# Test 4: Platform team elevated access
echo "Test 4: Platform Team"
echo "  Create namespace (should succeed):"
kubectl auth can-i create namespaces --as=platform-admin --as-group=platform-team
echo "  View nodes (should succeed):"
kubectl auth can-i get nodes --as=platform-admin --as-group=platform-team
echo "  Full access in monitoring namespace (should succeed):"
kubectl auth can-i delete deployments -n monitoring --as=platform-admin --as-group=platform-team
echo "  Delete deployment in frontend (should fail):"
kubectl auth can-i delete deployments -n frontend --as=platform-admin --as-group=platform-team
echo "  View secrets in backend (should fail):"
kubectl auth can-i get secrets -n backend --as=platform-admin --as-group=platform-team
echo

# Test 5: Secret protection
echo "Test 5: Secret Protection (all teams except platform in monitoring)"
for team in "frontend-user/frontend-team" "backend-user/backend-team" "monitoring-user/monitoring-team"; do
    IFS='/' read -r user group <<< "$team"
    result=$(kubectl auth can-i get secrets -A --as=$user --as-group=$group 2>&1)
    if [[ $result == *"no"* ]]; then
        echo "  ✓ $user cannot access secrets"
    else
        echo "  ✗ $user CAN access secrets (SECURITY ISSUE!)"
    fi
done
echo

echo "=== Test Suite Complete ==="
```

```shell
# Make script executable
chmod +x rbac-validation.sh

# Run validation
./rbac-validation.sh
```

---

### Step 3: Test Operational Scenarios

**Scenario 1: Developer deploys application:**

```shell
echo "=== Scenario 1: Frontend developer deploys application ==="

# Frontend developer creates deployment
kubectl --kubeconfig=configs/frontend-user create deployment web-app \
  --image=nginx:alpine -n frontend

# Verify deployment created
kubectl --kubeconfig=configs/frontend-user get deployments -n frontend

# Try to deploy in wrong namespace (should fail)
kubectl --kubeconfig=configs/frontend-user create deployment web-app \
  --image=nginx:alpine -n backend || echo "✓ Correctly denied"

# Cleanup
kubectl --kubeconfig=configs/frontend-user delete deployment web-app -n frontend
echo
```

**Scenario 2: Monitoring team troubleshoots issue:**

```shell
echo "=== Scenario 2: Monitoring team investigates pod issue ==="

# View pods across all namespaces
kubectl --kubeconfig=configs/monitoring-user get pods -A

# Check logs in frontend namespace
kubectl --kubeconfig=configs/monitoring-user logs -n frontend -l app=frontend --tail=10

# Check logs in backend namespace
kubectl --kubeconfig=configs/monitoring-user logs -n backend -l app=backend --tail=10

# Try to fix issue by deleting pod (should fail)
kubectl --kubeconfig=configs/monitoring-user delete pod -n frontend -l app=frontend || echo "✓ Correctly denied - cannot modify"
echo
```

**Scenario 3: Platform team onboards new team:**

```shell
echo "=== Scenario 3: Platform team creates namespace for new team ==="

# Create namespace for new team
kubectl --kubeconfig=configs/platform-admin create namespace data-science

# Label namespace
kubectl --kubeconfig=configs/platform-admin label namespace data-science team=data-science

# Verify namespace created
kubectl --kubeconfig=configs/platform-admin get namespace data-science

# Platform team cannot access existing team secrets
kubectl --kubeconfig=configs/platform-admin get secrets -n frontend || echo "✓ Correctly denied - cannot access application secrets"

# Cleanup
kubectl --kubeconfig=configs/platform-admin delete namespace data-science
echo
```

---

### Step 4: Document Final Configuration

**Create comprehensive documentation:**

```plaintext
RBAC Implementation Summary:
============================

Date: [Current Date]
Cluster: k3s
Teams: 4 (Frontend, Backend, Monitoring, Platform)

Certificate-Based Authentication:
- All users authenticate with X.509 certificates
- CN field = username
- O field = group membership
- Certificates signed by Kubernetes CA
- 1 year expiration (renewable)

RBAC Configuration:

1. Frontend Team (frontend-user, frontend-team group)
   - ClusterRole: developer (reusable definition)
   - RoleBinding: frontend-team-binding in frontend namespace
   - Permissions: Full management in frontend namespace only
   - Kubeconfig: configs/frontend-user

2. Backend Team (backend-user, backend-team group)
   - ClusterRole: developer (same as frontend)
   - RoleBinding: backend-team-binding in backend namespace
   - Permissions: Full management in backend namespace only
   - Kubeconfig: configs/backend-user

3. Monitoring Team (monitoring-user, monitoring-team group)
   - ClusterRole: cluster-reader (read-only cluster-wide)
   - ClusterRoleBinding: monitoring-team-binding
   - Permissions: Read-only access to pods, logs, events in all namespaces
   - Kubeconfig: configs/monitoring-user

4. Platform Team (platform-admin, platform-team group)
   - ClusterRole: platform-admin (namespace/storage management)
   - ClusterRoleBinding: platform-team-binding
   - RoleBinding: platform-admin-binding in monitoring namespace
   - Permissions: Namespace management, view nodes, full monitoring namespace
   - Kubeconfig: configs/platform-admin

Security Boundaries Achieved:
✓ Complete namespace isolation between application teams
✓ Least privilege principle enforced for all teams
✓ Cross-namespace monitoring with read-only access
✓ Elevated platform operations without cluster-admin
✓ Secret protection across all namespaces
✓ Audit trail through certificate-based identity

Next Steps:
- Implement certificate rotation procedures
- Set up audit log monitoring for RBAC events
- Document break-glass procedures for emergencies
- Create runbooks for onboarding new teams
- Integrate with external identity provider (LDAP/AD)
```

---

## Troubleshooting Common Issues

### Issue 1: Certificate Not Trusted

**Symptoms:**

```plaintext
Error from server (Forbidden): ... is forbidden: User "system:anonymous"
Unable to connect to the server: x509: certificate signed by unknown authority
```

**Solutions:**

```shell
# Check if CA certificate is correct in kubeconfig
kubectl --kubeconfig=configs/frontend-user config view --raw | grep certificate-authority-data

# Verify certificate was issued by cluster CA
openssl verify -CAfile ca.crt frontend-user.crt

# Ensure cluster server URL is correct
kubectl --kubeconfig=configs/frontend-user config view | grep server

# Rebuild kubeconfig with correct CA
```

---

### Issue 2: CSR Pending Forever

**Symptoms:**

```
NAME            AGE   SIGNERNAME                            REQUESTOR   CONDITION
frontend-user   5m    kubernetes.io/kube-apiserver-client   admin       Pending
```

**Solutions:**

```shell
# Approve the CSR manually
kubectl certificate approve frontend-user

# Check if you have permission to approve CSRs
kubectl auth can-i approve certificatesigningrequests

# View CSR details for any errors
kubectl describe csr backend-user
```

---

### Issue 3: Permissions Don't Work After Creating RoleBinding

**Symptoms:**

```plaintext
Error from server (Forbidden): pods is forbidden: User "frontend-user"
cannot list resource "pods" in API group "" in the namespace "frontend"
```

**Solutions:**

```shell
# Verify RoleBinding exists
kubectl get rolebinding -n frontend

# Check RoleBinding references correct Role/ClusterRole
kubectl describe rolebinding frontend-team-binding -n frontend

# Verify subject matches certificate O field
kubectl get rolebinding frontend-team-binding -n frontend -o yaml

# Check Role has correct permissions
kubectl describe role developer -n frontend

# Verify user's group membership
kubectl --kubeconfig=configs/frontend-user auth whoami
# Should show Group: frontend-team

# Common mistakes:
# 1. Subject kind is "User" instead of "Group"
# 2. Group name doesn't match O field in certificate
# 3. RoleBinding in wrong namespace
# 4. Role has wrong apiGroups (e.g., "" instead of "apps" for deployments)
```

---

### Issue 4: API Group Confusion

**Symptoms:**

```plaintext
# Deployments don't work even though Role includes them
Error: deployments.apps is forbidden
```

**Solutions:**

```shell
# Check what apiGroup deployments use
kubectl api-resources | grep deployments
# Shows: deployments ... apps

# Fix Role to use correct apiGroup
rules:
- apiGroups: ["apps"]      # NOT "", which is core API group
  resources: ["deployments"]
  verbs: ["get", "list", "create", "update", "delete"]

# Common apiGroups:
# "" (empty) = core (pods, services, configmaps, secrets)
# "apps" = deployments, replicasets, statefulsets, daemonsets
# "batch" = jobs, cronjobs
# "networking.k8s.io" = ingresses, networkpolicies
```

---

### Issue 5: ClusterRole vs Role Confusion

**Symptoms:**

```plaintext
# User can't access resources even though ClusterRole exists
Error: pods is forbidden in namespace "frontend"
```

**Solutions:**

```shell
# ClusterRole needs binding
# Option 1: ClusterRoleBinding (cluster-wide access)
# Option 2: RoleBinding (namespace-scoped access)

# Check if binding exists
kubectl get rolebinding -n frontend
kubectl get clusterrolebinding

# Verify binding references ClusterRole correctly
kubectl describe rolebinding frontend-team-binding -n frontend
# Should show:
# Role:
#   Kind: ClusterRole  <-- Must be ClusterRole, not Role
#   Name: developer
```

---

### Issue 6: Cannot View Logs

**Symptoms:**

```plaintext
Error: pods/log is forbidden: User cannot get resource "pods/log"
```

**Solutions:**

```shell
# Add pods/log to Role or ClusterRole
rules:
- apiGroups: [""]
  resources: ["pods/log"]
  verbs: ["get", "list"]

# Verify permission
kubectl auth can-i get pods/log -n frontend --as=frontend-user --as-group=frontend-team
```

---

## Cleanup

**Remove all RBAC resources:**

```shell
# Delete namespaces (includes all resources inside)
kubectl delete namespace frontend
kubectl delete namespace backend
kubectl delete namespace monitoring

# Delete ClusterRoles
kubectl delete clusterrole developer
kubectl delete clusterrole cluster-reader
kubectl delete clusterrole platform-admin

# Delete ClusterRoleBindings
kubectl delete clusterrolebinding monitoring-team-binding
kubectl delete clusterrolebinding platform-team-binding

# Delete CSRs
kubectl delete csr frontend-user
kubectl delete csr backend-user
kubectl delete csr monitoring-user
kubectl delete csr platform-admin

# Remove certificate files
cd ~/k8s-rbac-lab/certs
rm -f *.key *.csr *.crt *.kubeconfig

# Remove lab directory
cd ~
rm -rf k8s-rbac-lab
```

---

## Learning Outcomes

### Technical Skills Acquired

- [x] Generate OpenSSL private keys and certificate signing requests
- [x] Create and approve Kubernetes CertificateSigningRequest objects
- [x] Extract signed certificates from Kubernetes
- [x] Build kubeconfig files from scratch with embedded certificates
- [x] Create Roles with appropriate permission granularity
- [x] Create ClusterRoles for reusable or cluster-wide permissions
- [x] Create RoleBindings to grant namespace-specific access
- [x] Create ClusterRoleBindings for cluster-wide access
- [x] Use kubectl auth can-i to test permissions
- [x] Troubleshoot RBAC "forbidden" errors systematically
- [x] Implement the ClusterRole + RoleBinding pattern
- [x] Understand apiGroups and their importance

### Conceptual Understanding

- [x] Certificate-based authentication in Kubernetes
- [x] How CN and O map to username and groups
- [x] Difference between authentication and authorization
- [x] RBAC additive permission model (no deny rules)
- [x] Role vs ClusterRole use cases
- [x] RoleBinding vs ClusterRoleBinding scope
- [x] Namespace-scoped vs cluster-scoped resources
- [x] Principle of least privilege in practice
- [x] Group-based vs user-based RBAC
- [x] How RBAC enables multi-tenancy

### Production Patterns

- [x] Team-based namespace isolation
- [x] Read-only cross-namespace monitoring access
- [x] Elevated platform operations without cluster-admin
- [x] Secret protection strategies
- [x] Reusable ClusterRole definitions
- [x] Certificate lifecycle basics
- [x] Permission testing methodology
- [x] Security boundary validation

---

## Next Steps: OpenShift RBAC

The RBAC concepts and skills learned in this lab apply directly to OpenShift:

**Same Concepts:**

- Role, ClusterRole, RoleBinding, ClusterRoleBinding API is identical
- Certificate-based authentication works the same way
- kubectl auth can-i works the same

**OpenShift Additions:**

- Projects = Namespaces + additional RBAC layer
- OAuth server handles authentication (optional)
- Additional built-in roles (system:*) for OpenShift components
- Web console for easier RBAC management
- SCC (Security Context Constraints) integrated with RBAC

**Upcoming in Module 11-12:**

- OpenShift authentication providers (LDAP, OAuth)
- Project-based multi-tenancy
- SCC and RBAC interaction
- Web console RBAC management
- Enterprise integration patterns

The foundation you've built here makes OpenShift RBAC straightforward to learn.

---

**Difficulty:** Intermediate to Expert
**Learning Validation:** Students can create complete RBAC configurations for multi-team Kubernetes environments using certificate-based authentication and implement principle of least privilege.
