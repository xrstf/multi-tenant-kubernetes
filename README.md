# Multi-Tenancy Kubernetes For The Brave

This repository contains the proof of concept for a very simple, very limited multi-tenancy Kubernetes system.

The goal is to offer multiple, independent Kubernetes API servers that are backed by a single etcd (cluster). There exists a bunch of prior art, like [vcluster](https://github.com/loft-sh/vcluster) or [kcp](https://github.com/kcp-dev/kcp), but this one is mine.

The idea is as simple as it gets: run a proxy between the Kube Apiserver and etcd and make that proxy simply inject a common prefix to all keys. As it turns out, such a proxy is already [part of etcd](https://etcd.io/docs/v3.5/op-guide/grpc_proxy/) and it even already supports segregating keys (by using a `--namespace`, not to be confused with Kubernetes namespaces).

This allows me to run a single etcd plus (apiserver+controller-manager+grpc-proxy) for each workspace (independent Kubernetes API) that i want to handle.

## Try it out

Download the repository, get yourself docker-compose and then simply

```bash
docker-compose up etcd etcd-prefix1
```

to start both the classic etcd server and an example proxy. Then you have to choose which to use by editing the `docker-compose.yaml` and adjusting the `--etcd-servers` flag for the Kubernetes Apiserver. Then you can just start it with

```bash
docker-compose up apiserver
```

and use the `test.kubeconfig` to interact with it.
