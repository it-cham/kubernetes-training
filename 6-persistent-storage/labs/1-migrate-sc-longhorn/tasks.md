## Lab: Persistent Storage - Migrate to Longhorn Storage Class

### Scenario

The WordPress application deployed in previous modules is gaining popularity, but the current storage architecture presents significant risks for a production environment.
The application uses local-path storage which creates single points of failure and scaling limitations.

Management has requested an evaluation of distributed storage solutions to improve reliability and enable future scaling requirements.

### Current Application State

WordPress + MySQL deployment from Module 5:

- MySQL uses PersistentVolumeClaim with local-path storage class
- Single replica database deployment
- Configuration managed via ConfigMaps and Secrets
- Storage tied to individual cluster nodes

### Prerequisites

On MacOS and Linux, Rancher Desktop uses a Lima virtual machine where k3s will be installed.
To install any iSCSI storage server or client solution, the `open-iscsi` package is required.

This can be automated during the startup/creation of the virtual machine placing the `override.yaml` configuration file in the following location:

- MacOS: `~/Library/Application Support/rancher-desktop/lima/_config/override.yaml`
- Linux: `~/.local/share/rancher-desktop/lima/_config/override.yaml`

### Your Tasks

1. **Audit current storage configuration** and understand the underlying storage implementation
2. **Validate storage limitations** by testing scaling scenarios and failure conditions
3. **Deploy Longhorn distributed storage** to replace local-path storage
4. **Migrate MySQL storage** from local-path to Longhorn storage class
5. **Verify application functionality** and test improved storage capabilities
6. **Validate distributed storage benefits** through scaling and resilience testing

### Challenge Questions

- Where does the MySQL data actually reside on the cluster nodes?
- What happens when attempting to scale MySQL to multiple replicas with local-path storage?
- How does Longhorn provide distributed storage capabilities on a single-node cluster?
- What are the key differences between local-path and Longhorn storage classes?
- How can distributed storage improve application reliability and availability?
- What storage features become available when migrating from local-path to Longhorn?

### Success Criteria

- [ ] Current storage configuration documented and understood
- [ ] Local-path storage limitations demonstrated through scaling tests
- [ ] Longhorn successfully deployed and operational in the cluster
- [ ] New Longhorn storage class created and configured
- [ ] MySQL storage successfully migrated from local-path to Longhorn
- [ ] WordPress application maintains full functionality after storage migration
- [ ] MySQL scaling now works with multiple replicas using distributed storage
- [ ] Storage replication and distributed features validated
- [ ] Performance and reliability improvements documented
