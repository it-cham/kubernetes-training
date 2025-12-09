# Lab Solution: Network Isolation with Network Policies

## Overview

This comprehensive solution guides you through implementing Kubernetes NetworkPolicies to achieve namespace isolation and traffic control in a two-tier application.

> **Journey:** Open Network → Automatic Isolation → Selective Allow → Validated Security

**Important Concept:** Kubernetes uses automatic isolation - when the first NetworkPolicy is applied to select a pod, that pod becomes isolated and all traffic is denied by default unless explicitly allowed.

This is one of the most common sources of confusion with NetworkPolicies:

> NetworkPolicies Target Pods, Not Services; This means, that the services act as a translation layer!

**Key Points:**

1. NetworkPolicies select pods using labels (podSelector)
2. The `port` field in a NetworkPolicy refers to the pod's `containerPort`, not the service port
3. Services are just routing mechanisms - traffic ultimately goes to pods
4. When you access a service, the NetworkPolicy is evaluated when traffic reaches the pod

**Example Scenario:**

```yaml
Service:
  port: 80          # External service port
  targetPort: 8081  # Routes to pod port 8081

Pod:
  containerPort: 8081  # Pod listens on 8081

NetworkPolicy:
  port: 8081        # MUST match pod port (8081), not service port (80)!
```

---

## Phase 1: Environment Setup and Default Behavior (10-15 minutes)

### Step 1: Create Namespace Structure

**Create namespaces with appropriate labels:**

```bash
# Create frontend namespace
kubectl create namespace frontend

# Create backend namespace
kubectl create namespace backend

# Verify namespaces were created
kubectl get namespaces frontend backend

# Expected output should show both namespaces
```

**About namespace labels:**

Kubernetes automatically adds the label `kubernetes.io/metadata.name=<namespace-name>` to every namespace. NetworkPolicies use `namespaceSelector` with this built-in label to allow traffic from specific namespaces - no manual labeling required!

---

### Step 2: Deploy Frontend Application

**Create frontend deployment:**

```yaml
# manifests/frontend-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend-deployment
  namespace: frontend
  labels:
    app: frontend
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
```

**Create frontend service:**

```yaml
# manifests/frontend-service.yaml
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
      port: 9090
      targetPort: 8080
      protocol: TCP
  type: ClusterIP
  sessionAffinity: ClientIP
```

**Deploy:**

```bash
# Apply frontend resources
kubectl apply -f manifests/frontend/deployment.yaml
kubectl apply -f manifests/frontend/service.yaml

# Verify deployment
kubectl get all -n frontend

# Wait for pod to be ready
kubectl wait --for=condition=ready pod -l app=frontend -n frontend --timeout=120s

# Check pod is running
kubectl get pods -n frontend
```

---

### Step 3: Deploy Backend Application

**Create backend deployment (modified for port 8081):**

```yaml
# manifests/backend-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend-deployment
  namespace: backend
  labels:
    app: backend
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
            - containerPort: 8081
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
            - name: nginx-config
              mountPath: /etc/nginx/conf.d
      volumes:
        - name: tmp
          emptyDir: {}
        - name: nginx-config
          configMap:
            name: backend-nginx-config
---
# manifests/backend-nginx-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: backend-nginx-config
  namespace: backend
data:
  default.conf: |
    server {
        listen 8081;
        server_name localhost;

        location / {
            root   /usr/share/nginx/html;
            index  index.html index.htm;
        }

        error_page   500 502 503 504  /50x.html;
        location = /50x.html {
            root   /usr/share/nginx/html;
        }
    }
```

**Create backend service:**

```yaml
# manifests/backend-service.yaml
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
      port: 9091
      targetPort: 8081
      protocol: TCP
  type: ClusterIP
  sessionAffinity: ClientIP
```

**Deploy:**

```bash
# Apply backend resources
kubectl apply -f manifests/backend/deployment.yaml
kubectl apply -f manifests/backend/configmap-nginx.yaml
kubectl apply -f manifests/backend/service.yaml

# Verify deployment
kubectl get all -n backend

# Wait for pod to be ready
kubectl wait --for=condition=ready pod -l app=backend -n backend --timeout=120s

# Check pod is running
kubectl get pods -n backend
```

---

### Step 4: Test Default Unrestricted Connectivity

**Understanding what we're testing:**

- Services provide DNS names and load balancing
- Services route traffic to backend pods
- **NetworkPolicies are evaluated at the pod level**
- Whether you connect via service or directly to pod IP, the pod receives the traffic
- Without NetworkPolicies, all pod-to-pod communication is allowed

**Test 1: Frontend → Backend Service (via DNS):**

```bash
# Test HTTP connectivity using service DNS name
kubectl exec -n frontend deployment/frontend-deployment -- curl -s -o /dev/null -w "%{http_code}\n" http://backend-service.backend:9091

# Expected: 200 (success)
# What happens:
# 1. DNS resolves backend-service.backend to ClusterIP
# 2. Service routes to backend pod IP
# 3. Traffic reaches backend pod (no NetworkPolicy blocking it)
# 4. Pod responds

# Important: The NetworkPolicy (if it existed) would be evaluated at step 3
```

**Test 2: Frontend → Backend Pod (direct IP):**

```bash
# Get backend pod IP
BACKEND_POD_IP=$(kubectl get pod -n backend -l app=backend -o jsonpath='{.items[0].status.podIP}')
echo "Backend Pod IP: $BACKEND_POD_IP"

# Test direct pod-to-pod communication (bypassing service)
kubectl exec -n frontend deployment/frontend-deployment -- curl -s -o /dev/null -w "%{http_code}\n" http://$BACKEND_POD_IP:8081

# Expected: 200 (success)
# This proves:
# - Pods can communicate directly without services
# - NetworkPolicies would apply here too (they protect pods, not services)
# - Service is just a convenience layer, not a security boundary
```

**Test 3: Backend → Frontend Service:**

```bash
# Test if backend can reach frontend (via service)
kubectl exec -n backend deployment/backend-deployment -- curl -s -o /dev/null -w "%{http_code}\n" http://frontend-service.frontend:9090

# Expected: 200 (success)
# Shows bi-directional communication is allowed by default
# Service routes to frontend pod, NetworkPolicy would be evaluated at pod level
```

