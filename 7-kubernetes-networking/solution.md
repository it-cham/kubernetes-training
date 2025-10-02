# Lab: Advanced Networking and Service Exposure - Solution

## Objective

Deploy web-based database management interface with production-ready Ingress-based routing and HTTPS termination, demonstrating the practical advantages of Ingress controllers for web application exposure.

## Prerequisites

- MySQL application running in `test-lab` namespace from previous modules
- k3s cluster with sufficient resources for Ingress controller
- kubectl configured and operational

## Application Overview

We'll build a complete application exposure architecture by:

- **Analyzing**: Current Service exposure limitations and challenges
- **Deploying**: NGINX Ingress Controller for HTTP-aware routing
- **Implementing**: Host-based and path-based routing patterns
- **Securing**: Application with TLS termination and certificate management
- **Validating**: Advanced routing features and operational procedures

---

## Phase 1: Service Limitation Analysis (10-15 minutes)

### Step 1: Document Current Service Configuration

**Check existing service exposure:**

```bash
# Verify current deployment state
kubectl get all -n test-lab

# Examine service configuration
kubectl get svc -n test-lab
kubectl describe svc -n test-lab

# Check if NodePort services exist
kubectl get svc -n test-lab -o wide
```

### Step 2: Create NodePort Service for MySQL (Demonstration)

Create a NodePort service to demonstrate limitations:

```yaml
# service-mysql-nodeport.yaml
apiVersion: v1
kind: Service
metadata:
  name: mysql-nodeport
  namespace: test-lab
spec:
  type: NodePort
  ports:
    - port: 3306
      targetPort: 3306
      nodePort: 30306
  selector:
    app: mysql
```

```bash
# Apply NodePort service
kubectl apply -f service-mysql-nodeport.yaml

# Verify external access
nc -zv localhost 30306
```

### Step 3: Document NodePort Limitations

**Current challenges with NodePort approach:**

```plaintext
NodePort Limitations Identified:

1. Port Management:
   - MySQL: Port 30306 (non-standard database port)
   - Future web services: Port sprawl (30080, 30081, 30082, etc.)
   - Each web service needs unique high port

2. No HTTPS:
   - All web traffic in plain HTTP
   - No SSL/TLS termination capability
   - Database connections exposed on non-standard ports

3. No Host-based Routing:
   - Cannot use proper domain names
   - All services need different ports
   - Difficult to remember port numbers

4. Limited Features:
   - No advanced routing (path-based, etc.)
   - No centralized configuration
   - No built-in load balancing intelligence

5. Production Issues:
   - Firewall complexity (multiple ports)
   - Certificate management challenges
   - Difficult monitoring and troubleshooting
   - User confusion with non-standard ports
```

```bash
# Remove demonstration NodePort service
kubectl delete svc mysql-nodeport -n test-lab
```

---

## Phase 2: NGINX Ingress Controller Deployment (15-20 minutes)

### Step 1: Deploy NGINX Ingress Controller

**Method 1: Using Helm:**

```bash
# Add NGINX Ingress Helm repository
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Install NGINX Ingress Controller
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace

# Verify installation
helm list -n ingress-nginx
```

**Method 2: Using YAML manifests:**

```bash
# Deploy NGINX Ingress Controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.13.3/deploy/static/provider/cloud/deploy.yaml

# Wait for deployment to complete
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=300s
```

### Step 2: Verify Ingress Controller Installation

**Check controller deployment:**

```bash
# Verify pods are running
kubectl get pods -n ingress-nginx

# Check services created
kubectl get svc -n ingress-nginx

# Verify controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller --tail=50
```

**Expected output verification:**

```bash
# Controller should show as ready
kubectl get deployment -n ingress-nginx ingress-nginx-controller

# LoadBalancer service should be available (shows EXTERNAL-IP as localhost in k3s)
kubectl get svc -n ingress-nginx ingress-nginx-controller
```

### Step 3: Validate Ingress Controller Functionality

**Test controller health endpoints:**

```bash
# Get controller service details
kubectl get svc -n ingress-nginx ingress-nginx-controller

# Test health check
curl http://localhost/healthz

# Check if controller is responding to requests
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller --tail=10
```

---

## Phase 3: Deploy phpMyAdmin with Basic HTTP Routing (20-25 minutes)

### Step 1: Deploy phpMyAdmin Application

**phpMyAdmin deployment configuration:**

