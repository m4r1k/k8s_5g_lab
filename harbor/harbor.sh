#!/bin/bash

# Harbor script for CentOS Stream 8 adapted from https://gist.github.com/kacole2/95e83ac84fec950b1a70b0853d6594dc

# Verify the permission
if [ `whoami` != 'root' ]; then
    echo "You must be root to do this."
    exit 1
fi

# Verify previus installations
if [ -d /root/harbor ]; then
    echo "Error, a previus installation of Harbor seems existing."
    exit 1
fi

# Verify if the RootCA KEY is available to sign the Harbor PEM
if ! [ -f /root/ca.key ]; then
    echo "Error, missing RootCA Key under /root/ca.key."
    exit 1
fi

# Verify if the RootCA CRT is available to sign the Harbor PEM
if ! [ -f /root/ca.crt ]; then
    echo "Error, missing RootCA Key under /root/ca.crt."
    exit 1
fi

echo "Welcome to the Harbor installation for CentOS 8 Stream"
echo "https://github.com/goharbor/harbor"

# Ask whether IP Address or FQDN installation
PS3='Would you like to install Harbor based on IP or FQDN? '
select option in IP FQDN
do
    case $option in
        IP)
            IPorFQDN=$(hostname -I|cut -d" " -f 1)
            break;;
        FQDN)
            IPorFQDN=$(hostname -f)
            break;;
     esac
done

# Update all packages and install a couple of deps
echo "[Step 0]: Update all the packages ..."
dnf makecache
dnf update -y
dnf install -y wget vim git bash-completion

# Disable swap
echo "[Step 0]: Disable Swap ..."
swapoff --all
sed -r '/\sswap\s/s/^#?/#/' -i /etc/fstab

# Install Docker CE stable
echo "[Step 0]: Install latest Docker-CE Stable ..."
dnf module -y remove podman skopeo buildah
dnf config-manager \
    --add-repo \
    https://download.docker.com/linux/centos/docker-ce.repo
dnf makecache
dnf install -y docker-ce docker-ce-cli containerd.io
systemctl enable --now docker

# Ensure local Docker can trust Harbor
echo "[Step 0]: Disable local registry verification ..."
cat > /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "insecure-registries" : ["$IPorFQDN:443","$IPorFQDN:80"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF
systemctl restart docker


# Install Docker Compose
echo "[Step 0]: Install Docker Compose ..."
COMPOSEVERSION=$(curl -s https://github.com/docker/compose/releases/latest/download 2>&1 | grep -Po [0-9]+\.[0-9]+\.[0-9]+)
curl -L "https://github.com/docker/compose/releases/download/$COMPOSEVERSION/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Create local CA and PEM for Harbor
echo "[Step 0]: Create Harbor PEM ..."
_DIR=/root/certs
mkdir -p /root/certs

# Create OpenSSL Config for the Certificate
cat > "${_DIR}/openssl.cnf" << EOF
[req]
default_bits = 2048
encrypt_key  = no
default_md   = sha256
prompt       = no
utf8         = yes
distinguished_name = req_distinguished_name
req_extensions = v3_req

[req_distinguished_name]
CN = $(hostname -f)

[v3_req]
basicConstraints     = CA:FALSE
subjectKeyIdentifier = hash
keyUsage             = digitalSignature, keyEncipherment
extendedKeyUsage     = clientAuth, serverAuth
subjectAltName       = @alt_names

[alt_names]
IP.1  = $(hostname -I|cut -d" " -f 1)
DNS.1 = $(hostname -f)
EOF

# Create Certificate Key
openssl req \
 -new -newkey rsa:2048 \
 -keyout "${_DIR}/cert.key" \
 -out "${_DIR}/cert.csr" \
 -config "${_DIR}/openssl.cnf"

# Create PEM
openssl x509 \
 -req \
 -days 1825 \
 -in "${_DIR}/cert.csr" \
 -extensions v3_req \
 -extfile "${_DIR}/openssl.cnf" \
 -CA "/root/ca.crt" \
 -CAkey "/root/ca.key" \
 -CAcreateserial \
 -out "${_DIR}/cert.pem"

# Download and run Harbor installation
echo "[Step 0]: Install Latest Stable Harbor Release ..."
mkdir -p /root/harbor
cd /root/harbor
HARBORVERSION=$(curl -s https://github.com/goharbor/harbor/releases/latest/download 2>&1 | grep -Po [0-9]+\.[0-9]+\.[0-9]+)
curl -s https://api.github.com/repos/goharbor/harbor/releases/latest | grep browser_download_url | grep online | cut -d '"' -f 4 | wget -qi -
tar xvf harbor-online-installer-v$HARBORVERSION.tgz
cd harbor
cp harbor.yml.tmpl harbor.yml
sed -i "s/reg.mydomain.com/$IPorFQDN/g" harbor.yml
sed -i "s|/your/certificate/path|${_DIR}/cert.pem|g" -i harbor.yml
sed -i "s|/your/private/key/path|${_DIR}/cert.key|g" -i harbor.yml

./install.sh --with-notary --with-trivy --with-chartmuseum

# Print default login credentials
echo "Harbor installation completed!"
echo "Login at ${IPorFQDN} using the default credentials: admin/Harbor12345"

exit 0