**Test 4: Backend → Frontend Pod (direct IP):**

```bash
# Get frontend pod IP
FRONTEND_POD_IP=$(kubectl get pod -n frontend -l app=frontend -o jsonpath='{.items[0].status.podIP}')
echo "Frontend Pod IP: $FRONTEND_POD_IP"

# Test direct pod-to-pod communication
kubectl exec -n backend deployment/backend-deployment -- curl -s -o /dev/null -w "%{http_code}\n" http://$FRONTEND_POD_IP:8080

# Expected: 200 (success)
# Confirms pods can always reach each other directly
```

**Key Insight:**

```plaintext
Service vs Pod Communication:
==============================

Via Service:
  frontend-pod → [DNS] → backend-service (ClusterIP) → backend-pod
                                                        → NetworkPolicy evaluated here

Direct to Pod:
  frontend-pod → backend-pod-ip
                 → NetworkPolicy evaluated here

Result: NetworkPolicies protect pods regardless of how you connect (service or direct)
```

---

### Step 5: Document Baseline Security Posture

**Create documentation of current state:**

```plaintext
Baseline Network Security Analysis:
====================================

Test Results (all should return 200):
✓ Frontend → Backend Service: ALLOWED
✓ Frontend → Backend Pod IP: ALLOWED
✓ Backend → Frontend Service: ALLOWED
✓ Backend → Frontend Pod IP: ALLOWED

Current Security Posture:
- No network segmentation between namespaces
- Bi-directional communication allowed
- No restrictions on network traffic

Security Risks:
1. Compromised frontend pod can directly access backend pods
2. Backend can initiate connections to frontend (unnecessary)
3. No defense-in-depth at network layer
4. Cannot enforce API-level security policies
5. Lateral movement possible across namespace boundaries

Compliance Status:
✗ Does not meet zero-trust requirements
✗ Violates principle of least privilege
✗ No audit trail for network access
```

**Understanding the Default Behavior:**

```plaintext
Kubernetes Default Network Model:
==================================

WITHOUT NetworkPolicies:
- All pods can communicate with all pods
- All pods can communicate with all services
- Across all namespaces
- No restrictions whatsoever

This is called "flat networking" and is the default for:
- Simplicity during development
- Ease of initial setup
- Backward compatibility

However, in production this creates significant security risks.
NetworkPolicies change this default behavior.
```

---

## Phase 2: Understanding Network Policy Isolation (15-20 minutes)

### Step 1: Apply First NetworkPolicy to Backend

**Create initial backend NetworkPolicy (deny all ingress):**

```yaml
# manifests/backend-isolation.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-isolation
  namespace: backend
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  # Empty ingress rules means: deny all ingress traffic
  # This is the key to understanding automatic isolation
```

**Apply the policy:**

```bash
# Apply the NetworkPolicy
kubectl apply -f manifests/backend/networkpolicy.yaml

# Verify NetworkPolicy created
kubectl get networkpolicy -n backend

# Describe the policy to see details
kubectl describe networkpolicy backend-isolation -n backend
```

**Expected output from describe:**

```plaintext
Name:         backend-isolation
Namespace:    backend
Created on:   <timestamp>
Labels:       <none>
Annotations:  <none>
Spec:
  PodSelector:     app=backend
  Allowing ingress traffic:
    <none> (Selected pods are isolated for ingress connectivity)
  Not affecting egress traffic
  Policy Types: Ingress
```

**Key observation:** "Selected pods are isolated for ingress connectivity" - this is automatic isolation!

---

### Step 2: Observe Automatic Isolation

**Test that backend is now isolated:**

```bash
# Test 1: Frontend → Backend Service (should FAIL now)
echo "Testing frontend → backend service..."
kubectl exec -n frontend deployment/frontend-deployment -- curl -s -o /dev/null -w "%{http_code}\n" --max-time 5 http://backend-service.backend:9091 || echo "Connection failed (expected)"

# Expected: Connection timeout or failure
# The NetworkPolicy has isolated backend pods

# Test 2: Frontend → Backend Pod IP (should also FAIL)
echo "Testing frontend → backend pod IP..."
BACKEND_POD_IP=$(kubectl get pod -n backend -l app=backend -o jsonpath='{.items[0].status.podIP}')
kubectl exec -n frontend deployment/frontend-deployment -- curl -s -o /dev/null -w "%{http_code}\n" --max-time 5 http://$BACKEND_POD_IP:8081 || echo "Connection failed (expected)"

# Expected: Connection timeout or failure
```

**Test that egress still works from backend:**

```bash
# Backend can still make outbound connections (egress not restricted)
echo "Testing backend → frontend service (egress)..."
kubectl exec -n backend deployment/backend-deployment -- curl -s -o /dev/null -w "%{http_code}\n" --max-time 5 http://frontend-service.frontend:9090

# Expected: 200 (success)
# Egress is not restricted because policyTypes only includes Ingress
```

---

### Step 3: Understand What Happened

**The Automatic Isolation Mechanism:**

```plaintext
How NetworkPolicy Isolation Works:
===================================

BEFORE any NetworkPolicy exists:
- Default behavior: Allow all traffic
- Pods are in "non-isolated" mode
- No restrictions on ingress or egress

AFTER first NetworkPolicy applied:
- Pods matching podSelector enter "isolated" mode
- For policy types specified (Ingress/Egress):
  - Default changes from "allow all" to "deny all"
  - Must explicitly define allowed traffic

Our backend-isolation policy:
  podSelector:
    matchLabels:
      app: backend
→ Selects pods with label app=backend

  policyTypes:
  - Ingress
→ Controls ingress (incoming) traffic only

  ingress: []
→ Empty list = deny all ingress

Result:
âœ— All ingress traffic to backend pods: BLOCKED
✓ Egress traffic from backend pods: Still ALLOWED (not in policyTypes)

This is NOT an explicit "deny" rule - it's automatic isolation!
```

**Visual representation:**