```yaml
# deployment-phpmyadmin.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: phpmyadmin
  namespace: test-lab
  labels:
    app: phpmyadmin
spec:
  replicas: 1
  selector:
    matchLabels:
      app: phpmyadmin
  template:
    metadata:
      labels:
        app: phpmyadmin
    spec:
      containers:
        - image: phpmyadmin/phpmyadmin:5.2
          name: phpmyadmin
          env:
            - name: PMA_HOST
              value: "mysql.test-lab.svc.cluster.local"
          ports:
            - containerPort: 80
          resources:
            requests:
              cpu: "50m"
              memory: "128Mi"
            limits:
              cpu: "150m"
              memory: "256Mi"
```

```bash
# Deploy phpMyAdmin
kubectl apply -f deployment-phpmyadmin.yaml

# Verify deployment
kubectl get deployment phpmyadmin -n test-lab
kubectl wait --for=condition=available deployment/phpmyadmin -n test-lab --timeout=300s
```

### Step 2: Create ClusterIP Service

```yaml
# service-phpmyadmin.yaml
apiVersion: v1
kind: Service
metadata:
  name: phpmyadmin
  namespace: test-lab
spec:
  type: ClusterIP
  ports:
    - port: 80
      targetPort: 80
  selector:
    app: phpmyadmin
```

```bash
# Apply service configuration
kubectl apply -f service-phpmyadmin.yaml

# Verify service
kubectl get svc phpmyadmin -n test-lab
```

### Step 3: Create Basic Ingress Resource

**Simple HTTP Ingress configuration:**

```yaml
# ingress-phpmyadmin-basic.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: phpmyadmin
  namespace: test-lab
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: phpmyadmin.k3s.test.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: phpmyadmin
            port:
              number: 80
```

```bash
# Apply Ingress resource
kubectl apply -f ingress-phpmyadmin-basic.yaml

# Verify Ingress creation
kubectl get ingress -n test-lab
kubectl describe ingress phpmyadmin-ingress -n test-lab
```

### Step 4: Test Basic Ingress Routing

**Configure local hostname resolution:**

```bash
# Add entry to /etc/hosts (Linux/Mac) or C:\Windows\System32\drivers\etc\hosts (Windows)
echo "127.0.0.1 phpmyadmin.k3s.test.local" | sudo tee -a /etc/hosts

# For Windows users (run as Administrator):
# echo 127.0.0.1 phpmyadmin.k3s.test.local >> C:\Windows\System32\drivers\etc\hosts
```

**Test HTTP access:**

```bash
# Test with proper hostname
curl -H "Host: phpmyadmin.k3s.test.local" http://localhost/ | grep -i phpmyadmin

# Test with browser - visit http://phpmyadmin.k3s.test.local
# Should show phpMyAdmin login page
# Login credentials: root / <password from mysql-credentials secret>

# Verify Ingress controller processed the request
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller --tail=10
```

### Step 5: Validate Routing Behavior

**Examine Ingress controller configuration:**

```bash
# Check Ingress resource status
kubectl get ingress phpmyadmin-ingress -n test-lab -o yaml

# View controller's generated configuration (optional)
kubectl exec -n ingress-nginx deployment/ingress-nginx-controller -- cat /etc/nginx/nginx.conf | grep -A 10 -B 5 phpmyadmin
```

---

## Phase 4: TLS Termination and HTTPS (25-30 minutes)

### Step 1: Generate Self-Signed Certificate

**Create certificate for phpMyAdmin:**

```bash
# Create certificate directory
mkdir -p certs
cd certs

# Generate certificate for phpMyAdmin
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout phpmyadmin-tls.key -out phpmyadmin-tls.crt \
  -subj "/CN=phpmyadmin.k3s.test.local/O=phpmyadmin.k3s.test.local"

# Verify certificate creation
ls -la *.crt *.key

# View certificate details
openssl x509 -in phpmyadmin-tls.crt -noout -text | head -20
```

### Step 2: Create Kubernetes TLS Secret

```bash
# Create TLS secret for phpMyAdmin
kubectl create secret tls phpmyadmin-tls-secret \
  --key phpmyadmin-tls.key \
  --cert phpmyadmin-tls.crt \
  -n test-lab

# Verify secret creation
kubectl get secrets -n test-lab | grep tls
kubectl describe secret phpmyadmin-tls-secret -n test-lab
```

### Step 3: Update Ingress with TLS Configuration

```yaml
# ingress-with-tls.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: phpmyadmin-ingress-tls
  namespace: test-lab
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - phpmyadmin.k3s.test.local
    secretName: phpmyadmin-tls-secret
  rules:
  - host: phpmyadmin.k3s.test.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: phpmyadmin
            port:
              number: 80
```

