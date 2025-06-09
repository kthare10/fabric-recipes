# FABRIC Recipes

This repository provides a collection of example notebooks and scripts to help users get started with the [FABRIC testbed](https://portal.fabric-testbed.net/). These recipes cover various experiment configurations, network services, and monitoring tools that can be deployed across distributed sites.

## New: perfSONAR for Network Performance Monitoring

We have added a new notebook demonstrating how to deploy and run perfSONAR-based network measurements between two FABRIC VMs:

* **perfsonar-within-fabric.ipynb**

  * Deploys a shore-side VM with the perfSONAR Toolkit and Result Archiver.
  * Deploys a ship-side VM (emulated in FABRIC) with a Docker-based perfSONAR testpoint.
  * Automates periodic network tests (throughput, RTT, latency, trace).
  * Stores results locally and remotely for visualization.
  * Compatible with FABRIC resources or other environments.

This notebook is particularly useful for mobile edge simulations (e.g., ship-to-shore), but can also be generalized for any network performance experiment between FABRIC sites.

## How to Use

1. Clone this repository.
2. Follow instructions in each notebook to provision resources and run experiments.
3. Make sure you have access to FABRIC. Sign up at [FABRIC Portal](https://portal.fabric-testbed.net/).
4. Contact the maintainer to be added to a project for access.

## License

MIT License

---

For questions, feel free to open an issue or reach out to the repository kthare10@email.unc.edu.