```plaintext
Before NetworkPolicy:
┌──────────────────────────────────────┐
│  Frontend Pod                        │
│       │                              │
│       │ ✓ HTTP allowed               │
│       ↓                              │
│  Backend Pod (non-isolated)          │
└──────────────────────────────────────┘

After NetworkPolicy Applied:
┌──────────────────────────────────────┐
│  Frontend Pod                        │
│       │                              │
│       │ ✗ HTTP blocked               │
│       ↓                              │
│  Backend Pod (ISOLATED)              │
│  └─ NetworkPolicy applied            │
└──────────────────────────────────────┘
```

---

### Step 4: Document the Isolation

**Current state documentation:**

```plaintext
Post-NetworkPolicy Status:
==========================

Backend Namespace:
✓ NetworkPolicy "backend-isolation" applied
✓ Backend pods are now ISOLATED for ingress
✗ All incoming traffic blocked
✓ Outgoing traffic still allowed

Test Results:
✗ Frontend → Backend Service: BLOCKED (timeout)
✗ Frontend → Backend Pod IP: BLOCKED (timeout)
✓ Backend → Frontend Service: ALLOWED (egress works)

Application Status:
✗ Application is broken (frontend cannot reach backend)
✓ This is expected and intentional
✓ Foundation for zero-trust networking established

Next Step:
- Selectively allow only required traffic
- Maintain security boundaries
- Restore application functionality
```

**Understanding the foundation:**

```plaintext
Why Start with "Deny All"?
===========================

Security Philosophy: Zero-Trust Networking
1. Deny everything by default
2. Explicitly allow only what's needed
3. Easier to audit what IS allowed
4. Prevents accidental exposure
5. Industry best practice for security

Alternative Approach (NOT recommended):
- Start with "allow all"
- Try to block specific traffic
- Hard to ensure everything is blocked
- Risk of forgotten exceptions
- Security by obscurity

Zero-Trust Approach (Recommended):
- Start with "deny all" (automatic isolation)
- Explicitly allow needed traffic
- Security by design
- Clear audit trail
- Compliance-friendly
```

---

## Phase 3: Allow Required Traffic (20-25 minutes)

### Step 1: Allow Frontend → Backend Communication

**Update backend NetworkPolicy to allow frontend:**

```yaml
# manifests/backend-allow-frontend.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-allow-frontend
  namespace: backend
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: frontend
    ports:
    - protocol: TCP
      port: 8081
```

**Apply the updated policy:**

```bash
# Apply the policy
kubectl apply -f manifests/backend/networkpolicy-allow-frontend.yaml

# Verify policy applied
kubectl get networkpolicy -n backend
kubectl describe networkpolicy backend-allow-frontend -n backend
```

**Test connectivity restored:**

```bash
# Test frontend → backend service
echo "Testing frontend → backend service..."
kubectl exec -n frontend deployment/frontend-deployment -- curl -s -o /dev/null -w "%{http_code}\n" http://backend-service.backend:9091

# Expected: 200 (success)
# Communication restored!

# Test frontend → backend pod IP
echo "Testing frontend → backend pod IP..."
BACKEND_POD_IP=$(kubectl get pod -n backend -l app=backend -o jsonpath='{.items[0].status.podIP}')
kubectl exec -n frontend deployment/frontend-deployment -- curl -s -o /dev/null -w "%{http_code}\n" http://$BACKEND_POD_IP:8081

# Expected: 200 (success)
# Direct pod access also works (same namespace selector)
```

---

### Step 2: Understanding the Policy

**Policy breakdown:**

```yaml
spec:
  podSelector:
    matchLabels:
      app: backend
```

**Meaning:** This policy applies to pods with label `app=backend` in the `backend` namespace

```yaml
  policyTypes:
  - Ingress
```

**Meaning:** This policy controls incoming traffic (ingress) only

```yaml
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: frontend
```

**Meaning:** Allow ingress from any pod in the frontend namespace (using built-in label)

```yaml
    ports:
    - protocol: TCP
      port: 8081
```

**Complete interpretation:**

```plaintext
NetworkPolicy Translation:
==========================

This policy says:
"For pods labeled app=backend in the backend namespace,
allow incoming TCP traffic on port 8081 from any pod
in the frontend namespace (using built-in kubernetes.io/metadata.name label)"

CRITICAL - Port Specification:
================================
The port (8081) refers to the backend pod's containerPort.

Example if ports were different:
  Service:      port: 9091 → targetPort: 8081
  Pod:          containerPort: 8081
  NetworkPolicy: port: 8081 (matches pod, not service)

Why namespaceSelector?
- Allows entire namespace to access backend pods
- All frontend pods can reach backend pods
- Scalable: new frontend pods automatically allowed
- Clear boundary: frontend namespace vs others

Alternative (more granular):
podSelector:
  matchLabels:
    app: frontend-web
→ Only specific pods, not entire namespace
→ More granular but harder to manage at scale
→ Still refers to source pods, not services

```

---

### Step 3: Handle DNS Resolution

**Why DNS is needed:**

When we test with `http://backend-service.backend:9091`, the frontend pod must:

1. Resolve `backend-service.backend` to an IP address (DNS query to CoreDNS)
2. Connect to that IP address

Without DNS resolution, service names don't work (only IPs would work).

**Check if DNS works:**

```bash
# Test DNS resolution from frontend
kubectl exec -n frontend deployment/frontend-deployment -- nslookup backend-service.backend

# If this fails, we need egress policy for DNS
```

**Create DNS egress policies:**

```yaml
# manifests/frontend-allow-dns.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: frontend-allow-dns
  namespace: frontend
spec:
  podSelector: {}  # Applies to all pods in frontend namespace
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - protocol: UDP
      port: 53
---
# manifests/backend-allow-dns.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-allow-dns
  namespace: backend
spec:
  podSelector: {}  # Applies to all pods in backend namespace
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - protocol: UDP
      port: 53
```

**Apply DNS policies:**

```bash
# Apply DNS egress policies
kubectl apply -f manifests/frontend/networkpolicy-allow-dns.yaml
kubectl apply -f manifests/backend/networkpolicy-allow-dns.yaml

# Verify policies created
kubectl get networkpolicy -n frontend
kubectl get networkpolicy -n backend

# Test DNS resolution
kubectl exec -n frontend deployment/frontend-deployment -- nslookup backend-service.backend
kubectl exec -n backend deployment/backend-deployment -- nslookup frontend-service.frontend

# Expected: DNS resolution works
```