```bash
# Remove previous Ingress
kubectl delete ingress phpmyadmin-ingress -n test-lab

# Apply TLS-enabled Ingress
kubectl apply -f ingress-with-tls.yaml

# Verify TLS configuration
kubectl describe ingress phpmyadmin-ingress-tls -n test-lab
```

### Step 4: Test HTTPS Access

```bash
# Test HTTPS access (accept self-signed certificate)
curl -k https://phpmyadmin.k3s.test.local/ | grep -i phpmyadmin

# Test HTTP to HTTPS redirect
curl -I http://phpmyadmin.k3s.test.local/

# Verify certificate details
openssl s_client -connect phpmyadmin.k3s.test.local:443 -servername phpmyadmin.k3s.test.local < /dev/null 2>/dev/null | openssl x509 -noout -dates

# Check certificate subject
openssl s_client -connect phpmyadmin.k3s.test.local:443 -servername phpmyadmin.k3s.test.local < /dev/null 2>/dev/null | openssl x509 -noout -subject

# Access via browser (accept certificate warning):
# https://phpmyadmin.k3s.test.local
```

---

## Phase 5: Advanced Routing Patterns (15-20 minutes)

### Step 1: Multiple Hostnames for Same Service

**Create additional hostname routing:**

```yaml
# ingress-multi-hostname.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: phpmyadmin-multi-host
  namespace: test-lab
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - phpmyadmin.k3s.test.local
    - db-admin.k3s.test.local
    - admin.k3s.test.local
    secretName: phpmyadmin-tls-secret
  rules:
  - host: phpmyadmin.k3s.test.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: phpmyadmin
            port:
              number: 80
  - host: db-admin.k3s.test.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: phpmyadmin
            port:
              number: 80
  - host: admin.k3s.test.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: phpmyadmin
            port:
              number: 80
```

```bash
# Add additional hostnames to /etc/hosts
echo "127.0.0.1 db-admin.k3s.test.local admin.k3s.test.local" | sudo tee -a /etc/hosts

# Replace current Ingress
kubectl apply -f ingress-multi-hostname.yaml

# Test multiple hostname access to same service
curl -k https://phpmyadmin.k3s.test.local/ | grep -i phpmyadmin
curl -k https://db-admin.k3s.test.local/ | grep -i phpmyadmin
curl -k https://admin.k3s.test.local/ | grep -i phpmyadmin

echo "All three hostnames route to the same phpMyAdmin service"
```

### Step 2: Path-Based Routing Example

**Demonstrate path-based routing patterns:**

```yaml
# ingress-path-based.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: phpmyadmin-paths
  namespace: test-lab
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - db.k3s.test.local
    secretName: phpmyadmin-tls-secret
  rules:
  - host: db.k3s.test.local
    http:
      paths:
      - path: /phpmyadmin
        pathType: Prefix
        backend:
          service:
            name: phpmyadmin
            port:
              number: 80
      - path: /admin
        pathType: Prefix
        backend:
          service:
            name: phpmyadmin
            port:
              number: 80
```

```bash
# Add db.k3s.test.local to /etc/hosts
echo "127.0.0.1 db.k3s.test.local" | sudo tee -a /etc/hosts

# Apply path-based routing
kubectl apply -f ingress-path-based.yaml

# Test path-based routing
curl -k https://db.k3s.test.local/phpmyadmin | head -10
curl -k https://db.k3s.test.local/admin | head -10

echo "Testing routing paths:"
echo "- https://db.k3s.test.local/phpmyadmin → phpMyAdmin"
echo "- https://db.k3s.test.local/admin → phpMyAdmin"
```

### Step 3: Add NGINX Annotation Example

**Demonstrate annotation usage for customization:**

```yaml
# ingress-with-annotations.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: phpmyadmin-annotated
  namespace: test-lab
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "300"
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "300"
    nginx.ingress.kubernetes.io/client-body-buffer-size: "1m"
    # Rate limiting example (10 requests per second)
    nginx.ingress.kubernetes.io/limit-rps: "10"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - phpmyadmin.k3s.test.local
    secretName: phpmyadmin-tls-secret
  rules:
  - host: phpmyadmin.k3s.test.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: phpmyadmin
            port:
              number: 80
```

