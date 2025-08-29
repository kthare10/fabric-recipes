# FABRIC Recipes

This repository provides a collection of example notebooks and scripts to help users get started with the [FABRIC testbed](https://portal.fabric-testbed.net/). These recipes cover various experiment configurations, network services, and monitoring tools that can be deployed across distributed sites.

## 1: perfSONAR for Network Performance Monitoring

We have added a new notebook demonstrating how to deploy and run perfSONAR-based network measurements between two FABRIC VMs:

* **perfsonar-within-fabric.ipynb**

  * Deploys a shore-side VM with the perfSONAR Toolkit and Result Archiver.
  * Deploys a ship-side VM (emulated in FABRIC) with a Docker-based perfSONAR testpoint.
  * Automates periodic network tests (throughput, RTT, latency, trace).
  * Stores results locally and remotely for visualization.
  * Compatible with FABRIC resources or other environments.

This notebook is particularly useful for mobile edge simulations (e.g., ship-to-shore), but can also be generalized for any network performance experiment between FABRIC sites.

* **perfsonar-psconfig.ipynb**
  *  Deploys a central VM with perfSONAR Testpoint, perfSONAR Archive and perfSONAR Grafana.
  *  Deploys one or more Remote VM with perfSONAR Testpoint, perfSONAR Archive and perfSONAR Grafana.
  *  Configures Hosts on the Central VM via psConfig.
  *  Configures Hosts, Tests, Schedulues, Tasks on Remote VMs.
  *  All tests are archived locally on each Remote VM and optionally on the Central VM.

---

## 2:  static_routes_sshuttle

This notebook demonstrates two methods for enabling communication between nodes across different subnets within a FABRIC topology:

1. **Dynamic Tunneling with `sshuttle`**
   A quick solution using `sshuttle` to forward TCP traffic over SSH without explicit routing configuration. It is helpful for debugging or for temporary access where protocol flexibility is not a concern.

2. **Static Routing with IP Forwarding**
   A realistic approach that sets up one or more intermediate nodes as routers using `ip route` commands. This supports all traffic types (TCP, UDP, ICMP) and offers complete visibility and control over the routing path.

**Use Cases:**

* Multi-subnet experiments requiring end-to-end connectivity
* Debugging topology-level communication issues
* Setting up testbed environments that emulate real-world routed networks

## How to Use

1. Clone this repository.
2. Follow instructions in each notebook to provision resources and run experiments.
3. Make sure you have access to FABRIC. Sign up at [FABRIC Portal](https://portal.fabric-testbed.net/).
4. Contact the maintainer to be added to a project for access.

## License

MIT License

---

For questions, feel free to open an issue or reach out to the repository kthare10@email.unc.edu.