**Understanding DNS policy:**

```plaintext
DNS NetworkPolicy Explained:
============================

Why needed?
- CoreDNS runs in kube-system namespace
- DNS queries go to port 53 UDP
- Without egress policy, isolated pods can't resolve names

Policy breakdown:
  podSelector: {}
→ Applies to ALL pods in the namespace

  policyTypes:
  - Egress
→ Controls outgoing traffic

  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
→ Allow egress to kube-system namespace (where CoreDNS is)

    ports:
    - protocol: UDP
      port: 53
→ Only allow DNS port (53 UDP)

Result: Pods can resolve service names via DNS
```

---

### Step 4: Allow Backend Egress to Frontend (Complete the Connection)

**Current state:**

- Frontend can reach backend ✓
- Backend needs to send responses back to frontend

**Wait - responses are already allowed!**

Kubernetes NetworkPolicies are stateful:

- When frontend initiates connection to backend
- Backend's response traffic is automatically allowed
- Don't need separate policy for response traffic

**However, if you want backend to INITIATE connections to frontend:**

```yaml
# manifests/backend-allow-egress-frontend.yaml (optional)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-allow-egress-frontend
  namespace: backend
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: frontend
    ports:
    - protocol: TCP
      port: 8080
  - to:  # Keep DNS working
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - protocol: UDP
      port: 53
```

**Note:** In our scenario, backend doesn't need to initiate connections to frontend, so this is optional.

---

### Step 5: Optional - Isolate Frontend Namespace

**Create comprehensive frontend isolation:**

```yaml
# manifests/frontend-isolation.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: frontend-isolation
  namespace: frontend
spec:
  podSelector:
    matchLabels:
      app: frontend
  policyTypes:
  - Ingress
  - Egress
  ingress:
  # Allow from ingress controller (if using Ingress resources)
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: ingress-nginx
    ports:
    - protocol: TCP
      port: 8080
  egress:
  # Allow to backend
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: backend
    ports:
    - protocol: TCP
      port: 8081
  # Allow DNS
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - protocol: UDP
      port: 53
```

**Apply frontend isolation:**

```bash
# Apply frontend NetworkPolicy
kubectl apply -f manifests/frontend/networkpolicy-allow-backend.yaml

# Verify policy
kubectl get networkpolicy -n frontend
kubectl describe networkpolicy frontend-isolation -n frontend

# Test that everything still works
kubectl exec -n frontend deployment/frontend-deployment -- curl -s -o /dev/null -w "%{http_code}\n" http://backend-service.backend:9091

# Expected: 200
```

**Test that backend cannot reach frontend:**

```bash
# This should now fail (if backend doesn't have frontend ingress policy)
kubectl exec -n backend deployment/backend-deployment -- curl -s -o /dev/null -w "%{http_code}\n" --max-time 5 http://frontend-service.frontend:9090 || echo "Connection blocked (expected)"

# Expected: Timeout/failure
# Backend is not allowed to initiate connections to frontend
```

---

### Step 6: Review All Policies

**List all NetworkPolicies:**

```bash
# View all policies
kubectl get networkpolicy -A

# Expected output:
# NAMESPACE   NAME                          POD-SELECTOR   AGE
# frontend    frontend-allow-dns            <none>         Xm
# frontend    frontend-isolation            app=frontend   Xm
# backend     backend-allow-frontend        app=backend    Xm
# backend     backend-allow-dns             <none>         Xm
```

**Current architecture:**

```plaintext
Network Policy Architecture:
============================

Frontend Namespace:
├─ frontend-allow-dns
│  └─ Allows DNS egress to kube-system
└─ frontend-isolation
   ├─ Ingress: From ingress-nginx namespace
   └─ Egress: To backend namespace + DNS

Backend Namespace:
├─ backend-allow-dns
│  └─ Allows DNS egress to kube-system
└─ backend-allow-frontend
   ├─ Ingress: From frontend namespace on port 8081
   └─ Egress: Not restricted (default allow)

Traffic Flows:
✓ Ingress Controller → Frontend (port 8080)
✓ Frontend → Backend (port 8081)
✓ Frontend → DNS (port 53 UDP)
✓ Backend → DNS (port 53 UDP)
✗ Backend → Frontend (blocked if frontend isolated)
✗ Any other cross-namespace traffic
```

---

## Phase 4: Validation and Troubleshooting (10-15 minutes)

### Step 1: Comprehensive Security Testing

```bash
echo "Test 1: Frontend → Backend Service"
kubectl exec -n frontend deployment/frontend-deployment -- curl -s -o /dev/null -w "%{http_code}\n" http://backend-service.backend:9091
echo "Expected: 200 ✓"
echo

echo "Test 2: Frontend → Backend Pod IP"
BACKEND_POD_IP=$(kubectl get pod -n backend -l app=backend -o jsonpath='{.items[0].status.podIP}')
kubectl exec -n frontend deployment/frontend-deployment -- curl -s -o /dev/null -w "%{http_code}\n" http://$BACKEND_POD_IP:8081
echo "Expected: 200 ✓"
echo

echo "Test 3: Backend → Frontend (should fail if frontend isolated)"
kubectl exec -n backend deployment/backend-deployment -- curl -s -o /dev/null -w "%{http_code}\n" --max-time 5 http://frontend-service.frontend:9090 || echo "Blocked ✓"
echo "Expected: Blocked or timeout ✓"
echo

echo "Test 4: DNS Resolution from Frontend"
kubectl exec -n frontend deployment/frontend-deployment -- nslookup backend-service.backend > /dev/null 2>&1 && echo "DNS works ✓" || echo "DNS failed ✗"
echo

echo "Test 5: DNS Resolution from Backend"
kubectl exec -n backend deployment/backend-deployment -- nslookup frontend-service.frontend > /dev/null 2>&1 && echo "DNS works ✓" || echo "DNS failed ✗"
echo

echo "=== Tests Complete ==="
```

