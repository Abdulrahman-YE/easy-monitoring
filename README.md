# Easy Monitoring

This script installs and configures a lightweight yet powerful monitoring stack on a Linux server. The stack includes:

- **Grafana** – a visualization and analytics platform
- **Prometheus** – a monitoring and alerting toolkit
- **Node Exporter** – a tool to expose hardware and OS metrics

The script also sets up essential firewall rules, creates dedicated service users, configures systemd services, and backs up existing configuration files.

---

## Table of Contents

1. [Overview](#overview)
2. [Features](#features)
3. [Prerequisites](#prerequisites)
4. [Recommended Pre-Installation Checklist](#recommended-pre-installation-checklist)
5. [Configuration Options](#configuration-options)
6. [Usage](#usage)
7. [Deployment Considerations](#deployment-considerations)
8. [Post-Installation Verification](#post-installation-verification)
9. [Troubleshooting and Logging](#troubleshooting-and-logging)
10. [License](#license)

---

## Overview

This Bash script automates the installation and configuration of a monitoring stack consisting of **Grafana, Prometheus, and Node Exporter**. It is designed for simplicity, efficiency, and reliability. The script ensures that:

- The latest specified versions of Prometheus and Node Exporter are installed.
- Grafana is installed and configured with an auto-provisioned Prometheus datasource.
- All components run under non-privileged service users.
- A firewall (UFW) is configured to allow only the required ports.
- Any existing configurations are backed up before being overwritten.

---

## Features

- **Simple One-Command Setup:** Quickly install and configure the monitoring stack with minimal effort.
- **Customizable Parameters:** Easily override default values via environment variables or command-line arguments.
- **Idempotent Execution:** Ensures no duplicate installations and safely skips existing configurations.
- **Logging and Error Handling:** Installation logs are stored for debugging, and strict shell options (`set -euo pipefail`) prevent partial installations.
- **Security Best Practices:** Runs services under dedicated users and configures minimal firewall rules.

---

## Prerequisites

- **Operating System:** Debian-based Linux distributions (e.g., Ubuntu) with APT package management.
- **Privileges:** Must be run as the `root` user or with sudo privileges.
- **Internet Connectivity:** Required to download necessary packages.
- **Installed Packages:** Utilities such as `wget`, `curl`, `tar`, and `gpg` should be available (the script installs them if missing).

---

## Recommended Pre-Installation Checklist

### Verify Port Availability

```bash
ss -tulpn | grep -E ':3000|:9090|:9100'
```

### Check Existing Firewall Rules

```bash
ufw status verbose
```

### Ensure Adequate Resources

```bash
free -h && df -h
```

### Verify System Architecture

```bash
uname -m  # Ensure x86_64 architecture
```

---

## Configuration Options

The following parameters can be set as environment variables or via command-line arguments:

| Parameter               | Description                              | Default Value                  |
| ----------------------- | ---------------------------------------- | ------------------------------ |
| `GRAFANA_PORT`          | Port on which Grafana will be accessible | 3000                           |
| `PROMETHEUS_PORT`       | Port for Prometheus to listen on         | 9090                           |
| `NODE_EXPORTER_PORT`    | Port for Node Exporter to expose metrics | 9100                           |
| `PROMETHEUS_VERSION`    | Version of Prometheus to install         | 2.51.0                         |
| `NODE_EXPORTER_VERSION` | Version of Node Exporter to install      | 1.7.0                          |
| `LOG_FILE`              | Log file to record installation output   | `/var/log/easy_monitoring.log` |

---

## Usage

Run the script as root. You can override defaults using environment variables or command-line options.

### Examples

- **Run with defaults:**

  ```bash
  sudo ./install_monitoring.sh
  ```

- **Specify custom ports:**

  ```bash
  sudo ./install_monitoring.sh --grafana-port 8080 --prometheus-port 9095 --node-exporter-port 9110
  ```

- **Display Help:**
  ```bash
  sudo ./install_monitoring.sh --help
  ```

---

## Deployment Considerations

Before running this script on a production server:

- **Test in a Staging Environment**
- **Ensure Adequate System Resources**
- **Verify Firewall Rules**
- **Backup Existing Configurations**

---

## Post-Installation Verification

### Check Service Status

```bash
systemctl status grafana-server prometheus node_exporter
```

### Verify Metrics Collection

```bash
# Check Node Exporter metrics
curl -s http://127.0.0.1:${NODE_EXPORTER_PORT}/metrics | head

# Check Prometheus targets
curl -s http://127.0.0.1:${PROMETHEUS_PORT}/targets | grep 'UP'
```

---

## Troubleshooting and Logging

- **Log File Location:**  
  `/var/log/easy_monitoring.log` contains detailed logs.

- **Check Systemd Logs:**

  ```bash
  journalctl -u <service-name>
  ```

- **APT Locks:**  
  If the script aborts due to an APT lock, ensure that no other package operations are running.

---

## License

_This script is provided as-is without warranty. Modify and distribute it as needed for your organization._

---

🚀 **Easy Monitoring makes infrastructure monitoring effortless and reliable!**
