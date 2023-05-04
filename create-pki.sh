#!/usr/bin/env bash

set -euo pipefail
cd $(dirname $0)

# cfssl has lots of files, let's not litter the root directory
OUTPUT_DIR="${OUTPUT_DIR:-pki}"
mkdir -p -- "$OUTPUT_DIR"
OUTPUT_DIR="$(realpath "$OUTPUT_DIR")"

function cleanup() {
  echo "Removing temporary files..."

  rm -f "$OUTPUT_DIR/cfssl.json"

  for cert in ca etcd-server etcd-client apiserver kubelet user service-account-signer; do
    rm -f "$OUTPUT_DIR/$cert.json" "$OUTPUT_DIR/$cert.csr"
  done
}
trap cleanup EXIT SIGINT SIGTERM

########################################
# preare cfssl config

cd "$OUTPUT_DIR"

cat <<EOF > cfssl.json
{
  "signing": {
    "default": {
      "expiry": "876000h"
    },
    "profiles": {
      "server": {
        "expiry": "8760h",
        "usages": [
          "signing",
          "digital signing",
          "key encipherment",
          "server auth"
        ]
      },
      "client": {
        "expiry": "876000h",
        "usages": [
          "signing",
          "digital signature",
          "key encipherment",
          "client auth"
        ]
      }
    }
  }
}
EOF

########################################
# preare the CA cert

if ! [ -f ca.pem ]; then
  cat <<EOF > ca.json
{
  "CN": "xrstf CA",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "DE",
      "L": "Hamburg",
      "OU": "xrstf CA"
    }
  ]
}
EOF
  cfssl gencert -initca ca.json | cfssljson -bare ca
fi

########################################
# prepare etcd serving certificate

if ! [ -f etcd-server.pem ]; then
  cat <<EOF > "etcd-server.json"
  {
    "hosts": [
      "etcd",
      "etcd-prefix1"
    ],
    "CN": "etcd",
    "names": [{
      "O": "system:authenticated"
    }],
    "key": {
      "algo": "rsa",
      "size": 2048
    }
  }
EOF

  # generate private key, CSR (unused) and serving certificate
  cfssl gencert -ca ca.pem -ca-key ca-key.pem -config cfssl.json -profile server etcd-server.json | cfssljson -bare etcd-server
fi

########################################
# prepare etcd client certificate

if ! [ -f etcd-client.pem ]; then
  # must have an empty CN, otherwise etcd's grpc-proxy will complain and refuse to use it
  cat <<EOF > "etcd-client.json"
  {
    "CN": "",
    "names": [{
      "O": "system:authenticated"
    }],
    "key": {
      "algo": "rsa",
      "size": 2048
    }
  }
EOF

  # generate private key, CSR (unused) and serving certificate
  cfssl gencert -ca ca.pem -ca-key ca-key.pem -config cfssl.json -profile client etcd-client.json | cfssljson -bare etcd-client
fi

########################################
# prepare kubelet client certificate

if ! [ -f kubelet.pem ]; then
  cat <<EOF > "kubelet.json"
  {
    "CN": "kubelet",
    "names": [{
      "O": "system:authenticated"
    }],
    "key": {
      "algo": "rsa",
      "size": 2048
    }
  }
EOF

  # generate private key, CSR (unused) and serving certificate
  cfssl gencert -ca ca.pem -ca-key ca-key.pem -config cfssl.json -profile client kubelet.json | cfssljson -bare kubelet
fi

########################################
# prepare kube-apiserver serving certificate

if ! [ -f apiserver.pem ]; then
  cat <<EOF > "apiserver.json"
  {
    "hosts": [
      "apiserver",
      "127.0.0.1",
      "localhost"
    ],
    "CN": "apiserver",
    "names": [{
      "O": "system:authenticated"
    }],
    "key": {
      "algo": "rsa",
      "size": 2048
    }
  }
EOF

  # generate private key, CSR (unused) and serving certificate
  cfssl gencert -ca ca.pem -ca-key ca-key.pem -config cfssl.json -profile server apiserver.json | cfssljson -bare apiserver
fi

########################################
# prepare user client certificate

if ! [ -f user.pem ]; then
  cat <<EOF > "user.json"
  {
    "CN": "xrstf",
    "names": [{
      "O": "system:masters"
    }],
    "key": {
      "algo": "rsa",
      "size": 2048
    }
  }
EOF

  # generate private key, CSR (unused) and serving certificate
  cfssl gencert -ca ca.pem -ca-key ca-key.pem -config cfssl.json -profile client user.json | cfssljson -bare user
fi

########################################
# prepare service account signing key

if ! [ -f service-account-signer-key.pem ]; then
  cat <<EOF > "service-account-signer.json"
  {
    "CN": "service-account-signer",
    "names": [{
      "O": "system:authenticated"
    }],
    "key": {
      "algo": "rsa",
      "size": 2048
    }
  }
EOF

  # generate private key, CSR (unused) and serving certificate
  cfssl genkey service-account-signer.json | cfssljson -bare service-account-signer
fi

########################################
# prepare a nice kubeconfig

cd -

OLDCONFIG="test.kubeconfig.src"
NEWCONFIG="test.kubeconfig"
CLUSTER_NAME="testcluster"
USER_NAME="test"
CONTEXT="as-test"
cp "$OLDCONFIG" "$NEWCONFIG"

yq --inplace 'del(.users)' "$NEWCONFIG"
yq --inplace 'del(.contexts)' "$NEWCONFIG"

export KUBECONFIG="$NEWCONFIG"

kubectl config set-cluster "$CLUSTER_NAME" \
  --certificate-authority="$OUTPUT_DIR/ca.pem" \
  --server="https://127.0.0.1:30068" \
  --embed-certs=true

kubectl config set-credentials "$USER_NAME" \
  --client-certificate="$OUTPUT_DIR/user.pem" \
  --client-key="$OUTPUT_DIR/user-key.pem" \
  --embed-certs=true

kubectl config set-context "$CONTEXT" \
  --user="$USER_NAME" \
  --cluster="$CLUSTER_NAME"

kubectl config use-context "$CONTEXT"
