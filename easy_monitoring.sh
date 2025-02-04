#!/bin/bash
set -euo pipefail

#############################################
### Enterprise Monitoring Stack Installer ###
#############################################

# Configuration: Either set environment variables or pass as arguments
# Usage: ./easy_monitoring.sh [OPTIONS]
# Environment variables override defaults

### Parameter Defaults ###
: "${GRAFANA_PORT:=3000}"
: "${PROMETHEUS_PORT:=9090}"
: "${NODE_EXPORTER_PORT:=9100}"
: "${PROMETHEUS_VERSION:=2.51.0}"
: "${NODE_EXPORTER_VERSION:=1.7.0}"
: "${WORKDIR:=/tmp/monitoring-$(date +%s)}"
: "${LOG_FILE:=/var/log/easy_monitoring.log}"
: "${GRAFANA_DS_PROVISION:=/etc/grafana/provisioning/datasources/prometheus.yml}"
: "${PROMETHEUS_MEMORY_LIMIT:=2G}"

### Service Configuration ###
PROMETHEUS_USER="prometheus"
NODE_EXPORTER_USER="node_exporter"
PROMETHEUS_DIR="/etc/prometheus"
PROMETHEUS_DATA_DIR="/var/lib/prometheus"

### Initialize Logging ###
exec > >(awk '{ print strftime("[%Y-%m-%d %H:%M:%S]"), $0 }' | tee -a "${LOG_FILE}") 2>&1
echo "=== Installation started ==="

### Argument Parsing ###
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
  --grafana-port PORT         Set Grafana port (default: 3000)
  --prometheus-port PORT      Set Prometheus port (default: 9090)
  --node-exporter-port PORT   Set Node Exporter port (default: 9100)
  --prometheus-version VER    Set Prometheus version (default: 2.51.0)
  --node-exporter-version VER Set Node Exporter version (default: 1.7.0)
  --memory-limit SIZE         Set Prometheus memory limit (default: 2G)
  --help                      Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --grafana-port)
        GRAFANA_PORT="$2"
        shift
        ;;
        --prometheus-port)
        PROMETHEUS_PORT="$2"
        shift
        ;;
        --node-exporter-port)
        NODE_EXPORTER_PORT="$2"
        shift
        ;;
        --prometheus-version)
        PROMETHEUS_VERSION="$2"
        shift
        ;;
        --node-exporter-version)
        NODE_EXPORTER_VERSION="$2"
        shift
        ;;
        --memory-limit)
        PROMETHEUS_MEMORY_LIMIT="$2"
        shift
        ;;
        --help)
        show_help
        exit 0
        ;;
        *)
        echo "Unknown parameter: $1"
        exit 1
        ;;
    esac
    shift
done

### Error Handling Functions ###
critical_error() {
    echo "CRITICAL ERROR: $1"
    echo "Check ${LOG_FILE} for details"
    exit 1
}

check_command() {
    if ! "$@"; then
        critical_error "Command failed: $*"
    fi
}

### System Checks ###
check_uid() {
    if [[ $EUID -ne 0 ]]; then
        critical_error "This script must be run as root"
    fi
}

check_apt_lock() {
    if fuser /var/lib/apt/lists/lock >/dev/null 2>&1; then
        critical_error "APT system is locked - ensure no other package operations are running"
    fi
}

### Idempotency Checks ###
service_exists() {
    systemctl list-unit-files | grep -q "^$1"
}

package_installed() {
    dpkg -l | grep -q "^ii.*$1"
}

### Backup Functions ###
backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local backup="${file}.bak-$(date +%s)"
        echo "Creating backup of existing file: ${file} -> ${backup}"
        cp "$file" "$backup" || critical_error "Failed to backup ${file}"
    fi
}

### Installation Functions ###
setup_working_dir() {
    echo "Creating workspace: ${WORKDIR}"
    mkdir -p "${WORKDIR}"
    cd "${WORKDIR}"
}

install_grafana() {
    if package_installed grafana; then
        echo "Grafana already installed - skipping"
        return 0
    fi

    echo "Adding Grafana repository..."
    check_command wget -q -O - https://packages.grafana.com/gpg.key | gpg --dearmor > /etc/apt/trusted.gpg.d/grafana.gpg
    echo "deb [signed-by=/etc/apt/trusted.gpg.d/grafana.gpg] https://packages.grafana.com/oss/deb stable main" > /etc/apt/sources.list.d/grafana.list
    
    echo "Updating package lists..."
    check_command apt-get update -qq
    
    echo "Installing Grafana..."
    check_command apt-get install -y -qq grafana

    echo "Configuring Grafana provisioning..."
    mkdir -p "$(dirname "${GRAFANA_DS_PROVISION}")"
    backup_file "${GRAFANA_DS_PROVISION}"
    cat > "${GRAFANA_DS_PROVISION}" << EOF
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://127.0.0.1:${PROMETHEUS_PORT}
    isDefault: true
    editable: false
EOF

    echo "Updating Grafana port..."
    backup_file "/etc/grafana/grafana.ini"
    sed -i "s/;http_port = 3000/http_port = ${GRAFANA_PORT}/" /etc/grafana/grafana.ini
}