**Expected results:**

```plaintext
=== Network Policy Validation ===

Test 1: Frontend → Backend Service
200
Expected: 200 ✓

Test 2: Frontend → Backend Pod IP
200
Expected: 200 ✓

Test 3: Backend → Frontend (should fail if frontend isolated)
Blocked ✓
Expected: Blocked or timeout ✓

Test 4: DNS Resolution from Frontend
DNS works ✓

Test 5: DNS Resolution from Backend
DNS works ✓

=== Tests Complete ===
```

---

### Step 2: Troubleshooting Exercise

**Intentionally break a policy:**

```bash
# Edit backend-allow-frontend policy to use wrong port
kubectl get networkpolicy backend-allow-frontend -n backend -o yaml > manifests/broken-policy.yaml

# Edit the file and change port from 8081 to 9999
# Then apply
kubectl apply -f manifests/broken-policy.yaml
```

**Observe the failure:**

```bash
# Test connection - should fail now
kubectl exec -n frontend deployment/frontend-deployment -- curl -s -o /dev/null -w "%{http_code}\n" --max-time 5 http://backend-service.backend:9091 || echo "Connection failed"

# Expected: Timeout or connection refused
```

**Debug systematically:**

```bash
# Step 1: Check if NetworkPolicy exists
kubectl get networkpolicy -n backend

# Step 2: Describe the policy
kubectl describe networkpolicy backend-allow-frontend -n backend

# Look for:
# Spec:
#   ...
#   Allowing ingress traffic:
#     To Port: 9999/TCP  <-- WRONG! Should be 8081
#   ...

# Step 3: Check pod labels match
kubectl get pods -n backend --show-labels
# Should show: app=backend

# Step 4: Check namespace labels match
kubectl get namespace frontend --show-labels
# Should show: name=frontend

# Step 5: Identify the issue
echo "Port mismatch: Policy allows 9999, but service uses 8081"
```

**Fix the policy:**

```bash
# Reapply correct policy
kubectl apply -f manifests/backend-allow-frontend.yaml

# Verify fix
kubectl exec -n frontend deployment/frontend-deployment -- curl -s -o /dev/null -w "%{http_code}\n" http://backend-service.backend:9091

# Expected: 200 (works again)
```

**Debugging methodology summary:**

```plaintext
NetworkPolicy Debugging Checklist:
===================================

1. Does the NetworkPolicy exist?
   kubectl get networkpolicy -n <namespace>

2. What does the policy actually say?
   kubectl describe networkpolicy <name> -n <namespace>

3. Do pod labels match podSelector?
   kubectl get pods -n <namespace> --show-labels
   Compare with policy's podSelector

4. Do namespace labels match namespaceSelector?
   kubectl get namespace <namespace> --show-labels
   Compare with policy's namespaceSelector

5. Are ports and protocols correct?
   Check port numbers match service/pod ports
   Check protocol (TCP vs UDP)

6. Are multiple policies combining correctly?
   kubectl get networkpolicy -n <namespace>
   Policies are additive (allow rules combine)

7. Is CNI configured to support NetworkPolicies?
   kubectl get pods -n kube-system
   Look for network policy enforcement components
```

---

### Step 3: Document Security Architecture

**Create comprehensive documentation:**

```plaintext
Final Network Security Architecture:
====================================

Namespaces:
-----------
frontend (label: name=frontend)
  - frontend-deployment (label: app=frontend)
  - frontend-service (ClusterIP on port 8080)

backend (label: name=backend)
  - backend-deployment (label: app=backend)
  - backend-service (ClusterIP on port 8081)

NetworkPolicies:
----------------
Frontend Namespace:
1. frontend-allow-dns
   - Type: Egress
   - Allows: DNS queries to kube-system (port 53 UDP)
   - Applies to: All pods in frontend namespace

2. frontend-isolation (optional)
   - Type: Ingress + Egress
   - Ingress allows: From ingress-nginx namespace on port 8080
   - Egress allows: To backend namespace on port 8081, DNS
   - Applies to: Pods with app=frontend label

Backend Namespace:
1. backend-allow-dns
   - Type: Egress
   - Allows: DNS queries to kube-system (port 53 UDP)
   - Applies to: All pods in backend namespace

2. backend-allow-frontend
   - Type: Ingress
   - Ingress allows: From frontend namespace on port 8081
   - Applies to: Pods with app=backend label

Allowed Traffic Flows:
----------------------
✓ User → Ingress Controller → Frontend (port 8080)
✓ Frontend → Backend Service (port 8081)
✓ Frontend → DNS (port 53 UDP)
✓ Backend → DNS (port 53 UDP)
✓ Backend → Response to Frontend (stateful - automatic)

Blocked Traffic Flows:
----------------------
✗ Backend → Frontend (initiate new connections)
✗ Any namespace → Backend (except frontend)
✗ Any namespace → Frontend (except ingress-nginx)
✗ Frontend → Any external IPs (not explicitly allowed)
✗ Backend → Any external IPs (not explicitly allowed)

Security Improvements:
----------------------
Before NetworkPolicies:
- Open communication between all pods
- No segmentation
- Lateral movement possible
- No compliance

After NetworkPolicies:
✓ Zero-trust networking implemented
✓ Namespace isolation enforced
✓ Least privilege access (only required traffic allowed)
✓ Defense in depth (network + RBAC + Pod Security)
✓ Compliance-ready (PCI-DSS, HIPAA compatible)
✓ Audit trail (policies define allowed traffic)
✓ Blast radius limited (compromised pod can't move laterally)

Compliance Mapping:
-------------------
- PCI-DSS Requirement 1.2: Network segmentation ✓
- PCI-DSS Requirement 1.3: Restrict traffic between segments ✓
- HIPAA §164.312(e)(1): Network transmission security ✓
- ISO 27001 A.13.1: Network security management ✓
```

---

### Step 4: Visual Network Diagram

**Before NetworkPolicies:**

