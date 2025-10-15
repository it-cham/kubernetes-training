# Lab: High-Availability k3s Cluster with Load Balancing

## Scenario

The single-node k3s setup on Rancher Desktop or on a development server served well for learning, but production workloads require true high availability.

The infrastructure for a multi-node cluster expects:

- Corporate DNS integration
- Zero downtime during planned maintenance
- Automatic failover during node failures
- Load-balanced API and application traffic
- Scalable architecture for future growth

## Infrastructure Overview

You have been provisioned the following infrastructure:

### Control Plane Nodes (3x)

- `lx-k3s-server-01`: 192.168.168.111
- `lx-k3s-server-02`: 192.168.168.112
- `lx-k3s-server-03`: 192.168.168.113

### Worker Nodes (2x)

- `lx-k3s-agent-01`: 192.168.168.121
- `lx-k3s-agent-02`: 192.168.168.122

### Network Configuration

- DNS domain: `k3s.test.local`
- Wildcard DNS: `*.k3s.test.local` → 192.168.168.100
- Virtual IP (VIP) for cluster access: 192.168.168.100

### External Services

- DNS server (Bind9) available
- Firewall/gateway configured for internal access

## Architecture Requirements

### High Availability Stack

Each control plane node must run:

1. **Keepalived** - VRRP protocol for virtual IP management
2. **HAProxy** - Load balancer for Kubernetes API and Ingress traffic
3. **k3s server** - Kubernetes control plane in clustered mode

### Load Balancing Strategy

HAProxy must provide load balancing for:

- **Kubernetes API:** Port 6443 → HAProxy port 8443 (accessed via VIP)
- **HTTP Ingress:** Port 30080 → HAProxy port 80
- **HTTPS Ingress:** Port 30443 → HAProxy port 443

### Cluster Access Pattern

```plaintext
User/Application
    ↓
DNS Resolution (k3s.test.local → 192.168.168.100)
    ↓
Virtual IP (Keepalived VRRP)
    ↓
HAProxy Load Balancer
    ↓
Kubernetes API / Ingress Controllers
    ↓
Services & Applications
```

## Prerequisites

### Infrastructure Access

- SSH access to all 5 Linux nodes (Ubuntu/Debian)
- Root or sudo privileges on all nodes
- Nodes can communicate with each other
- DNS server accessible for configuration

### Knowledge Requirements

- Completed Modules 1-7 (including Ingress concepts)
- Understanding of Linux system administration
- Familiarity with load balancing concepts
- Basic networking knowledge (VIP, DNS, routing)

### Tools Required

- kubectl configured for cluster access
- Helm (for NGINX Ingress Controller installation)
- openssl for certificate generation
- Text editor for configuration files

## Your Tasks

### Phase 1: High Availability Infrastructure Setup

Configure Keepalived for virtual IP management

- Install and configure Keepalived on all control plane nodes
- Implement VRRP for floating IP (192.168.168.100)
- Configure proper priority and authentication
- Test VIP failover between control plane nodes

Deploy HAProxy for load balancing

- Install HAProxy on all control plane nodes
- Configure load balancing for Kubernetes API (port 8443)
- Configure load balancing for HTTP/HTTPS Ingress traffic
- Implement health checks for backend servers
- Validate load balancer functionality

### Phase 2: Kubernetes Cluster Deployment

Initialize multi-master k3s cluster

- Deploy first control plane node with cluster initialization
- Add TLS SAN for virtual IP address
- Disable default Traefik ingress controller
- Verify first control plane is operational

Join additional control plane nodes

- Add second and third control plane nodes to cluster
- Verify etcd cluster formation and health
- Validate multi-master API availability through HAProxy

Add worker nodes to cluster

- Join both worker nodes as agents
- Verify node status and readiness
- Validate cluster topology

### Phase 3: DNS Integration

Configure DNS zones

- Create forward zone for `k3s.test.local`
- Configure A records for all nodes
- Implement wildcard record pointing to VIP
- Create reverse DNS zone
- Test DNS resolution from client machines

### Phase 4: Ingress Controller Deployment

Deploy NGINX Ingress Controller

- Install NGINX Ingress Controller using Helm
- Configure as DaemonSet for all control plane nodes
- Use NodePort service type (ports 30080/30443)
- Apply node selectors and tolerations for control plane placement
- Set as default IngressClass

### Phase 5: Application Deployment and Validation

Deploy test application with Ingress

- Deploy NGINX application with resource limits
- Create ClusterIP service
- Generate TLS certificate for `nginx.k3s.test.local`
- Create Ingress resource with TLS termination
- Verify application accessibility via DNS

Validate high availability

- Test API access through virtual IP
- Verify application access through HAProxy load balancer
- Test control plane node failure scenarios
- Validate automatic VIP failover
- Document recovery behavior

## Challenge Questions

### Architecture Understanding

- Why is a virtual IP necessary instead of accessing control plane nodes directly?
- How does Keepalived determine which node should hold the virtual IP?
- What happens to the virtual IP when the master node fails?
- Why run HAProxy on all control plane nodes instead of dedicated load balancer nodes?

### Load Balancing Strategy