install_prometheus() {
    if command -v prometheus >/dev/null; then
        echo "Prometheus already installed - skipping"
        return 0
    fi

    echo "Downloading Prometheus v${PROMETHEUS_VERSION}..."
    check_command wget -q "https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
    check_command tar -xzf "prometheus-${PROMETHEUS_VERSION}.linux-amd64.tar.gz"
    
    echo "Installing Prometheus..."
    cd "prometheus-${PROMETHEUS_VERSION}.linux-amd64"
    check_command install -m 0755 prometheus promtool /usr/local/bin/
    
    echo "Creating directories..."
    mkdir -p "${PROMETHEUS_DIR}" "${PROMETHEUS_DATA_DIR}"
    cp -r consoles console_libraries "${PROMETHEUS_DIR}/"
    
    echo "Configuring Prometheus..."
    backup_file "${PROMETHEUS_DIR}/prometheus.yml"
    cat > "${PROMETHEUS_DIR}/prometheus.yml" << EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'node_exporter'
    static_configs:
    - targets: ['127.0.0.1:${NODE_EXPORTER_PORT}']
EOF

    echo "Creating Prometheus service user..."
    if ! id "${PROMETHEUS_USER}" &>/dev/null; then
        check_command useradd --no-create-home --shell /bin/false "${PROMETHEUS_USER}"
    fi
    
    echo "Setting permissions..."
    chown -R "${PROMETHEUS_USER}:${PROMETHEUS_USER}" "${PROMETHEUS_DIR}" "${PROMETHEUS_DATA_DIR}"

    echo "Creating systemd service with resource limits..."
    cat > /etc/systemd/system/prometheus.service << EOF
[Unit]
Description=Prometheus
After=network.target

[Service]
User=${PROMETHEUS_USER}
Group=${PROMETHEUS_USER}
MemoryLimit=${PROMETHEUS_MEMORY_LIMIT}
Restart=on-failure
ExecStart=/usr/local/bin/prometheus \\
    --config.file=${PROMETHEUS_DIR}/prometheus.yml \\
    --storage.tsdb.path=${PROMETHEUS_DATA_DIR} \\
    --web.listen-address=:${PROMETHEUS_PORT}

[Install]
WantedBy=multi-user.target
EOF
}

install_node_exporter() {
    if command -v node_exporter >/dev/null || service_exists node_exporter; then
        echo "Node Exporter already installed - skipping"
        return 0
    fi

    echo "Downloading Node Exporter v${NODE_EXPORTER_VERSION}..."
    check_command wget -q "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"
    check_command tar -xzf "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz"

    echo "Installing Node Exporter..."
    cd "node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64"
    check_command install -m 0755 node_exporter /usr/local/bin/

    echo "Creating Node Exporter service user..."
    if ! id "${NODE_EXPORTER_USER}" &>/dev/null; then
        check_command useradd --no-create-home --shell /bin/false "${NODE_EXPORTER_USER}"
    fi

    echo "Creating systemd service..."
    backup_file "/etc/systemd/system/node_exporter.service"
    cat > /etc/systemd/system/node_exporter.service << EOF
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=${NODE_EXPORTER_USER}
Group=${NODE_EXPORTER_USER}
Restart=on-failure
ExecStart=/usr/local/bin/node_exporter \\
    --web.listen-address=127.0.0.1:${NODE_EXPORTER_PORT} \\
    --collector.systemd \\
    --collector.textfile

[Install]
WantedBy=multi-user.target
EOF
}

### Main Execution ###
main() {
    check_uid
    check_apt_lock
    setup_working_dir

    echo "Starting system update..."
    check_command apt-get update -qq
    check_command apt-get upgrade -y -qq
    check_command apt-get install -y -qq curl wget tar ufw

    echo "Configuring firewall..."
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow "${GRAFANA_PORT}/tcp"
    ufw allow "${PROMETHEUS_PORT}/tcp"
    ufw allow "${NODE_EXPORTER_PORT}/tcp"
    ufw --force enable

    install_grafana
    install_prometheus
    install_node_exporter

    echo "Reloading systemd and starting services..."
    systemctl daemon-reload
    systemctl enable --now grafana-server prometheus node_exporter

    echo "Installation complete"
    echo "Grafana URL: http://$(curl -s icanhazip.com):${GRAFANA_PORT}"
    echo "Prometheus URL: http://127.0.0.1:${PROMETHEUS_PORT}"
    echo "Node Exporter metrics: http://127.0.0.1:${NODE_EXPORTER_PORT}/metrics"
    echo "Full log available at: ${LOG_FILE}"
}

### Execution Trap ###
cleanup() {
    echo "Cleaning temporary files..."
    rm -rf "${WORKDIR}"
    echo "=== Installation completed at $(date) ==="
}
trap cleanup EXIT

main