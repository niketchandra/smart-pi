#!/bin/bash

# Update and upgrade the system
sudo apt-get update
sudo apt-get upgrade -y

# Install necessary dependencies
sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common

# Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --authkey $TAILSCALE_AUTHKEY

# Install Prometheus
wget https://github.com/prometheus/prometheus/releases/download/v2.30.3/prometheus-2.30.3.linux-armv7.tar.gz
tar -xzf prometheus-2.30.3.linux-armv7.tar.gz
sudo mv prometheus-2.30.3.linux-armv7 /usr/local/prometheus
sudo useradd -M -r -s /bin/false prometheus
sudo chown -R prometheus:prometheus /usr/local/prometheus

# Create Prometheus configuration file
sudo tee /usr/local/prometheus/prometheus.yml > /dev/null <<EOL
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'ansible-nodes'
    static_configs:
      - targets:
EOL

for i in {1..255}; do
  echo "        - '192.168.1.$i:9100'" | sudo tee -a /usr/local/prometheus/prometheus.yml
done

# Create Prometheus service file
sudo tee /etc/systemd/system/prometheus.service > /dev/null <<EOL
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/prometheus/prometheus --config.file=/usr/local/prometheus/prometheus.yml --storage.tsdb.path=/usr/local/prometheus/data

[Install]
WantedBy=multi-user.target
EOL

# Start and enable Prometheus service
sudo systemctl daemon-reload
sudo systemctl start prometheus
sudo systemctl enable prometheus

# Install Grafana
sudo apt-get install -y software-properties-common
wget -q -O - https://packages.grafana.com/gpg.key | sudo apt-key add -
sudo add-apt-repository "deb https://packages.grafana.com/oss/deb stable main"
sudo apt-get update
sudo apt-get install -y grafana
sudo systemctl start grafana-server
sudo systemctl enable grafana-server

# Install Node Exporter on all Ansible hosts
sudo apt-get install -y ansible

# Create ansible user
sudo useradd -m -s /bin/bash ansible
echo 'ansible ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/ansible
sudo -u ansible mkdir -p /home/ansible/.ssh

# Create Ansible inventory
sudo tee /home/ansible/inventory > /dev/null <<EOL
[servers]
EOL

for i in {1..255}; do
  echo "192.168.1.$i" | sudo tee -a /home/ansible/inventory
done

sudo chown -R ansible:ansible /home/ansible

# Create Ansible playbook to install Node Exporter
sudo tee /home/ansible/install_node_exporter.yml > /dev/null <<EOL
---
- name: Install Node Exporter
  hosts: servers
  become: yes
  tasks:
    - name: Download Node Exporter
      get_url:
        url: https://github.com/prometheus/node_exporter/releases/download/v1.3.1/node_exporter-1.3.1.linux-armv7.tar.gz
        dest: /tmp/node_exporter.tar.gz

    - name: Extract Node Exporter
      unarchive:
        src: /tmp/node_exporter.tar.gz
        dest: /usr/local/bin/
        remote_src: yes

    - name: Create Node Exporter user
      user:
        name: node_exporter
        shell: /bin/false

    - name: Create systemd service file
      copy:
        dest: /etc/systemd/system/node_exporter.service
        content: |
          [Unit]
          Description=Node Exporter
          Wants=network-online.target
          After=network-online.target

          [Service]
          User=node_exporter
          Group=node_exporter
          Type=simple
          ExecStart=/usr/local/bin/node_exporter-1.3.1.linux-armv7/node_exporter

          [Install]
          WantedBy=default.target

    - name: Start Node Exporter
      systemd:
        name: node_exporter
        enabled: yes
        state: started
EOL

sudo chown -R ansible:ansible /home/ansible

# Run Ansible playbook to install Node Exporter on all hosts
sudo -u ansible ansible-playbook -i /home/ansible/inventory /home/ansible/install_node_exporter.yml

# Print completion message
echo "Prometheus, Grafana, and Ansible setup completed."
echo "Access Grafana at http://<your-raspberry-pi-ip>:3000"
