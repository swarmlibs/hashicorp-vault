# Quick reference

- **Maintained by**:  
  [the Swarm Library Maintainers](https://github.com/swarmlibs)

- Source of this image:  
 [repo (/hashicorp-vault)](https://github.com/swarmlibs/hashicorp-vault)

# About

A tool for secrets management, encryption as a service, and privileged access management

https://www.vaultproject.io

<img width="300" alt="Vault Logo" src="https://raw.githubusercontent.com/hashicorp/vault/f22d202cde2018f9455dec755118a9b84586e082/Vault_PrimaryLogo_Black.png">

Vault is a tool for securely accessing secrets. A secret is anything that you want to tightly control access to, such as API keys, passwords, certificates, and more. Vault provides a unified interface to any secret, while providing tight access control and recording a detailed audit log.

A modern system requires access to a multitude of secrets: database credentials, API keys for external services, credentials for service-oriented architecture communication, etc. Understanding who is accessing what secrets is already very difficult and platform-specific. Adding on key rolling, secure storage, and detailed audit logs is almost impossible without a custom solution. This is where Vault steps in.

The key features of Vault are:

* **Secure Secret Storage**: Arbitrary key/value secrets can be stored
  in Vault. Vault encrypts these secrets prior to writing them to persistent
  storage, so gaining access to the raw storage isn't enough to access
  your secrets. Vault can write to disk, [Consul](https://www.consul.io),
  and more.

* **Dynamic Secrets**: Vault can generate secrets on-demand for some
  systems, such as AWS or SQL databases. For example, when an application
  needs to access an S3 bucket, it asks Vault for credentials, and Vault
  will generate an AWS keypair with valid permissions on demand. After
  creating these dynamic secrets, Vault will also automatically revoke them
  after the lease is up.

* **Data Encryption**: Vault can encrypt and decrypt data without storing
  it. This allows security teams to define encryption parameters and
  developers to store encrypted data in a location such as a SQL database without
  having to design their own encryption methods.

* **Leasing and Renewal**: All secrets in Vault have a _lease_ associated
  with them. At the end of the lease, Vault will automatically revoke that
  secret. Clients are able to renew leases via built-in renew APIs.

* **Revocation**: Vault has built-in support for secret revocation. Vault
  can revoke not only single secrets, but a tree of secrets, for example,
  all secrets read by a specific user, or all secrets of a particular type.
  Revocation assists in key rolling as well as locking down systems in the
  case of an intrusion.


## Features

- Automatically join the Vault cluster within the same stack using the **Integrated Raft Storage** backend and perform peer discovery using the **Docker** service discovery mechanism.
- Configure part of the Vault instance using **Environment Variables**.
- Exported metrics for monitoring using **Prometheus**.

## Entrypoints

There are two entrypoints for the **Vault** container:
- `default`: [`/docker-entrypoint-shim.sh`](./rootfs/docker-entrypoint-shim.sh)
    
    The `default` entrypoint is used for the **Vault** container to start in **standalone** mode with the **Integrated Raft Storage** backend. It also provides the ability to configure the **Vault** instance using **Environment Variables**.
- `dockerswarm`: [`/dockerswarm-entrypoint.sh`](./rootfs/dockerswarm-entrypoint.sh)
    
    The `dockerswarm` entrypoint is used for starting **Vault** in a **Docker Swarm** environment. It will automatically join the **Vault** cluster within the same stack using the **Integrated Raft Storage** backend and perform peer discovery using the **Docker** service discovery mechanism.

    > The `dockerswarm` entrypoint will redirect the execution context to the `default` entrypoint for starting the **Vault** instance.

## Environment Variables

The following **Environment Variables** can be used to configure the **Vault** instance:

### Bind Addresses

> [!NOTE]
> By default, **Vault** listens on all interfaces.

### Advertising Addresses

- `VAULT_API_INTERFACE`: Allow setting `VAULT_API_ADDR` using an interface name instead of an IP address.
- `VAULT_REDIRECT_INTERFACE`: Allow setting `VAULT_REDIRECT_ADDR` using an interface name instead of an IP address.
- `VAULT_CLUSTER_INTERFACE`: Allow setting `VAULT_CLUSTER_ADDR` using an interface name instead of an IP address.


> [!NOTE]
> If `VAULT_*_ADDR` is also set, the resulting URI will combine the protocol and port number with the IP of the named interface.

### Cluster Configurations

**Cluster Information**:
- `VAULT_CLUSTER_NAME`: Specifies the identifier for the Vault cluster. If omitted, Vault will generate a value. When connecting to Vault Enterprise, this value will be used in the interface. It also used to identify the cluster in the Prometheus metrics.

**Integrated Raft Storage**:
- `VAULT_RAFT_NODE_ID`: The identifier for the node in the Raft cluster. If unset, Vault assigns a random GUID during initialization and writes the value to `data/node-id` in the directory specified by the `VAULT_RAFT_PATH` variable.
- `VAULT_RAFT_PATH` `(default: /vault/file)`: The file system path where all the Vault data gets stored.

### General Configurations

- `VAULT_UI` `(default: true)`: Enables the built-in web UI, which is available on all listeners (address + port) at the `/ui` path. Browsers accessing the standard Vault API address will automatically redirect there.
- `VAULT_LOG_LEVEL` `(default: info)`: Log verbosity level. Supported values (in order of descending detail) are `trace`, `debug`, `info`, `warn`, and `error`.
- `VAULT_LOG_REQUESTS_LEVEL` `(default: off)`: The acceptable logging levels are `error`, `warn`, `info`, `debug`, `trace`, and `off`, which is the default

### Advanced Configurations

- `VAULT_RAW_STORAGE_ENDPOINT` `(default: false)`: Enables the `sys/raw` endpoint which allows the decryption/encryption of raw data into and out of the security barrier. This is a highly privileged endpoint.

## Docker Stack

The following is an example of a **Docker Stack** configuration for deploying a **Vault** service in a **Docker Swarm** environment:

```yaml
x-replicas: &x-replicas 1
x-published-port: &x-published-port 8200

x-placement-constraints: &x-placement-constraints
  - "node.role == manager"

services:
  server:
    image: swarmlibs/hashicorp-vault:1.16
    entrypoint: /dockerswarm-entrypoint.sh
    command: server
    environment:
      # Specifies the identifier for the Vault cluster
      VAULT_CLUSTER_NAME:
      # Specifies the address (full URL) to advertise to other Vault servers in the cluster for
      # client redirection to this node when in High Availability mode. (default to VAULT_CLUSTER_ADDR value)
      # You can set either one of these values, the priority is as follows:
      VAULT_API_ADDR: 
      VAULT_REDIRECT_ADDR: 
      # !!! DO NOT CHANGE THIS VALUES BELOW !!!
      # Default values for VAULT_ADVERTISE_ADDR & VAULT_CLUSTER_ADDR
      VAULT_ADVERTISE_ADDR: http://vault-{{.Node.ID}}.svc.cluster.local:8200
      VAULT_CLUSTER_ADDR: http://vault-{{.Node.ID}}.svc.cluster.local:8201
      # Docker Swarm service template variables
      DOCKERSWARM_SERVICE_ID: "{{.Service.ID}}"
      DOCKERSWARM_SERVICE_NAME: "{{.Service.Name}}"
      DOCKERSWARM_NODE_ID: "{{.Node.ID}}"
      DOCKERSWARM_NODE_HOSTNAME: "{{.Node.Hostname}}"
      DOCKERSWARM_TASK_ID: "{{.Task.ID}}"
      DOCKERSWARM_TASK_NAME: "{{.Task.Name}}"
      DOCKERSWARM_TASK_SLOT: "{{.Task.Slot}}"
      DOCKERSWARM_STACK_NAMESPACE: '{{ index .Service.Labels "com.docker.stack.namespace" }}'
    hostname: vault-{{.Node.ID}}.svc.cluster.local
    networks:
      vault_network:
    ports:
      - target: 8200
        published: *x-published-port
        protocol: tcp
        mode: host
    volumes:
      - vault-data:/vault/file
    cap_add:
      - IPC_LOCK
    deploy:
      mode: replicated
      replicas: *x-replicas
      placement:
        max_replicas_per_node: 1
        constraints: *x-placement-constraints

volumes:
  vault-data:

networks:
  vault_network:
```

## Raft AutoPilot Configuration

The following is an example of Raft AutoPilot Configuration recommended for a **Vault** cluster:

```sh
curl -X 'POST' \
  'http://localhost:8200/v1/sys/storage/raft/autopilot/configuration' \
  -H 'accept: */*' \
  -H 'Content-Type: application/json' \
  -H 'X-Vault-Token: hvs.fqZ4JTEaWrDBkr3neGIw1mel' \
  -d '{
  "cleanup_dead_servers": true,
  "dead_server_last_contact_threshold": "24h",
  "last_contact_threshold": "10s",
  "max_trailing_logs": 1000,
  "min_quorum": 3,
  "server_stabilization_time": "10s"
}'
```


## Prometheus Metrics

The **Vault** instance exports metrics for monitoring using **Prometheus**. The metrics are available at the `/v1/sys/metrics` path on the `8282` port.
This port DOES NOT REQUIRE authentication, so it is recommended to restrict access to this port to only the **Prometheus** service.

The following is an example of a **Prometheus** configuration for scraping the **Vault** metrics:

```yaml
services:
  server:
    image: swarmlibs/hashicorp-vault:1.16
    # ...
    deploy:
      # ...
      labels:
        io.prometheus.enabled: "true"
        io.prometheus.job_name: "vault"
        io.prometheus.scrape_port: "8282"
        io.prometheus.metrics_path: "/v1/sys/metrics"
        io.prometheus.param_format: "prometheus"
```