```plaintext
┌─────────────────────────────────────────────────────────────┐
│  Kubernetes Cluster (Default - No NetworkPolicies)         │
│                                                             │
│  ┌──────────────────────────┐  ┌──────────────────────────┐│
│  │ Frontend Namespace       │  │ Backend Namespace        ││
│  │                          │  │                          ││
│  │  ┌────────────────────┐  │  │  ┌────────────────────┐ ││
│  │  │  frontend-pod      │◄─┼──┼──│  backend-pod       │ ││
│  │  │  (port 8080)       │  │  │  │  (port 8081)       │ ││
│  │  └────────────────────┘  │  │  └────────────────────┘ ││
│  │           │              │  │           │             ││
│  │           ↓              │  │           ↓             ││
│  │  frontend-service ──────────────► backend-service    ││
│  │  (routes to pod)         │  │  (routes to pod)        ││
│  │                          │  │                          ││
│  └──────────────────────────┘  └──────────────────────────┘│
│                                                             │
│  Key Points:                                                │
│  • All pods can reach all other pods directly              │
│  • Services provide DNS and load balancing only            │
│  • No network-level security or segmentation               │
│                                                             │
│  Security: ✗ No restrictions, all traffic allowed          │
│  Risk: High - Lateral movement possible                    │
└─────────────────────────────────────────────────────────────┘
```

**After NetworkPolicies:**

```plaintext
┌─────────────────────────────────────────────────────────────┐
│  Kubernetes Cluster (With NetworkPolicies)                 │
│                                                             │
│  ┌──────────────────────────┐  ┌──────────────────────────┐│
│  │ Frontend Namespace       │  │ Backend Namespace        ││
│  │ (name=frontend)          │  │ (name=backend)           ││
│  │                          │  │                          ││
│  │  ┌────────────────────┐  │  │  ┌────────────────────┐ ││
│  │  │  frontend-pod      │──┼──┼─►│  backend-pod       │ ││
│  │  │  [ISOLATED]        │✓│  │  │  [ISOLATED]        │ ││
│  │  │  port 8080         │  │  │  │  port 8081         │ ││
│  │  │  (NetworkPolicy    │  │  │  │  (NetworkPolicy    │ ││
│  │  │   protects this)   │  │  │  │   protects this)   │ ││
│  │  └────────────────────┘  │  │  └────────────────────┘ ││
│  │           ║              │  │           ║             ││
│  │           ║ blocked      │  │           â•' blocked    ││
│  │           ◄══════════════┼──┼═══════════╝             ││
│  │           │              │  │           │             ││
│  │  frontend-service        │  │  backend-service        ││
│  │  (DNS/routing only)      │  │  (DNS/routing only)     ││
│  │                          │  │                          ││
│  │  NetworkPolicy:          │  │  NetworkPolicy:          ││
│  │  Ingress: ingress-nginx  │  │  Ingress: frontend ns    ││
│  │  Egress: backend ns,DNS  │  │  Egress: DNS             ││
│  └──────────────────────────┘  └──────────────────────────┘│
│                                                             │
│  Key Points:                                                │
│  • NetworkPolicies protect PODS (not services)              │
│  • Services still provide DNS/routing (unchanged)           │
│  • Policy evaluated when traffic reaches pod                │
│  • Port in policy = pod's containerPort                     │
│                                                             │
│  Security: ✓ Namespace isolation, least privilege         │
│  Risk: Low - Lateral movement prevented at pod level       │
└─────────────────────────────────────────────────────────────┘
```

**Traffic Flow with Services and NetworkPolicies:**

```plaintext
How Traffic Flows with NetworkPolicies:
========================================

Step-by-Step Example: Frontend calls Backend

1. Frontend pod initiates connection to backend-service.backend:9091
   └─ frontend-pod (10.42.1.5) → DNS query for backend-service.backend

2. DNS (CoreDNS) resolves to service ClusterIP
   └─ backend-service.backend → 10.43.0.10 (ClusterIP)

3. Service selects backend pod using label selector (app=backend)
   └─ Service chooses backend-pod-xyz (10.42.2.8)

4. Service performs NAT and forwards to backend pod
   └─ Connection: frontend-pod (10.42.1.5) → backend-pod (10.42.2.8:8081)

5. **NetworkPolicy evaluated HERE** (at backend pod)
   └─ Check: Is source pod from namespace with label name=frontend?
   └─ Check: Is destination port 8081?
   └─ Result: ALLOW (both conditions met)

6. Traffic reaches backend pod
   └─ Backend pod processes request

7. Response flows back (stateful - automatically allowed)
   └─ backend-pod → frontend-pod

CRITICAL:
- Service operates at steps 2-4 (DNS, load balancing, routing)
- NetworkPolicy operates at step 5 (pod-level protection)
- They are independent mechanisms working together
```

---

## Troubleshooting Common Issues

### Issue 1: Connection Timeouts After Applying Policy

**Symptoms:**

```bash
kubectl exec -n frontend deployment/frontend-deployment -- curl http://backend-service.backend:9091
# Hangs and times out
```

**Diagnosis:**

```bash
# Check if NetworkPolicy exists and is correct
kubectl get networkpolicy -n backend
kubectl describe networkpolicy backend-allow-frontend -n backend

# Check the Allowing ingress traffic section
# Should show: from namespaceSelector with name=frontend
```

**Common Causes:**

1. **Wrong namespace label:**

   ```bash
   # Check namespace label
   kubectl get namespace frontend --show-labels
   # Should have: name=frontend

   # If missing, add it:
   kubectl label namespace frontend name=frontend
   ```

2. **Wrong pod label:**

   ```bash
   # Check pod labels
   kubectl get pods -n backend --show-labels
   # Should have: app=backend

   # Check policy's podSelector matches
   kubectl get networkpolicy backend-allow-frontend -n backend -o yaml | grep -A 2 podSelector
   ```

3. **Wrong port number:**

   ```bash
   # Check service port
   kubectl get svc backend-service -n backend
   # Note the port (should be 8081)

   # Check policy allows this port
   kubectl describe networkpolicy backend-allow-frontend -n backend | grep Port
   # Should show: 8081/TCP
   ```

**Solution:**

- Fix labels, port numbers, or selectors as needed
- Reapply corrected policy

---

### Issue 2: DNS Resolution Fails

**Symptoms:**

