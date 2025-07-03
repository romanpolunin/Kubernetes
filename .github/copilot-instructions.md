# Introduction
This project is a collection of scripts and configuration files to set up 
a bunch of VMs and a Kubernetes cluster from scratch, 
provision an Nginx ingress, a distributed storage with Rook + Ceph,
and then deploy Grafana-based telemetry stack on it.

In addition to Kubernetes itself, these scripts also set up supporting software
and pre-download files and images used by node VMs and Kubernetes. 
This is to prevent them from being downloaded over and over again as you continuously nuke and rebuild the cluster.

The Kubernetes cluster runs on a set of Multipass VMs running Ubuntu 24.10.
Required software:
- Multipass, for the node VMs
- Podman, for the supporting software that's external to the cluster

Created node VMs:
- `kub-control-lb`: load balancer (HAProxy) for the control plane
- `kub-control-01`: first control plane node
- `kub-control-02`: second control plane node
- `kub-worker-01` : worker
- `kub-worker-02` : worker
- `kub-worker-03` : worker
- `kub-worker-04` : worker

Software that runs on the host, in Podman containers:
- Image Registry: configured by `./setup/create-once-cachingregistry.ps1`
- DNS forwarder (dnsmasq): configured by `./setup/create-once-dnsforwarder.ps1`

Most container images used by the software in Kubernetes cluster
are pulled from a locally running registry on `cachingregistry:5001` - you have to put that domain name into etc/hosts.

Every worker VM has a data folder `/home/ubuntu/ext-data` mapped into it from the MacOS host filesystem under `./data/{VM-NAME}`.
The other mapped folder `/home/ubuntu/ext-common` is for commonly used files under `./data/common`.

# Known Issues

The cluster (as run on a Mac Pro M4 with 48GB RAM and 2TB space) is not stable, specifically:
- when Mac goes into suspension for longer than maybe 30 or so minutes, networking gets completely messed up
  - make sure to caffeinate your Mac before closing the lid :-)
- time breaks on VMs after suspension and needs to be fixed
- Multipass VMs sometimes become unresponsive for no obvious reason (again, suspecting networking stack) after a long day

# Usage

First, one-time setup. No need to re-run this when you nuke/rebuild the cluster:
- Install Multipass
  - enable privileged mounts
  - use QEMU on Mac, and Hyper-V on Windows
- Install Podman
- edit your `etc/hosts` file
  - add `127.0.0.1        cachingregistry`
  - add `192.168.64.200   cluster.local`
- `./setup/create-once-cachingregistry.ps1`
- `./setup/create-once-aptgetpackages.ps1`
- `./setup/create-once-dnsforwarder.ps1`

Next, create Kubernetes cluster's backbone, the control plane and worker nodes:
- `./setup/create-nodes-controlplane.ps1`
- `./setup/create-nodes-workers.ps1`

Now all the software:
- `./stacks/ingress/create.ps1`
- `./stacks/storage/rook-ceph/create.ps1`
- `./stacks/telemetry/create.ps1`

# Teardown

To destroy the entire Kubernetes cluster with its node VMs, leaving external components intact:
- `./setup/nuke-cluster.ps1`

NOTE: Multipass might hang while executing VM deletion in `nuke-cluster.ps1`, 
so you may want to manually execute a command such as `killall qemu-system-aarch64`, 
or manually force-quit those processes.

To destroy one-time setup components:
- delete `dnsmasq` and `local-registry` containers in Podman
- delete `./data/registry` folder
- delete `./data/common` folder

To remove individual stacks, use `teardown.ps1` scripts in corresponding folders.

# Stacks

## Images and packages

Most of the container images are edited to point to our local container registry.
See `./setup/create-once-cachingregistry.ps1` for the full list of cached images.
This is done to prevent multi-gigabyte Internet downloads from happening every time the cluster or individual stacks are provisioned.

Same applies to the VM apt-get updates and installations, 
most if not all involved packages are cached by `create-once-aptgetpackages.ps1`,
and downloaded files are then mounted into every VM upon start.

## Ingress

Controller: `ingress-nginx`. We configure it in two places:
- via ConfigMap (images, HTTP ports, TCP ports)
- directly in ingress controller YAML file (images, TCP ports such as OTEL 4317 and 4318)
