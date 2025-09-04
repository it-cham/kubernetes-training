# Kubernetes Training

A comprehensive hands-on training program that guides you from container and Docker basics to advanced Kubernetes concepts and operations.

## Overview

This training is designed for developers, DevOps engineers, and system administrators who want to master containerization and Kubernetes orchestration. It follows a progressive learning path from foundational container concepts to production-ready Kubernetes deployments.

## Learning Path

### Phase 1: Container Fundamentals

- Docker installation and configuration
- Container lifecycle management
- Container networking fundamentals
- Volume management and data persistence
- Docker Compose for multi-container applications
- Advanced Docker concepts and optimization

### Phase 2: Kubernetes Foundation

- Kubernetes architecture and components
- Container orchestration concepts
- Setting up local development environment with k3s/Rancher Desktop
- Prerequisites and environment preparation

### Phase 3: Kubernetes Operations

- kubectl command-line interface
- Basic cluster operations and management
- Working with Kubernetes resources

## Prerequisites

### System Requirements

- **Operating System**: Windows 10/11, macOS, or Linux
- **Hardware**: 4GB RAM minimum (8GB recommended), 20GB free disk space
- **Network**: Internet connection for downloading images and packages

### Required Software

- **Rancher Desktop**: Lightweight Kubernetes distribution with k3s
- **Docker**: Container runtime (can be configured during Rancher Desktop setup)
- **Terminal/Shell**: Enhanced shell setup recommended (see [Shell Setup Guide](common/setup-shell.md))

## Getting Started

### 1. Environment Setup

Follow the [Shell Setup Guide](common/setup-shell.md) to configure your development environment with:

- Modern terminal with Kubernetes context display
- Essential tools and utilities
- Shell enhancements for productivity

### 2. Install Rancher Desktop

Download and install [Rancher Desktop](https://rancherdesktop.io/) with these configurations:

- **Container Runtime**: Docker or containerd (recommended)
- **Kubernetes**: k3s distribution
- **Traefik**: Disable (will be installed separately if needed)

### 3. Verify Installation

```bash
# Check Docker installation
docker --version

# Check Kubernetes cluster
kubectl cluster-info

# List cluster nodes
kubectl get nodes
```

## Training Modules

### 🐳 Module 2: Container Hands-On

**Focus**: Master Docker fundamentals and container operations

### ☸️ Module 3: Understanding Kubernetes

**Focus**: Kubernetes concepts and local setup

### 🚀 Module 4: First Steps with kubectl

**Focus**: Hands-on Kubernetes operations

## Learning Objectives

By the end of this training, you will be able to:

### Container Skills

- ✅ Install and configure Docker environments
- ✅ Create and manage container images
- ✅ Implement container networking and storage
- ✅ Orchestrate multi-container applications with Docker Compose
- ✅ Apply container optimization techniques

### Kubernetes Skills

- ✅ Understand Kubernetes architecture and components
- ✅ Set up and manage local Kubernetes clusters
- ✅ Use kubectl for cluster operations
- ✅ Deploy and manage containerized applications
- ✅ Implement basic networking and storage solutions

## Support and Resources

### Troubleshooting

- Check the individual lab `solution.md` files for step-by-step guidance
- Verify prerequisites are met before starting each module
- Ensure Rancher Desktop is running and cluster is accessible

### Additional Resources

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Rancher Desktop Documentation](https://docs.rancherdesktop.io/)

### Getting Help

- Review the `tasks.md` file in each lab for detailed instructions
- Check `solution.md` files for complete walkthroughs
- Verify your shell setup using the provided [Shell Setup Guide](common/setup-shell.md)
