# Lab: Multi-Team Access Control with RBAC

## Scenario

Your company is consolidating three development teams onto a shared Kubernetes cluster.
The current setup has a critical security flaw: everyone uses the same admin kubeconfig file with full cluster-admin privileges.

The security audit identified these violations:

- All developers have cluster-admin access
- No namespace isolation between teams
- No audit trail of who performed which actions
- Production and development environments share permissions
- Violates principle of least privilege
- Cannot comply with security certifications (SOC2, ISO 27001)

Management has mandated immediate implementation of proper role-based access control:

**Team Requirements:**

1. **Frontend Team**: Full management of their microservices in `frontend` namespace only
2. **Backend Team**: Full management of their APIs and databases in `backend` namespace only
3. **Monitoring Team**: Read-only access to view pods and logs across all namespaces
4. **Platform Team**: Elevated permissions to manage cluster infrastructure without full admin access

Your mission: Implement certificate-based authentication with proper RBAC for each team, ensuring complete namespace isolation while enabling necessary cross-team visibility.

---

## Prerequisites

- k3s cluster with cluster-admin kubeconfig access
- kubectl configured and operational
- OpenSSL installed for certificate generation
- Understanding of basic Kubernetes objects (pods, deployments, services)
- Completed Module 9 Sessions 1 & 2 (Network Policies, Pod Security Standards)

---

## Your Tasks

### Phase 1: Environment Setup and Current State Analysis (10-15 minutes)

**Objective:** Establish baseline environment and understand current permission landscape

1. **Create namespace structure:**
   - Create three namespaces: `frontend`, `backend`, `monitoring`

2. **Deploy sample applications:**
   - Deploy demo application in `frontend` namespace
   - Deploy demo application in `backend` namespace
   - Verify both applications are running successfully

3. **Analyze current access:**
   - List/Document all resources you can view and modify
   - Understand the baseline for comparison

**Challenge Questions:**

- What command shows you all permissions your current user has?
- Can you access resources in all namespaces with your current kubeconfig?
- What would happen if you gave this kubeconfig to a junior developer?
- How do you verify if a specific user can perform an action?

---

### Phase 2: Frontend Team - Certificate-Based Authentication (20-25 minutes)

**Objective:** Learn Kubernetes certificate-based authentication workflow

1. **Generate private key and Certificate Signing Request (CSR):**
   - Create private key for frontend user
   - Generate CSR with appropriate CN (Common Name) and O (Organization)
   - Understand what CN and O represent in Kubernetes

2. **Submit CSR to Kubernetes:**
   - Create CertificateSigningRequest object in Kubernetes
   - Use appropriate signer for client authentication
   - Submit the CSR for approval

3. **Approve CSR and extract certificate:**
   - Approve the pending CSR
   - Extract the signed certificate from Kubernetes
   - Save certificate to file for kubeconfig creation

4. **Build kubeconfig file:**
   - Add cluster information (server URL, CA certificate)
   - Add user credentials (client certificate and key)
   - Create context linking cluster and user
   - Set the new context as current

5. **Test authentication:**
   - Try accessing cluster resources with new kubeconfig
   - Verify authentication works (even if authorization fails)
   - Understand the difference between authentication and authorization

**Challenge Questions:**

- What does the CN (Common Name) field in the certificate become in Kubernetes?
- What does the O (Organization) field in the certificate become in Kubernetes?
- Why does `kubectl get pods` fail even though your certificate is valid?
- How does Kubernetes trust your certificate?
- What information does Kubernetes extract from your certificate for identity?

---

### Phase 3: Frontend Team - RBAC Configuration (15-20 minutes)

**Objective:** Create Role and RoleBinding to grant namespace-specific permissions

1. **Create Role for developers:**
   - Define permissions for pods, deployments, services, replicasets
   - Include verbs: get, list, watch, create, update, patch, delete
   - Add permissions for pods/log and pods/exec (debugging)
   - Scope to `frontend` namespace only

2. **Create RoleBinding:**
   - Bind the Role to a Group (not individual user)
   - Use the group from certificate's O field
   - Verify binding is in correct namespace

3. **Test permissions systematically:**
   - Test allowed operations in frontend namespace
   - Test that operations in backend namespace are denied
   - Test that cluster-level operations are denied
   - Use kubectl auth can-i for validation

4. **Verify namespace isolation:**
   - Attempt to access resources in other namespaces
   - Confirm access is properly restricted
   - Document permission boundaries

**Challenge Questions:**

- Why bind the Role to a Group instead of a specific User?
- What happens if you create another certificate with the same O field?
- Can the frontend user delete the frontend namespace itself?
- What's the difference between a Role and a ClusterRole?
- How would you grant permission to view resources but not modify them?

