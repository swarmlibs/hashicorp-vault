#!/bin/bash

# Allow setting VAULT_API_ADDR using an interface
# name instead of an IP address. The interface name is specified using
# VAULT_API_INTERFACE environment variables. If
# VAULT_*_ADDR is also set, the resulting URI will combine the protocol and port
# number with the IP of the named interface.
get_addr () {
	local if_name=$1
	local uri_template=$2
	ip addr show dev $if_name | awk -v uri=$uri_template '/\s*inet\s/ { \
	  ip=gensub(/(.+)\/.+/, "\\1", "g", $2); \
	  print gensub(/^(.+:\/\/).+(:.+)$/, "\\1" ip "\\2", "g", uri); \
	  exit}'
}

# VAULT_DATA_DIR is exposed as a volume for possible persistent storage. The
# VAULT_CONFIG_DIR isn't exposed as a volume but you can compose additional
# config files in there if you use this image as a base, or use
# VAULT_LOCAL_CONFIG below.
VAULT_DATA_DIR=/vault/file
VAULT_CONFIG_DIR=/vault/config
VAULT_PID_FILE=/vault/config/vault.pid
VAULT_STORAGE_CONFIG_FILE=${VAULT_STORAGE_CONFIG_FILE:-"$VAULT_CONFIG_DIR/raft-storage.hcl"}

# Specifies the address (full URL) to advertise to other
# Vault servers in the cluster for client redirection.
if [ -n "$VAULT_API_INTERFACE" ]; then
	export VAULT_API_ADDR=$(get_addr $VAULT_API_INTERFACE ${VAULT_API_ADDR:-"https://0.0.0.0:8200"})
	echo "Using $VAULT_API_INTERFACE for VAULT_API_ADDR: $VAULT_API_ADDR"
fi

# Configure the Vault API address for CLI usage
export VAULT_ADDR=${VAULT_API_ADDR:-${VAULT_REDIRECT_ADDR:-${VAULT_ADVERTISE_ADDR:-"http://localhost:8200"}}}

# Integrated storage (Raft) backend
if [[ -n "${VAULT_RAFT_NODE_ID}" ]]; then
	echo "Configure VAULT_RAFT_NODE_ID as \"$VAULT_RAFT_NODE_ID\""
	export VAULT_RAFT_NODE_ID=${VAULT_RAFT_NODE_ID}
fi
export VAULT_RAFT_PATH=${VAULT_RAFT_PATH:-"/vault/file"}
echo "Configure VAULT_RAFT_PATH to \"$VAULT_RAFT_PATH\""

# If VAULT_STORAGE_CONFIG_FILE doesn't exist, generate a default "raft" storage configuration
if [ ! -f "$VAULT_STORAGE_CONFIG_FILE" ]; then
	# Vault Cloud Auto Join
	if [[ -n "${VAULT_CLOUD_AUTO_JOIN}" ]]; then
		VAULT_CLOUD_AUTO_JOIN_SCHEME=${VAULT_CLOUD_AUTO_JOIN_SCHEME:-"https"}
		VAULT_CLOUD_AUTO_JOIN_PORT=${VAULT_CLOUD_AUTO_JOIN_PORT:-"8201"}
		echo "storage \"raft\" { retry_join { auto_join_scheme=\"${VAULT_CLOUD_AUTO_JOIN_SCHEME}\" auto_join_port=${VAULT_CLOUD_AUTO_JOIN_PORT} auto_join=\"${VAULT_CLOUD_AUTO_JOIN}\" } }" > "$VAULT_STORAGE_CONFIG_FILE"
	fi

	# Write the listener configuration to the file
	echo "storage \"raft\" { /* default config */ }" > "$VAULT_STORAGE_CONFIG_FILE"
fi

# If VAULT_SEAL_TYPE is set to "transit", configure the transit seal
# https://developer.hashicorp.com/vault/docs/configuration/seal/transit
if [[ -n "$VAULT_SEAL_SECRET_FILE" ]] && [ -f "$VAULT_SEAL_SECRET_FILE" ]; then
	echo "==> The Transit seal configuration is provided by the file \"$VAULT_SEAL_SECRET_FILE\", activating the Transit seal..."
	cp "$VAULT_SEAL_SECRET_FILE" "$VAULT_CONFIG_DIR"
fi

# Specifies the identifier for the Vault cluster.
# When connecting to Vault Enterprise, this value will be used in the interface.
# This value also used to identify the cluster in the Prometheus metrics.
VAULT_CLUSTER_NAME=${VAULT_CLUSTER_NAME:-"vault"}
echo "Configure VAULT_CLUSTER_NAME as \"$VAULT_CLUSTER_NAME\""

# These are a set of custom environment variables that can be used to
# generate a configuration file on the fly.

VAULT_UI=${VAULT_UI:-"true"}
VAULT_LOG_LEVEL=${VAULT_LOG_LEVEL:-"info"}
VAULT_LOG_REQUESTS_LEVEL=${VAULT_LOG_REQUESTS_LEVEL:-"off"}

# Listener configuration
VAULT_LISTENER_TLS_DISABLE=${VAULT_LISTENER_TLS_DISABLE:-"true"}

# enables a PROXY protocol version 1 behavior for the listener
if [[ -n "${VAULT_PROXY_PROTOCOL_BEHAVIOR}" ]]; then
	VAULT_PROXY_PROTOCOL_BEHAVIOR="proxy_protocol_behavior = \"${VAULT_PROXY_PROTOCOL_BEHAVIOR}\""
