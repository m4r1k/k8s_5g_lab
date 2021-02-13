# OpenShift 5G Telco Lab
## 1 - Introduction
The 5G Mobile Network standard is built from the ground up to be [cloud-native](https://www.lightreading.com/cloud-native-nfv/5gs-future-includes-a-cloud-native-architecture-complete-with-containers/d/d-id/762116). Over the years, and thanks to new standards, not only the legacy architectures have been decoupled ([CUPS](https://www.sdxcentral.com/articles/news/why-cups-is-a-critical-tool-in-the-5g-toolbox/2018/10/)), but even more flexible initiatives ([O-RAN](https://www.sdxcentral.com/5g/ran/definitions/what-is-open-ran-radio-access-network/)) are now taking over the marker.

Many Telcos are moving to containerized architectures and ditching for good the legacy, which historically is built on layers of proprietary and specialized solutions.

During the past decade, many Telcos have looked at OpenStack for their 4G Virtualized Network Functions needs as the solution for the NFVi. While many succeeding *and also some failing*, OpenStack was never truly build to orchestrate containers. Put that together with the [community's current status](https://www.theregister.com/2020/10/22/openstack_at_10/), you'll get that 5G represents an opportunity to do things differently and hopefully better.

Telco applications have been re-written and decouple even further into hundreds of micro-services to embrace a containerized architecture. Orchestrating these massive applications without something like Kubernetes would be impossible.

## 2 - 5G is Containers
From [Ericsson](https://www.ericsson.com/en/cloud-native) to [Nokia](https://www.nokia.com/blog/containers-and-the-evolving-5g-cloud-native-journey/), from [Red Hat](https://www.redhat.com/en/resources/optimize-5g-with-containers-on-bare-metal-whitepaper) to [VMware](https://www.fiercewireless.com/tech/samsung-vmware-team-cloud-native-5g-functions), and with leading examples like [Verizon](https://www.fiercewireless.com/tech/verizon-readies-initial-shift-to-5g-standalone-core-after-successful-trial) and [Rakuten](https://www.fiercewireless.com/5g/rakuten-s-5g-network-will-be-built-containers), there is absolutely no douth that 5G means containers, and as everybody knows, containers mean Kubernetes. There are many debates whether the more significant chunk of the final architecture would be virtualized or natively running on bare-metal (there are still some cases where hardware virtualization is a fundamental need) but, in all instances, Kubernetes is the dominant and de-facto standard to build applications.

Operating in a containerized cloud-native world represents such a significant shift for all Telco operators that the NFVi LEGO approach seems easy now.

For those who have any doubts about the capability of Kubernetes to run an entire mobile network, I encourage you to watch:

* [KubeCon NA 2019 Keynote](https://www.youtube.com/watch?v=IL4nxbmUIX8) - [Slides](https://static.sched.com/hosted_files/kccncna19/c9/5%20HEATHER%20KIRKSEY%20-%20V3.pptx.pdf)
* [Build Your Own Private 5G Network on Kubernetes](https://www.youtube.com/watch?v=R_JOhWlwsXo) - [Slides](https://static.sched.com/hosted_files/kccncna19/02/KubeCon%202019%20-%20BYO%205G%20Network.pdf)

## 3 - About this document
The primary aim for this document is deploying a 5G Telco Lab using mix of virtual and physical components. Several technical choices - combination of virtual/physical, NFS server, *limited* resources for the OpenShift Master, some virtual Worker nodes, etc - are just compromises to cope with the Lab resources. *As a reference, all this stuff runs at my home*.

Everything that is built on top of the virtualization stack (in my case VMware vSphere) is explained in greater detail, but the vSphere environment itself is only lightly touched.

**<div align="center"><span style="color:red">For the sake of explanation, limited automation is provided</span></div>**

### 3.1 - TODOs and upcoming releases
In the near future the following topics will also be covered

  - SR-IOV Operator (w/o the Webhook)
  - K8s' CPU Manager
  - PAO (w/ and w/o RT)
  - FD.IO VPP App
  - LACP Bond for physical nodes
  - Use an external CA for the entire platform
  - Local *cache* (OCI Registry + RHCOS Images)
  - Disable the `ixgbevf` and `i40evf` modules
  - MetalLB BGP
  - Contour
  - CNV

## 4 - Lab High-Level
![](https://raw.githubusercontent.com/m4r1k/k8s_5g_lab/main/media/lab_drawing.png)

The lab is quite linear. Fundamentally there are three PowerEdge and a Brocade Fabric:

* A single Brocade ICX 6610 as Network Fabric for 1/10/40Gbps connections
	* 1Gbps on copper
	* 10 and 40Gbps on DAC
	* The ICX will also act as a BGP router for MetalLB
* For the server hardware, three PowerEdge server G13 from Dell-EMC
	* The ESXi node is an R630 with 2x Xeon E5-2673 v4 (40 cores/80 threads) and 256GB of memory
	* The physical OCP Worker node is also Dell-EMC R630 with 2x Xeon E5-2678 v3 (24 cores/48 threads) and 64GB of memory
	* There is a 3rd node, an R730xd (2x Xeon E5-2673 v4 + 128GB of memory) currently used only as a traffic generator

More physical and connectivity details available in Google Spreadsheet [Low-Level Design](https://docs.google.com/spreadsheets/d/1Pyq2jnS4-T_WjBzWAP6GJyQLLqqhAeh5xg40jMQVHAs/edit?usp=sharing). [Brocade ICX config available as well](https://github.com/m4r1k/k8s_5g_lab/tree/main/switch).

Software-wise, things are also very linear:

* As the generic OS to provide all sort of functions (Routing, NAT, DHCP, DNS, NTP etc): CentOS Stream 8
* CentOS Stream 8 is also used for NFS (the [Kubernetes SIG NFS Client](https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner) is deployed to have the NFS Storage Class) and as soon as OCP moves to the [RHEL 8.3 kernel](https://bugzilla.redhat.com/show_bug.cgi?id=1761352) (spoiler, it will happen with 4.7), [`NFS nconnect`](https://www.spinics.net/lists/linux-nfs/msg63368.html) will be available
* OpenShift Container Platform version 4.6 (but the aim here is to have something entirely usable for future major releases)

## 5 - vSphere Architecture
#TODO - Pic of vSphere
Let's address the elephant in the room: why VMware vSphere? Well, there are a couple of reasons, but before that let me state loud and clear, everything achived in this document can absolutely be done on plain Linux KVM. VMware vSphere is my choise and doesn't have to be yours: 

* While OpenShift supports many on-premise platforms (OpenStack, oVirt, pure bare-metal, and vSphere), the power of an indeed Enterprise Virtualization Platform could play an essential role in how the lab evolves, and it could also act as a reference (for example, today real production on bare-metal has a minimum footprint of 7 nodes: 3x Master + 3x Infra + 1x Provisioner)
* *In general*, VMware is just better at hardware virtualization and there might be some edge cases where it becomes instrumental. Last year my [OpenStack NFVi Lab moved to vSphere](https://github.com/m4r1k/nfvi_lab/commit/d7149a1) because I wanted to expose virtual NVME devices to my Ceph Storage nodes (of course, not everything is better, *tip: if you're interested, compare CPU & NUMA Affinity and the SMP topology capability of ESXi and KVM*)

The vSphere architecture is also very lean:

* ESXi 7.0 U1d (`17551050`)
* vCenter Server deployed through vCSA 7.0 U1d (`7.0.1.00300`)
* The vSphere topology has a single DC (`NFVi`) and a single cluster (`Cluster`)
* DRS in the cluster is enabled (but having a single ESXi, it won't make any migration)
* DRS's CPU over-commit ratio is not configured
* A dedicated VMFS6 datastore (using a local NVME) of 1TB for this Lab (running off a Samsung 970 Evo Plus)
* On the network side
	* VMware vSS for the default *VM Network* that has Internet access (What's the reason? Laziness :-P). Being a single host, we have here also the default VMkernel
	* VMware vDS (with two uplinks @ 10Gbps) for the *OCP Machine Network*
	* VMware vDS (with two uplinks @ 1Gbps) for the *OCP Provisioning Network*

A quick note about the Distributed Port Groups security configuration:

* `Promiscuous mode` configured to `Accept` (default `Reject`)
* `MAC address changes` configured to `Accept` (default `Reject`)
* `Forged transmits` configured to `Accept` (default `Reject`)

Regarding the VMs configuration:

* All the VM use the latest [vHW 18](https://docs.vmware.com/en/VMware-vSphere/7.0/com.vmware.vsphere.vm_admin.doc/GUID-789C3913-1053-4850-A0F0-E29C3D32B6DA.html)
* The VM Guest OS Profile is configured for RHEL8 (the firmware is set to `EFI` and `Secure Boot` is disabled)
* `vNUMA` is disabled, exposing a single socket (aka equal number of `vCPU` and `Cores per socket`)
* `I/O MMU` and `Hardware virtualization` (aka `Nested Virtualization`) are both enabled
* VMXNET3 is the network para-virtualized driver
* VMware NVME is the storage controller for all non-OCP VMs (for who's asking about PVSCSI vs. NVME, [see the comparison](https://www.thomas-krenn.com/en/wiki/VMware_Performance_Comparison_SCSI_Controller_and_NVMe_Controller))
* VMware PVSCSI is the storage controller for all OCP VMs (*no matter what, I wasn't able to use the NVME as root device even with [Root device hints](https://docs.openshift.com/container-platform/4.6/installing/installing_bare_metal_ipi/ipi-install-installation-workflow.html#root-device-hints_ipi-install-configuration-files)*)

### 5.1 - Virtual Baseboard Management Controller
The only real peculiarity in this environment is that OpenShift is deployed using IPI for Bare-metal on a mix vSphere and physical hardware. VMware doesn't have something like a virtual IPMI device; hence a vBMC solution is used.

* For this environment, *[virtualbmc-for-vsphere](https://github.com/kurokobo/virtualbmc-for-vsphere)* is the vBMC solution managing the power management of the VMs. HUGE Thanks to @kurokobo for his massive work on *virtualbmc-for-vsphere* and effectively setting the [foundation of this lab](https://blog.kurokobo.com/archives/3524) (in case the blog disappear, [link to web archive](https://web.archive.org/web/20201127180855/https://blog.kurokobo.com/archives/3524))
* As an alternative option, a combination of *[python-virtualbmc](https://pypi.org/project/virtualbmc/) plus libvirt* is also possible (this is how my [OpenStack NFVi Lab works](https://github.com/m4r1k/nfvi_lab/blob/osp16/hci-esxi/vBMC.sh))

I personally tested both methods and they work very well. Moreover, for about a year now, the pure *python-virtualbmc plus libvirt* approach has been rock solid in my NFVi OpenStack Lab, but there is a caveat: while with *python-virtualbmc* the VM's boot order must be manually configured (PXE always first) @kurokobo [made a specific implementation](https://github.com/kurokobo/virtualbmc-for-vsphere/commit/2380859) to solve this problem effectively making *virtualbmc-for-vsphere* superior.

### 5.2 How to get VMware Subscriptions
There are mainly two ways (*besides buying a complete subscription*)

* [60-days VMware evaluation](https://www.vmware.com/try-vmware.html) most (all?) VMware products come with a trial of 60 days.
* [VMUG Learning Program](https://www.vmug.com/membership/vmug-advantage-membership) is basically the must-have solution to learn all VMware solutions. With 200$/year, one gets access to NRF subscriptions for all VMware software  + offline training.

## 6 - Red Hat OpenShift Architecture
Similar to VMware vSphere, why OpenShift and not pure Kubernetes? Also here, many reasons:

* As with all Red Hat Products, one gets a well-integrated and well-tested plateau of open source solutions that greatly expand the final value. See the [official architectural notes](https://docs.openshift.com/container-platform/4.6/architecture/architecture.html) about what OpenShift includes.
* **Performance**: Telcos have some of the most bizarre performance requirements in the entire industry: network latency, packet-per-second rate, packet-drop rate, scheduling latency, fault detection latency, NUMA affinity, dedicated resources (CPU, L3 cache, Memory bandwidth, PCI devices) etc. Red Hat has been working for many years now to achieve deterministic performance (you can read more on my posts at [Tuning for Zero Packet Loss in OpenStack Part1](https://www.redhat.com/en/blog/tuning-zero-packet-loss-red-hat-openstack-platform-part-1), [Part2](https://www.redhat.com/en/blog/tuning-zero-packet-loss-red-hat-openstack-platform-part-2), and [Part3](https://www.redhat.com/en/blog/tuning-zero-packet-loss-red-hat-openstack-platform-part-3) and also [Going full deterministic using real-time in OpenStack](https://www.redhat.com/en/blog/going-full-deterministic-using-real-time-openstack)). That work, which started with RHEL and eventually included also OpenStack, is now covering OpenShift as well with PAO (or [Performance Addon Operator](https://docs.openshift.com/container-platform/4.6/scalability_and_performance/cnf-performance-addon-operator-for-low-latency-nodes.html)).
* **Security**: in February 2019, to date, the major vulnerability of RunC ([CVE-2019-5736](https://nvd.nist.gov/vuln/detail/CVE-2019-5736)) allowed malicious containers to literally take control of the host. This made people literally scramble and yet OpenShift, [thanks to SELinux](https://access.redhat.com/security/cve/cve-2019-5736), was protected from the start.
* **Usability**: honestly, the OpenShift Console and the features in the OC (OpenShift Client) CLI are nothing less than spectacular.
* **Immutability**: CoreOS makes the entire upgrade experience, finally, trivial.
* **Observability**: OpenShift ships with pre-configured Alarms and Performance Monitoring ([based on Prometheus](https://docs.openshift.com/container-platform/4.6/monitoring/understanding-the-monitoring-stack.html)), and additionally fully supported Logging Operator ([based on EFK](https://docs.openshift.com/container-platform/4.6/logging/cluster-logging.html)) is also available.
* **Virtualization**: Well it might sound odd but having around virtualization capability within the same platform actually can be very handy. For cloud-native develop because maybe there is a monolith not cloud-native yet, for Telco because perhaps they have e.g. a QNX appliance which, for apparent reason, won't become Linux-base any time soon.
* **RHEL**: RHCOS (Red Hat CoreOS) uses the same RHEL Kernel and userland as a regular RHEL 8 (albeit the userland utilities are minimal). People may say stuff like *"the RHEL kernel is outdated"* but I dear you to check the amounts of backports Red Hat does (`rpm -q --changelog kernel`) plus all the stability and scalability testing and, of course, [upstream improvements](https://www.linuxfoundation.org/wp-content/uploads/linux-kernel-report-2017.pdf). Latest doesn't necessarily mean most excellent. In RHEL, the versioning number is fricking meaningless. A couple of examples to dig more details about the [Networking stack of RHEL](https://www.redhat.com/en/blog/pushing-limits-kernel-networking) and the [Linux kernel virtualization limits](https://sysdig.com/blog/container-isolation-gone-wrong/) and how using a tested version is essential.

*Much more is available in OpenShift (Argo CI, Istio, a vast ecosystem of certified solutions, etc), but it won't be cover here.*

About the OpenShift Architecture, as the diagram above shows:

* Standard OpenShift control-plane architecture made out of three Master (with highly available ETCD)
* Three virtualized Worker nodes to run internal services (e.g. console, oauth, monitoring etc) and anything non-performance intensive
* One physical Worker node to run Pods with SR-IOV devices
* The deployment is Bare-metal IPI (installer-provisioned infrastructure), but the VMware VMs are created manually 
* Being a bare-metal deployment, a LoadBalancer solution is required and for this, [MetalLB](https://metallb.universe.tf/#why) is the go-to choice
* A Linux router is available to provide the typical network services such as DHCP, DNS, and NTP as well Internet access
* A Linux NFS server is installed and, later on, the [Kubernetes SIG NFS Client](https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner) is deployed through `Helm`
* Lastly, OVN-Kubernetes is the default CNI Network provider 

To reassume the VMs configuration

VM Name    |vHW|vCPU|vMemory|Root vDisk|Data vDisk|vNIC1 *(ens160)*|vNIC2 *(ens192)*|Storage Device|Ethernet Device|
----------:|:-:|:--:|:-----:|:--------:|:--------:|:--------------:|:--------------:|:------------:|:-------------:|
Router     |18 |4   |16 GB  |20GiB     |n/a       |VM Network      |OCP Baremetal   |NVME          |VMXNET3        |
Provisioner|18 |4   |16 GB  |70GiB     |n/a       |OCP Baremetal   |OCP Provisioning|NVME          |VMXNET3        |
Master-0   |18 |4   |16 GB  |70GiB     |n/a       |OCP Provisioning|OCP Baremetal   |PVSCSI        |VMXNET3        |
Master-1   |18 |4   |16 GB  |70GiB     |n/a       |OCP Provisioning|OCP Baremetal   |PVSCSI        |VMXNET3        |
Master-2   |18 |4   |16 GB  |70GiB     |n/a       |OCP Provisioning|OCP Baremetal   |PVSCSI        |VMXNET3        |
Worker-0   |18 |8   |32 GB  |70GiB     |n/a       |OCP Provisioning|OCP Baremetal   |PVSCSI        |VMXNET3        |
Worker-1   |18 |8   |32 GB  |70GiB     |n/a       |OCP Provisioning|OCP Baremetal   |PVSCSI        |VMXNET3        |
Worker-2   |18 |8   |32 GB  |70GiB     |n/a       |OCP Provisioning|OCP Baremetal   |PVSCSI        |VMXNET3        |
NFS Server |18 |2   |16 GB  |70GiB     |300GiB    |OCP Baremetal   |n/a             |NVME          |VMXNET3        |

Also available in Google Spreadsheet the [Low-Level Design](https://docs.google.com/spreadsheets/d/1Pyq2jnS4-T_WjBzWAP6GJyQLLqqhAeh5xg40jMQVHAs/edit?usp=sharing) of the lab in much greater detail.

The OpenShift Domain configuration

* Base Domain: `bm.nfv.local`
* Cluster Name: `ocp4`

### 6.1 - Performance Addon Operator aka PAO

[![Hello this is PAO](https://github.com/openshift-kni/performance-addon-operators/raw/master/docs/interactions/diagram.png)](https://github.com/openshift-kni/performance-addon-operators/blob/master/docs/interactions/diagram.png)

If you don't know what PAO is, I strongly encourage you to [read the official documentation](https://docs.openshift.com/container-platform/4.6/scalability_and_performance/cnf-performance-addon-operator-for-low-latency-nodes.html). In short, is a [Tuned CPU-Partitioning](https://github.com/redhat-performance/tuned/tree/master/profiles/cpu-partitioning) on steroid, taking into account also the K8s Topology Manager. Of course, PAO is applied only to the physical worker node(s).

* **CPU**: One `reserved` full core (aka 2 threads) per NUMA node, all the others `isolated` for the applications
* **Memory**: 16GB available for the OS and infra Pods while all the rest configured as 1GB HugePages
* **Topology Manager**: set to `single-numa-node` to ensure the NUMA Affinity of the Pods ([well, actually each Container in the Pod](https://kubernetes.io/docs/tasks/administer-cluster/topology-manager/#policy-single-numa-node))
* **Kernel**: the standard, low-latency, non-RealTime kernel is used. Not every single CNF will benefit from a RealTime Kernel. RealTime always requires a RTOS and an RT application. When is not, thing will be slower without any deterministic benefit.

Also available in Google Spreadsheet a table view [Low-Level Design](https://docs.google.com/spreadsheets/d/1Pyq2jnS4-T_WjBzWAP6GJyQLLqqhAeh5xg40jMQVHAs/edit?usp=sharing) of the partitioning.

## 7 - Deployment
This section aims to provide the configuration needed to deploy all the components.

### 7.1 - Router, NFS Server and Provisioner VMs
The Router, NFS Server and Provisioner VMs are created manually in vSphere (refer to the VMware section for the details). Follows a list of configurations common to all of them:

 * CentOS Stream 8
 * Minimal Install + *Guest Agents*
 * UTC Timezone
 * LVM, no swap, XFS file-system
 * Static IP Addresses (see the [LLD](https://docs.google.com/spreadsheets/d/1Pyq2jnS4-T_WjBzWAP6GJyQLLqqhAeh5xg40jMQVHAs/edit?usp=sharing) for the details)

#### 7.1.1 - Common steps
*A set of common steps are applied to all the VM*

After the CentOS Stream 8 is installed, all the packages are updated

* Install the Advanced-Virtualization Repos
* Disable the standard RHEL Virtualization module
* Enable the Container-tool module (by default enabled)
* Update all the packages

```bash
cat > /etc/yum.repos.d/Advanced-Virtualization.repo << 'EOF'
[Advanced-Virtualization]
name=CentOS Stream 8 - Advanced Virtualization
baseurl=http://mirror.centos.org/centos/8/virt/x86_64/advanced-virtualization/
enabled=1
gpgcheck=0
EOF

dnf makecache
dnf module enable -y container-tools:rhel8
dnf module disable -y virt
dnf upgrade -y
```
Once concluded, several packages are installed (the list is self-explanatory)

```bash
dnf install -y bash-completion bind-utils cockpit cockpit-storaged \
               chrony httpd git httpd-tools jq lsof open-vm-tools \
               podman-docker tcpdump tmux vim

dnf module -y install container-tools
```
Run the Open VM-Tools at boot

```bash
systemctl enable --now vmtoolsd vgauthd
```
Finally run the RHEL Cockpit web interface

```bash
systemctl enable --now cockpit.socket
firewall-cmd --permanent --zone=external --add-service=cockpit
firewall-cmd --reload
```
### 7.2 - Router
First off, let's install DNSMasq. Being an OpenStack guy, DNSMasq feels home (back in my old public-cloud days, I remember experiencing a DoS caused by the `log-queries` facility when malicious users generate many 1000s of DNS queries per second)

```bash
dnf install -y dnsmasq
```
Let's move then to the configuration of NTP through Chrony

* Allow Chrony to provide NTP to any host in the OCP Baremetal Network 
* If running, restart the service
* If not configured to start at boot, enable and start it now

```bash
echo "allow 10.0.11.0/27" | tee -a /etc/chrony.conf
systemctl is-active chronyd && systemctl restart chronyd
systemctl is-enabled chronyd || systemctl enable --now chronyd
```
Now it's time for the DNS

* Internal DNS Resolution
* Basic DNSMasq configuration with the local domain `ocp4.bm.nfv.local` and name resolution caching
* If running, restart the service
* If not configured to start at boot, enable it and start it now

```bash
cat > /etc/hosts.dnsmasq << 'EOF'
10.0.11.1  diablo
10.0.11.2	 openshift-master-0
10.0.11.3	 openshift-master-1
10.0.11.4	 openshift-master-2
10.0.11.5	 openshift-worker-0
10.0.11.6	 openshift-worker-1
10.0.11.7	 openshift-worker-2
10.0.11.11 openshift-worker-3
10.0.11.18 api
10.0.11.28 provisioner
10.0.11.29 nfs-server
10.0.11.30 router
EOF

cat > /etc/resolv.dnsmasq << 'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

cat > /etc/dnsmasq.d/dns.dnsmasq << 'EOF'
domain-needed
bind-dynamic
bogus-priv
domain=ocp4.bm.nfv.local
interface=ens160,ens192
no-dhcp-interface=ens160
no-hosts
addn-hosts=/etc/hosts.dnsmasq
resolv-file=/etc/resolv.dnsmasq
expand-hosts
cache-size=500
address=/.ocp4.bm.nfv.local/10.0.11.19
EOF

systemctl is-active dnsmasq && systemctl restart dnsmasq
systemctl is-enabled dnsmasq || systemctl enable --now dnsmasq
```
DHCP Time

* Set the DHCP Range (from 10.0.11.2 to 10.0.11.17)
* Define the default route to 10.0.11.30 (config `server` and more commonly `option 6`)
* Define the DNS to 10.0.11.30 (`option 3`)
* Define the NTP to 10.0.11.30 (`option 42`)  

```bash
cat > /etc/dnsmasq.d/dhcp.dnsmasq << 'EOF'
domain-needed
bind-dynamic
bogus-priv
domain=ocp4.bm.nfv.local
dhcp-range=10.0.11.2,10.0.11.17
dhcp-option=3,10.0.11.30
dhcp-option=42,10.0.11.30
server=10.0.11.30

dhcp-host=00:50:56:8e:56:31,openshift-master-0.ocp4.bm.nfv.local,10.0.11.2
dhcp-host=00:50:56:8e:8e:6d,openshift-master-1.ocp4.bm.nfv.local,10.0.11.3
dhcp-host=00:50:56:8e:66:b0,openshift-master-2.ocp4.bm.nfv.local,10.0.11.4
dhcp-host=00:50:56:8e:16:11,openshift-worker-0.ocp4.bm.nfv.local,10.0.11.5
dhcp-host=00:50:56:8e:c9:8e,openshift-worker-1.ocp4.bm.nfv.local,10.0.11.6
dhcp-host=00:50:56:8e:f2:26,openshift-worker-2.ocp4.bm.nfv.local,10.0.11.7
dhcp-host=ec:f4:bb:dd:96:29,openshift-worker-3.ocp4.bm.nfv.local,10.0.11.11
EOF

systemctl restart dnsmasq
```
Now that we have it, let's also use DNSMasq for local resolution

```
nmcli connection modify ens160 ipv4.dns 127.0.0.1
nmcli connection modify ens160 ipv4.dns-search ocp4.bm.nfv.local
```
Let's configure routing capability

* Associate the `External` zone to `ens160` (connected to VM Network with Internet access)
* Associate the `Internal` zone to `ens192` (connected to OSP Baremetal)
* Allow Masquerade between Internal to External (effectively NAT)

```bash
nmcli connection modify ens160 connection.zone external
nmcli connection modify ens192 connection.zone internal
firewall-cmd --permanent --zone=internal --add-masquerade
firewall-cmd --reload
```
Let's open the firewall for all relevant services

* Internal Zone: NTP, DNS, and DHCP
* External Zone: DNS and Cockpit

```bash
firewall-cmd --permanent --zone=internal --add-service=ntp
firewall-cmd --permanent --zone=internal --add-service=dns
firewall-cmd --permanent --zone= external --add-service=dns
firewall-cmd --permanent --zone=internal --add-service=dhcp
firewall-cmd --reload
```
The final step, after all the updates and config changes, let's reboot the VM

```bash
reboot
```

#### 7.2.1 - vBMC
The `virtualbmc` effectively runs off the router in my lab but it can be executed anywhere else (like in a container)

I might take a somehow outdated way of managing python packages, would definitely be cool running in a container :-P but I'll leave this for the future. At least I'm **NOT BADLY** doing `pip install` on the live system but inside a sane and safe `virtualenv`

Let's, first of all, install Python virtual environments

```bash
dnf install -y ipmitool OpenIPMI python3-virtualenv python3-pyvmomi gcc make
``` 
Then we can proceed with the installation of `virtualbmc-for-vsphere` from @kurokobo - Thanks again!

```bash
virtualenv /root/vBMC
source /root/vBMC/bin/activate
pip install --upgrade pip
pip install vbmc4vsphere
```
Once done, we allow the IPMI connections in the firewall

```bash
firewall-cmd --permanent --zone=internal --add-port=623/udp
firewall-cmd --reload
```

Lastly, we can start our `virtualbmc-for-vsphere`. I've created a simple wrapper:

* Activate the Python virtualenv
* Retrieve the password for the vSphere connection
* Add local IP Address (one per vBMC instance)
* Start the `vbmcd` daemon
* Verify if the vBMC instance exist and eventually add it
* Start the IPMI service
* Check the IPMI status
* It's important to note that the vBMC name **MUST** match the VM's name in vSphere

Additionally, being a lab, during a cold OCP start if vBMC is not already running, Metal3 will lose the ability to manage the nodes until the `power status` is reset (*indeed, this is something to report upstream, losing connectivity with the BMC is relatively common: firmware upgrade, OoB upgrade, network outage etc*)

![](https://raw.githubusercontent.com/m4r1k/k8s_5g_lab/main/media/metal3_error.png)

```bash
cat > /root/vBMC.sh << 'EOF'
#!/bin/bash

echo -n "vCenter Administrator Password: "
read -s _PASSWORD
echo

_vCSACONNECTION="--viserver 192.168.178.11 --viserver-username administrator@vpshere.local --viserver-password ${_PASSWORD}"

source /root/vBMC/bin/activate

ip addr show ens160 | grep -q "192.168.178.25/24" || ip addr add 192.168.178.25/24 dev ens160
ip addr show ens160 | grep -q "192.168.178.26/24" || ip addr add 192.168.178.26/24 dev ens160
ip addr show ens160 | grep -q "192.168.178.27/24" || ip addr add 192.168.178.27/24 dev ens160
ip addr show ens160 | grep -q "192.168.178.28/24" || ip addr add 192.168.178.28/24 dev ens160
ip addr show ens160 | grep -q "192.168.178.29/24" || ip addr add 192.168.178.29/24 dev ens160
ip addr show ens160 | grep -q "192.168.178.30/24" || ip addr add 192.168.178.30/24 dev ens160

pkill -15 vbmcd
rm -f /root/.vbmc/master.pid
vbmcd

vbmc show "OCP4 BM - Master0" 2>/dev/null || vbmc add --username root --password calvin --address 192.168.178.25 --port 623 ${_vCSACONNECTION} "OCP4 BM - Master0"
vbmc show "OCP4 BM - Master1" 2>/dev/null || vbmc add --username root --password calvin --address 192.168.178.26 --port 623 ${_vCSACONNECTION} "OCP4 BM - Master1"
vbmc show "OCP4 BM - Master2" 2>/dev/null || vbmc add --username root --password calvin --address 192.168.178.27 --port 623 ${_vCSACONNECTION} "OCP4 BM - Master2"
vbmc show "OCP4 BM - Worker0" 2>/dev/null || vbmc add --username root --password calvin --address 192.168.178.28 --port 623 ${_vCSACONNECTION} "OCP4 BM - Worker0"
vbmc show "OCP4 BM - Worker1" 2>/dev/null || vbmc add --username root --password calvin --address 192.168.178.29 --port 623 ${_vCSACONNECTION} "OCP4 BM - Worker1"
vbmc show "OCP4 BM - Worker2" 2>/dev/null || vbmc add --username root --password calvin --address 192.168.178.30 --port 623 ${_vCSACONNECTION} "OCP4 BM - Worker2"

vbmc show "OCP4 BM - Master0" | grep status | grep -q running || vbmc start "OCP4 BM - Master0"
vbmc show "OCP4 BM - Master1" | grep status | grep -q running || vbmc start "OCP4 BM - Master1"
vbmc show "OCP4 BM - Master2" | grep status | grep -q running || vbmc start "OCP4 BM - Master2"
vbmc show "OCP4 BM - Worker0" | grep status | grep -q running || vbmc start "OCP4 BM - Worker0"
vbmc show "OCP4 BM - Worker1" | grep status | grep -q running || vbmc start "OCP4 BM - Worker1"
vbmc show "OCP4 BM - Worker2" | grep status | grep -q running || vbmc start "OCP4 BM - Worker2"

ipmitool -H 192.168.178.25 -U root -P calvin -p 623 -I lanplus power status
ipmitool -H 192.168.178.26 -U root -P calvin -p 623 -I lanplus power status
ipmitool -H 192.168.178.27 -U root -P calvin -p 623 -I lanplus power status
ipmitool -H 192.168.178.28 -U root -P calvin -p 623 -I lanplus power status
ipmitool -H 192.168.178.29 -U root -P calvin -p 623 -I lanplus power status
ipmitool -H 192.168.178.30 -U root -P calvin -p 623 -I lanplus power status
EOF
```
At this point, to run our vBMC server, just execute the following

```bash
chmod +x /root/vBMC.sh
/root/vBMC.sh
```

### 7.3 - NFS Server
This time around, the number of steps is way less. Let's install the NFS packages

```bash
dnf install nfs-utils nfs4-acl-tools sysstat -y
```
Let's enable the NFS Server

```
systemctl enable --now nfs-server
```

Let's make NFS fully accessible, restart the NFS client services and export it

```bash
chown -R nobody: /nfs
chmod -R 777 /nfs

cat > /etc/exports << 'EOF'
/nfs   10.0.11.0/27(rw,sync,no_all_squash,root_squash)
EOF

systemctl restart nfs-utils

exportfs -arv
```
And indeed open up the firewall

```bash
firewall-cmd --permanent --add-service=nfs
firewall-cmd --permanent --add-service=rpc-bind
firewall-cmd --permanent --add-service=mountd
firewall-cmd --reload
```
Once all done, the system can be rebooted to also pick up the newer Kernel

```bash
reboot
```
### 7.4 - Provisioner
Well, if the Router was kinda hard and the NFS Server definitely lighter, the Provisioner has more manual activities than what I'd personally expect from OCP. I guess that's due to the `version 1.0` effect. In short, we need to reconfigure the networking (adding two Linux bridge) and also install and configure Libvirt (and later download a *special* installer packer).

Let's start creating the `provisioning` bridge connected to our `OCP Provisioning` network. In this lab `ens192` is our device. What we're going to do is the following

* Delete the `ens192` connection details in NetworkManager
* Create the `provisioning` bridge and connect it to `ens192`
* Re-add its own Network settings
* IPv6 only link-local
* Disable STP (otherwise the connection takes 30 seconds to establish)

```bash
nmcli connection down ens192
nmcli connection delete ens192
nmcli connection add ifname provisioning type bridge con-name provisioning
nmcli con add type bridge-slave ifname ens192 master provisioning
nmcli connection modify provisioning ipv4.addresses 10.0.10.28/27 ipv4.method manual
nmcli connection modify provisioning ethernet.mtu 9000
nmcli connection modify bridge-slave-ens192 ethernet.mtu 9000
nmcli connection modify provisioning ipv6.method link-local
nmcli connection modify provisioning bridge.stp no
nmcli connection modify provisioning connection.autoconnect yes
nmcli connection down provisioning
nmcli connection up provisioning
```
The second bridge to create is the `baremetal` connected to our `OCP Baremetal`. Our SSH session is going through this link. *Looks like NetworkManager doesn't support performing a group of atomic operation at once* (I may be wrong of course), so we're going to execute an entire block of NetworkManager commands in an uninterruptible manner through `nohup`. Same as before

* Delete the `ens160` connection details in NetworkManager
* Create the `baremetal` bridge and connect it to `ens160`
* Re-add its own Network settings
* IPv6 only link-local
* Disable STP (otherwise the connection takes 30 seconds to establish)

```bash
nohup bash -c "
              nmcli connection down ens160
              nmcli connection delete ens160
              nmcli connection add ifname baremetal type bridge con-name baremetal
              nmcli con add type bridge-slave ifname ens160 master baremetal
              nmcli connection modify baremetal ipv4.addresses 10.0.11.28/27 ipv4.method manual
              nmcli connection modify baremetal ipv4.dns 10.0.11.30
              nmcli connection modify baremetal ipv4.gateway 10.0.11.30
              nmcli connection modify baremetal ethernet.mtu 9000
              nmcli connection modify bridge-slave-ens160 ethernet.mtu 9000
              nmcli connection modify baremetal ipv6.method link-local
              nmcli connection modify baremetal bridge.stp no
              nmcli connection modify baremetal connection.autoconnect yes
              nmcli connection down baremetal
              nmcli connection up baremetal
"
```
If the connection dropped, inspect the `nohup.out` file, it may reveal what went wrong :-D. Otherwise, that file can be deleted and we can install libvirt and start the service

```bash
dnf install -y libvirt qemu-kvm mkisofs python3-devel jq ipmitool OpenIPMI
systemctl enable --now libvirtd
```
Once done, let's add the a privilaged `kni` user, which ultimately kickstart the deployment

* Add the `kni` user
* No password
* Allow it to become root without prompting for password
* Add `kni` to the `libvirt` group

```bash
useradd kni
passwd --delete kni
echo "kni ALL=(root) NOPASSWD:ALL" | tee -a /etc/sudoers.d/kni
chmod 0440 /etc/sudoers.d/kni
usermod --append --groups libvirt kni
```
Let's finish the KNI user configuration. **Connect to the KNI user first**

* Create an SSH Key (*optionally*, you can import your own)
* Define the default Libvirt storage pool

```bash
sudo su - kni
ssh-keygen -b 2048 -t rsa -f ~/.ssh/id_rsa -q -N ""
sudo virsh pool-define-as --name default --type dir --target /var/lib/libvirt/images
sudo virsh pool-start default
sudo virsh pool-autostart default
```
Lastly, let's reboot the system to also pick up the newer Kernel

```bash
reboot
```

### 7.5 - OpenShift deployment
Once all the above is done, it's finally time to perform the deployment of OCP. As the [official procedure clearly hint](https://docs.openshift.com/container-platform/4.6/installing/installing_bare_metal_ipi/ipi-install-installation-workflow.html), there are many manual steps needed before we can truly start. Hopefully, in the future, the product will require fewer human interactions.

As a first step, we need to install a different kind of `openshift-install` client, which includes the baremetal *Metal3* provider. It's called `openshift-baremetal-install`. *Honestly, I don't even understand why there is a dedicated client-specific for baremetal, anyways ...* to download it you need your Pull Secret. You can [download it manually](https://cloud.redhat.com/openshift/install/metal/user-provisioned) or create a neat `showpullsecret` CLI command [following this KCS](https://access.redhat.com/solutions/4844461). In both ways, ensure you have it locally available at `~/pull-secret.json`. With that out of the way, we can finally download the baremetal client

```bash
_CMD=openshift-baremetal-install
_PULLSECRETFILE=~/pull-secret.json
_DIR=/home/kni/
_VERSION=latest-4.6
_URL="https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${_VERSION}"

_RELEASE_IMAGE=$(curl -s ${_URL}/release.txt | grep 'Pull From: quay.io' | awk -F ' ' '{print $3}')


curl -s ${_URL}/openshift-client-linux.tar.gz | tar zxvf - oc
sudo mv -f oc /usr/local/bin
oc adm release extract \
  --registry-config "${_PULLSECRETFILE}" \
  --command=${_CMD} \
  --to "${_DIR}" ${_RELEASE_IMAGE}

sudo mv -f openshift-baremetal-install /usr/local/bin
```

Optionally you could [configure a local image cache](https://docs.openshift.com/container-platform/4.6/installing/installing_bare_metal_ipi/ipi-install-installation-workflow.html#ipi-install-creating-an-rhcos-images-cache_ipi-install-installation-workflow) and in case of slow Internet connection, you should. I'm personally not going to explain it now in this first release. In the next follow-up, local cache and local OCI mirror will be both included (in the lab diagram, a local registry is already present).

Now the next major task is writing down the `install-config.yaml` file, on the [official document you have examples](https://docs.openshift.com/container-platform/4.6/installing/installing_bare_metal_ipi/ipi-install-installation-workflow.html#configuring-the-install-config-file_ipi-install-configuration-files) and also [all the options](https://docs.openshift.com/container-platform/4.6/installing/installing_bare_metal_ipi/ipi-install-installation-workflow.html#additional-install-config-parameters_ipi-install-configuration-files), there are only two thing to keep in mind:

* `provisioningNetworkInterface` rappresents the name of the interface in the Master which is connected to Provisioning Network (in my case `ens160`)
* In case you don't have enough resources to run 3 Workers, you can adjust down `compute.replicas`, see the official indications

Follows you can find my working `install-config`. The initial deployment goes without the physical Worker Node(s). They are included later together with a custom MachineSet.

```yaml
apiVersion: v1
baseDomain: bm.nfv.local
metadata:
  name: ocp4
networking:
  machineCIDR: 10.0.11.0/27
  networkType: OVNKubernetes
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  serviceNetwork:
  - 172.30.0.0/16
compute:
- name: worker
  replicas: 3
controlPlane:
  name: master
  replicas: 3
  platform:
    baremetal: {}
platform:
  baremetal:
    apiVIP: 10.0.11.18
    ingressVIP: 10.0.11.19
    provisioningBridge: provisioning
    provisioningNetworkInterface: ens160
    provisioningNetworkCIDR: 10.0.10.0/27
    provisioningDHCPRange: 10.0.10.5,10.0.10.17
    externalBridge: baremetal
    bootstrapProvisioningIP: 10.0.10.3
    clusterProvisioningIP: 10.0.10.4
    hosts:
      - name: openshift-master-0
        role: master
        bmc:
          address: ipmi://192.168.178.25
          username: root
          password: calvin
        bootMACAddress: 00:50:56:8e:3b:92
      - name: openshift-master-1
        role: master
        bmc:
          address: ipmi://192.168.178.26
          username: root
          password: calvin
        bootMACAddress: 00:50:56:8e:81:cf
      - name: openshift-master-2
        role: master
        bmc:
          address: ipmi://192.168.178.27
          username: root
          password: calvin
        bootMACAddress: 00:50:56:8e:50:a1
      - name: openshift-worker-0
        role: master
        bmc:
          address: ipmi://192.168.178.28
          username: root
          password: calvin
        bootMACAddress: 00:50:56:8e:b5:6e
      - name: openshift-worker-1
        role: master
        bmc:
          address: ipmi://192.168.178.29
          username: root
          password: calvin
        bootMACAddress: 00:50:56:8e:11:9f
      - name: openshift-worker-2
        role: master
        bmc:
          address: ipmi://192.168.178.30
          username: root
          password: calvin
        bootMACAddress: 00:50:56:8e:72:bf
fips: false
pullSecret: '{"auths":{<SNIP>}}'
sshKey: 'ssh-rsa <SNIP>'
```
The initial deployment may fail due to multiple reasons:

* Timeout due to slow Internet speed -> enable RHCOS image cache and/or local OCI registry
* DHCP issues (wrong IP, wrong Hostname, no DHCP) -> Check DNSMasq (if there is matching between `dns.dnsmasq` and `hosts.dnsmasq` no weird issues should happen
* No Internet -> Check the Router and specifically the Firewalld's Masquerade
* Not able to provide DHCP from the Provisioner -> You didn't disable the security features in vDS
* VMware VMs stuck in boot loop -> Disable `Secure Boot` or switch to `BIOS`
* Not able to boot the Bastion VM on the provisioner -> `Nested Virtualization` not enabled

To deploy, let's copy the `install-config.yaml` into a new folder and then run the installation

```bash
mkdir ~/manifests
cp ~/install-config.yaml ~/manifests/
openshift-baremetal-install create cluster --dir ~/manifests --log-level debug
```

#TODO PXE BOOT Console

Follows the installation logs
```console
DEBUG OpenShift Installer 4.6.12
DEBUG Built from commit eded5eb5b6c77e2af2a2c537093da8bf3711f494
<SNIP>
DEBUG module.masters.ironic_node_v1.openshift-master-host[2]: Creating...
DEBUG module.masters.ironic_node_v1.openshift-master-host[1]: Creating...
DEBUG module.masters.ironic_node_v1.openshift-master-host[0]: Creating...
DEBUG module.bootstrap.libvirt_pool.bootstrap: Creating...
DEBUG module.bootstrap.libvirt_ignition.bootstrap: Creating...
<SNIP>
DEBUG module.bootstrap.libvirt_pool.bootstrap: Creation complete after 2m0s
<SNIP>
DEBUG module.bootstrap.libvirt_ignition.bootstrap: Creation complete after 2m0s
<SNIP>
DEBUG module.masters.ironic_node_v1.openshift-master-host[2]: Creation complete after 17m13s
DEBUG module.masters.ironic_node_v1.openshift-master-host[1]: Creation complete after 17m13s
DEBUG module.masters.ironic_node_v1.openshift-master-host[0]: Creation complete after 17m13s
<SNIP>
DEBUG module.masters.ironic_deployment.openshift-master-deployment[1]: Creating...
DEBUG module.masters.ironic_deployment.openshift-master-deployment[0]: Creating...
DEBUG module.masters.ironic_deployment.openshift-master-deployment[2]: Creating...
<SNIP>
DEBUG module.masters.ironic_deployment.openshift-master-deployment[2]: Creation complete after 1m31s
DEBUG module.masters.ironic_deployment.openshift-master-deployment[1]: Creation complete after 1m31s
DEBUG module.masters.ironic_deployment.openshift-master-deployment[0]: Creation complete after 1m31s
<SNIP>
DEBUG Apply complete! Resources: 13 added, 0 changed, 0 destroyed.
DEBUG OpenShift Installer 4.6.12
DEBUG Built from commit eded5eb5b6c77e2af2a2c537093da8bf3711f494
INFO Waiting up to 20m0s for the Kubernetes API at https://api.ocp4.bm.nfv.local:6443...
INFO API v1.19.0+9c69bdc up
INFO Waiting up to 30m0s for bootstrapping to complete...
DEBUG Bootstrap status: complete
INFO Destroying the bootstrap resources...
<SNIP>
INFO Waiting up to 1h0m0s for the cluster at https://api.ocp4.bm.nfv.local:6443 to initialize...
DEBUG Still waiting for the cluster to initialize: Working towards 4.6.12: 30% complete
DEBUG Still waiting for the cluster to initialize: Working towards 4.6.12: 42% complete
DEBUG Still waiting for the cluster to initialize: Working towards 4.6.12: 61% complete
DEBUG Still waiting for the cluster to initialize: Working towards 4.6.12: 67% complete
DEBUG Still waiting for the cluster to initialize: Multiple errors are preventing progress:
* Could not update build "cluster" (19 of 617)
<SNIP>
* Could not update oauthclient "console" (379 of 617)
<SNIP>
DEBUG Still waiting for the cluster to initialize: Working towards 4.6.12: 95% complete
<SNIP>
DEBUG Still waiting for the cluster to initialize: Working towards 4.6.12: 100% complete
DEBUG Cluster is initialized
INFO Waiting up to 10m0s for the openshift-console route to be created...
<SNIP>
INFO Install complete!
INFO To access the cluster as the system:admin user when using 'oc', run 'export KUBECONFIG=/home/kni/ocp-telco-lab/manifests/auth/kubeconfig'
INFO Access the OpenShift web-console here: https://console-openshift-console.apps.ocp4.bm.nfv.local
INFO Login to the console with user: "kubeadmin", and password: "qDovf-CxYp8-VzVv9-uRkpC"
DEBUG Time elapsed per stage:
DEBUG     Infrastructure: 18m54s
DEBUG Bootstrap Complete: 11m11s
DEBUG  Bootstrap Destroy: 14s
DEBUG  Cluster Operators: 30m28s
INFO Time elapsed: 1h0m56s
```

Once the deployment is over, we can proceed with the first step: the authentication. To make things simple, we will rely upon `HTPasswd`. Single `admin` user with password `admin`, later this will give the flexibility to add additional users with fewer privileges.

```bash
htpasswd -c -b -B /home/kni/htpasswd admin admin
```
Let's then create a secret with the admin's user credential

```bash
export KUBECONFIG=~/manifests/auth/kubeconfig

oc create secret generic htpasswd-secret --from-file=htpasswd=/home/kni/htpasswd -n openshift-config
```

We're now going to create a config file for `OAuth` where we say to use `HTPasswd` as another Identity Provider and to take the `htpasswd` file from the secret. Follows my working file

```yaml
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
  - name: ocp4.bm.nfv.local
    mappingMethod: claim
    type: HTPasswd
    htpasswd:
      fileData:
        name: htpasswd-secret
```
Then, as usual, let's apply it and then grant role `cluster-admin` and `registry-editor` to the `admin` user

```bash
oc apply -f <path/to/oauth/yaml>`
oc adm policy add-cluster-role-to-user cluster-admin admin
oc policy add-role-to-user registry-editor admin
```

Last step, let's first test the new login credentials and **IF SUCCESFUL** delete the `kubeadmin` user
```bash
unset KUBECONFIG
oc login https://api.ocp4.bm.nfv.local:6443 \
    --username=admin --password=admin \
    --insecure-skip-tls-verify=true

oc delete secrets kubeadmin -n kube-system --ignore-not-found=true
```

It's time to connect to the OpenShift Console. The router already allows the communication both ways. Simply add a `static route` and also use the router as your DNS.

# TODO Console Pic

### 7.6 - Adding Physical OpenShift Nodes
Now let's add some real physical nodes to the cluster. It's important to create a new MachineSet in this way, we have a clear demarcation mark between real physical nodes and virtual ones. This is gonna be instrumental later on for PAO. *Happening through the `hostSelector.matchLabels` who looks for `node-role.kubernetes.io/worker-cnf`*

Follows the working template to import, be aware, you will need to customize RHCOS image `spec.template.spec.providerSpec.value.checksum` and `spec.template.spec.providerSpec.value.url`. You can see them by using `oc describe MachineSet -n openshift-machine-api`. Additionally also the Cluster ID needs to be contextualized use `oc get -o jsonpath='{.status.infrastructureName}' infrastructure cluster` to retrive it (in my case `ocp4-d9lqz`).

```yaml
apiVersion: machine.openshift.io/v1beta1
kind: MachineSet
metadata:
  creationTimestamp: null
  labels:
    machine.openshift.io/cluster-api-cluster: ocp4-d9lqz
  name: ocp4-d9lqz-worker-cnf
  namespace: openshift-machine-api
spec:
  replicas: 0
  selector:
    matchLabels:
      machine.openshift.io/cluster-api-cluster: ocp4-d9lqz
      machine.openshift.io/cluster-api-machineset: ocp4-d9lqz-worker-cnf
  template:
    metadata:
      labels:
        machine.openshift.io/cluster-api-cluster: ocp4-d9lqz
        machine.openshift.io/cluster-api-machine-role: worker-cnf
        machine.openshift.io/cluster-api-machine-type: worker-cnf
        machine.openshift.io/cluster-api-machineset: ocp4-d9lqz-worker-cnf
    spec:
      taints:
      - effect: NoSchedule
        key: node-function
        value: cnf
      metadata:
        creationTimestamp: null
      providerSpec:
        value:
          apiVersion: baremetal.cluster.k8s.io/v1alpha1
          kind: BareMetalMachineProviderSpec
          hostSelector:
            matchLabels:
              node-role.kubernetes.io/worker-cnf: ""
          image:
            checksum: >-
              http://10.0.10.3:6180/images/rhcos-46.82.202011260640-0-openstack.x86_64.qcow2/rhcos-46.82.202011260640-0-compressed.x86_64.qcow2.md5sum
            url: >-
              http://10.0.10.3:6180/images/rhcos-46.82.202011260640-0-openstack.x86_64.qcow2/rhcos-46.82.202011260640-0-compressed.x86_64.qcow2
          metadata:
            creationTimestamp: null
          userData:
            name: worker-user-data
```

The template can be deployed with a simple `oc apply -f <path/to/machine/set/yaml>` ([BTW, about `create` vs. `apply`](https://stackoverflow.com/questions/47369351/kubectl-apply-vs-kubectl-create)).

Once that's done, we can also provision the new node, follows my working template. Ensure the same labels between the MachineSet's `hostSelector.matchLabels` and `metadata.labels` here.

```yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: openshift-worker-3-bmc-secret
  namespace: openshift-machine-api
type: Opaque
data:
  username: cm9vdA==
  password: Y2Fsdmlu
---
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: openshift-worker-3
  namespace: openshift-machine-api
  labels:
    node-role.kubernetes.io/worker-cnf: ""
spec:
  online: true
  bootMACAddress: ec:f4:bb:dd:96:28
  bmc:
    address: redfish://192.168.178.232/redfish/v1/Systems/System.Embedded.1
    credentialsName: openshift-worker-3-bmc-secret
    disableCertificateVerification: True
```

Also this time an `oc apply -f <path/to/node/yaml>` gets the job done. To check the status use `oc get BareMetalHost -n openshift-machine-api` once it goes into provisioning's state `ready`, you can scale the MachineSet and the node will be included into the cluster `oc scale --replicas=1 machineset ocp4-d9lqz-worker-cnf -n openshift-machine-api`

This is how it will look like once deployed

```console
oc get BareMetalHost,Nodes -n openshift-machine-api
NAME                                         STATUS   PROVISIONING STATUS      CONSUMER                           BMC                                                              HARDWARE PROFILE   ONLINE   ERROR
baremetalhost.metal3.io/openshift-master-0   OK       externally provisioned   ocp4-d9lqz-master-0                ipmi://192.168.178.25                                                               true
baremetalhost.metal3.io/openshift-master-1   OK       externally provisioned   ocp4-d9lqz-master-1                ipmi://192.168.178.26                                                               true
baremetalhost.metal3.io/openshift-master-2   OK       externally provisioned   ocp4-d9lqz-master-2                ipmi://192.168.178.27                                                               true
baremetalhost.metal3.io/openshift-worker-0   OK       provisioned              ocp4-d9lqz-worker-0-z6vwn          ipmi://192.168.178.28                                            unknown            true
baremetalhost.metal3.io/openshift-worker-1   OK       provisioned              ocp4-d9lqz-worker-0-9rwnf          ipmi://192.168.178.29                                            unknown            true
baremetalhost.metal3.io/openshift-worker-2   OK       provisioned              ocp4-d9lqz-worker-0-g2227          ipmi://192.168.178.30                                            unknown            true
baremetalhost.metal3.io/openshift-worker-3   OK       provisioned              ocp4-d9lqz-worker-cnf-6bbkc   redfish://192.168.178.232/redfish/v1/Systems/System.Embedded.1   unknown            true

NAME                      STATUS   ROLES    AGE     VERSION
node/openshift-master-0   Ready    master   27h     v1.19.0+9c69bdc
node/openshift-master-1   Ready    master   27h     v1.19.0+9c69bdc
node/openshift-master-2   Ready    master   27h     v1.19.0+9c69bdc
node/openshift-worker-0   Ready    worker   27h     v1.19.0+9c69bdc
node/openshift-worker-1   Ready    worker   27h     v1.19.0+9c69bdc
node/openshift-worker-2   Ready    worker   27h     v1.19.0+9c69bdc
node/openshift-worker-3   Ready    worker   3h10m   v1.19.0+9c69bdc
```

### 7.7 - NFS Storage Class and OCP internal Registry
Next step is to lavarage the RHEL NFS Server for persistent storage. Luckly this is uber easy (don't forget to [install the `helm` CLI](https://mirror.openshift.com/pub/openshift-v4/clients/helm/latest)). See the official documentation for [all the supported options by the Helm Chart](https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner/blob/master/charts/nfs-subdir-external-provisioner/README.md) (such as `storageClass.accessModes`, `nfs.mountOptions`, `storageClass.reclaimPolicy`, etc)

* Add NFS SIG Repo
* Install the NFS SIG

```bash

_NAMESPACE="nfs-external-provisioner"

helm repo add nfs-subdir-external-provisioner \
     https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/

helm install nfs-subdir-external-provisioner \
     nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
     --set nfs.server=nfs-server \
     --set nfs.path=/nfs
     --set storageClass.defaultClass=true \
     --create-namespace ${_NAMESPACE}
```
In case you face issues with the SCC, make sure to add it to the namespace

```bash
_NAMESPACE="nfs-external-provisioner"
oc adm policy add-scc-to-user hostmount-anyuid system:serviceaccount:${_NAMESPACE}:nfs-client-provisioner
```
To actually see (and check) the result, run the following

```
oc get events -n nfs-external-provisioner --sort-by='lastTimestamp'
oc get all -n nfs-external-provisioner
```
Installing the NFS Storage Class was very easy, now let's ensure the internal OCP Registry will user it

* Set the Registry status as `managed`
* Define the storage to claim a PVC (and by default the system will make a claim from the default `StorageClass`)
* Expose the Registry to the outside

```bash
oc patch configs.imageregistry.operator.openshift.io/cluster --type merge --patch '{"spec":{"managementState":"Managed"}}'

oc patch configs.imageregistry.operator.openshift.io/cluster --type merge --patch '{"spec":{"storage":{"pvc":{"claim":""}}}}'

oc patch configs.imageregistry.operator.openshift.io/cluster --type merge -p '{"spec":{"defaultRoute":true}}'

oc get pvc -n openshift-image-registry
```

Let's check the status, first logging in to the registry and then pushing an `alpine`

```bash
_HOST=$(oc get route default-route -n openshift-image-registry --template='{{ .spec.host }}')
sudo podman login -u $(oc whoami) -p $(oc whoami -t) --tls-verify=false ${_HOST}
sudo podman image pull docker.io/library/alpine:latest
sudo podman image tag docker.io/library/alpine:latest ${_HOST}/default/alpine:latest
sudo podman image push ${_HOST}/default/alpine:latest --tls-verify=false
sudo podman search ${_HOST}/ --tls-verify=false
```

### 7.8 - LoadBalancer Class
Something currently missing from OCP for Baremetal is a LoadBalancer. We're going to use MetalLB here.

* Create the `metallb-system` namespace
* Grant privilaged status for `speaker` user in the `metallb-system` namespace
* Deploy MetalLB removing the hardcoded UID
* Generate a secret key

```
_VER="v0.9.5"

oc create -f https://raw.githubusercontent.com/metallb/metallb/${_VER}/manifests/namespace.yaml

oc adm policy add-scc-to-user privileged -n metallb-system -z speaker

curl -s https://raw.githubusercontent.com/metallb/metallb/${_VER}/manifests/metallb.yaml | sed -e "/runAsUser: 65534/d" | oc create -f -

oc create secret generic -n metallb-system memberlist --from-literal=secretkey="$(openssl rand -base64 128)"
```
Once done, we need to write the MetalLB L2 configuration (BGP will be covered in a future update of this document). In my lab, I've dedicated these 5 IPs from the Baremetal Network range.

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: metallb-system
  name: config
data:
  config: |
    address-pools:
    - name: default
      protocol: layer2
      addresses:
      - 10.0.11.20-10.0.11.24
```

As usual `oc apply -f <path/to/meltallb/config>` and the MetalLB configuration is done.

### 7.9 - Basic HelloWorld
To prove that the setup is working, let's deploy a simple HelloWorld.

```bash
kubectl create namespace hello-k8s
kubectl apply -f https://raw.githubusercontent.com/paulbouwer/hello-kubernetes/master/yaml/hello-kubernetes.yaml -n hello-k8s
```
To check the status, run the following commands

```bash
kubectl get pods -n hello-k8s
kubectl get deployment -n hello-k8s
kubectl get services -n hello-k8s
```
Connecting to the LoadBalancer External-IP, the HelloWorld should be available

```bash
$ oc get services -n hello-k8s
NAME               TYPE           CLUSTER-IP       EXTERNAL-IP   PORT(S)        AGE
hello-kubernetes   LoadBalancer   172.30.247.222   10.0.11.20    80:32742/TCP   24h
```