---

### Phase 4: Backend Team - Rapid Implementation (10-15 minutes)

**Objective:** Apply learned workflow to create second team's access

1. **Create backend team authentication:**
   - Generate certificate with appropriate CN and O for backend team
   - Follow the same CSR workflow
   - Create kubeconfig for backend user

2. **Implement backend team RBAC:**
   - Create similar permissions as frontend team
   - Scope to `backend` namespace
   - Consider: Create ClusterRole that both teams can use?

3. **Test cross-namespace isolation:**
   - Verify backend user can access backend namespace
   - Verify backend user CANNOT access frontend namespace
   - Confirm complete namespace isolation between teams

**Challenge Questions:**

- Could you create one ClusterRole and reuse it for both teams? How?
- What's the advantage of ClusterRole + RoleBinding over Role + RoleBinding?
- How does this RBAC approach scale to 10 or 20 development teams?
- What permissions do both teams have in common?

---

### Phase 5: Monitoring Team - Cross-Namespace Read-Only Access (15-20 minutes)

**Objective:** Implement cluster-wide read access using ClusterRole and ClusterRoleBinding

1. **Generate monitoring team certificate:**
   - Create certificate with appropriate identity for monitoring team
   - Build kubeconfig for monitoring user

2. **Create ClusterRole for read-only access:**
   - Define permissions to view pods, services, deployments across all namespaces
   - Include pods/log permission for log viewing
   - Explicitly exclude secrets and configmaps (sensitive data)
   - Make it cluster-scoped, not namespace-scoped

3. **Create ClusterRoleBinding:**
   - Bind ClusterRole to monitoring team group
   - Verify it grants cluster-wide access

4. **Test cross-namespace read access:**
   - View resources in frontend namespace
   - View resources in backend namespace
   - View resources in monitoring namespace
   - Access pod logs across namespaces
   - Attempt write operations (should fail)
   - Attempt to access secrets (should fail)

5. **Validate read-only enforcement:**
   - Try to create, update, or delete resources
   - Try to access sensitive resources like secrets
   - Confirm monitoring team cannot modify anything

**Challenge Questions:**

- Why use ClusterRole + ClusterRoleBinding instead of multiple Roles?
- What's the security risk of allowing monitoring team to view secrets?
- How would you give monitoring access to only frontend and backend namespaces, not all?
- Could monitoring team view secrets if they had access to pods/exec? Why?
- What built-in ClusterRole provides similar read-only access?

---

### Phase 6: Platform Team - Elevated But Limited Access (15-20 minutes)

**Objective:** Create elevated operational permissions without granting cluster-admin

1. **Generate platform team certificate:**
   - Create certificate with platform team identity
   - Build kubeconfig

2. **Design platform team permissions:**
   - Cluster-level resources: nodes (read-only), namespaces (full management)
   - PersistentVolumes and StorageClasses (full management)
   - Full access to monitoring namespace
   - NO access to secrets in application namespaces (frontend, backend)

3. **Implement multi-level RBAC:**
   - Create ClusterRole for cluster-scoped resources
   - Create ClusterRoleBinding for cluster access
   - Create RoleBinding in monitoring namespace for full access
   - Consider: Should platform team see all namespaces?

4. **Test platform operations:**
   - Create and delete namespaces
   - View node information
   - Manage PersistentVolumes
   - Full operations in monitoring namespace
   - Attempt to access frontend secrets (should fail)
   - Attempt to modify RBAC in application namespaces (should fail)

5. **Verify security boundaries:**
   - Confirm platform team does NOT have cluster-admin
   - Verify they cannot access application secrets
   - Document what they can and cannot do

**Challenge Questions:**

- Why not just give platform team cluster-admin?
- What's the principle of least privilege and how does this apply here?
- How would you handle emergency "break-glass" scenarios?
- What additional permissions might platform team need for cluster upgrades?
- How do you balance operational needs with security restrictions?

---

### Phase 7: Validation and Permission Testing (10-15 minutes)

**Objective:** Systematically validate all RBAC configurations

1. **Create permission matrix:**
   - Document what each team can do in each namespace
   - Document what each team can do at cluster level
   - Identify any permission gaps or overlaps

2. **Test each permission boundary:**
   - Use kubectl auth can-i for each team/resource combination
   - Try operations that should be allowed
   - Try operations that should be denied
   - Verify logs and secrets are properly protected

3. **Test operational scenarios:**
   - Frontend developer deploys application in frontend namespace
   - Frontend developer tries to deploy in backend namespace (should fail)
   - Monitoring team views logs across all namespaces
   - Platform team creates new namespace
   - Platform team cannot view frontend team's secrets