```bash
kubectl exec -n frontend deployment/frontend-deployment -- nslookup backend-service.backend
# Error: server can't find backend-service.backend
```

**Diagnosis:**

```bash
# Check if DNS egress policy exists
kubectl get networkpolicy -n frontend | grep dns

# If missing or if policy exists but doesn't work:
kubectl describe networkpolicy frontend-allow-dns -n frontend
```

**Common Causes:**

1. **No DNS egress policy:**

   ```bash
   # Need to create DNS egress policy
   ```

2. **Wrong kube-system namespace selector:**

   ```bash
   # Check if kube-system has the right label
   kubectl get namespace kube-system --show-labels
   # Should have: kubernetes.io/metadata.name=kube-system
   ```

3. **Wrong protocol (TCP instead of UDP):**

   ```bash
   # DNS uses UDP port 53, not TCP
   # Check policy allows UDP
   kubectl describe networkpolicy frontend-allow-dns -n frontend | grep -A 2 ports
   # Should show: 53/UDP
   ```

**Solution:**

- Apply correct DNS egress policy
- Ensure protocol is UDP port 53
- Target kube-system namespace correctly

---

### Issue 3: Policy Not Taking Effect

**Symptoms:**

- Applied NetworkPolicy but traffic still works when it shouldn't
- Or traffic blocked when policy should allow it

**Diagnosis:**

```bash
# Check CNI supports NetworkPolicies
kubectl get pods -n kube-system

# For k3s, look for components like:
# - canal, calico, or kube-router pods
# These provide network policy enforcement

# Check policy was actually created
kubectl get networkpolicy -A

# Describe the specific policy
kubectl describe networkpolicy <name> -n <namespace>
```

**Common Causes:**

1. **CNI doesn't support NetworkPolicies:**
   - Some CNIs don't support NetworkPolicy (e.g., Flannel without Canal)
   - k3s default includes support

2. **Policy in wrong namespace:**

   ```bash
   # NetworkPolicies are namespaced resources
   # Must be in same namespace as pods they select
   kubectl get networkpolicy -A  # Check all namespaces
   ```

3. **Selector doesn't match any pods:**

   ```bash
   # Check pod labels
   kubectl get pods -n <namespace> --show-labels

   # Compare with policy's podSelector
   kubectl get networkpolicy <name> -n <namespace> -o yaml
   ```

**Solution:**

- Verify CNI supports NetworkPolicies
- Ensure policy is in correct namespace
- Fix selector labels to match pods

---

### Issue 4: Multiple Policies Causing Confusion

**Symptoms:**

- Not sure which policy is affecting traffic
- Unexpected allow/deny behavior

**Diagnosis:**

```bash
# List all policies affecting a namespace
kubectl get networkpolicy -n <namespace>

# Describe each one
for policy in $(kubectl get networkpolicy -n backend -o name); do
  echo "=== $policy ==="
  kubectl describe $policy -n backend
  echo
done
```

**Understanding Policy Combination:**

```plaintext
How Multiple Policies Combine:
===============================

NetworkPolicies are ADDITIVE:
- If pod is selected by multiple policies
- Allow rules from ALL policies are combined (OR logic)
- If ANY policy allows traffic, it's allowed
- There are NO deny rules (only absence of allow)

Example:
Policy 1: Allow from namespace A
Policy 2: Allow from namespace B
Result: Traffic from A OR B is allowed

This is different from firewall rules which often have deny rules.
```

**Solution:**

- Review all policies selecting the same pods
- Understand they combine with OR logic
- Remove unnecessary policies if they conflict
- Use more specific selectors if needed

---

### Issue 5: Testing with Wrong Tools

**Symptoms:**

- `ping` doesn't work but `curl` does
- Confusion about what's blocked vs allowed

**Understanding:**

```plaintext
NetworkPolicy and ICMP (Ping):
===============================

NetworkPolicies control Layer 4 (TCP/UDP):
✓ HTTP/HTTPS (TCP)
✓ DNS (UDP)
✓ Most application protocols

NetworkPolicies do NOT explicitly control ICMP:
✗ Ping uses ICMP, not TCP/UDP
✗ Different CNIs handle ICMP differently
✗ Don't use ping to test NetworkPolicies

Correct Testing Tools:
✓ curl (HTTP/HTTPS)
✓ nc (netcat) for TCP/UDP
✓ nslookup/dig for DNS
✓ Application-specific clients
```

**Solution:**

- Use curl for HTTP testing
- Use nc for TCP/UDP port testing
- Use nslookup for DNS testing
- Don't rely on ping

---

### Issue 6: Service Port vs Pod Port Confusion

**Symptoms:**

- NetworkPolicy looks correct but traffic is blocked
- Used service port instead of pod port in NetworkPolicy

**Example of the problem:**

```yaml
# Service definition
apiVersion: v1
kind: Service
metadata:
  name: backend-service
spec:
  ports:
  - port: 80          # Service listens on port 80
    targetPort: 8081  # Routes to pod port 8081

# Pod definition
spec:
  containers:
  - name: backend
    ports:
    - containerPort: 8081  # Pod listens on 8081

# WRONG NetworkPolicy (using service port)
spec:
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: frontend
    ports:
    - protocol: TCP
      port: 80        # ✗ WRONG! This is the service port

# CORRECT NetworkPolicy (using pod port)
spec:
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: frontend
    ports:
    - protocol: TCP
      port: 8081      # ✓ CORRECT! This is the pod port
```

**Diagnosis:**

```bash
# Check service configuration
kubectl get svc backend-service -n backend -o yaml | grep -A 5 ports

# Output shows:
# ports:
# - port: 80         <-- Service port
#   targetPort: 8081 <-- Pod port

# Check pod configuration
kubectl get pod -n backend -o yaml | grep containerPort

# Output shows:
# - containerPort: 8081  <-- This is what NetworkPolicy needs!

# Check NetworkPolicy
kubectl describe networkpolicy backend-allow-frontend -n backend | grep Port

# Should show: 8081/TCP (matching pod port, not service port)
```

**Why this happens:**

