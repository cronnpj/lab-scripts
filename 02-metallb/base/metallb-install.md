# MetalLB Installation (Automated via bootstrap.ps1)

MetalLB provides LoadBalancer support for bare-metal Kubernetes clusters.

In cloud environments (AWS, Azure, GCP), the cloud provider assigns external IPs automatically.

In bare-metal environments (like this lab), MetalLB assigns external IPs from a predefined pool.

---

## How MetalLB Is Installed

You do NOT need to manually install MetalLB.

It is installed automatically when you run:

    .\bootstrap.ps1

The script applies:

    02-metallb/base/
    02-metallb/overlays/example/

---

## What This Does

1. Installs MetalLB controller + speaker components
2. Creates an IPAddressPool
3. Creates an L2Advertisement

The default IP pool is:

    192.168.1.200/32

This allows services of type LoadBalancer (like ingress-nginx) to receive:

    192.168.1.200

---

## Why This Matters

Without MetalLB:

    LoadBalancer services would remain in <pending> state.

With MetalLB:

    ingress-nginx receives an external IP.
    You can access your application from the network.

---

## Advanced

If you want to change the VIP address, run:

    .\bootstrap.ps1 -VipIP 192.168.1.210

The script will automatically update the MetalLB pool.
