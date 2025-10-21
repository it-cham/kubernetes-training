# Lab Solution: Pod Security Standards & Container Hardening

## Overview

This comprehensive solution guides you through transforming an insecure TomEE application into a production-ready, hardened workload that meets enterprise security standards and runs successfully on both k3s and OpenShift.

> **Journey:** Insecure → Analyzed → Hardened → Validated → OpenShift-Ready

**Important:** Throughout this lab, you will progressively improve the same resources. Each phase builds upon the previous one by patching and updating the existing deployment rather than creating new resources.

---

## Phase 1: Security Analysis on k3s (15-20 minutes)

### Step 1: Deploy Insecure Application

**Create namespace:**

```bash
# Create dedicated namespace for security lab
kubectl create namespace sticky-session-secure

```

**Create initial deployment (insecure baseline):**

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: stickysessions-deployment
  namespace: sticky-session-secure
  labels:
    app: stickysessions
spec:
  replicas: 1
  selector:
    matchLabels:
      app: stickysessions
  template:
    metadata:
      labels:
        app: stickysessions
    spec:
      containers:
      - name: stickysessions
        image: registry.company.com/REPO/stickysessions:0.1
        ports:
        - containerPort: 8080
```

**Create service:**

```yaml
# service.yaml
apiVersion: v1
kind: Service
metadata:
  name: stickysessions-service
  namespace: sticky-session-secure
spec:
  type: ClusterIP
  sessionAffinity: ClientIP
  selector:
    app: stickysessions
  ports:
    - name: http
      port: 8080
      targetPort: 8080
      protocol: TCP
```

**Deploy:**

```bash
# Deploy application
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml

# Verify deployment
kubectl get pods -n sticky-session-secure
kubectl get svc -n sticky-session-secure
```

---

### Step 2: Analyze Security Posture

**Check running user:**

```bash
# Check which user the process runs as
kubectl exec -n sticky-session-secure deployment/stickysessions-deployment -- id

# Expected output: uid=0(root) gid=0(root) groups=0(root)...
```

**Examine filesystem permissions:**

```bash
# Check TomEE directory ownership
kubectl exec -n sticky-session-secure deployment/stickysessions-deployment -- ls -la /usr/local/tomee/
```

**Check capabilities:**

```bash
# View container security context (default)
kubectl get pod -n sticky-session-secure stickysessions-deployment-PLACEHOLDER -o jsonpath='{.spec.containers[0].securityContext}' | jq .

# Expected output: null or {} (no security context defined)
```

**Document findings:**

```plaintext
Security Analysis - Insecure Baseline:
=====================================
x Running as root (UID 0)
x Full filesystem write access
x No security context defined
x All capabilities available
x Privileged processes
x Can potentially access host resources
x Writable root filesystem

Risk Level: CRITICAL
```

---

### Step 3: Enable Pod Security Standards

**Apply PSS labels (audit and warn mode):**

```bash
# Add PSS labels to namespace
kubectl label namespace sticky-session-secure \
  pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/enforce-version=latest \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/audit-version=latest \
  pod-security.kubernetes.io/warn=restricted \
  pod-security.kubernetes.io/warn-version=latest \
  --overwrite

# Verify labels
kubectl get namespace sticky-session-secure --show-labels
```

**Redeploy to see violations:**

```bash
# Delete and recreate deployment to trigger warnings
kubectl delete deployment stickysessions-deployment -n sticky-session-secure
kubectl apply -f deployment.yaml

```

**Document PSS violations:**

```plaintext

Pod Security Standard Violations (Restricted):
===============================================
1. allowPrivilegeEscalation not set to false
2. readOnlyRootFilesystem not set to true
3. runAsNonRoot not set to true
4. Running as root user
5. Capabilities not dropped
6. No seccomp profile defined

Current State: Violates "restricted" policy requirements
```

---

## Phase 2: Apply Security Contexts on k3s (20-25 minutes)

### Step 1: Add Basic Security Context

**Attempt 1: Run as non-root user (UID 1001):**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: stickysessions-deployment
  namespace: sticky-session-secure
spec:
  replicas: 1
  selector:
    matchLabels:
      app: stickysessions-deployment
  template:
    metadata:
      labels:
        app: stickysessions-deployment
    spec:
      securityContext:
        runAsUser: 1001
        runAsGroup: 1001
      containers:
      - name: stickysessions
        image: registry.company.com/stickysessions:0.1.1
        ports:
        - containerPort: 8080
```