```plaintext
Common Misconception:
=====================

"I access the service on port 80, so my NetworkPolicy should use port 80"

Reality:
========

Service (port 80) → Routes to → Pod (port 8081)
                                 → NetworkPolicy evaluated HERE

The NetworkPolicy protects the pod, not the service.
Therefore, use the pod's containerPort, not the service port.

In our lab: Service port = Pod port = 8081 (no confusion)
In production: Service port often differs from pod port (e.g., 80 → 8080)
```

**Solution:**

- Always check pod's containerPort
- Use containerPort in NetworkPolicy, not service port
- Remember: NetworkPolicies protect pods, not services

---

## Architecture Comparison Table

| Aspect | Before NetworkPolicies | After NetworkPolicies |
|--------|------------------------|----------------------|
| **Default Behavior** | Allow all traffic | Deny all (when policy applied) |
| **Frontend → Backend** | ✓ Allowed (any pod, any port) | ✓ Allowed (port 8081 only) |
| **Backend → Frontend** | ✓ Allowed (any pod, any port) | ✗ Blocked |
| **Cross-Namespace** | ✓ Unrestricted | ✗ Blocked by default, ✓ Allowed explicitly |
| **DNS Resolution** | ✓ Works | ✓ Works (requires egress policy) |
| **What Policies Protect** | N/A | Pods (using labels), not services |
| **Port in Policy** | N/A | Pod's containerPort (not service port) |
| **Security Posture** | ✗ Flat network, no segmentation | ✓ Zero-trust, least privilege |
| **Lateral Movement** | ✓ Easy (any pod to any pod) | ✗ Prevented (isolated namespaces) |
| **Compliance** | ✗ Does not meet standards | ✓ Meets PCI-DSS, HIPAA, ISO 27001 |
| **Audit Trail** | ✗ No record of allowed traffic | ✓ Policies document allowed flows |
| **Blast Radius** | ✗ High (cluster-wide access) | ✓ Limited (namespace boundaries) |

---

## Production Readiness Checklist

### Network Security

- [ ] NetworkPolicies applied to all application namespaces
- [ ] Default deny implemented (automatic via first policy)
- [ ] Only required traffic explicitly allowed
- [ ] DNS resolution enabled where needed
- [ ] Port restrictions implemented
- [ ] Cross-namespace access documented and justified

### Documentation

- [ ] Network diagram created showing allowed flows
- [ ] All NetworkPolicies documented with purpose
- [ ] Troubleshooting runbook created
- [ ] Policy change procedures documented

### Testing

- [ ] All application traffic flows validated
- [ ] Negative testing performed (blocked traffic verified)
- [ ] DNS resolution tested from all namespaces
- [ ] Performance impact assessed
- [ ] Failure scenarios tested

### Operations

- [ ] Monitoring for policy violations configured
- [ ] Alerting on unexpected traffic patterns
- [ ] Policy review schedule established
- [ ] Break-glass procedures documented
- [ ] Team trained on NetworkPolicy concepts

---

## Cleanup

**Remove all lab resources:**

```bash
# Delete namespaces (includes all resources inside)
kubectl delete namespace frontend
kubectl delete namespace backend

# Verify cleanup
kubectl get namespaces
kubectl get networkpolicy -A

# All frontend and backend resources should be gone
```

---

## Learning Outcomes

### Technical Skills Acquired

- [x] Deploy applications across multiple namespaces
- [x] Understand Kubernetes default network model (allow all)
- [x] Apply NetworkPolicies to create automatic isolation
- [x] Configure ingress policies with namespace selectors
- [x] Configure egress policies for DNS resolution
- [x] Use podSelector and namespaceSelector effectively
- [x] Implement port-based traffic restrictions
- [x] **Understand NetworkPolicies target pods, not services**
- [x] **Use pod containerPort in policies, not service port**
- [x] Debug NetworkPolicy issues systematically
- [x] Test security boundaries comprehensively

### Conceptual Understanding

- [x] Automatic isolation mechanism when first policy applied
- [x] Difference between ingress and egress policies
- [x] How NetworkPolicies combine (additive/OR logic)
- [x] Zero-trust networking principles
- [x] Defense in depth through network segmentation
- [x] Stateful connection tracking in Kubernetes

### Production Patterns

- [x] Namespace-to-namespace traffic control
- [x] DNS resolution in isolated environments
- [x] Service-based communication patterns
- [x] Security boundary definition and validation
- [x] Troubleshooting methodology for network issues

---

## Next Steps: Complete Security Posture

**Module 9 Security Trilogy:**

1. **Network Policies** (This Lab) ✓
   - Controls: Who can talk to whom
   - Layer: Network (Layer 4)
   - Prevents: Lateral movement, unauthorized access

2. **Pod Security Standards** (Session 2)
   - Controls: What pods can do
   - Layer: Runtime security
   - Prevents: Privilege escalation, container breakout

3. **RBAC** (Session 3)
   - Controls: Who can do what with Kubernetes API
   - Layer: Authorization
   - Prevents: Unauthorized cluster operations

**Combined Defense in Depth:**

```plaintext
Complete Security Architecture:
================================

Network Layer (NetworkPolicies):
└─ Controls traffic between pods/namespaces
   └─ Prevents compromised pod from accessing others

Workload Layer (Pod Security Standards):
└─ Controls what pods can do at runtime
   └─ Prevents privilege escalation, container escapes

Access Layer (RBAC):
└─ Controls who can deploy/modify workloads
   └─ Prevents unauthorized cluster changes

Together: Defense in Depth
✓ Network segmentation
✓ Workload hardening
✓ Access control
✓ Compliance ready
✓ Production secure
```

**OpenShift Transition:**

NetworkPolicies in OpenShift:

- Same API and concepts
- OpenShift SDN or OVN-Kubernetes as CNI
- Additional EgressNetworkPolicy (OpenShift-specific)
- Multi-tenancy isolation by default (some SDN modes)
- Web console for policy visualization
- Integration with Projects (namespaces + RBAC)

Skills learned here transfer directly to OpenShift.

---

**Estimated Completion Time:** 60 minutes
**Learning Validation:** Students understand automatic isolation, can implement namespace-to-namespace policies, and can troubleshoot network connectivity issues in isolated environments.