```bash
# Apply annotated configuration
kubectl apply -f ingress-with-annotations.yaml

# Test rate limiting by making rapid requests
for i in {1..15}; do curl -k -w "%{http_code}\n" -o /dev/null -s https://phpmyadmin.k3s.test.local/; done

# Expected: First 10 requests return 200, subsequent may return 503 if rate limit triggered
```

---

## Phase 6: Operations and Troubleshooting (15-20 minutes)

### Step 1: Certificate Management Operations

**Check certificate expiration and renewal:**

```bash
# Check certificate expiration dates
kubectl get secret phpmyadmin-tls-secret -n test-lab -o jsonpath='{.data.tls\.crt}' | \
  base64 -d | openssl x509 -noout -dates

# View certificate details
kubectl get secret phpmyadmin-tls-secret -n test-lab -o jsonpath='{.data.tls\.crt}' | \
  base64 -d | openssl x509 -noout -text | head -20

# Simulate certificate renewal
kubectl delete secret phpmyadmin-tls-secret -n test-lab
kubectl create secret tls phpmyadmin-tls-secret \
  --key certs/phpmyadmin-tls.key \
  --cert certs/phpmyadmin-tls.crt \
  -n test-lab

# Verify certificate reload (no downtime required)
curl -k https://phpmyadmin.k3s.test.local/ | head -10
```

### Step 2: Systematic Troubleshooting Practice

**Troubleshooting methodology demonstration:**

```bash
# Step 1: Check Ingress Controller health
kubectl get pods -n ingress-nginx
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller --tail=20

# Step 2: Verify Ingress resource configuration
kubectl get ingress -n test-lab
kubectl describe ingress phpmyadmin-annotated -n test-lab

# Step 3: Check backend services
kubectl get svc -n test-lab
kubectl get endpoints -n test-lab

# Step 4: Test DNS resolution
nslookup phpmyadmin.k3s.test.local
nslookup db.k3s.test.local

# Step 5: Check pod health
kubectl get pods -n test-lab
kubectl logs deployment/phpmyadmin -n test-lab --tail=10
```

### Step 3: Common Issue Resolution

**Simulate and resolve typical problems:**

**Issue 1: Service selector mismatch**

```bash
# Create problem - wrong selector
kubectl patch svc phpmyadmin -n test-lab -p '{"spec":{"selector":{"app":"wrong-app"}}}'

# Observe 503 errors
curl -k https://phpmyadmin.k3s.test.local/

# Debug the issue
kubectl get endpoints phpmyadmin -n test-lab  # Should be empty
kubectl get pods -n test-lab -l app=phpmyadmin  # Pods exist but not selected

# Fix the issue
kubectl patch svc phpmyadmin -n test-lab -p '{"spec":{"selector":{"app":"phpmyadmin"}}}'

# Verify resolution
kubectl get endpoints phpmyadmin -n test-lab
curl -k https://phpmyadmin.k3s.test.local/ | head -10
```

**Issue 2: Certificate hostname mismatch**

```bash
# Simulate certificate issue - wrong hostname
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout certs/wrong-tls.key -out certs/wrong-tls.crt \
  -subj "/CN=wrong.k3s.test.local/O=wrong.k3s.test.local"

kubectl create secret tls wrong-tls-secret \
  --key certs/wrong-tls.key \
  --cert certs/wrong-tls.crt \
  -n test-lab

# Update Ingress to use wrong certificate
kubectl patch ingress phpmyadmin-annotated -n test-lab -p '{"spec":{"tls":[{"hosts":["phpmyadmin.k3s.test.local"],"secretName":"wrong-tls-secret"}]}}'

# Test and observe certificate warning
openssl s_client -connect phpmyadmin.k3s.test.local:443 -servername phpmyadmin.k3s.test.local 2>&1 | grep -i "verify return"

# Fix certificate issue
kubectl patch ingress phpmyadmin-annotated -n test-lab -p '{"spec":{"tls":[{"hosts":["phpmyadmin.k3s.test.local"],"secretName":"phpmyadmin-tls-secret"}]}}'

# Verify fix
openssl s_client -connect phpmyadmin.k3s.test.local:443 -servername phpmyadmin.k3s.test.local 2>&1 | grep subject
```

### Step 4: Monitoring and Health Checks

**Verify monitoring capabilities:**