**Deploy and observe failure:**

```bash
# Deploy
kubectl apply -f deployment.yaml

# Check pod status
kubectl get pods -n sticky-session-secure -l app=stickysessions

# Expected: Pod fails to start (CrashLoopBackOff or Error)

# Check logs for errors
kubectl logs -n sticky-session-secure -l app=stickysessions --tail=50

# Expected errors:
# - Permission denied writing to /usr/local/tomee/logs/
# - Cannot create directory /usr/local/tomee/temp/
# - java.io.IOException: Permission denied
```

---

### Step 2: Identify Writable Directory Requirements

**Investigate TomEE directory structure:**

```bash
# Exec into insecure container to understand structure

# Check TomEE directories
kubectl exec -n sticky-session-secure deployment/stickysessions-deployment -- find /usr/local/tomee -type d -name logs -o -name temp -o -name work

# Expected output:
# /usr/local/tomee/logs
# /usr/local/tomee/temp
# /usr/local/tomee/work

# Check what gets written during startup
kubectl exec -n sticky-session-secure deployment/stickysessions-deployment -- ls -la /usr/local/tomee/logs/
kubectl exec -n sticky-session-secure deployment/stickysessions-deployment -- ls -la /usr/local/tomee/temp/
kubectl exec -n sticky-session-secure deployment/stickysessions-deployment -- ls -la /usr/local/tomee/work/
```

**TomEE writable directories identified:**

```
Required Writable Paths:
========================
/usr/local/tomee/logs/  - Application and server logs
/usr/local/tomee/temp/  - Temporary files during operation
/usr/local/tomee/work/  - JSP compilation and work files
```

---

### Step 3: Add Volume Mounts for Writable Directories

**Create deployment with volume mounts:**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: stickysessions-deployment
  namespace: sticky-session-secure
spec:
  replicas: 1
  selector:
    matchLabels:
      app: stickysessions
  template:
    metadata:
      labels:
        app: stickysessions
    spec:
      securityContext:
        runAsUser: 1001
        runAsGroup: 1001
        fsGroup: 0
      containers:
      - name: stickysessions
        image: registry.company.com/stickysessions:0.1.1
        ports:
        - containerPort: 8080
        volumeMounts:
        - name: logs
          mountPath: /usr/local/tomee/logs
        - name: temp
          mountPath: /usr/local/tomee/temp
        - name: work
          mountPath: /usr/local/tomee/work
      volumes:
      - name: logs
        emptyDir: {}
      - name: temp
        emptyDir: {}
      - name: work
        emptyDir: {}
```

**Deploy and test:**

```bash
# Deploy
kubectl apply -f deployment.yaml

# Check status (likely still fails)
kubectl get pods -n sticky-session-secure -l app=stickysessions

# Check logs
kubectl logs -n sticky-session-secure deployment/stickysessions-deployment --tail=50

# Expected: Still permission errors because files/directories
# in the image are owned by root, not UID 1001
```

**Key learning:** Volume mounts alone aren't enough - the image itself needs proper ownership

---

### Step 4: Apply Full Security Context (Will Fail)

**Attempt full hardening with current image:**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: stickysessions-deployment
  namespace: sticky-session-secure
spec:
  replicas: 1
  selector:
    matchLabels:
      app: stickysessions
  template:
    metadata:
      labels:
        app: stickysessions
    spec:
      securityContext:
        runAsUser: 1001
        runAsGroup: 1001
        fsGroup: 0
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: stickysessions
        image: registry.company.com/stickysessions:0.1.1
        ports:
        - containerPort: 8080
        securityContext:
          runAsNonRoot: true
          readOnlyRootFilesystem: true
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
        volumeMounts:
        - name: logs
          mountPath: /usr/local/tomee/logs
        - name: temp
          mountPath: /usr/local/tomee/temp
        - name: work
          mountPath: /usr/local/tomee/work
      volumes:
      - name: logs
        emptyDir: {}
      - name: temp
        emptyDir: {}
      - name: work
        emptyDir: {}
```

