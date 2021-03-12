# Harbor Readme

As mentioned in the main readme document, the platform also has a local registry.

The OpenShift integrated registry is nice but lacks a WebUI, scanning and replication capability. Harbor does that and is also **simple**. To set it up is literally few commands to prep the OS and then VMware provides an official [installation shell script](https://github.com/goharbor/harbor/blob/master/make/install.sh). *I wish was that easy to also use Quay.*

Just deploy a CentOS 8 Stream/RHEL8 VM, minimal install with [enough system resources](https://goharbor.io/docs/2.2.0/install-config/installation-prereqs/).

Once done, first copy the RootCA `crt` and `key` under `/root` and then run the [`harbor.sh`](https://github.com/m4r1k/k8s_5g_lab/blob/main/harbor/harbor.sh) in this repository and you're done. Keep in mind that all Harbor data is under `/data`

<img src="https://github.com/m4r1k/k8s_5g_lab/raw/main/media/harbor.png" width="75%" />

## Mirror OCP4 Contents
Well, few but important steps:
 - Create a new namespace in Harbor, or use the default `library` (in my example is called ocp4)
 - Create a new user in Harbor, or use `admin` (using admin)
 - In case a new user is created, ensure it has access to the new namespace

You need then to create the `pull-secret`, mine looks like the following
```json
{
  "auths": {
    "cloud.openshift.com": {
      "auth": "<SNAP>",
      "email": "fiezzi@redhat.com"
    },
    "quay.io": {
      "auth": "<SNAP>",
      "email": "fiezzi@redhat.com"
    },
    "registry.connect.redhat.com": {
      "auth": "<SNAP>",
      "email": "fiezzi@redhat.com"
    },
    "registry.redhat.io": {
      "auth": "<SNAP>",
      "email": "fiezzi@redhat.com"
    },
    "harbor.ocp4.bm.nfv.io": {
      "auth": "<SNAP>",
      "email": "ocp4@ocp4.bm.nfv.io"
    }
  }
}
```

To generate the one for `harbor.ocp4.bm.nfv.io` you just need the Base64 of `username:password`
```console
# echo -n 'admin:Harbor12345' | base64 -w0
YWRtaW46SGFyYm9yMTIzNDU=
```

Once done, from the provisioning (or anywhere with the latest `oc` CLI) run the following (here the mirroring will be OCP 4.7.0 but you can choose a different version)

```bash
LOCAL_SECRET_JSON=~/pull-secret_harbor.json
PRODUCT_REPO="openshift-release-dev"
RELEASE_NAME="ocp-release"
OCP_RELEASE="4.7.0"
ARCHITECTURE="x86_64"
LOCAL_REGISTRY="harbor.ocp4.bm.nfv.io"
LOCAL_REPOSITORY="ocp4/openshift4"

oc adm -a ${LOCAL_SECRET_JSON} release mirror \
  --from=quay.io/${PRODUCT_REPO}/${RELEASE_NAME}:${OCP_RELEASE}-${ARCHITECTURE} \
  --to=${LOCAL_REGISTRY}/${LOCAL_REPOSITORY} \
  --to-release-image=${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}:${OCP_RELEASE}-${ARCHITECTURE}
```
## Mirror OperatorHub
If you want to mirror the four OCP OperatorHub (`redhat-operator-index`, `certified-operator-index`, `redhat-marketplace-index`, and `community-operator-index`) make sure to enlarge the NGiNX Client Header Buffers otherwise you will get an HTTP error 414.

You can do it as follows. Additionally, I open a PR [to fix the problem upstream](https://github.com/goharbor/harbor/pull/14429).
```bash
cat > /root/harbor/harbor/common/config/nginx/conf.d/uploads.upstream.conf << EOF
fastcgi_buffers 8 16k;
fastcgi_buffer_size 32k;

client_body_buffer_size 128k;

client_header_buffer_size 5120k;
large_client_header_buffers 16 5120k;
EOF
docker restart nginx
```

To initiate the OperatorHub mirroring, run the following shell script (remember to create the `ocp4_operatorhub` namespace in Harbor)
```bash
oc adm catalog mirror \
  registry.redhat.io/redhat/redhat-operator-index:v4.7 \
  harbor.ocp4.bm.nfv.io/ocp4_operatorhub \
  a ~/pull-secret_harbor.json \
  --filter-by-os=linux/amd64 \
  --max-per-registry=64
```

## Verify OCP Release information
The following is an example for OCP 4.7.0 for x86
```console
# oc adm release info quay.io/openshift-release-dev/ocp-release:4.7.0-x86_64
Name:           4.7.0
Digest:         sha256:d74b1cfa81f8c9cc23336aee72d8ae9c9905e62c4874b071317a078c316f8a70
Created:        2021-02-22T09:03:37Z
OS/Arch:        linux/amd64
Manifests:      480
Metadata files: 1

Pull From: quay.io/openshift-release-dev/ocp-release@sha256:d74b1cfa81f8c9cc23336aee72d8ae9c9905e62c4874b071317a078c316f8a70

Release Metadata:
  Version:  4.7.0
  Upgrades: 4.6.15, 4.6.16, 4.6.17, 4.6.18, 4.6.19, 4.7.0-fc.1, 4.7.0-fc.2, 4.7.0-fc.3, 4.7.0-fc.4, 4.7.0-fc.5, 4.7.0-rc.1, 4.7.0-rc.2, 4.7.0-rc.3
  Metadata:
    url: https://access.redhat.com/errata/RHSA-2020:5633

Component Versions:
  kubernetes 1.20.0-beta.2
  machine-os 47.83.202102090044-0 Red Hat Enterprise Linux CoreOS

Images:
  NAME                                           DIGEST
  aws-ebs-csi-driver                             sha256:9d1d8cc8f9d4b5b03918fbead0b15053a6bc83c8ede8489cc2544e6ee85325aa
  aws-ebs-csi-driver-operator                    sha256:019cfb83cbaba44bdae4fd12819bacceae9b562982d6c4b86f7e144c31c441de
  aws-machine-controllers                        sha256:2d7a3a8d14b161fc0245bf33a672a4e917e103492770b5829c2941b462904aa3
  aws-pod-identity-webhook                       sha256:30d25b2bd9a7bd9ff59ed4fe15fe3b2628f09993004fd4bf318a80ab0715809c
  azure-machine-controllers                      sha256:7def5045fa042d3b563fafa52b5e87d897e0362314be8f7f56f84c94d2ffd65a
  baremetal-installer                            sha256:09850bd26871446b32ee0920b330182b1700d5cb63e4844dcf85f29a1ecebb97
  baremetal-machine-controllers                  sha256:d45f3cb5cd39cc1fc46164c80fc58268dd4ff6b29838a774e518953c9fa1f323
  baremetal-operator                             sha256:46fee5f883aa77344f2e585880f8890d2569a204b8663342fa4949e6ae954831
  baremetal-runtimecfg                           sha256:c54bcd5799cbad9d5f0e87427dc47ce8f53ffa1bba57a0ea97b45d70ca4e696a
  cli                                            sha256:5c791b29a6a5e2770d6301c789e7561f52fffb22cc0d1cb899e5e462ace8b2b3
  cli-artifacts                                  sha256:1e8cdc0cadf06b272fa20efefb7b5e215c49a3d8f011f47b3789cf31f6e9541a
  cloud-credential-operator                      sha256:49a43623fc2674e37ff4b4705421e6ec114780e8a84446c65eec6cb34a4b7c57
  cluster-authentication-operator                sha256:784d05992a7a449a4fbc66074597c84b555efa90b1df51cba8520787de9335cd
  cluster-autoscaler                             sha256:dcd6a108f3cadfb6dafaae81decfff8a728d37c57229ae26cd25561460c49809
  cluster-autoscaler-operator                    sha256:34a5895cadc8fa9aca20c09854e415e02ca7dbc0a5348aeb0187c6a57ef2eefc
  cluster-baremetal-operator                     sha256:9561c5045fe7550ba9cac1778e4d77be00e119a3895bf4402f780297a875b951
  cluster-bootstrap                              sha256:878d5f544df7db8b8a0a193031e01058b63166100d12cc47affb3e0de5c8cd6c
  cluster-config-operator                        sha256:b088f6485385289a5c61646dde94b05ece735f3d542e090e501999427eb7b0bd
  cluster-csi-snapshot-controller-operator       sha256:a66ed3a0114b21dbc3c258200e3553e7e1b2487b2f65907139951702f5ef625c
  cluster-dns-operator                           sha256:d401e2fb24b1a9a53e418611a574d84bcecfb646738c6e39a3e3e7bb45e57f14
  cluster-etcd-operator                          sha256:dfadb274e8ed99003a9f1fd3ed606196430898d24caf83a643b8426e49b43486
  cluster-image-registry-operator                sha256:97539f199834a597ab38e25956ed297d1f4855b935610108d3a3b6b937cc08d0
  cluster-ingress-operator                       sha256:10223e3c8a0d027970f60566b9e07d598941a5a135a42146efe9518f76680a68
  cluster-kube-apiserver-operator                sha256:57efb9e35b63657b0264b23715eaa6f14099dd9bc273272b2e1dbf6c69bcdf38
  cluster-kube-controller-manager-operator       sha256:b53ac52bb505443a946967fd32d433535bfe2139883ae60c2113a67f9d4c4b25
  cluster-kube-scheduler-operator                sha256:a3d0df04038808e7e95eb8ef4cb41a11b80ca3f31864b1078fa01e34156b5c15
  cluster-kube-storage-version-migrator-operator sha256:10a4f8b6140d61888f8707905309a0e7ed7f6eae6b5c59d42b263e58e24271c0
  cluster-machine-approver                       sha256:a8492014930da85a4ed1036a4d1f6907c1a7cf76fffae7490ea7e18a89cdfd10
  cluster-monitoring-operator                    sha256:df9b1e1d04ada670d627e906e80b25ea9c33dc23d439a80bbf10de0758d22e0b
  cluster-network-operator                       sha256:772bfad0055acc94ee7ce9f3ed44008003f5a9b6c05865ec0b6a331c67dda76b
  cluster-node-tuning-operator                   sha256:37cb19d8baec6b606f4fed07bda26384daba91c8e6d61be4297a3d357c876d2a
  cluster-openshift-apiserver-operator           sha256:764ed0b5a79f750aae88f9f17dbf74c8b6134b39010c28c182d6a6fd6be40b1d
  cluster-openshift-controller-manager-operator  sha256:3713b2eae1dae62d7c48408b30af9994e423ec3fd21627c120b56830fb2e98c5
  cluster-policy-controller                      sha256:b2417522d6a39de312b693ef81868321a40b6c55b923bd9813f0e155ad2c8864
  cluster-samples-operator                       sha256:78bc86b3ad4a53f4f5cd2b2d6bfdaa240db9b0de0200de4749e3214e776846af
  cluster-storage-operator                       sha256:b1eebad14107c785dc34a1c0a540ad7bd9e45577314f9864abdcf396465f8bcd
  cluster-update-keys                            sha256:2e2c8997ca30035cbd0aed43cddaeb1a5485e828609a2a460545998d5595c2a4
  cluster-version-operator                       sha256:c4516f81cb0e172679b5af58d25bf893f4eef0280bcc9bf140c9691eabf81122
  configmap-reloader                             sha256:464203caecb2c21d17443ab6d453de50c40b25e264e9a9a74dc67c684488b407
  console                                        sha256:04ccdbde19db99a8ab46d97955d037c175b68676a005a5e719267efb07ac0e5b
  console-operator                               sha256:94ecbd40c1044136419ea91b8655fa8f63cd32ef6ac8fc996981a1ac387be944
  container-networking-plugins                   sha256:8d392bcf2d877e60889225f4188b503691a1797df5d616889d797bfd8c1e60a8
  coredns                                        sha256:783e3ce48487edc6afa8ae7b9ebda1713c601bdf125412217772827c3cd3887f
  csi-driver-manila                              sha256:cc4b09ef6e8012f77a35d81e30059385c236d8d1192ea53979c4167a513568f0
  csi-driver-manila-operator                     sha256:ffea6041346119fd0d862f4fc1a78d51f41c6d44fa624552d8eb3d2e997b545d
  csi-driver-nfs                                 sha256:15d5b4079fcf0dbf5add9483d6ffd414a96fc03386be675c5cb56324d05cca2d
  csi-external-attacher                          sha256:05302fab01c683af02c51571dae4211c02774bab7cb02c8ac65495f055149722
  csi-external-provisioner                       sha256:b351d835fd1a99b99b97586ca641042ebfd7478f5f6f6c45757482e6b717fa25
  csi-external-resizer                           sha256:895b861d68025ca3ae0626f7fc139288d6af87a7c6b84e3faad6d3c3a5581bfa
  csi-external-snapshotter                       sha256:d55c080ff787da7db25005e1095ab80c85b9bfe22c82cf3cfc24265c270024bf
  csi-livenessprobe                              sha256:fd06232a538b1ca7bbdcee3aff81bd4cc6171685984b348db9633fe8c71d3948
  csi-node-driver-registrar                      sha256:0dcdce3985fc6c6003f3f6f01a8ce400873cce1727324635e368a4ecf92d7c84
  csi-snapshot-controller                        sha256:3f873e59e71a3b6b1962e016094968a0ad4d03f27d73ac9c11490f9be11983a7
  csi-snapshot-validation-webhook                sha256:566746d46669b030dbef3bfcc8d7535a4f068824b52a47aa343279238724f3fe
  deployer                                       sha256:cb27ec9c60306aa34fcf631f7a82d71fb5d648570a38830308d38bddee197b18
  docker-builder                                 sha256:d1116c80c75dc867ef8b28aa7bcb10d5b95382e55d21439f58d2998619d737ca
  docker-registry                                sha256:2d0368b9b6c4bfe87af2a7221fdb3140ceaf5c7eab89a0bab66476f1b6047d8a
  egress-router-cni                              sha256:bd3fcfb17a961b6b1d213e141d7861abd7790b4a75f299a39a2b04f54cbdc0e3
  etcd                                           sha256:4ddd95fbe24108f4e2ba36e022251f685a79df4fb1763f5e8ca68e284392fbd3
  gcp-machine-controllers                        sha256:df1da997d28753e4875b6e8bf19e33f818bf392df077541168962c12e4c6bd37
  gcp-pd-csi-driver                              sha256:55776c17dc428be018decaaf501802774490647ece82edf66cccd197961a4195
  gcp-pd-csi-driver-operator                     sha256:0dbd8aa26ac936e520389299d9818362f433e4e5ff11fbbab3e4beb89dc8baf2
  grafana                                        sha256:fd9ef70c928b7fd5bd18a8dbfcd0bf8bf4ab8354fdb7748ffa2c700c9813f4ae
  haproxy-router                                 sha256:883d123bf27e4e61fc539e1a8e1d7340b15859f8e3501c95c21c519c9a7e20f1
  hello-openshift                                sha256:ef11bb0352137fbe4221f2bb631424cdb2524e891ff1b68d5e76d59511070249
  hyperkube                                      sha256:9f3a61ed639646b1e333c7ae6891af370d61949fb13347ea8e2a14398605023b
  insights-operator                              sha256:d9649eaed742c7c53e01326f6a9871d5597e9e7ef8abc7006f2cd2763e2a5b15
  installer                                      sha256:5acfb2ce9512d8c8bee394e9aaefd6154c56fbf01628262f75240c6ff5173514
  installer-artifacts                            sha256:0c064ac8f55d4b5f329fd0f74053c86cf90bbf2710cb948660e2b5fc694881a3
  ironic                                         sha256:e1d2a359babe8f020fa8ec059e1084736d8e3dfe5d4d86c58767065c35aafa7d
  ironic-hardware-inventory-recorder             sha256:f8b38206219e010851a991c308cf8dfa0e212f5ee15584602afc4630889a436d
  ironic-inspector                               sha256:7f48979dea047ffb794fc3697be72f34694e93078bdc4aeec50976f13c317859
  ironic-ipa-downloader                          sha256:782accb14dc82400e97c645a870f46959dd709718bd90e418c17a8a55713dddb
  ironic-machine-os-downloader                   sha256:35cb207747bf2fc3fdee56d849ab0347e23e5322f500d6b6710850d96e1f4078
  ironic-static-ip-manager                       sha256:33cc9f3f8d5ed815bb9f09a6f39f387cb8dafcaa265f81a34d3d9a294b5ab303
  jenkins                                        sha256:1a6e328adea42cfacf379caa39a41750173bba81c7e93ce4511123e69a45afd4
  jenkins-agent-base                             sha256:b1ea7ac1d6681987a06fc67a676ad4c8e055d9248ec1009429ed77eee9e7b1da
  jenkins-agent-maven                            sha256:7ca4f8997bf3bc6108d3cd07c60f0bcf51a5ffb921c0c5bd8d170376e63e1640
  jenkins-agent-nodejs                           sha256:b03831e65f2c83fdf3497aa34d97b80aa78a61b450db1d736483ab27041b7cab
  k8s-prometheus-adapter                         sha256:e580df078522fed0d83f516fc9c3c21409b113a4e00973670884603c58e4a05e
  keepalived-ipfailover                          sha256:63a3427f540a326103a11ee3053aa1c90a48589ddae9cad4826502280b82ca99
  kube-proxy                                     sha256:3426b76f85511237b0d634e9346afdf5df8efaa6c039640ce0b6679d0d201165
  kube-rbac-proxy                                sha256:286594a73fcc8d6be9933e64b24455e4d0ac1dd90e485ec8ea1927dc77f38f5c
  kube-state-metrics                             sha256:4be78f2efc4a692c0a59e5d3ae74e8ffc15fd0725d3465367c110132355a133d
  kube-storage-version-migrator                  sha256:718dc731c331ba82be549f3601d32e251f3bdcbcab24d101929e007b66a17b2b
  kuryr-cni                                      sha256:9e7029338b8eee4b0a27ba4725b77a49da750a26dfba19518a10f916ba6d5442
  kuryr-controller                               sha256:f5dd204bdc254653e2cff7fc6776fcf0f8e9f15a54a224a2aa8a966bf5a89e0c
  libvirt-machine-controllers                    sha256:ce640b89ac10e25ffe3238696aa991a12df8edb1372b4511e19d026b258388eb
  local-storage-static-provisioner               sha256:3e2de795237a5bf63a616fa89295741b53639710878a614a1f29a75c137b59cc
  machine-api-operator                           sha256:955dfea54b13c5aa6a7ebc1cd4eb766ee524ccd2a93b4d82eb172a261398f067
  machine-config-operator                        sha256:b8a2ab2010f67d097f824e46717c3246f3f8d5e671cf10d0160ced7fad4b01c9
  machine-os-content                             sha256:a32077727aa2ef96a1e2371dbcc53ba06f3d9727e836b72be0f0dd4513937e1e
  mdns-publisher                                 sha256:42efd628e581354a1ecc3d661a7e10490d35a34ba109be37b9ca453098dbc768
  multus-admission-controller                    sha256:6089dffb9568338215f1c333259920a0af6b658f0439d12b978fe722311950d0
  multus-cni                                     sha256:ee91400e21de42bc277608d0e3f7f40a1a3c942dc7ff78e2e1cf6fb3f91f5a1a
  multus-route-override-cni                      sha256:03f04863fc3b8bea21de31dba2e6c24f95257c41337a5fc2132ca389718590d0
  multus-whereabouts-ipam-cni                    sha256:4f12814a283d81f4db98facd07e2ff9c48acc9c5b849435b9a3b983634a1a848
  must-gather                                    sha256:b52c1d685b2ec2c674d8abb6ed0e69fd5e71f8c4e0c086fd6d2ca0e3f498470f
  network-metrics-daemon                         sha256:9882c6d797a2c202a2aa2dfaef3e83ae27eb3981977a8d6b7c4af0fb17b7e6ef
  oauth-apiserver                                sha256:c1878340a395b581b3d0cf37bed99c2b137f3141264465205334ba74e1e0e108
  oauth-proxy                                    sha256:5e835968ba75f93187f489e9b815ef1b22dda8692da06b5b24bbf94e11df2cb1
  oauth-server                                   sha256:a374ea60852791e199db075925137545ec4b35dcc5ce135d7315a88e2c90f53f
  openshift-apiserver                            sha256:def904b5a407af5d1fee89d0a9fcab021d411fae08097d52def31498ef9df65e
  openshift-controller-manager                   sha256:3a58a5159c9fb05bf7e5c57f50518d63fdec337c629a90cfc4bc583e790f9ccd
  openshift-state-metrics                        sha256:bef4ea85c2ffbb2800380531d3cc31b37180bf4beddc97eb5309bd5afb50592d
  openstack-cinder-csi-driver                    sha256:469d175be42748757c186255954854c273493ad028cd56b114741cf98873754f
  openstack-cinder-csi-driver-operator           sha256:03516e7a32eff72a0894afe3f6fc59534dd1708338bc18c5fc6a8f7f1bbf2d95
  openstack-machine-controllers                  sha256:3a730270f01cc75a9dd0cc64add5a96075f1e6a94392c8d15b4350b0e8dfc3c0
  operator-lifecycle-manager                     sha256:08d81d44f449025c59b133fd040f01423c090ac043a632b30880caf8d725b7e6
  operator-marketplace                           sha256:a57007e295775c3cd44c8cef03614a5a71bb412903a8a26ef273e1e2cffa883a
  operator-registry                              sha256:0ef1757a9334675bfd06275e1ed53af30f31a88ad8c711b19833e3a9539aa932
  ovirt-csi-driver                               sha256:5a9cbb5ef81f78dbee07a545fb595a071bfcfe5313b29d8efce8f0ff60537c02
  ovirt-csi-driver-operator                      sha256:964f7379052ffb13da8e897d55ee17c63e7f08236b757bb82cde7af04c62bc40
  ovirt-machine-controllers                      sha256:7eeee57798bc349ab1ede28070b1709344d22b28326031708609fa89672eaa7e
  ovn-kubernetes                                 sha256:3ac06e61e72bf84ab1553bf28eeb8e038e483d5df6472aa6cd26635033d082d7
  pod                                            sha256:5994ce07b8fa5b3fa9a1ecd99f509ccf960918d9520d60fdf0087d0d656d6b23
  prom-label-proxy                               sha256:19757106e33c95c1b7e61338fa7ffe1bb043197292162c3c47b95f2af0d53b58
  prometheus                                     sha256:4b283e711b616610bd0c4fac72cee7bc07343036e3b1ef36cd66d21209fb0906
  prometheus-alertmanager                        sha256:ae79797901399df5abf6f4afb08451c48f261a10a7c9251447d21396089f87e2
  prometheus-config-reloader                     sha256:f1e82f08e81f929146e4ea9865d8f384adb324b2316519a51f5ac2671b9e160a
  prometheus-node-exporter                       sha256:a42d1895c93e16c68f9147175fcb49716cb8b7f2562a93e5615673606d78941d
  prometheus-operator                            sha256:4bf1837c729641f1653d86dadc3690377ffc68b27c010b47cf2b23a45c8bfc00
  sdn                                            sha256:6eed5ba56da56da0d83e6f7ddd09714043c9de50c612afb6ec77ac6ab22ec0d5
  service-ca-operator                            sha256:e401ae9497bb32c6e29d46048fd6caf75d02dc775fef96e4d3a9c2f62f389f57
  telemeter                                      sha256:307b425c8bea5913ea564d06707d4b9dc2263898e26c04ab7eae5dc5133eb982
  tests                                          sha256:51786515100d15c475a1337c3756b08ec49cc9498b50e9f61c97da17da25db90
  thanos                                         sha256:a623d0bd671a449d7c5b43bf22a839717a0210b4bd7f896bc7448214a0cae293
  tools                                          sha256:5a1ff3e2240f10a6c7ca5e2364149286c19df32575a479e6f2b10009ad64fedd
  vsphere-problem-detector                       sha256:041d92cfbd97b7c96dbf5d27498c57b636a62c3e6eedceed35148422c5f382c1
```