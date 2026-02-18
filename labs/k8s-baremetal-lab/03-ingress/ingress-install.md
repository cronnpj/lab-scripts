# Ingress Controller Installation (Automated via bootstrap.ps1)

This lab uses the NGINX Ingress Controller to route HTTP traffic
to applications inside the Kubernetes cluster.

You do NOT install ingress manually.

It is installed automatically when you run:

    .\bootstrap.ps1

---

## How It Is Installed

The bootstrap script runs:

    helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
    helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
        --namespace ingress-nginx --create-namespace \
        --set controller.service.type=LoadBalancer

This:

1. Installs the ingress controller
2. Creates the namespace `ingress-nginx`
3. Creates a LoadBalancer service

---

## Why LoadBalancer?

In cloud environments, the cloud provider assigns an external IP.

In this bare-metal lab:

- MetalLB provides the external IP
- The ingress controller receives 192.168.1.200
- Traffic can enter the cluster

---

## How Traffic Flows

Client → pfSense (port forward)  
→ 192.168.1.200 (MetalLB)  
→ ingress-nginx-controller  
→ nginx service  
→ nginx pods  

---

## What This Enables

Once installed, you can:

- Create Ingress rules
- Route traffic by host or path
- Deploy multiple applications behind one IP
- Demonstrate reverse proxy behavior

---

## Verification

After bootstrap completes:

    kubectl get svc -n ingress-nginx

You should see:

    ingress-nginx-controller   LoadBalancer   192.168.1.200

You can then access:

    http://192.168.1.200