```bash
# Check Ingress controller metrics endpoint
kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 10254:10254 &
curl http://localhost:10254/metrics | grep nginx_ingress

# Stop port-forward
pkill -f "port-forward.*10254"

# Monitor access logs in real-time
kubectl logs -f -n ingress-nginx -l app.kubernetes.io/component=controller &

# Generate some traffic and observe logs
curl -k https://phpmyadmin.k3s.test.local/
curl -k https://db-admin.k3s.test.local/

# Stop log monitoring
pkill -f "kubectl logs"

# Check Ingress controller resource usage
kubectl top pods -n ingress-nginx
```

### Step 5: Load Balancing Test

**Scale phpMyAdmin and verify load balancing:**

```bash
# Scale phpMyAdmin to multiple replicas
kubectl scale deployment phpmyadmin -n test-lab --replicas=3

# Wait for pods to be ready
kubectl wait --for=condition=ready pod -l app=phpmyadmin -n test-lab --timeout=120s

# Check endpoints - should show multiple IPs
kubectl get endpoints phpmyadmin -n test-lab

# Test load balancing by checking pod logs
kubectl logs -f deployment/phpmyadmin -n test-lab --all-containers=true &

# Generate traffic to observe load distribution
for i in {1..10}; do curl -k -s https://phpmyadmin.k3s.test.local/ > /dev/null; echo "Request $i sent"; sleep 1; done

# Stop log monitoring
pkill -f "kubectl logs"

# Scale back to single replica
kubectl scale deployment phpmyadmin -n test-lab --replicas=1
```

---

## Troubleshooting Common Issues

### Issue 1: Ingress Controller Not Starting

**Symptoms:**

```
ingress-nginx-controller pods in CrashLoopBackOff or Pending
```

**Solutions:**

```bash
# Check resource constraints
kubectl describe pod -n ingress-nginx -l app.kubernetes.io/component=controller

# Check node resources
kubectl top nodes

# View detailed logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller --previous

# Verify RBAC permissions
kubectl get clusterroles | grep ingress-nginx
```

### Issue 2: DNS Resolution Problems

**Symptoms:**

```
curl: (6) Could not resolve host: phpmyadmin.k3s.test.local
```

**Solutions:**

```bash
# Verify /etc/hosts entries
grep -E "\.k3s.test.local" /etc/hosts

# Test with Host header instead
curl -H "Host: phpmyadmin.k3s.test.local" http://localhost/

# Check if using correct IP (should be 127.0.0.1 for local testing)
ping phpmyadmin.k3s.test.local
```

### Issue 3: TLS Certificate Warnings

**Symptoms:**

```
SSL certificate verify failed or browser warnings
```

**Solutions:**

```bash
# Check certificate matches hostname
openssl x509 -in certs/phpmyadmin-tls.crt -noout -text | grep -E "(Subject|DNS)"

# Verify certificate is loaded in secret
kubectl get secret phpmyadmin-tls-secret -n test-lab -o yaml

# Test certificate chain
openssl s_client -connect phpmyadmin.k3s.test.local:443 -servername phpmyadmin.k3s.test.local 2>&1 | head -30
```

### Issue 4: 404 Not Found Errors

**Symptoms:**

```
default backend - 404
```

**Solutions:**

```bash
# Check Ingress rules configuration
kubectl describe ingress -n test-lab

# Verify service and endpoints exist
kubectl get svc,endpoints -n test-lab

# Check path matching
curl -v -k https://phpmyadmin.k3s.test.local/nonexistent

# Verify Ingress class is specified
kubectl get ingress -n test-lab -o yaml | grep ingressClassName
```

### Issue 5: 503 Service Unavailable

**Symptoms:**

```
503 Service Temporarily Unavailable
```

**Solutions:**

```bash
# Check if service has endpoints
kubectl get endpoints phpmyadmin -n test-lab

# Verify pods are running and ready
kubectl get pods -l app=phpmyadmin -n test-lab

# Check pod logs for errors
kubectl logs deployment/phpmyadmin -n test-lab

# Verify service selector matches pod labels
kubectl describe svc phpmyadmin -n test-lab
kubectl describe pod -l app=phpmyadmin -n test-lab | grep Labels
```

---

## Architecture Comparison

### Before Ingress (NodePort)

```plaintext
Internet
   │
   └── :30080 ──► phpMyAdmin Service ──► phpMyAdmin Pods

Limitations:
- High-numbered port (30080)
- No HTTPS termination
- No hostname routing
- No advanced HTTP features
```

### After Ingress (NGINX)

