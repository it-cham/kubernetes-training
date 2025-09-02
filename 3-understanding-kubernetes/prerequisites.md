## Module 3: Understanding Kubernetes

### Prerequisites

The lightweight Kubernetes distribution `k3s` is used for the individual students to follow the Kubernetes labs.

To streamline the installation on both Windows and Linux, Rancher Desktop is used.

During the installation, the following parameters can be used to use the existing container runtime `Docker`.
Alternatively, this can be switched to `containerd` here.

![Installation parameter - Rancher Desktop](_attachments/params-rancher-desktop.png)

In addition to the installation parameters, make sure to disable the traefik ingress controller in the settings.
If this is required, it will be installed later on seperately.

![Kubernetes preferences - Rancher Desktop](_attachments/k8s-rancher-desktop.png)

Once all settings have been accepted, the `k3s` single node cluster will be installed. For this, the below images are required.

![Prerequisite images - Rancher Desktop](_attachments/k8s-images-rancher-desktop.png)

If Windows (WSL) is used, it's possible that a proxy server needs to be configured under `Preferences - WSL`.

![Proxy settings - Rancher Desktop](_attachments/proxy-wsl-rancher-desktop.png)
