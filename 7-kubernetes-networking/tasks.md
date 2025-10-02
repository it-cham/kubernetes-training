## Lab: Advanced Networking and Service Exposure

### Scenario

The MySQL database from previous modules is operational with Longhorn storage, and the team needs to deploy a web-based database management interface. Management requires proper domain names and HTTPS for the administrative interface.

Current Service-based exposure with NodePort creates challenges for production deployment, including non-standard ports and lack of HTTPS support.

### Current Application State

MySQL deployment in `test-lab` namespace:

- MySQL deployment with Longhorn persistent storage
- Configuration managed via ConfigMaps and Secrets
- Services currently using basic exposure patterns

### Prerequisites

- Working MySQL application from previous modules
- k3s cluster with Rancher Desktop
- Basic understanding of Service types and DNS resolution
- Access to create cluster-wide resources (Ingress controllers)

### Your Tasks

1. **Evaluate current Service exposure limitations** by documenting the challenges of NodePort-based access patterns
2. **Deploy NGINX Ingress Controller** to provide HTTP-aware routing capabilities
3. **Deploy phpMyAdmin** as a database management interface
4. **Implement basic HTTP routing** by creating Ingress-based routing for phpMyAdmin
5. **Implement TLS termination** to provide HTTPS access
6. **Test advanced routing patterns** including path-based routing and multiple hostname configurations
7. **Validate operational procedures** for certificate management and troubleshooting

### Challenge Questions

- What limitations do NodePort services create for production web application deployment?
- How does an Ingress controller differ from a basic Kubernetes Service in terms of capabilities?
- What advantages does centralized HTTP routing provide over multiple individual services?
- How does TLS termination at the Ingress layer impact application architecture?
- What routing patterns can be implemented using a single Ingress controller for one application?
- How can you troubleshoot connectivity issues when requests flow through Ingress → Service → Pod?

### Success Criteria

- [ ] Current Service limitations documented and demonstrated
- [ ] NGINX Ingress Controller successfully deployed and operational
- [ ] phpMyAdmin deployed and accessible via proper hostname routing
- [ ] Application secured with HTTPS using TLS termination
- [ ] Multiple routing patterns tested (different hostnames, path-based routing)
- [ ] Certificate management and renewal procedures validated
- [ ] Systematic troubleshooting methodology applied to resolve routing issues
- [ ] Load balancing behavior verified across multiple application replicas
- [ ] Ingress controller monitoring and operational health confirmed

### Learning Validation

Upon completion, you should be able to explain the architectural benefits of Ingress controllers over basic Services, demonstrate TLS certificate management, and troubleshoot common HTTP routing issues in a systematic manner.

The lab builds practical skills for implementing production-ready web application exposure patterns using industry-standard tools.