```plaintext
Internet
   │
   ▼ :80/:443
┌─────────────────────┐
│ NGINX Ingress       │
│ Controller          │
│ - TLS Termination   │
│ - Host Routing      │
│ - Path Routing      │
└─────────────────────┘
   │
   ├── phpmyadmin.k3s.test.local ──► phpMyAdmin Service ──► phpMyAdmin Pods
   ├── db-admin.k3s.test.local ────► phpMyAdmin Service ──► phpMyAdmin Pods
   └── admin.k3s.test.local ───────► phpMyAdmin Service ──► phpMyAdmin Pods

Benefits:
- Standard ports (80/443)
- Centralized TLS termination
- Multiple hostname routing
- Single certificate management
- Advanced HTTP features
```

---

## Feature Comparison

| Feature | NodePort Services | NGINX Ingress |
|---------|-------------------|---------------|
| **Port Management** | High ports (30000+) | Standard 80/443 |
| **HTTPS/TLS** | Manual per service | Centralized termination |
| **Hostname Routing** | Not supported | Multiple hosts supported |
| **Path-based Routing** | Not supported | Advanced patterns |
| **Load Balancing** | Basic round-robin | Advanced algorithms |
| **Rate Limiting** | Not available | Built-in annotations |
| **Certificate Management** | Manual per service | Centralized |
| **Monitoring** | Basic | Rich metrics |

---

## Production Readiness Checklist

### Security

- [ ] TLS certificates properly configured and valid
- [ ] Rate limiting implemented where appropriate
- [ ] Security headers configured via annotations
- [ ] Access logs enabled for audit trails

### Operations

- [ ] Certificate expiration monitoring in place
- [ ] Health check endpoints functional
- [ ] Troubleshooting procedures documented
- [ ] Monitoring and alerting configured

### Scalability

- [ ] Ingress controller resource limits set
- [ ] Load balancing validated across multiple pod replicas
- [ ] Performance testing completed
- [ ] Multiple controller replicas for high availability (production)

---

## Cleanup and Resource Management

### Remove Lab Resources

```bash
# Remove Ingress resources
kubectl delete ingress -n test-lab --all

# Remove TLS secrets
kubectl delete secret phpmyadmin-tls-secret wrong-tls-secret -n test-lab --ignore-not-found=true

# Remove phpMyAdmin
kubectl delete deployment phpmyadmin -n test-lab
kubectl delete svc phpmyadmin -n test-lab

# Clean up certificate files
rm -rf certs/

# Remove /etc/hosts entries
sudo sed -i.bak '/phpmyadmin.k3s.test.local\|db-admin.k3s.test.local\|admin.k3s.test.local\|db.k3s.test.local/d' /etc/hosts

# Remove NGINX Ingress Controller (optional)
kubectl delete -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.0-beta.0/deploy/static/provider/cloud/deploy.yaml
```

### Preserve Core Application

```bash
# Keep MySQL running
kubectl get all -n test-lab

# Verify MySQL service still available
kubectl get svc mysql -n test-lab
```

---

## Learning Outcomes

### Technical Skills Acquired

- [ ] Understand practical limitations of NodePort services for production use
- [ ] Deploy and configure NGINX Ingress Controller successfully
- [ ] Implement both host-based and path-based routing patterns
- [ ] Configure TLS termination and certificate management
- [ ] Apply systematic troubleshooting methodology for HTTP routing issues

### Ingress Concepts Mastered

- [ ] Ingress Controller vs Ingress Resource relationship
- [ ] HTTP routing precedence and rule evaluation
- [ ] Certificate lifecycle management and renewal procedures
- [ ] Advanced NGINX annotations and configuration patterns
- [ ] Monitoring and operational health validation

### Production Skills Developed

- [ ] Web application exposure architecture design
- [ ] HTTPS security implementation with TLS termination
- [ ] Systematic approach to network troubleshooting
- [ ] Certificate management operational procedures
- [ ] Load balancing validation and performance testing

---

## Next Steps: Advanced Networking

With NGINX Ingress now operational, future modules will build on this foundation:

- **Network Policies**: Implement micro-segmentation and traffic restrictions
- **Service Mesh**: Advanced traffic management with Istio or Linkerd
- **External DNS**: Automatic DNS record management for services
- **Certificate Automation**: Let's Encrypt integration with cert-manager
- **Advanced Load Balancing**: Multi-cluster and cross-region routing patterns

The Ingress controller foundation enables these advanced networking patterns in enterprise Kubernetes environments.

---

**Estimated Completion Time**: 100-130 minutes
**Learning Validation**: Students should be able to explain when to use Ingress over Services, implement HTTPS termination, and troubleshoot HTTP routing issues systematically.
