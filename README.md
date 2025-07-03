# Introduction

It's a set of Powershell scripts with supporting configs to bring up a local Kubernetes cluster for testing purposes.
Designed for frequent rebuilds of the entire cluster, all container images are modified to point to the locally running registry.

Powered by Multipass, brings up 7 virtual machines, of which
- 1 is the HAProxy load balancer for Kubernetes control plane API
- 2 are control plane nodes
- 4 are worker nodes

Powershell is used to make it cross-platform, and to avoid some behavior differences between zsh/bash/sh on Mac.

Full build of this cluster and software stacks takes maybe 15 minutes on Mac Pro M4 with 48GB RAM, 
provided that one-time setup has been completed.

As of writing this, a Windows version is awaiting resolution of some issues with Multipass.

# Why?

Minikube and its friends fake and hide a lot of the Kubernetes internals, to the point where they are basically unfit for my needs.
A multi-VM cluster is a fairly taxing deployment for a single computer, but it's really about your available RAM and disk.
To slim this down, get rid of control plane LB, one of the control plane nodes, and reduce the number of worker nodes.

# Caveats

This is a relatively taxing deployment, due to having all VMs running on the same machine. 
`caffeinate -imsu` your Mac if you don't keep it on high power setting and plugged in.
Be prepared to nuke and re-create this cluster more than once a day, especially if you don't caffeinate.
It's guaranteed to become unresponsive and not usable if Mac is suspended (time is broken, virtual networking components losing state).
On the positive note, these scripts are created to automate very frequent teardowns and rebuilds.

With all stuff deployed and running on a Mac Pro M4 with 48GB RAM and 2TB disk, 
you'll get  
- 40% CPU used constantly, with ~41GB RAM used up,
- 4GB of cached files and images under ./data
- 4 OSD data files (mapped into VMs as loop devices, for Ceph), they claim to be 20GB each but don't take that much space initially
- VM disks under wherever you have MULTIPASS_STORAGE

# What's deployed in the cluster

- HAProxy load balancer for the Kubernetes control plane API
    - HAProxy dashboard is usually on http://192.168.64.2 (or whatever IP you get for the kub-control-lb machine in your current build)
- Kubernetes 1.33.2
- Tigera/Calico networking
- containerd for containers
- MetalLB on Mac for allocation of "external" IPs (192.168.64.200 for the ingress controller on `cluster.local`) - to avoid host networking
- Nginx ingress controller (for Ceph dashboard, Grafana, OTel Collector)
- "True" distributed storage with Ceph, using Rook operator - to eliminate the need for host mounts in application manifests
- Telemetry stack for the cluster itself and for applications (dedicated OTel Collectors for cluster/infra/apps, Grafana, Grafana Tempo, Grafana Loki, Prometheus)
- Ceph dashboard and Grafana are exposed over the ingress on `cluster.local` (192.168.64.200 on Mac)
    - `http://cluster.local/ceph-dashboard/#/dashboard`
    - `http://cluster.local/grafana`
- OTel Collector for apps, specifically their OTLP endpoints, are exposed via a Kubernetes Service on ingress:
    - `cluster.local:4318`
    - `cluster.local:4317`

# Detailed instructions

Refer to .github/copilot-instructions.md for usage and all sorts of additional details,
including known issues, one-time setup, etc.

That file is automatically picked up by Github Copilot in VSCode, so most details are there for now.