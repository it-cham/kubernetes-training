# Lab: Pod Security Standards & Container Hardening

## Scenario

Your company has a TomEE-based web application that displays client request information (source IP and container IP). This application was developed using standard practices but without security considerations.

Management has mandated that all applications must meet enterprise security standards before deployment to production OpenShift environment.

The security team has identified multiple vulnerabilities in the current deployment:

- Application runs as root user
- Full filesystem write access
- No security policies enforced
- Image contains unnecessary tools and packages
- Does not run on OpenShift

Your mission: Transform this insecure application into a production-ready, hardened workload that runs successfully in "regular" and OpenShift environments.

---

## Prerequisites

- k3s cluster with kubectl access
- OpenShift cluster with CLI access
- Docker or Podman for image building
- Access to image registry

---

## Your Tasks

### Phase 1: Security Analysis on k3s (15-20 minutes)

**Objective:** Understand the current security posture and identify vulnerabilities

1. **Deploy the insecure application** to k3s in the `sticky-session-secure` namespace
   - Create deployment using existing image
   - Expose application via NodePort service
   - Verify application functionality

2. **Analyze security posture:**
   - Identify which user the container runs as
   - Check filesystem permissions inside container
   - Document running processes and their privileges
   - Examine available Linux capabilities

3. **Enable Pod Security Standards:**
   - Apply PSS labels to namespace (audit and warn mode only)
   - Deploy application again and review warnings
   - Document all policy violations

**Challenge Questions:**

- What user ID (UID) is the application running as?
- What are the security implications of running as this user?
- How many Pod Security Standard violations are detected?
- Which directories does TomEE need to write to during operation?

---

### Phase 2: Apply Security Contexts on k3s (20-25 minutes)

**Objective:** Learn what breaks when security is enforced

1. **Add basic security context:**
   - Set `runAsUser: 1001`
   - Deploy and observe what breaks

2. **Identify writable directory requirements:**
   - Check container logs for permission errors
   - Exec into container and test which directories need write access
   - Document all required writable paths

3. **Add volume mounts for writable directories:**
   - Create emptyDir volumes for required paths
   - Mount volumes in deployment
   - Test application startup

4. **Apply full security context:**
   - `runAsNonRoot: true`
   - `readOnlyRootFilesystem: true`
   - `allowPrivilegeEscalation: false`
   - Drop all capabilities
   - Add seccomp profile

**Challenge Questions:**

- Why does the application fail with `runAsUser: 1001`?
- Which TomEE directories require write access and why?
- Can you make the application work with current image + security contexts alone?
- What is the fundamental problem that prevents full hardening?

**Expected Outcome:** Application cannot fully start with restrictive security contexts due to file ownership issues in the image

---

### Phase 3: Dockerfile Hardening (30-40 minutes)

**Objective:** Rebuild the container image to support security requirements

1. **Create hardened Dockerfile:**
   - Create non-root user (UID 1001, username: tomee)
   - Install required tools, then remove package manager cache
   - Set proper file ownership for TomEE directories
   - Configure group permissions (prepare for OpenShift arbitrary UIDs)
   - Switch to non-root user
   - Consider multi-stage build if beneficial

2. **Build and push hardened image:**
   - Build image locally: `stickysessions:0.1.X`
   - Tag for company registry
   - Push to registry: `registry.company.local/stickysessions:0.1.X`

3. **Deploy hardened image with security contexts:**
   - Update deployment to use new image
   - Apply all security context settings
   - Test application functionality thoroughly

**Challenge Questions:**

- Which directories need ownership changes?
- Why set group permissions (chmod g+rwx) in addition to user permissions?
- Should you install unzip as root and then switch users, or vice versa?
- How can you minimize the final image size?

---

### Phase 4: Pod Security Standards Enforcement (15-20 minutes)

**Objective:** Validate compliance with Restricted policy

1. **Review current PSS violations:**
   - Check audit logs in namespace
   - Document remaining violations

2. **Fix remaining violations:**
   - Update security contexts as needed
   - Ensure all Restricted policy requirements met

3. **Enable enforcement:**
   - Change namespace labels from warn/audit to enforce: restricted
   - Redeploy application
   - Verify successful deployment

4. **Validation:**
   - Test application functionality
   - Verify all security settings active
   - Document security improvements

**Challenge Questions:**

- What is the difference between Baseline and Restricted policies?
- Can you deploy a privileged pod in this namespace now?
- What happens if you try to deploy the original insecure image?

