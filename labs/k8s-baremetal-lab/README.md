# Kubernetes Bare-Metal Lab

### CITA 360 – Infrastructure Automation & Modern Deployment

This lab walks you through building a fully functional **bare-metal Kubernetes cluster** using:

* **Talos Linux**
* **MetalLB**
* **NGINX Ingress Controller (Helm)**
* **Portainer CE (Helm)**
* **Sample NGINX Application**

The goal is to build the cluster quickly and reliably so that we can focus on:

* Deploying applications
* Scaling workloads
* Configuring services
* Using ingress rules
* Understanding traffic flow
* Practicing infrastructure automation

---

# Lab Architecture Overview

This lab creates:

* 1 Control Plane node
* 2 Worker nodes
* MetalLB for LoadBalancer support
* ingress-nginx for reverse proxy routing
* A sample NGINX web application

Traffic Flow:

```
Client Browser
    ↓
pfSense (Port Forward)
    ↓
MetalLB VIP (192.168.1.200)
    ↓
ingress-nginx controller
    ↓
nginx service
    ↓
nginx pods
```

---

# Repository Structure

```
01-talos/
    student-overrides/   → Talos configs generated locally (NOT committed)

02-metallb/
    base/                → MetalLB installation manifests
    overlays/example/    → IP pool configuration (VIP)

03-ingress/
    ingress-install.md   → Documentation
    nginx-ingress.yaml   → Ingress routing rule

04-app/
    nginx-deployment.yaml
    nginx-service.yaml

bootstrap.ps1            → Fully automated cluster build script
```

---

# Requirements (Talos CTL VM)

The following must be installed on the Talos CTL machine:

* talosctl
* kubectl
* helm
* git

---

# How to Run the Lab

From the root of this repository:

```powershell
.\bootstrap.ps1
```

Default node IPs:

* Control Plane: 192.168.1.3
* Worker 1: 192.168.1.6
* Worker 2: 192.168.1.7
* VIP: 192.168.1.200

If you need to override:

```powershell
.\bootstrap.ps1 `
  -ControlPlaneIP 192.168.1.13 `
  -Worker1IP 192.168.1.16 `
  -Worker2IP 192.168.1.17 `
  -VipIP 192.168.1.210
```

---

# What bootstrap.ps1 Does

1. Generates Talos configs locally
2. Applies configs to nodes
3. Bootstraps Kubernetes
4. Retrieves kubeconfig
5. Installs MetalLB
6. Installs ingress-nginx via Helm
7. Waits for external IP assignment
8. Deploys sample NGINX app
9. Creates ingress rule
10. Optionally installs Portainer CE + ingress host

After completion:

```
http://192.168.1.200
```

Should display the NGINX welcome page.

Install Portainer only (after ingress/VIP are working):

```powershell
.\bootstrap.ps1 -PortainerOnly -InstallPortainer
```

Install Portainer with a custom host:

```powershell
.\bootstrap.ps1 -AddonsOnly -InstallPortainer -PortainerDomain doom.local
```

---

# Why Talos?

Talos is a minimal, immutable OS designed specifically for Kubernetes.

Advantages in this lab:

* No SSH configuration required
* Fully declarative cluster configuration
* Clean, repeatable builds
* Excellent for automation-focused coursework

---

# Why MetalLB?

Cloud providers automatically assign external IPs.

Bare-metal clusters do not.

MetalLB provides LoadBalancer support in non-cloud environments, allowing ingress-nginx to receive a real external IP address.

---

# Why Ingress?

Ingress allows:

* Path-based routing
* Host-based routing
* Multiple apps behind one IP
* Reverse proxy behavior
* TLS termination (future lab)

This lab sets the foundation for advanced Kubernetes networking topics.

---

# Security Notes

Talos configuration files contain:

* Private keys
* Cluster certificates
* Join tokens

These are generated locally and are NOT committed to GitHub.

Never commit:

* controlplane.yaml
* worker.yaml
* talosconfig
* kubeconfig

---

# Troubleshooting

Check cluster status:

```powershell
kubectl get nodes
kubectl get pods -A
kubectl get svc -A
kubectl get ingress
```

If something fails:

1. Delete contents of `01-talos/student-overrides/`
2. Re-run `bootstrap.ps1`

---

# Learning Objectives

After completing this lab, you should understand:

* How Kubernetes clusters are bootstrapped
* Difference between cloud and bare-metal networking
* Service types (ClusterIP, NodePort, LoadBalancer)
* How ingress controllers route traffic
* How Helm installs production-grade components
* Infrastructure-as-Code principles

---

# Instructor Notes

This lab is intentionally automated to allow students to focus on:

* Application deployment
* Scaling
* Configuration management
* Reverse proxy behavior
* Kubernetes networking concepts

Cluster build complexity is abstracted to reduce setup friction.