else
	VAULT_PROXY_PROTOCOL_BEHAVIOR="# proxy_protocol_behavior = \"\""
fi
if [[ -n "${VAULT_PROXY_PROTOCOL_AUTHORIZED_ADDRS}" ]]; then
	# check if VAULT_PROXY_PROTOCOL_AUTHORIZED_ADDRS being/end with "[...]"", indicating a list
	if [[ "${VAULT_PROXY_PROTOCOL_AUTHORIZED_ADDRS}" == "["* ]] && [[ "${VAULT_PROXY_PROTOCOL_AUTHORIZED_ADDRS}" == *"]" ]]; then
		VAULT_PROXY_PROTOCOL_AUTHORIZED_ADDRS="proxy_protocol_authorized_addrs = ${VAULT_PROXY_PROTOCOL_AUTHORIZED_ADDRS}"
	else
		VAULT_PROXY_PROTOCOL_AUTHORIZED_ADDRS="proxy_protocol_authorized_addrs = \"${VAULT_PROXY_PROTOCOL_AUTHORIZED_ADDRS}\""
	fi
else
	VAULT_PROXY_PROTOCOL_AUTHORIZED_ADDRS="# proxy_protocol_authorized_addrs = \"\""
fi

# Vault telemetry configuration
VAULT_TELEMETRY_USAGE_GAUGE_PERIOD=${VAULT_TELEMETRY_USAGE_GAUGE_PERIOD:-"10m"}

# Lease configuration
VAULT_DEFAULT_LEASE_TTL=${VAULT_DEFAULT_LEASE_TTL:-"0"}
VAULT_MAX_LEASE_TTL=${VAULT_MAX_LEASE_TTL:-"0"}
VAULT_DEFAULT_MAX_REQUEST_DURATION=${VAULT_DEFAULT_MAX_REQUEST_DURATION:-"0"}

# Raw storage endpoint configuration
VAULT_RAW_STORAGE_ENDPOINT=${VAULT_RAW_STORAGE_ENDPOINT:-"false"}
if [[ "${VAULT_RAW_STORAGE_ENDPOINT}" == "true" ]]; then
	echo ""
	echo "----------------------------------------------------------------------"
	echo "                            !!! WARNING !!!                           "
	echo "----------------------------------------------------------------------"
	echo "Vault is configured to use the raw storage endpoint. This is a highly"
	echo "privileged endpoint"
	echo ""
	echo "Enables the sys/raw endpoint which allows the decryption/encryption"
	echo "of raw data into and out of the security barrier."
	echo "----------------------------------------------------------------------"
fi

# Save the configuration to a file
echo "Generating configuration file at \"$VAULT_CONFIG_DIR/docker.hcl\""
cat <<EOT > "$VAULT_CONFIG_DIR/docker.hcl"
ui = ${VAULT_UI}
cluster_name = "${VAULT_CLUSTER_NAME}"
log_level = "${VAULT_LOG_LEVEL}"
log_requests_level = "${VAULT_LOG_REQUESTS_LEVEL}"
pid_file = "${VAULT_PID_FILE}"

# Enables the addition of an HTTP header in all of Vault's HTTP responses: X-Vault-Hostname.
enable_response_header_hostname = true
# Enables the addition of an HTTP header in all of Vault's HTTP responses: X-Vault-Raft-Node-ID.
enable_response_header_raft_node_id = true

# Enables the sys/raw endpoint which allows the decryption/encryption of
# raw data into and out of the security barrier.
# This is a highly privileged endpoint.
raw_storage_endpoint = ${VAULT_RAW_STORAGE_ENDPOINT}

# Lease configuration
default_lease_ttl = "${VAULT_DEFAULT_LEASE_TTL}"
default_max_request_duration = "${VAULT_DEFAULT_MAX_REQUEST_DURATION}"
max_lease_ttl = "${VAULT_MAX_LEASE_TTL}"

# Listener configuration
listener "tcp" {
  address = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"
  tls_disable = ${VAULT_LISTENER_TLS_DISABLE}
  tls_cert_file = "${VAULT_LISTENER_TLS_CERT_FILE}"
  tls_key_file = "${VAULT_LISTENER_TLS_KEY_FILE}"
  ${VAULT_PROXY_PROTOCOL_BEHAVIOR}
  ${VAULT_PROXY_PROTOCOL_AUTHORIZED_ADDRS}
}

# Prometheus metrics listener configuration
listener "tcp" {
	address = "0.0.0.0:8282"
	tls_disable = true
	telemetry {
		unauthenticated_metrics_access = true
	}
}

# Prometheus metrics
telemetry {
	# It is recommended to also enable the option disable_hostname to avoid having prefixed metrics with hostname.
	disable_hostname = true
	# Specifies the interval at which high-cardinality usage data is collected, such as token counts, entity counts, and secret counts. 
	usage_gauge_period = "${VAULT_TELEMETRY_USAGE_GAUGE_PERIOD}"
	# Specifies the amount of time that Prometheus metrics are retained in memory.
	prometheus_retention_time = "24h"
}
EOT

# run the original entrypoint
echo "==> Starting Vault server..."
exec docker-entrypoint.sh "${@}"
