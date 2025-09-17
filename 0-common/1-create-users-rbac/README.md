# RBAC - Create dedicated user namespaces

The scripts in this sub-directory are used to create individual Kubernetes namespaces and RBAC configuration for a training/development environment.

The following will be achieved:

- Create Keypair + CSR for each individual user
- Submit CSR and get user certificate
- Create user namespace and RBAC configuration (list all namespaces, full-access in user namespace)
- Create Kubeconfig for individual user

The scripts require `openssl` to be available on the host machine, as well as administrator/system privileges of the Kubernetes cluster that should be configured.

For the kubeconfig, the Kubernetes CA certificate is required and can be extracted from the administrator kubeconfig.
In k3s it can also be exported like this:

```shell
kubectl get configmaps kube-root-ca.crt -o jsonpath="{['data']['ca\.crt']}"
```

```shell
./generate-csr.sh --user "USERNAME"

./create-user-rbac.sh --user "USERNAME"

./create-kubeconfig.sh --user "USERNAME" --server "https://127.0.0.1:6443" --ca-cert "kube-ca.crt"
```
