#!/bin/bash
# generate-user-csr.sh
# Purpose: Generate private key, CSR, and Kubernetes CSR YAML for a user

set -e

# Default values
OUTPUT_DIR="./csr"
USER=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --user)
            USER="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 --user <username> [--output-dir <directory>]"
            echo ""
            echo "Options:"
            echo "  --user         Username for certificate generation (required)"
            echo "  --output-dir   Output directory for generated files (default: ./csr)"
            echo "  -h, --help     Show this help message"
            echo ""
            echo "Example:"
            echo "  $0 --user alice --output-dir /tmp/certs"
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

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"
cd "$OUTPUT_DIR"

# Check if CSR already exists in Kubernetes
if kubectl get csr "${USER}-csr" &>/dev/null; then
    echo "ERROR: CSR ${USER}-csr already exists in Kubernetes cluster"
    echo "Delete the existing CSR first: kubectl delete csr ${USER}-csr"
    exit 1
fi

echo "Generating certificate materials for user: ${USER}"
echo "Output directory: ${OUTPUT_DIR}"
echo "================================================"

# Step 1: Generate private key
echo "1. Generating private key..."
if [ -f "${USER}.key" ]; then
    echo "WARNING: Private key ${USER}.key already exists. Skipping generation."
else
    openssl genrsa -out "${USER}.key" 2048
    chmod 600 "${USER}.key"
    echo "Private key generated: ${USER}.key"
fi

# Step 2: Generate Certificate Signing Request
echo ""
echo "2. Generating Certificate Signing Request..."
if [ -f "${USER}.csr" ]; then
    echo "WARNING: CSR ${USER}.csr already exists. Skipping generation."
else
    openssl req -new -key "${USER}.key" -out "${USER}.csr" -subj "/CN=${USER}"
    echo "CSR generated: ${USER}.csr"
fi

# Step 3: Create Kubernetes CSR YAML
echo ""
echo "3. Creating Kubernetes CSR YAML..."

# Encode CSR in base64
CSR_CONTENT=$(cat "${USER}.csr" | base64 | tr -d '\n')

# Create the Kubernetes CSR YAML file
cat <<EOF > "${USER}-csr.yaml"
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: ${USER}-csr
spec:
  request: ${CSR_CONTENT}
  signerName: kubernetes.io/kube-apiserver-client
  usages:
  - client auth
EOF

echo "Kubernetes CSR YAML created: ${USER}-csr.yaml"