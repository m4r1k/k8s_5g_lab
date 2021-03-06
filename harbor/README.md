# Harbor Readme

As mentioned in the main readme document, the platform also has a local registry.

The OpenShift integrated registry is nice but lacks a WebUI, scanning and replication capability. Harbor does that and is also **simple**. To set it up is literally few commands to prep the OS and then VMware provides an official [installation shell script](https://github.com/goharbor/harbor/blob/master/make/install.sh). *I wish was that easy to also use Quay.*

Just deploy a CentOS 8 Stream/RHEL8 VM, minimal install with [enough system resources](https://goharbor.io/docs/2.2.0/install-config/installation-prereqs/).

Once done, first copy the RootCA `crt` and `key` under `/root` and then run the [`harbor.sh`](https://github.com/m4r1k/k8s_5g_lab/blob/main/harbor/harbor.sh) in this repository and you're done. Keep in mind that all Harbor data is under `/data`

<img src="https://github.com/m4r1k/k8s_5g_lab/raw/main/media/harbor.png" width="75%" />