**Deploy and observe failures:**

```bash
# Deploy
kubectl apply -f deployment.yaml

# Check status
kubectl get pods -n sticky-session-secure -w
# Expected/Possible: CrashLoopBackOff

# Check detailed logs
kubectl logs -n sticky-session-secure deployment/stickysessions-deployment --tail=100

# Possible errors:
# - Permission denied on read-only filesystem
# - Cannot read configuration files owned by root
# - Various file access errors
```

**Conclusion:** The insecure image cannot be fully secured with security contexts alone. The image must be rebuilt in many cases.

---

## Phase 3: Dockerfile Hardening (30-40 minutes)

### Step 1: Create Hardened Dockerfile

**Hardened Dockerfile with detailed comments:**

```dockerfile
# Use Alpine-based base image to decrease attack surface
FROM tomee:jre25-Temurin-alpine-plus

# hadolint ignore=DL3018
RUN apk add --no-cache bash unzip

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN addgroup -g 1001 tomee && \
    adduser -h /home/tomee -s /bin/sh -u 1001 -G tomee -D tomee

# Sometimes fetching doesn't work or container is built by CI/CD.
# Therefore, a downloaded local WAR could be copied into the container instead.
COPY src/StickySession.war /usr/local/tomee/webapps/

# unzip the Access Server WAR
RUN unzip /usr/local/tomee/webapps/StickySession.war -d /usr/local/tomee/webapps/

# remove configuration from WAR so that Docker Compose can map config files into the container
RUN rm -f /usr/local/tomee/webapps/*war

# copy the config files
COPY src/server.xml /usr/local/tomee/conf/
COPY src/catalina.properties /usr/local/tomee/conf/

USER tomee

EXPOSE 8080
```

---

### Step 2: Build and Push Hardened Image

**Build image:**

Build the updated image using `docker` or `podman` and push it to your container registry.

---

### Step 3: Deploy Hardened Image with Security Contexts

**Create fully secured deployment:**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: stickysessions-deployment
  namespace: sticky-session-secure
  labels:
    app: stickysessions
spec:
  replicas: 1
  selector:
    matchLabels:
      app: stickysessions
  template:
    metadata:
      labels:
        app: stickysessions
    spec:
      securityContext:
        runAsUser: 1001
        runAsGroup: 1001
        fsGroup: 0
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: stickysessions
        image: registry.company.com/tmp/stickysessions:0.1.2
        ports:
        - containerPort: 8080
          name: http
          protocol: TCP
        securityContext:
          runAsNonRoot: true
          readOnlyRootFilesystem: true
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        volumeMounts:
        - name: logs
          mountPath: /usr/local/tomee/logs
        - name: temp
          mountPath: /usr/local/tomee/temp
        - name: work
          mountPath: /usr/local/tomee/work
        livenessProbe:
          httpGet:
            path: /
            port: 8080
          initialDelaySeconds: 15
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /
            port: 8080
          initialDelaySeconds: 15
          periodSeconds: 5
      volumes:
      - name: logs
        emptyDir: {}
      - name: temp
        emptyDir: {}
      - name: work
        emptyDir: {}
```

**Create service:**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: stickysessions-service
  namespace: sticky-session-secure
spec:
  type: ClusterIP
  sessionAffinity: ClientIP
  selector:
    app: stickysessions
  ports:
  - name: http
    port: 8080
    targetPort: 8080
    protocol: TCP
```

**Deploy:**

```bash
# Apply deployment
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml

# Watch deployment progress
kubectl get pods -n sticky-session-secure -w
```

**Verify security context:**

```bash
# Check running user
kubectl exec -it -n sticky-session-secure deployment/stickysessions-deployment -- id
# Expected: uid=1001 gid=1001

# Check filesystem (should be read-only except mounted volumes)
kubectl exec -n sticky-session-secure deployment/stickysessions-deployment -- touch /test-file
# Expected: touch: cannot touch '/test-file': Read-only file system

# Check writable volumes work
kubectl exec -n sticky-session-secure deployment/stickysessions-deployment -- touch /usr/local/tomee/logs/test.log
# Expected: Success

# Check security context in pod spec
kubectl get pod -n sticky-session-secure stickysessions-deployment-PLACEHOLDER -o jsonpath='{.spec.containers[0].securityContext}' | jq .
```