4. **Verify security goals achieved:**
   - Namespace isolation between frontend and backend teams
   - Read-only monitoring access across namespaces
   - Platform team has elevated but not superuser access
   - No team has unnecessary permissions
   - All actions can be audited by user identity

**Challenge Questions:**

- How do you test permissions without actually performing risky operations?
- What's the difference between testing with --as flag vs actual kubeconfig?
- How would you audit who performed a specific action in the cluster?
- What happens if someone's certificate is compromised?
- How do you revoke access for a user?

---

## Success Criteria

- [ ] Three namespaces created with sample applications
- [ ] Frontend team has full access to frontend namespace only
- [ ] Backend team has full access to backend namespace only
- [ ] Monitoring team has read-only access to all namespaces
- [ ] Platform team has elevated access without cluster-admin
- [ ] Complete namespace isolation verified between teams
- [ ] Certificate-based authentication working for all teams
- [ ] Kubeconfig files created for all four teams
- [ ] All Roles and ClusterRoles properly scoped
- [ ] All RoleBindings and ClusterRoleBindings correctly configured
- [ ] kubectl auth can-i validates all expected permissions
- [ ] Security boundaries tested and confirmed
- [ ] No team has excessive permissions
- [ ] Permission matrix documented

---

## Expected Timeline

- Phase 1 (Environment Setup): 10-15 minutes
- Phase 2 (Frontend Authentication): 20-25 minutes
- Phase 3 (Frontend RBAC): 15-20 minutes
- Phase 4 (Backend Implementation): 10-15 minutes
- Phase 5 (Monitoring Cross-Namespace): 15-20 minutes
- Phase 6 (Platform Elevated Access): 15-20 minutes
- Phase 7 (Validation): 10-15 minutes

**Total:** 75-90 minutes (can extend to 105-120 with deeper exploration)

---

## Hints and Tips

**Certificate Generation:**

- CN (Common Name) becomes the username in Kubernetes
- O (Organization) becomes the group membership
- You can have multiple O fields for multiple groups
- Use descriptive names: CN=jane, O=frontend-team

**CSR Workflow:**

- CertificateSigningRequest is a Kubernetes object
- Must be approved by cluster admin before certificate is issued
- Use signer: kubernetes.io/kube-apiserver-client
- Certificate is base64 encoded in status.certificate field

**Role vs ClusterRole:**

- Role: Permissions in a specific namespace
- ClusterRole: Permissions cluster-wide OR reusable definition
- ClusterRole + RoleBinding = namespace-scoped permissions from reusable role
- ClusterRole + ClusterRoleBinding = cluster-wide permissions

**Common Issues:**

- Forgetting apiGroups: deployments are in "apps", not ""
- Using wrong namespace in RoleBinding
- Certificate CN/O not matching RoleBinding subjects
- Kubeconfig pointing to wrong cluster or context

**Testing:**

- kubectl auth can-i [verb] [resource] --as=[user] -n [namespace]
- kubectl auth can-i --list -n [namespace] --as=[user]
- Test both positive (should work) and negative (should fail) cases

---

## Advanced Challenges (Optional)

If you complete the main tasks early:

1. **Certificate Rotation:**
   - Generate new certificate for existing user
   - Update kubeconfig
   - Consider: How to revoke old certificate?

2. **Aggregated ClusterRoles:**
   - Create base ClusterRole with label
   - Create aggregated ClusterRole that combines multiple roles
   - Test inheritance behavior

3. **Resource-Specific Permissions:**
   - Grant access to specific named resources only
   - Use resourceNames field in Role rules
   - Test specificity of permissions

4. **ServiceAccount Integration:**
   - Create ServiceAccount for automated process
   - Grant it minimal required permissions
   - Generate kubeconfig using ServiceAccount token

5. **Audit and Compliance:**
   - Review audit logs for RBAC events
   - Document who can approve CSRs
   - Create procedure for access reviews

---

## Connection to OpenShift

The RBAC skills learned here directly apply to OpenShift:

- Same Role, ClusterRole, RoleBinding, ClusterRoleBinding API
- Certificate-based authentication works identically
- Main differences in OpenShift:
  - Projects add additional RBAC layer on top of namespaces
  - OAuth server handles authentication (vs external)
  - Additional built-in roles
  - Web console for easier RBAC management
  - SCC (Security Context Constraints) interact with RBAC

Students who master k3s RBAC will find OpenShift RBAC familiar.

---

**Note:** This lab teaches production-ready RBAC patterns. Take time to understand the authentication and authorization flow rather than rushing through the certificate generation steps. The certificate workflow is industry-standard and applies beyond Kubernetes.
