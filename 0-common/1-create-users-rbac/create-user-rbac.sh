#!/bin/bash
# create-user-rbac.sh
# Purpose: Create RBAC configuration for a user

set -e

# Default values
USER=""
NAMESPACE=""
OUTPUT_DIR="./rbac"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --user)
            USER="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 --user <username> [OPTIONS]"
            echo ""
            echo "Required Options:"
            echo "  --user         Username for RBAC configuration"
            echo ""
            echo "Optional:"
            echo "  --namespace    User namespace (default: user-<username>)"
            echo "  --output-dir   Directory for RBAC YAML files (default: ./rbac)"
            echo "  -h, --help     Show this help message"
            echo ""
            echo "Example:"
            echo "  $0 --user alice"
            echo "  $0 --user bob --namespace development --output-dir ./manifests"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

# Validate required arguments
if [ -z "$USER" ]; then
    echo "ERROR: --user parameter is required"
    echo "Use -h or --help for usage information"
    exit 1
fi

# Set default namespace if not provided
if [ -z "$NAMESPACE" ]; then
    NAMESPACE="user-${USER}"
fi

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

echo "Creating RBAC configuration for user: ${USER}"
echo "Namespace: ${NAMESPACE}"
echo "Output directory: ${OUTPUT_DIR}"
echo "================================================"

# Step 1: Create namespace
echo "1. Creating namespace..."
NAMESPACE_FILE="${OUTPUT_DIR}/${USER}-namespace.yaml"
cat <<EOF > "${NAMESPACE_FILE}"
apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
EOF

if kubectl get namespace "${NAMESPACE}" &>/dev/null; then
    echo "Namespace '${NAMESPACE}' already exists"
else
    kubectl apply -f "${NAMESPACE_FILE}"
    echo "Namespace created: ${NAMESPACE}"
fi

# Step 2: Create role for full namespace access
echo ""
echo "2. Creating role for namespace access..."
ROLE_FILE="${OUTPUT_DIR}/${USER}-role.yaml"
cat <<EOF > "${ROLE_FILE}"
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: ${NAMESPACE}
  name: ${USER}-full-access
rules:
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["*"]
EOF

kubectl apply -f "${ROLE_FILE}"
echo "Role created: ${USER}-full-access"

# Step 3: Create rolebinding
echo ""
echo "3. Creating rolebinding..."
ROLEBINDING_FILE="${OUTPUT_DIR}/${USER}-rolebinding.yaml"
cat <<EOF > "${ROLEBINDING_FILE}"
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${USER}-binding
  namespace: ${NAMESPACE}
subjects:
- kind: User
  name: ${USER}
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: ${USER}-full-access
  apiGroup: rbac.authorization.k8s.io
EOF

kubectl apply -f "${ROLEBINDING_FILE}"
echo "RoleBinding created: ${USER}-binding"

# Step 4: Create ClusterRole for namespace listing (only once)
echo ""
echo "4. Creating ClusterRole for namespace listing..."
CLUSTERROLE_FILE="${OUTPUT_DIR}/list-namespace-clusterrole.yaml"
cat <<EOF > "${CLUSTERROLE_FILE}"
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: list-namespace
rules:
- apiGroups: [""]
  resources: ["namespaces"]
  verbs: ["list", "get"]
EOF

if kubectl get clusterrole "list-namespace" &>/dev/null; then
    echo "ClusterRole 'list-namespace' already exists"
else
    kubectl apply -f "${CLUSTERROLE_FILE}"
    echo "ClusterRole created: list-namespace"
fi

# Step 5: Create ClusterRoleBinding for namespace listing
echo ""
echo "5. Creating ClusterRoleBinding for namespace listing..."
CLUSTERROLEBINDING_FILE="${OUTPUT_DIR}/${USER}-list-namespace-binding.yaml"
cat <<EOF > "${CLUSTERROLEBINDING_FILE}"
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ${USER}-list-namespace
subjects:
- kind: User
  name: ${USER}
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: list-namespace
  apiGroup: rbac.authorization.k8s.io
EOF

kubectl apply -f "${CLUSTERROLEBINDING_FILE}"
echo "ClusterRoleBinding created: ${USER}-list-namespace"

echo ""
echo "RBAC configuration completed successfully!"
echo "Generated YAML files:"
echo "  - ${NAMESPACE_FILE}"
echo "  - ${ROLE_FILE}"
echo "  - ${ROLEBINDING_FILE}"
echo "  - ${CLUSTERROLE_FILE}"
echo "  - ${CLUSTERROLEBINDING_FILE}"