- Why does HAProxy listen on port 8443 instead of 6443 for the Kubernetes API?
- How does HAProxy distribute traffic across multiple control plane nodes?
- What are the health check mechanisms ensuring traffic goes only to healthy backends?
- Why use NodePort for Ingress instead of LoadBalancer service type?

### Kubernetes Cluster Architecture

- What is the role of `--cluster-init` in the first control plane node?
- Why is `--tls-san` necessary when using a virtual IP for cluster access?
- How do additional control plane nodes discover and join the etcd cluster?
- What data is stored in etcd and why is it critical for cluster operation?

### DNS Integration

- Why use wildcard DNS (`*.k3s.test.local`) for Ingress routing?
- How does DNS resolution work for application hostnames?
- What is the purpose of reverse DNS zones?
- How would you configure DNS for multiple clusters?

### High Availability Validation

- How do you verify that etcd is running in a healthy clustered state?
- What tools can monitor the Keepalived VRRP state?
- How do you test failover without causing actual production impact?
- What metrics indicate proper load distribution across control plane nodes?

### Operational Considerations

- How would you perform maintenance on a control plane node without downtime?
- What backup strategy would you implement for this cluster?
- How would you scale worker nodes horizontally?
- What monitoring should be implemented for production readiness?

## Success Criteria

### Infrastructure Components

- [ ] Keepalived running on all 3 control plane nodes with VRRP configured
- [ ] Virtual IP (192.168.168.100) accessible and responds to ping
- [ ] HAProxy running on all 3 control plane nodes
- [ ] HAProxy statistics page accessible and showing backend health
- [ ] VIP automatically fails over when master Keepalived node stops

### Kubernetes Cluster

- [ ] 3 control plane nodes in Ready state
- [ ] 2 worker nodes in Ready state
- [ ] etcd cluster shows 3 healthy members
- [ ] kubectl commands work through virtual IP address (192.168.168.100:8443)
- [ ] All cluster nodes show correct roles (control-plane vs worker)

### DNS Configuration

- [ ] Forward DNS zone operational for `k3s.test.local`
- [ ] All node A records resolve correctly
- [ ] Wildcard DNS (`*.k3s.test.local`) resolves to VIP
- [ ] Reverse DNS lookups function properly
- [ ] DNS queries from client machines return correct results

### Ingress and Application

- [ ] NGINX Ingress Controller pods running on all 3 control plane nodes
- [ ] Ingress Controller set as default IngressClass
- [ ] Test NGINX application deployed and running
- [ ] HTTPS access to `nginx.k3s.test.local` works via browser
- [ ] TLS certificate validates correctly
- [ ] Application remains accessible when control plane node is stopped

### High Availability Testing

- [ ] Stopping one control plane node does not affect cluster operations
- [ ] VIP migrates to another control plane node within seconds
- [ ] Applications remain accessible during control plane node failure
- [ ] kubectl commands continue to work during failover
- [ ] HAProxy automatically removes failed backends from rotation

### Load Balancing

- [ ] HAProxy distributes API requests across all control plane nodes
- [ ] HAProxy distributes Ingress traffic across all Ingress Controller pods
- [ ] Health checks detect and remove unhealthy backends
- [ ] Traffic automatically rebalances when nodes recover

## Validation Procedures

### Test Virtual IP Failover

1. Identify which control plane node currently holds the VIP
2. Stop Keepalived service on that node
3. Verify VIP migrates to another control plane node
4. Confirm applications remain accessible throughout failover
5. Restart Keepalived and document recovery behavior

### Test API High Availability

1. Create a simple pod using kubectl
2. Stop the control plane node currently handling API requests
3. Execute kubectl commands and verify they still work
4. Check that HAProxy routed requests to healthy control plane nodes

### Test Application High Availability

1. Access application through browser at `nginx.k3s.test.local`
2. Stop one control plane node running Ingress Controller
3. Refresh browser and verify application remains accessible
4. Monitor HAProxy backend status during failure

## Documentation Requirements

Create documentation covering:

- Complete network topology diagram
- Keepalived configuration and VRRP explanation
- HAProxy backend pool configuration
- k3s cluster bootstrap procedure
- DNS zone configuration details
- Failover testing results and observations
- Troubleshooting procedures for common issues

## Time Estimate

- Infrastructure Setup: 45-60 minutes
- Cluster Deployment: 30-45 minutes
- DNS Configuration: 20-30 minutes
- Ingress Setup: 30-40 minutes
- Testing and Validation: 30-45 minutes
- Total: 2.5-3.5 hours

## Important Notes

- This lab requires actual infrastructure (VMs or physical servers) - cannot be completed on Rancher Desktop
- Virtual IP must be in the same subnet as control plane nodes
- Firewall rules may need adjustment for VRRP (protocol 112) and HAProxy health checks
- Token security is critical - use strong random tokens for production
- Configuration files should be backed up before modifications
- Document all changes for team knowledge sharing

## Next Steps After Completion

With a functioning HA cluster, you'll be prepared for:

- Implementing monitoring and alerting (Prometheus/Grafana)
- Configuring automatic certificate management (cert-manager)
- Deploying production applications with StatefulSets
- Implementing backup and disaster recovery procedures
- Exploring advanced networking (Network Policies, Service Mesh)
- Migrating to enterprise Kubernetes platforms (OpenShift)