---

## Phase 4: Pod Security Standards Enforcement (15-20 minutes)

### Step 1: Review Current PSS Violations

**Check audit logs:**

```bash
# View namespace labels
kubectl get namespace sticky-session-secure --show-labels

# Current: enforce=baseline, audit=restricted, warn=restricted
```

**Analyze hardened pod against Restricted policy:**

```bash
# Check each Restricted requirement:

kubectl get pod -n sticky-session-secure stickysessions-deployment-PLACEHOLDER -o jsonpath='{.spec.containers[0].securityContext}'

# Container Level
# 1. runAsNonRoot
# 2. readOnlyRootFilesystem
# 3. allowPrivilegeEscalation
# 4. capabilities

# Expected:
# {
#   "allowPrivilegeEscalation": false,
#   "capabilities": {
#     "drop": [
#       "ALL"
#     ]
#   },
#   "readOnlyRootFilesystem": true,
#   "runAsNonRoot": true
# }

kubectl get pod -n sticky-session-secure stickysessions-deployment-PLACEHOLDER -o jsonpath='{.spec.securityContext}'

# Pod Level
# 1. runAsUser
# 2. runAsGroup
# 3. fsGroup
# 4. seccompProfile

```

---

### Step 2: Fix Remaining Violations (if any)

**If violations exist, update deployment:**

Example: If seccompProfile is missing, add it

---

### Step 3: Enable Enforcement Mode

**Update namespace to enforce Restricted policy:**

```bash
# Change from privileged enforcement to restricted enforcement
kubectl label namespace sticky-session-secure \
  pod-security.kubernetes.io/enforce=restricted \
  --overwrite

```

**Test enforcement by trying to deploy insecure pod:**

```yaml
# test-insecure-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-insecure
  namespace: sticky-session-secure
spec:
  containers:
  - name: nginx
    image: nginx:latest
    # No security context - should be rejected
```

```bash
# Try to create insecure pod
kubectl apply -f test-insecure-pod.yaml

# Expected: Error message about policy violation
# Error: pods "test-insecure" is forbidden: violates PodSecurity "restricted:latest"

```

**Verify hardened pod still works:**

```bash
# Redeploy hardened application
kubectl delete deployment stickysessions-deployment -n sticky-session-secure
kubectl apply -f deployment.yaml

```

---

### Step 4: Validation

**Complete security validation:**

Re-run the validation steps from above to check both pod- and container-level `securityContext`

**Document security improvements:**

```plaintext
Security Improvements Achieved on k3s:
======================================
✓ Running as non-root user (UID 1001)
✓ Read-only root filesystem
✓ All capabilities dropped
✓ Privilege escalation prevented
✓ Seccomp profile applied (RuntimeDefault)
✓ Pod Security Standard: Restricted (enforced)
✓ Resource limits defined
✓ Health checks configured

Status: production-ready for k3s
```

---

## Phase 5: OpenShift Migration (25-30 minutes)

### Step 1: Initial OpenShift Deployment Attempt

**Note:** The project/namespace creation and initial deployment will be demonstrated in existing OpenShift/OKD environment.

The regular `kubectl` binary will be used for this example, as the dedicated OpenShift/OKD `oc` is not required here.

**Deploy using k3s manifests:**

```bash
# Try deploying with same manifests
kubectl apply -f deployment.yaml -n sticky-session-secure

# Check pod status
kubectl get pods -n sticky-session-secure

# Expected: Pods may fail to start or show warnings
```

**Check for failures:**

```bash
# Check events
kubectl describe deployment stickysessions-deployment -n sticky-session-secure

# Check logs
kubectl logs -n sticky-session-secure deployment/stickysessions-deployment

# Expected issues:
# - Permission denied on mounted volumes
# - Unable to write to logs/temp/work directories
```

---

### Step 2: Understand OpenShift SCC

**Examine Security Context Constraints:**

```bash
# List SCCs
kubectl get scc

# Check which SCC is applied to your pod
kubectl get pod -n sticky-session-secure -o yaml | grep -i scc
# Expected: restricted-v2 SCC

# View restricted-v2 SCC details
kubectl describe scc restricted-v2

# Key differences from k3s:
# - MustRunAsRange: OpenShift assigns random UID from namespace range
# - fsGroup: Required for volume permissions
# - User can be ANY UID in allocated range (1000000000+)
```

