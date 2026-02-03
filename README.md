Overview
This project provides a powerful automation script to deploy a fully functional Frappe Bench within a Docker infrastructure. While it assumes Docker and Docker Compose are already present on your system, the script handles the entire internal orchestration: initializing the Bench, pulling the necessary Docker images, and configuring a multi-app site from scratch.

The Full Stack
Unlike standard installers, this script automates the complex dependency chain for:

Frappe Framework: Core environment setup.

ERPNext: The main ERP suite.

HRMS: Human Resource Management system.

CRM: Sales and Lead management.

Telephony: Communication and call log integration.

Helpdesk: Advanced ticketing and support system.

Key Features
Bench Initialization: Automates the creation of the Frappe Bench inside Docker.

Multi-App Support: Handles the sequential get-app and install-app commands for 5+ modules.

Ubuntu 24.04 Ready: Optimized for the latest LTS environment.

Automated Site Creation: Configures MariaDB hosts, root credentials, and admin passwords automatically.

Dependency Management: Ensures apps like CRM and Telephony are installed in the correct order to avoid "Module Not Found" errors.

How to Use
Prerequisites: Ensure Docker and Docker Compose are installed and your user is in the docker group.

Run the Installer:

Bash
chmod +x deploy_bench.sh
./deploy_bench.sh
What's NOT included (Requirements)
Docker Engine (Version 27.0+ recommended).

Docker Compose V2.

Git & Python3 (Basic OS-level dependencies).
