# StrongSwan Server Container

A strongSwan IKEv2 VPN gateway in a Docker image, built from the official
release tarball, configured with `swanctl`, and shipped with a Prometheus
exporter. Every change is built, scanned with Trivy, and tested end to end
against Debian and Ubuntu clients before it is merged.

| Component | Version |
| --------- | ------- |
| strongSwan | 6.1.0 |
| [strongswan-exporter](https://github.com/ThaseG/strongswan-exporter) | v1.0.0 |
| Go (exporter build) | 1.27.2 |
| Base image | Ubuntu 26.04 LTS |

The versions above are defined in [`versions.sh`](./versions.sh), the single
source of truth for builds and tests. See the [changelog](./CHANGELOG.md).

## Features

- **strongSwan 6.1.0 built from source** – the release tarball is verified
  by SHA-256 before it is built.
- **Explicit plugin set** – every plugin is enabled or disabled on purpose in
  [`server/configure-strongswan.sh`](./server/configure-strongswan.sh);
  OpenSSL is the only crypto provider.
- **swanctl / VICI configuration** – no legacy `ipsec.conf` / stroke.
- **Prometheus exporter** built in, listening on port 9234.
- **Container-friendly runtime** – `tini` as PID 1, clean shutdown on
  `docker stop`, logs on stdout, Docker healthcheck.
- **Small attack surface** – multi-stage build, no compilers or headers in
  the final image, unused binaries removed.
- **Tested on every change** – Trivy scan plus an end-to-end suite with five
  client distributions; results are published per test in GitHub.
- **Automated version updates** – a weekly workflow proposes pull requests
  for new strongSwan, exporter and Go releases.

## Quick start

### 1. Build the image

```bash
docker build -t strongswan-server:latest -f server/strongswan.dockerfile .
```

The image is not published to a registry; build it from this repository.
Build arguments (`STRONGSWAN_VERSION`, `STRONGSWAN_SHA256`,
`EXPORTER_VERSION`, `GO_VERSION`, `UBUNTU_VERSION`) default to the values in
`versions.sh`.

### 2. Prepare the configuration

The container reads a standard swanctl directory, `/etc/swanctl` by default:

```
swanctl/
├── swanctl.conf        # connections and pools
├── x509/               # server certificate (PEM)
├── x509ca/             # CA certificates (PEM)
└── private/            # server private key (PEM) - keep mode 0700
```

A minimal road-warrior configuration (clients authenticate with
certificates and receive an address from `10.0.70.0/24`):

```
connections {
    rw {
        version = 2
        proposals = aes256gcm16-prfsha256-x25519-ecp256
        pools = rw_pool
        send_cert = always

        local {
            auth = pubkey
            certs = server.crt
            id = vpn.example.com
        }
        remote {
            auth = pubkey
            cacerts = ca.crt
        }
        children {
            protected {
                local_ts = 10.10.10.0/24
                esp_proposals = aes256gcm16
                dpd_action = clear
            }
        }
    }
}

pools {
    rw_pool {
        addrs = 10.0.70.0/24
    }
}
```

strongSwan matches IKE identities against the certificate's
subjectAltName, so `id` must appear there (for example `DNS:vpn.example.com`).
[`testing/generate_ca_and_certs.sh`](./testing/generate_ca_and_certs.sh) shows
how to create a matching Ed25519 test PKI with OpenSSL.

### 3. Run the container

```bash
docker run -d --name strongswan \
    --cap-add NET_ADMIN \
    --sysctl net.ipv4.ip_forward=1 \
    -p 500:500/udp -p 4500:4500/udp -p 9234:9234/tcp \
    -v /path/to/swanctl:/etc/swanctl:ro \
    strongswan-server:latest
```

- `NET_ADMIN` is required to manage IPsec (XFRM) state and policies.
- `net.ipv4.ip_forward=1` is required if clients reach networks behind the
  gateway.
- Hosts on the protected network need a route back to the VPN pool through
  the gateway.

Check the result:

```bash
docker logs strongswan
docker exec strongswan swanctl --list-conns
docker exec strongswan swanctl --list-sas
```

## Configuration reference

### Environment variables

| Variable | Default | Description |
| -------- | ------- | ----------- |
| `SWANCTL_DIR` | `/etc/swanctl` | swanctl configuration directory to load at startup. |
| `VICI_TIMEOUT` | `30` | Seconds to wait for charon's control socket before giving up. |
| `EXPORTER_ENABLED` | `true` | Set to `false` to not start the Prometheus exporter. |
| `CHARON_STOP_TIMEOUT` | `8` | Seconds charon gets to shut down before it is killed. Keep it below the `docker stop` timeout (10 s by default). |

### Startup and shutdown

The entrypoint starts charon, waits for the VICI socket
(`/var/run/charon.vici`), loads the configuration with
`swanctl --load-all --noprompt` and starts the exporter. The container exits
if the configuration fails to load, so mistakes are visible immediately.

On `docker stop` the exporter and charon are stopped cleanly and the
container exits with charon's exit code. To reload changed configuration
without a restart:

```bash
docker exec strongswan swanctl --load-all --noprompt
```

### Logging

charon logs to stdout (`docker logs`) at level 1, configured in
[`server/charon-logging.conf`](./server/charon-logging.conf). To change log
levels, mount your own file over
`/etc/strongswan.d/charon-logging-container.conf`.

### Healthcheck

The image's healthcheck runs `swanctl --stats` every 30 seconds; the
container is `healthy` while charon answers on its control socket.

### Ports

| Port | Purpose |
| ---- | ------- |
| 500/udp | IKE |
| 4500/udp | IKE and ESP with NAT traversal |
| 9234/tcp | Prometheus exporter |

## Monitoring

The bundled [strongswan-exporter](https://github.com/ThaseG/strongswan-exporter)
serves:

| Endpoint | Content |
| -------- | ------- |
| `/metrics` | Prometheus metrics |
| `/sessions` | Session list |
| `/sessions_local` | Local session list |
| `/static` | HTML overview of connected clients |

Main metrics:

| Metric | Description |
| ------ | ----------- |
| `probe_success` | 1 while the exporter can talk to charon |
| `strongswan_info` | strongSwan version |
| `strongswan_sessions_total` | Number of established IKE SAs |
| `strongswan_bytes_in_total` / `strongswan_bytes_out_total` | Traffic per client |

Data is refreshed every 15 seconds. Byte counters belong to the client's
current tunnel, so they restart from 0 when a client reconnects or the tunnel
is rekeyed.

## Plugin set

The image is built with OpenSSL as the only crypto backend; strongSwan's
native crypto plugins are disabled because they would only duplicate it.
Highlights:

- **Enabled:** openssl, curve25519, ml (ML-KEM), x509, pem, pkcs1/7/8,
  pubkey, revocation, constraints, curl, eap-identity, eap-tls, eap-radius,
  attr, resolve, updown, counters, certexpire, kernel-netlink, vici, swanctl.
- **Disabled:** stroke (legacy `ipsec.conf`), IKEv1-only plugins (xauth,
  unity), EAP-MD5/MSCHAPv2/PEAP/TTLS, MD4/MD5, pkcs12, kernel-libipsec,
  and the network helpers bypass-lan, farp, forecast and connmark.

bypass-lan in particular is disabled because it caused charon to hang on
shutdown. See the script for the full, commented list.

## Tests

Every push and pull request runs the [Validation Workflow](./.github/workflows/ci.yml)
on a self-hosted runner:

1. **pre-clean-up** – removes all Docker resources on the runner.
2. **Build** – builds the image with the versions from `versions.sh`.
3. **Trivy** – fails on unignored HIGH/CRITICAL vulnerabilities
   (exceptions in [`.trivyignore`](./.trivyignore)); the report is added to
   the job summary.
4. **End-to-end tests** – [`testing/e2e.bats`](./testing/e2e.bats), run with
   [bats](https://github.com/bats-core/bats-core). Results appear as a check
   with one entry per test; logs are uploaded as the `e2e-test-results`
   artifact.
5. **post-clean-up** – removes everything again, whatever the outcome.

The test topology:

```
clients (192.168.200.0/24) ──IPsec──> server ──> protected service (10.10.10.10)
```

One client runs on each supported release, using that distribution's own
strongSwan package: Debian 12 and 13, Ubuntu 22.04, 24.04 and 26.04. The
tests cover configuration loading, tunnel setup, virtual IP assignment,
traffic through the tunnel (verified by IPsec packet counters), the exporter,
container restart and clean shutdown.

To run the suite on a machine with Docker and bats:

```bash
docker build -t strongswan-server:latest -f server/strongswan.dockerfile .
testing/e2e.sh up
bats testing/e2e.bats
testing/e2e.sh down
```

`testing/e2e.sh` also has `connect` (reconnect all clients), `traffic`
(keep a slow ping running from every client) and `logs <dir>`.

## Automated version updates

The [Weekly Version Check](./.github/workflows/version-updates.yml) runs
every Wednesday at 06:00 UTC (or manually from the Actions tab). When a new
strongSwan, exporter or Go release is available,
[`scripts/check-updates.sh`](./scripts/check-updates.sh) updates
`versions.sh`, the Dockerfile and the changelog, and opens a pull request,
on which the Validation Workflow then runs.

It needs a repository secret `VERSION_UPDATE_TOKEN`: a fine-grained personal
access token for this repository with *Contents* and *Pull requests* set to
read and write.

## Upgrading strongSwan manually

1. Update `STRONGSWAN_VERSION` and `STRONGSWAN_SHA256` in `versions.sh` and
   the matching `ARG` defaults in `server/strongswan.dockerfile`.
2. Check strongSwan's `NEWS` for removed or renamed plugins and update
   `server/configure-strongswan.sh`.
3. Add a changelog entry and open a pull request; CI builds and tests it.

Running `scripts/check-updates.sh` locally does steps 1 and 3 for you.

## Repository layout

```
server/      Dockerfile, configure script, entrypoint, logging and exporter config
testing/     e2e test suite, test topology and certificate/config generators
scripts/     maintenance scripts (weekly version check)
versions.sh  component versions and test topology
```

## Contributing and contact

- See [CONTRIBUTING](./CONTRIBUTING.md) for the Git workflow and versioning.
- Contact the owner group: [ThaseG](mailto:andrej@hyben.net).

## License

MIT – see [LICENSE](./LICENSE).