**Check assigned UID:**

```bash
# Check actual UID OpenShift assigned
kubectl exec -n sticky-session-secure deployment/stickysessions-deployment -- id

# Expected: uid=1000XXXXXX (random UID in namespace range), gid=0(root) groups=0(root)
# NOT uid=1001 as specified in k3s deployment
```

---

### Step 3: Adjust Dockerfile for OpenShift Compatibility

**Create OpenShift-compatible Dockerfile:**

```dockerfile
# Use Alpine-based base image to decrease attack surface
FROM tomee:jre25-Temurin-alpine-plus

# hadolint ignore=DL3018
RUN apk add --no-cache \
    bash \
    unzip

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN addgroup -g 1001 tomee && \
    adduser -h /home/tomee -s /bin/sh -u 1001 -G tomee -D tomee

# Sometimes fetching doesn't work. A manual downloaded local WAR could be copied into the container instead.
COPY src/StickySession.war /usr/local/tomee/webapps/

# unzip the Access Server WAR
RUN unzip /usr/local/tomee/webapps/StickySession.war -d /usr/local/tomee/webapps/

# remove configuration from WAR so that Docker Compose can map config files into the container
RUN rm -f /usr/local/tomee/webapps/*war

# add OpenShift compatible permission sets
RUN chgrp -R 0 /home/tomee /usr/local/tomee/ && \
    chmod -R g=u /home/tomee /usr/local/tomee/ && \
    chmod -R g+rwx /usr/local/tomee/logs /usr/local/tomee/temp /usr/local/tomee/work

# copy the config files
COPY src/server.xml /usr/local/tomee/conf/
COPY src/catalina.properties /usr/local/tomee/conf/

USER tomee

EXPOSE 8080
```

**Key OpenShift differences:**

```plaintext
k3s Dockerfile:             OpenShift Dockerfile:

default permissions         chown root:0
                            chmod g=u + g+rwx

Why?
- OpenShift assigns arbitrary UIDs (e.g., 1000520000)
- All UIDs are members of root group (GID 0)
- Group permissions allow any UID in group 0 to access files
```

**Build and push OpenShift image:**

---

### Step 4: Update Kubernetes Manifests for OpenShift

**Create OpenShift-specific deployment:**

```yaml
# deployment-okd.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: stickysessions-deployment
  namespace: sticky-session-secure
  labels:
    app: stickysessions
spec:
  replicas: 1
  selector:
    matchLabels:
      app: stickysessions
  template:
    metadata:
      labels:
        app: stickysessions
    spec:
      securityContext:
        # DON'T specify runAsUser - let OpenShift assign
        # runAsUser: 1001  ← REMOVE THIS
        fsGroup: 0         # Required for volume ownership (root group is standard in OpenShift)
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: stickysessions
        image: registry.company.com/tmp/stickysessions:0.1.3
        ports:
        - containerPort: 8080
          name: http
        securityContext:
          runAsNonRoot: true
          readOnlyRootFilesystem: true
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        volumeMounts:
        - name: logs
          mountPath: /usr/local/tomee/logs
        - name: temp
          mountPath: /usr/local/tomee/temp
        - name: work
          mountPath: /usr/local/tomee/work
        livenessProbe:
          httpGet:
            path: /
            port: 8080
          initialDelaySeconds: 15
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /
            port: 8080
          initialDelaySeconds: 15
          periodSeconds: 5
      volumes:
      - name: logs
        emptyDir: {}
      - name: temp
        emptyDir: {}
      - name: work
        emptyDir: {}
```

**Create OpenShift Route - using Ingress :**

```yaml
# ingress-okd.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: stickysessions
  namespace: sticky-session-secure
  labels:
    app.kubernetes.io/name: stickysessions
  annotations:
    route.openshift.io/termination: edge
spec:
  ingressClassName: openshift-default
  rules:
    - host: stickysession.apps.okd.test.local
      http:
        paths:
          # Required for OpenShift router implementation
          - pathType: ImplementationSpecific
            path: "/"
            backend:
              service:
                name: stickysessions-service
                port:
                  number: 8080
```

