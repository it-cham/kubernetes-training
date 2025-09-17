#!/bin/bash
# process-csr-kubeconfig.sh
# Purpose: Process CSR, extract certificate, and generate kubeconfig

set -e

# Default values
INPUT_DIR="./csr"
OUTPUT_DIR="./kubeconfigs"
USER=""
SERVER=""
NAMESPACE=""
CLUSTER_NAME="kubernetes"

CA_CERT_PATH="/etc/kubernetes/pki/ca.crt"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --user)
            USER="$2"
            shift 2
            ;;
        --input-dir)
            INPUT_DIR="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --server)
            SERVER="$2"
            shift 2
            ;;
        --ca-cert)
            CA_CERT_PATH="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 --user <username> --server <api-server-url> [OPTIONS]"
            echo ""
            echo "Required Options:"
            echo "  --user         Username for certificate processing"
            echo "  --server       Kubernetes API server URL (e.g., https://k8s.example.com:6443)"
            echo ""
            echo "Optional:"
            echo "  --input-dir    Directory containing CSR files (default: ./csr)"
            echo "  --output-dir   Directory for kubeconfig output (default: ./kubeconfigs)"
            echo "  --ca-cert      Path to cluster CA certificate (default: /etc/kubernetes/pki/ca.crt)"
            echo "  --namespace    Default namespace for kubeconfig context (default: user-<username>)"
            echo "  -h, --help     Show this help message"
            echo ""
            echo "Example:"
            echo "  $0 --user alice --server https://k8s.example.com:6443"
            echo "  $0 --user bob --server https://k8s.example.com:6443 --input-dir ./certificates --output-dir ./configs"
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

if [ -z "$SERVER" ]; then
    echo "ERROR: --server parameter is required"
    echo "Use -h or --help for usage information"
    exit 1
fi

# Set default namespace if not provided
if [ -z "$NAMESPACE" ]; then
    NAMESPACE="user-${USER}"
fi

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Validate required files exist
if [ ! -f "${INPUT_DIR}/${USER}-csr.yaml" ]; then
    echo "ERROR: CSR YAML file '${USER}-csr.yaml' not found in ${INPUT_DIR}"
    echo "Run Part 1 (generate-user-csr.sh) first"
    exit 1
fi

if [ ! -f "${INPUT_DIR}/${USER}.key" ]; then
    echo "ERROR: Private key file '${USER}.key' not found in ${INPUT_DIR}"
    echo "Run Part 1 (generate-user-csr.sh) first"
    exit 1
fi

if [ ! -f "$CA_CERT_PATH" ]; then
    echo "ERROR: CA certificate not found at: $CA_CERT_PATH"
    echo "Specify correct path with --ca-cert option"
    exit 1
fi

echo "Processing CSR and generating kubeconfig for user: ${USER}"
echo "API Server: ${SERVER}"
echo "Input directory: ${INPUT_DIR}"
echo "Output directory: ${OUTPUT_DIR}"
echo "Default namespace: ${NAMESPACE}"
echo "================================================"

# Step 1: Submit CSR to Kubernetes
echo "1. Submitting CSR to Kubernetes..."
if kubectl get csr "${USER}-csr" &>/dev/null; then
    echo "CSR '${USER}-csr' already exists in cluster"
else
    kubectl apply -f "${INPUT_DIR}/${USER}-csr.yaml"
    echo "CSR submitted successfully"
fi

# Step 2: Check CSR status
echo ""
echo "2. Checking CSR status..."
kubectl get csr "${USER}-csr"

# Step 3: Approve CSR
echo ""
echo "3. Approving CSR..."
CSR_STATUS=$(kubectl get csr "${USER}-csr" -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "")
if [ "$CSR_STATUS" = "Approved" ]; then
    echo "CSR already approved"
else
    kubectl certificate approve "${USER}-csr"
    echo "CSR approved successfully"
fi

# Step 4: Extract signed certificate
echo ""
echo "4. Extracting signed certificate..."
CERT_FILE="${INPUT_DIR}/${USER}.crt"
if [ -f "$CERT_FILE" ]; then
    echo "Certificate '${USER}.crt' already exists in ${INPUT_DIR}. Skipping extraction."
else
    # Wait a moment for certificate to be available
    sleep 2
    kubectl get csr "${USER}-csr" -o jsonpath='{.status.certificate}' | base64 --decode > "$CERT_FILE"
    if [ -f "$CERT_FILE" ] && [ -s "$CERT_FILE" ]; then
        echo "Certificate extracted: ${CERT_FILE}"
    else
        echo "ERROR: Failed to extract certificate"
        exit 1
    fi
fi

# Step 5: Generate kubeconfig
echo ""
echo "5. Generating kubeconfig..."
KUBECONFIG_FILE="${OUTPUT_DIR}/${USER}.kubeconfig"


# Base64 encode certificates and key
CA_CERT_B64=$(cat "${CA_CERT_PATH}" | base64 | tr -d '\n')
USER_CERT_B64=$(cat "${INPUT_DIR}/${USER}.crt" | base64 | tr -d '\n')
USER_KEY_B64=$(cat "${INPUT_DIR}/${USER}.key" | base64 | tr -d '\n')

# Generate kubeconfig from template
cat <<EOF > "${KUBECONFIG_FILE}"
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: ${CA_CERT_B64}
    server: ${SERVER}
  name: ${CLUSTER_NAME}
contexts:
- context:
    cluster: ${CLUSTER_NAME}
    namespace: ${NAMESPACE}
    user: ${USER}
  name: ${CLUSTER_NAME}
current-context: ${CLUSTER_NAME}
kind: Config
preferences: {}
users:
- name: ${USER}
  user:
    client-certificate-data: ${USER_CERT_B64}
    client-key-data: ${USER_KEY_B64}
EOF

echo "Kubeconfig generated: ${KUBECONFIG_FILE}"

# Step 6: Verify kubeconfig
echo ""
echo "6. Verifying kubeconfig..."
if kubectl --kubeconfig="${KUBECONFIG_FILE}" version --client &>/dev/null; then
    echo "Kubeconfig validation successful"
else
    echo "WARNING: Kubeconfig validation failed - check cluster connectivity"
fi

echo ""
echo "Process completed successfully!"
echo "Generated files:"
echo "  - ${INPUT_DIR}/${USER}.crt        - Signed certificate"
echo "  - ${KUBECONFIG_FILE} - Kubeconfig file for user"