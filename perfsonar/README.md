# perfSONAR on FABRIC — Network Performance Monitoring

This directory contains Jupyter notebooks for deploying and operating **perfSONAR-based network performance monitoring** on the [FABRIC Testbed](https://portal.fabric-testbed.net/). The notebooks cover two deployment models — a **lightweight custom archiver stack** optimized for resource-constrained edge devices, and the **standard perfSONAR toolkit** for general-purpose multi-site mesh testing.

## Why a Custom Archiver Stack?

The standard perfSONAR toolkit (`perfsonar-archive` + `perfsonar-grafana` backed by OpenSearch and Logstash) requires significant memory and CPU, making it impractical for **edge devices** such as Raspberry Pis deployed on research vessels or remote field stations.

The custom **pScheduler Result Archiver** stack addresses this with a purpose-built alternative:

| | Standard perfSONAR Toolkit | Custom Archiver Stack |
|---|---|---|
| **Storage backend** | OpenSearch + Logstash | TimescaleDB (PostgreSQL) |
| **Memory footprint** | High (~4–8 GB baseline) | Low (~512 MB–1 GB) |
| **Target hardware** | Servers, VMs with ≥16 GB RAM | Raspberry Pi, edge devices, small VMs |
| **Visualization** | Grafana (perfsonar-grafana) | Grafana (lightweight provisioning) |
| **Result ingestion** | Logstash HTTP pipeline | REST API with bearer token auth |
| **Data model** | OpenSearch JSON documents | Relational with composite PK for idempotent upserts |
| **Compression** | OpenSearch index lifecycle | TimescaleDB native compression + retention policies |

The custom stack is fully containerized (TimescaleDB + Grafana + Archiver + Nginx) and maintains compatibility with standard perfSONAR pScheduler tools — tests run identically, only the archiving backend differs.

## Notebooks

### 1. `perfsonar-within-fabric.ipynb` — Ship-to-Shore with Custom Archiver

Deploys a **ship-side and shore-side** monitoring setup using the custom lightweight archiver stack on both ends.

- **Topology**: 2 VMs (shore + ship) connected via multiple FabNetv4 networks
- **Ship VM**: Multiple NICs for independent measurement of each network path, using `%` source-binding syntax (`dst_ip@name%interface`)
- **Shore VM**: Single NIC, runs archiver stack and receives results from ship
- **Archiver**: Custom stack (TimescaleDB, Grafana, REST Archiver, Nginx) on both VMs
- **Tests**: Latency, RTT, throughput, MTU, clock offset, traceroute — every 6 hours
- **Archiving**: Bidirectional — ship archives locally and to shore; shore archives locally
- **Access**: Grafana via SSH tunnel at `https://127.0.0.1:8443`
- **Resource requirements**: Ship as low as 4 cores / 16 GB RAM; Shore 16 cores / 32 GB RAM

**Best for**: Edge/vessel deployments, resource-constrained environments, scenarios requiring local + remote redundancy.

### 2. `perfsonar-psconfig.ipynb` — Multi-Site Mesh with Standard Toolkit

Deploys a **configurable N-node mesh** using the standard perfSONAR toolkit with pSConfig-based test orchestration.

- **Topology**: N VMs (1 central + N−1 remote), each on a separate FabNetv4 L3 network
- **Orchestration**: Central VM publishes a pSConfig mesh template; remote VMs subscribe and pull test schedules automatically
- **Archiver**: Standard perfSONAR toolkit (OpenSearch + Logstash + Grafana)
- **Tests**: Throughput (iperf3), latency (owping/twping/halfping), RTT (ping/tcpping), MTU, clock, traceroute
- **Configurable**: Node count (`TOTAL_NODE_CNT`), test interval (10M/2H/4H/6H), optional central archiving
- **Access**: Grafana via SSH tunnel at `https://127.0.0.1:8443+`
- **Resource requirements**: 16 cores / 32 GB RAM per VM

**Best for**: General-purpose multi-site performance testing, pSConfig mesh workflows, environments with sufficient resources.

### 3. `perfsonar-psconfig-fabnetv4ext.ipynb` — Multi-Site Mesh with Public IPs

Nearly identical to notebook 2, but uses **FabNetv4Ext** networks for publicly routable IP addresses.

- **Topology**: Same N-node mesh as notebook 2, but with external L3 networks and manual IP assignment
- **Key difference**: Public IPs enable direct Grafana access without SSH tunnels (with local routing configured)
- **Archiver**: Standard perfSONAR toolkit
- **Access**: Direct via public IP or SSH tunnel (fallback)

**Best for**: Scenarios requiring external accessibility to monitoring dashboards or integration with external systems.

## Quick Start

1. Open the desired notebook in the [FABRIC Portal](https://portal.fabric-testbed.net/) Jupyter environment or a local Jupyter session with FABlib configured.
2. Update the configuration cell (slice name, sites, node count, test interval).
3. Run cells sequentially — setup scripts are cloned from the [fabric-recipes](https://github.com/kthare10/fabric-recipes) repository directly onto the VMs.
4. For the custom archiver notebook, Grafana credentials default to `admin/perfsonar`.

## Related Repositories

- [pscheduler-result-archiver](https://github.com/kthare10/pscheduler-result-archiver) — Custom archiver REST API, TimescaleDB schema, Grafana dashboards, Docker Compose stack
- [perfsonar-extensions](https://github.com/kthare10/perfsonar-extensions) — Docker-based perfSONAR testpoint with cron-scheduled test execution and multi-archiver support
- [fabric-recipes](https://github.com/kthare10/fabric-recipes) — FABRIC experiment notebooks and deployment scripts (canonical location for `node_tools/`)