---

### Step 5: Deploy to OpenShift

**Deploy application:**

```bash
# Apply all manifests
kubectl apply -f deploy-okd.yaml
kubectl apply -f ingress-okd.yaml
kubectl apply -f service.yaml

# Watch deployment
kubectl get pods -n sticky-session-secure -w

```

**Verify deployment:**

```bash
# Check pod status
kubectl get pods -n sticky-session-secure

# Check assigned UID
kubectl exec -n sticky-session-secure deployment/stickysessions-deployment -- id

# Expected: uid=1000XXXXXX (OpenShift-assigned) gid=0(root)
# Note: GID is 0 (root group) - this is normal in OpenShift

# Check SCC applied
kubectl get pod -n sticky-session-secure -o yaml | grep scc

# Check volume permissions
kubectl exec -n sticky-session-secure deployment/stickysessions-deployment -- ls -la /usr/local/tomee/logs

```

**Test application via Route:**

```bash
# Get route URL
kubectl get route -n sticky-session-secure

# Test application
curl https://PLACEHOLDER_ROUTE_URL/

# Expected: Application works, shows request info
```

**Success!** Application now runs on OpenShift with proper security

---

## Phase 6: Validation & Documentation (10-15 minutes)

### Step 1: Security Comparison

**Create comparison table:**

```plaintext
Security Posture Comparison:
============================

| Aspect                  | Insecure (k3s) | Hardened (k3s) | OpenShift    |
|-------------------------|----------------|----------------|--------------|
| User                    | root (0)       | tomee (1001)   | Random UID   |
| Group                   | root (0)       | tomee (1001)   | root (0)     |
| Filesystem              | Writable       | Read-only      | Read-only    |
| Capabilities            | All            | None (dropped) | None         |
| Privilege Escalation    | Allowed        | Blocked        | Blocked      |
| Seccomp                 | None           | RuntimeDefault | RuntimeDefault|
| PSS/SCC                 | None           | Restricted     | restricted-v2|
| Vulnerabilities         | Many           | Fewer          | Fewer        |

Risk Level:                 CRITICAL         LOW              LOW
Production Ready:           NO               YES              YES
```

---

### Step 2: Platform Differences Documentation

**k3s vs OpenShift Security:**

```plaintext
Key Differences:
===============

Aspect                 k3s                          OpenShift
----------------       ------------------------     ---------------------------
UID Assignment         Specified in manifest        Randomly assigned by SCC
GID                    Specified in manifest        Always 0 (root group)
Security Policy        Pod Security Standards       Security Context Constraints
Default Policy         Privileged                   Restricted
File Ownership         user:group                   root:0 with group perms
fsGroup                Optional                     Required for volumes
Enforcement            Namespace labels             SCC assignment
Policy Levels          3 (Privileged/Baseline/      Many SCCs
                       Restricted)
Flexibility            More permissive              More restrictive

Migration Checklist:
===================
✓ Change file ownership to root:0
✓ Add group permissions (g=u, g+rwx)
✓ Remove runAsUser from manifests
✓ Add fsGroup for volumes
✓ Test with arbitrary UIDs
✓ Use Routes instead of NodePorts/LoadBalancers
✓ Verify SCC compliance
```

---

### Step 3: Validation Tests

**Comprehensive security validation:**

```bash
# Test 1: Verify non-root execution on both platforms
kubectl exec -n sticky-session-secure deployment/stickysessions-deployment -- id

# Test 2: Verify read-only filesystem
kubectl exec -n sticky-session-secure deployment/stickysessions-deployment -- touch /test || echo "Blocked"

# Test 3: Verify writable volumes work
kubectl exec -n sticky-session-secure deployment/stickysessions-deployment -- touch /usr/local/tomee/logs/test.log && echo "Volume writable"
```

---

### Step 4: Lessons Learned Documentation

**Document your experience:**

