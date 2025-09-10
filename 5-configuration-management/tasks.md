## Lab: Configuration Management

### Current problems with the existing deployment

Looking at our existing manifests:

- **Security Risk**: Database passwords are visible in plain text in deployment YAML files
- **Configuration Scattered**: Environment variables are hardcoded throughout deployment manifests
- **No Resource Management**: Pods can consume unlimited CPU and memory
- **Maintenance Issues**: Changing configuration requires editing and redeploying manifests

### Your Tasks

1. **Audit your current deployment** and identify all configuration security issues
2. **Create ConfigMaps** for non-sensitive configuration data
3. **Create Kubernetes Secrets** for all sensitive data (passwords, credentials)
4. **Update your deployments** to use externalized configuration instead of hardcoded values
5. **Implement resource requests and limits** for both WordPress and MySQL containers
6. **Test configuration management** by updating settings without changing deployments
7. **Validate security improvements** by ensuring no sensitive data appears in deployment manifests

### Challenge Questions

- What security risks exist in your current deployment?
- How do you identify which configuration should go in Secrets vs ConfigMaps?
- What's the difference between using `env` and `envFrom` when consuming ConfigMaps?
- What happens when a pod exceeds its memory limit vs CPU limit?
- How do resource requests and limits affect pod scheduling and performance?

### Success Criteria

- [ ] Non-sensitive configuration externalized to ConfigMaps
- [ ] All sensitive data (passwords) moved from deployment manifests to Secrets
- [ ] WordPress and MySQL deployments updated to use ConfigMaps and Secrets
- [ ] All containers have appropriate resource requests and limits defined
- [ ] Application functionality identical to Module 4 (WordPress installation works)
- [ ] Configuration can be updated without modifying deployment manifests
- [ ] No plaintext passwords visible anywhere in Kubernetes manifests
- [ ] WordPress connects successfully to MySQL using Secret-stored credentials
- [ ] Pods have predictable resource usage and Quality of Service classes
- [ ] Application survives configuration updates and pod restarts with data persistence
