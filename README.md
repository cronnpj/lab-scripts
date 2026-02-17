# CITA 360 – Kubernetes Bare Metal Lab (Talos)

This lab walks you through building a Kubernetes cluster using Talos Linux
and deploying applications using:

- Talos
- Kubernetes
- MetalLB
- NGINX Ingress
- Deployments & Services

You will run everything from your **Talos CTL VM** inside your isolated lab network.

---

# Lab Network Assumptions

Default IP plan:

| Role | IP Address |
|------|------------|
| Control Plane | 192.168.1.3 |
| Worker 1      | 192.168.1.6 |
| Worker 2      | 192.168.1.7 |
| LoadBalancer VIP | 192.168.1.200 |

If your IPs are different, you can override them when running the script.

---

# Step 1 – Clone the Repository

On your **Talos CTL VM**:

```powershell
git clone https://github.com/cronnpj/k8s-baremetal-lab.git
cd k8s-baremetal-lab