```markdown
## Lessons Learned

### Technical Insights
1. Security contexts alone cannot fix insecure images
2. File ownership in images is critical for security
3. OpenShift's arbitrary UIDs require group-based permissions
4. Read-only filesystems require careful volume planning
5. Security is iterative - test at each step

### Challenges Encountered
1. Permission denied errors when adding runAsUser initially
2. Identifying all directories that need write access
3. Understanding OpenShift's group-based permission model
4. Testing across both platforms for compatibility

### Best Practices Discovered
1. Build images with security in mind from the start
2. Use group permissions for maximum compatibility
3. Test security contexts progressively, not all at once
4. Document platform-specific requirements
5. Automate security scanning in CI/CD

### What I Would Do Differently
[Student fills in based on their experience]

### Questions for Discussion
1. How to balance security with operational requirements?
2. When to use baseline vs restricted policies?
3. How to handle legacy applications that can't be rebuilt?
4. Best practices for secrets management?
```

---

## Troubleshooting Guide

### Issue 1: Pod Fails to Start After Adding runAsUser

**Symptoms:**

```plaintext
State: CrashLoopBackOff
Logs : Permission denied
```

**Solutions:**

```bash
# Check file ownership in image
docker run --rm registry.company.com/stickysessions:0.1.1 ls -la /usr/local/tomee/

# Files owned by root, but running as UID 1001
# Solution: Rebuild image with proper ownership
```

---

### Issue 2: Read-Only Filesystem Errors

**Symptoms:**

```plaintext
java.io.IOException: Read-only file system
Cannot write to /usr/local/tomee/logs
```

**Solutions:**

```bash
# Identify which directories need write access
kubectl logs -n sticky-session-secure deployment/stickysessions-deployment | grep "Permission denied"

# Add volume mounts for those directories
```

---

### Issue 3: OpenShift Permission Denied on Volumes

**Symptoms:**

```plaintext
Permission denied writing to /usr/local/tomee/logs
Even though volume is mounted
```

**Solutions:**

```bash
# Check if fsGroup is set
kubectl get deployment stickysessions-deployment -n sticky-session-secure -o jsonpath='{.spec.template.spec.securityContext}'

# If empty, add fsGroup

# Check volume ownership after patch
kubectl exec -n sticky-session-secure deployment/stickysessions-deployment -- ls -la /usr/local/tomee/logs
# Should show gid matching fsGroup
```

---

### Issue 4: OpenShift Image Pull Errors

**Symptoms:**

```plaintext
ImagePullBackOff
Error: Failed to pull image
```

**Solutions:**

```bash
# Check image exists in registry

# Use full image path with registry

# Check image pull secrets
kubectl get secrets -n sticky-session-secure
```

---

### Issue 5: Pod Security Standard Violations

**Symptoms:**

```plaintext
Error: pods "tomee" is forbidden: violates PodSecurity "restricted:latest"
```

**Solutions:**

```bash
# Check specific violations
kubectl describe pod <pod-name> -n sticky-session-secure | grep -A 10 Warning

# Common fixes:
# 1. Add missing runAsNonRoot
# 2. Add missing capabilities drop
# 3. Add missing seccomp

```

---

## Cleanup

**Remove lab resources:**

```bash
# k3s cleanup
kubectl delete namespace sticky-session-secure

# OpenShift cleanup (if permitted)
kubectl delete project sticky-session-secure

# Remove local images
docker rmi registry.company.com/tmp/stickysessions:0.1.1
docker rmi registry.company.com/tmp/stickysessions:0.1.2
docker rmi registry.company.com/tmp/stickysessions:0.1.3
```

---

## Summary

**What We Accomplished:**

1. ✅ Analyzed insecure baseline application
2. ✅ Identified security vulnerabilities
3. ✅ Applied security contexts progressively
4. ✅ Hardened Dockerfile with non-root user
5. ✅ Implemented Pod Security Standards (Restricted)
6. ✅ Deployed to k3s with full security
7. ✅ Migrated to OpenShift with platform-specific adjustments
8. ✅ Validated security across both platforms

**Key Takeaways:**

- Security must be built into images, not just applied via contexts
- Different platforms have different security models
- Group permissions enable cross-platform compatibility
- Testing at each step prevents compound issues
- Documentation is critical for team knowledge

**Next Steps:**

- Apply these patterns to your own applications
- Implement automated security scanning
- Configure Network Policies
- Set up RBAC
- Prepare for production deployments

---

**Estimated Completion Time:** 115-150 minutes
**Difficulty Level:** Intermediate to Advanced
**Learning Validation:** Students can secure applications for production deployment on multiple platforms
