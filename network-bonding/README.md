# IPI Link Aggregation for physical nodes
This section aims to explain how to configure Link Aggregation in the platform in an IPI deployment.

While originally it was supposed to be part of the main document, due to limitations with `NMState` and `OVN-Kubernetes` I decided to create a separate document. This solution is only temporary and, more importantly, **not** declarative. Ultimately as soon as RHCOS moves to NetworkManager 1.3, `NMState` will handle the [complete networking layout nicely](https://www.nmstate.io/devel/api.html).

To deploy an IPI platform with an advanced networking topology, essentially, we need to customize the CoreOS Image.

The documentation around this topic is limited at best; My method may have flaws or typical day2 short-term issues (for example, for me is still unclear how to handle the life-cycle of these customized images).

## NetworkManager Configuration

The first, and probably the hardest, thing to do is crafting the NetworkManager configuration. The documentation around this topic is vague, and it looks like everybody has a different option. So, I'll give you mine too :-)

To come up with a working NetworkManager configuration, I ran a CentOS 8 Stream on my target hardware, configured the networking through `nmcli` (the `nmtui` and Gnome's NetworkManager GUI utilities are very convenient!), **tested it**, and then it acts as a working reference configuration. Using `nmcli connection show <Connection Name>` (of course, you need to clean up many things), you can see all the details.

This approach has two main advantages:
- The configuration is crafted directly from NetworkManager
- Pre-tested on the target hardware

*As an alternative and more synthetical approach, you can also look at the [NetworkManager tests](https://github.com/NetworkManager/NetworkManager-ci/blob/master/nmcli/features/bond.feature) for the bonding*
## CoreOS `nmconnection`

The next step is to create the network configuration files for RHCOS, taking as input all the details from NetworkManager done earlier.

Here my network topology
- First server interface `eno1` dedicated for the Provisioning network
- LACP Lag between second and third interfaces (respectively `eno2` and `eno3`)
- VLAN110 for the Baremetal network out of the LACP Lag

Based on the network topology, follows the configuration
- LACP Bond with two slaves interfaces (`eno2` and `eno3`)
- MAC Address of the **first** slave interface is also configured in the `install-config.yaml` and DNSMasq
- A VLAN interface with DHCP enable for the Baremetal Network

During the installation, the [OpenShift MCO will automatically connect the VLAN interface](https://github.com/trozet/machine-config-operator/commit/64b79df) under Open vSwitch's `br-ex` and [all the DHCP details](https://github.com/openshift/machine-config-operator/pull/2264) are also taken care of.

Follows the `bond0.nmconnection` config file for the bond
```ini
[connection]
id=bond0
type=bond
interface-name=bond0
[bond]
miimon=1
mode=802.3ad
[ipv4]
method=disabled
[ipv6]
method=disabled
```

Follows the `bond0-slave-1.nmconnection` config file for the first slave interface
```ini
[connection]
id=bond0-slave-1
type=ethernet
interface-name=eno2
master=bond0
slave-type=bond
```

Follows the `bond0-slave-2.nmconnection` config file for the second slave interface
```ini
[connection]
id=bond0-slave-2
type=ethernet
interface-name=eno3
master=bond0
slave-type=bond
```

Follows the `bond0.110.nmconnection` config file for the VLAN interface of the Baremetal Network, a few things to notice:
- `multi-connect=1` is required to migrate the interface under OVS's `br-ex` without any issue
- IPv4 `method=auto` to enable DHCP
- IPv6 `method=disabled` to disable DHCP
```ini
[connection]
id=bond0.110
type=vlan
interface-name=bond0.110
multi-connect=1
[vlan]
flags=1
id=110
parent=bond0
[ipv4]
may-fail=false
method=auto
[ipv6]
method=disabled
```

## CoreOS Image Customization
Okay, here the details on Internet are even less available. Simply put, CoreOS has a [facility to customize](https://github.com/coreos/fedora-coreos-config/blob/stable/overlay.d/05core/usr/lib/dracut/modules.d/35coreos-network/coreos-copy-firstboot-network.sh) the networking. All we need to do is copying the `nmconnection` config files in the [boot of the CoreOS image](https://github.com/coreos/fedora-coreos-config/blob/stable/overlay.d/05core/usr/lib/dracut/modules.d/35coreos-network/coreos-copy-firstboot-network.sh#L10). *This last bit was quite hard to figure out* -.-'

First things first, let's download the RHCOS Cluster OS Image (called `rhcos-openstack.x86_64.qcow2.gz`) which is available at https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/

Once done, let's extract the content (`pigz` is far faster thanks to its multi-threading than more traditional `gzip` and `gunzip`)
```bash
pigz --decompress --keep --verbose ~/rhcos-4.7.0-x86_64-openstack.x86_64.qcow2.gz
```

Then let's discover the Boot Partition (you need to install the `libguestfs-tools` package)
```bash
guestfish --ro -a ~/rhcos-4.7.0-x86_64-openstack.x86_64.qcow2 run : findfs-label boot : exit
```
In the output, you will have the boot device such as **`/dev/sda3`**

Once done, let's create the folder and copy all our `nmconnection` file
```bash
guestfish -a ~/rhcos-4.7.0-x86_64-openstack.x86_64.qcow2 \
  -m /dev/sda3 \
  mkdir-p /coreos-firstboot-network : \
  copy-in *.nmconnection /coreos-firstboot-network
```

To verify the content, see the following example
```console
# guestfish --ro -a ~/rhcos-4.7.0-x86_64-openstack.x86_64.qcow2 -m /dev/sda3 \
  ls /coreos-firstboot-network : \
  cat /coreos-firstboot-network/bond0.nmconnection
bond0-slave-1.nmconnection
bond0-slave-2.nmconnection
bond0.110.nmconnection
bond0.nmconnection
[connection]
id=bond0
type=bond
interface-name=bond0
[bond]
miimon=1
mode=802.3ad
primary=ens192
[ipv4]
method=disabled
[ipv6]
method=disabled
```

## Expose the Cluster OS Image

We now have only a few remaining steps. Let's start with the image compression
```bash
pigz --stdout ~/rhcos-4.7.0-x86_64-openstack.x86_64.qcow2 > ~/rhcos-4.7.0-x86_64-openstack-bonding-v1.x86_64.qcow2.gz
```

Then let's calculate the SHA256 (later to be used in the `install-config`)
```bash
sha256sum ~/rhcos-4.7.0-x86_64-openstack-bonding-v1.x86_64.qcow2.gz
```

On my Router VM, I'll run a simple `HTTPD` webserver to expose the image on port 8080
```bash
mkdir /var/lib/image-cache
podman create -it --name image-cache \
  -p 8080:80 \
  -v /var/lib/image-cache:/usr/local/apache2/htdocs:Z \
  docker.io/library/httpd:2.4

podman generate systemd image-cache > /etc/systemd/system/image-cache-container.service
```

Let's open the firewall and run the systemd `image-cache-container` service
```bash
firewall-cmd --permanent --zone=internal --add-port=8080/tcp
firewall-cmd --reload
systemctl daemon-reload
systemctl enable --now image-cache-container.service
```

The last step, copy the `rhcos-4.7.0-x86_64-openstack-bonding-v1.x86_64.qcow2.gz` under `/var/lib/image-cache` and is done :-)

## Use the customized image

In the `install-config.yaml` define the `clusterOSImage` under `platform.baremetal` having care also to specify the Image's SHA256
```yaml
platform:
  baremetal:
    clusterOSImage: http://10.0.11.30:8080/rhcos-4.7.0-x86_64-openstack-bonding-v1.x86_64.qcow2.gz?sha256=43cea5505284d429b15a1c50e1768035685b363329a4e1c8e8e3b65ee82dae1c
```

And how does it look the final result? Well, we can see that inside the `br-ex` we have the `bond0.110` Linux interface and also that `br-ex` has not only the baremetal IP Address but also the `bond0` MAC Address.

```console
[root@openshift-worker-cnf-1 ~]# ovs-vsctl show
<SNIP>
    Bridge br-ex
        Port bond0.110
            Interface bond0.110
                type: system
        Port patch-br-ex_vh10-to-br-int
            Interface patch-br-ex_vh10-to-br-int
                type: patch
                options: {peer=patch-br-int-to-br-ex_vh10}
        Port br-ex
            Interface br-ex
                type: internal
    ovs_version: "2.13.2"
[root@openshift-worker-cnf-1 ~]# ip address show br-ex
9: br-ex: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UNKNOWN group default qlen 1000
    link/ether ec:f4:bb:dd:96:29 brd ff:ff:ff:ff:ff:ff
    inet 10.0.11.11/27 brd 10.0.11.31 scope global dynamic noprefixroute br-ex
       valid_lft 3082sec preferred_lft 3082sec
    inet6 fe80::502b:19fd:a08d:f14f/64 scope link noprefixroute
       valid_lft forever preferred_lft forever
```