---

### Phase 5: OpenShift Migration (25-30 minutes)

**Objective:** Deploy to OpenShift and handle platform-specific requirements

1. **Initial OpenShift deployment:**
   - Create OpenShift project (tutor will demonstrate)
   - Deploy using same manifests from k3s
   - Observe any failures or warnings

2. **Handle OpenShift Security Context Constraints (SCC):**
   - Identify which SCC is being applied
   - Understand arbitrary UID assignment
   - Check file permission issues

3. **Adjust Dockerfile for OpenShift compatibility:**
   - Modify ownership to support arbitrary UIDs (root:0 with group permissions)
   - Rebuild and push: `registry.company.local/stickysessions:0.1.X`

4. **Update Kubernetes manifests:**
   - Add `fsGroup` to pod security context
   - Remove explicit `runAsUser` (let OpenShift assign)
   - Ensure `runAsNonRoot: true` is set

5. **Successful deployment:**
   - Deploy updated image and manifests
   - Verify application works on OpenShift
   - Test functionality

**Challenge Questions:**

- What UID does OpenShift assign to your container?
- Why does OpenShift use arbitrary UIDs instead of fixed UIDs?
- How is OpenShift SCC different from Kubernetes PSS?
- What changes were necessary between k3s and OpenShift?

---

### Phase 6: Validation & Documentation (10-15 minutes)

**Objective:** Compare before/after and document improvements

1. **Security comparison:**
   - Compare insecure vs hardened deployments side-by-side
   - Document security improvements achieved
   - List remaining security considerations

2. **Cross-platform validation:**
   - Verify application works on both k3s and OpenShift
   - Document platform-specific differences
   - Note any behavioral differences

3. **Lessons learned:**
   - What were the biggest challenges?
   - What would you do differently next time?
   - How would you apply this to other applications?

---

## Success Criteria

- [ ] Insecure application deployed and analyzed on k3s
- [ ] Security vulnerabilities identified and documented
- [ ] Pod Security Standard violations understood
- [ ] Security contexts applied progressively on k3s
- [ ] Writable directory requirements identified
- [ ] Dockerfile hardened with non-root user and proper permissions
- [ ] Hardened image successfully runs with Restricted PSS on k3s
- [ ] Application migrated to OpenShift successfully
- [ ] OpenShift-specific adjustments implemented and understood
- [ ] Application functions correctly in both environments
- [ ] Security improvements documented and validated
- [ ] Understanding of k3s vs OpenShift security differences

---

## Expected Timeline

- Phase 1 (k3s Analysis): 15-20 minutes
- Phase 2 (Security Contexts): 20-25 minutes
- Phase 3 (Dockerfile Hardening): 30-40 minutes
- Phase 4 (PSS Enforcement): 15-20 minutes
- Phase 5 (OpenShift Migration): 25-30 minutes
- Phase 6 (Validation): 10-15 minutes

**Total:** 115-150 minutes (approximately 2-2.5 hours)

---

## Hints and Tips

**TomEE Writable Directories:**

- TomEE typically needs write access to: logs, temp, work, and potentially webapps
- Default location: `/usr/local/tomee/`

**Dockerfile Best Practices:**

- Create user early, but install tools as root
- Clean up package manager cache after installations
- Use `--chown` flag with COPY commands
- Set both user (u+rwx) and group (g+rwx) permissions for OpenShift

**OpenShift Compatibility:**

- Files should be owned by root:0 (not user:user)
- Directories need group write permissions
- Don't hardcode UID in deployment (let OpenShift assign)
- Always set fsGroup for volume permissions

**Troubleshooting:**

- Use `kubectl logs` to see permission errors
- Use `kubectl exec` to inspect running container
- Check `kubectl describe pod` for security context rejections
- Review namespace events for policy violations

---

## Advanced Challenges (Optional)

If you complete the main tasks early:

1. **Minimize image size:**
   - Implement multi-stage build
   - Remove unnecessary files
   - Compare image sizes before/after

2. **Vulnerability scanning:**
   - Scan insecure image with Trivy
   - Scan hardened image
   - Compare vulnerability counts

3. **Resource optimization:**
   - Add appropriate resource requests and limits
   - Test under load
   - Optimize for production

4. **Additional security:**
   - Implement network policies
   - Add liveness and readiness probes
   - Configure pod disruption budgets

---

**Note:** This lab prepares you for real-world enterprise security requirements and OpenShift deployments. Take time to understand each phase rather than rushing through.
