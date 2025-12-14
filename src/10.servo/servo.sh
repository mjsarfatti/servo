#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(dirname -- "${BASH_SOURCE[0]}")"
source "$SCRIPT_DIR/../00.libs/beddu.sh"

# Override run function from beddu.sh to allow for dry-run mode
run() {
    local outvar_name errvar_name
    local -n outvar errvar # Declare namerefs (will be assigned below if needed)
    local cmd
    while [[ $# -gt 0 ]]; do
        case "$1" in
        --out)
            outvar_name="$2"
            shift 2
            ;;
        --err)
            errvar_name="$2"
            shift 2
            ;;
        *)
            cmd=("$@")
            break
            ;;
        esac
    done
    if [[ $DRY_RUN == true ]]; then
        if spinning; then
            sleep 1
            spop
        else
            sleep 0.1
        fi
        pen -n red "▶ "
        pen "$*"
        return 0
    fi
    [[ -n "${outvar_name}" ]] && local -n outvar="${outvar_name}"
    [[ -n "${errvar_name}" ]] && local -n errvar="${errvar_name}"
    local stdout_file stderr_file
    stdout_file=$(mktemp)
    stderr_file=$(mktemp)
    set +e # Don't immediately exit on error
    "${cmd[@]}" >"${stdout_file}" 2>"${stderr_file}"
    local exit_code=$?
    # shellcheck disable=SC2034
    [[ -n "${outvar_name}" ]] && outvar="$(<"$stdout_file")"
    # shellcheck disable=SC2034
    [[ -n "${errvar_name}" ]] && errvar="$(<"$stderr_file")"
    if [ $exit_code -ne 0 ] && [[ -z "${errvar_name}" ]]; then
        cleaned_errvar=$(sed 's/^[^:]\{1,\}:\( line [0-9]\{1,\}:\)\{0,1\} \(.*\)/\2/' "$stderr_file")
        line
        throw "Command \`$(pen 245 "${cmd[*]}")\` failed with error:"
        pen 245 "  ${cleaned_errvar}"
        pen "  called from: $(pen 245 "${BASH_SOURCE[1]}:${BASH_LINENO[0]}") in $(pen 245 "${FUNCNAME[1]:-main}")"
        line
    fi
    rm -f "${stdout_file}" "${stderr_file}"
    set -e # restore errexit
    return $exit_code
}

# Override run function from beddu.sh to allow for dry-run mode
check() {
    if spinning; then
        spop
        if [[ ! $DRY_RUN == true ]]; then
            upclear
        fi
    fi
    pen -n green "${_mark:-✓} "
    pen "$@"
}

# Function to print section headers
section() {
    line
    pen blue bold "▶ $1"
    pen blue bold "$(printf '–%.0s' {1..80})"
}

# Function to print success messages
success() {
    check "$1"
}

# Function to print info messages
info() {
    pen -n cyan "${_info:-ℹ} "
    pen "$1"
}

# Function to print warning messages
warning() {
    warn "$1"
}

# Check if script is run as root (except in dry-run mode)
if [[ "${EUID}" -ne 0 ]]; then
    throw "This script must be run as root"
    # exit 1
fi

for arg in "$@"; do
    if [[ "$arg" == "--dry-run" ]]; then
        DRY_RUN=true
        break
    else
        pen "Usage: $0 [--dry-run]"
        pen "Options:"
        pen "  --dry-run    Show what would be done without making changes"
        exit 1
    fi
done

line
pen purple "================================================================================"
pen purple "=                                                                              ="
pen purple "=                     Ubuntu Server Hardening Script                           ="
pen purple "=                                                                              ="
pen purple "================================================================================"
line

# Step 1: Create non-root user
section "Creating a non-root user"

new_user() {
    request NEW_USER "Enter username for the new non-root user"
    run --out FOUND_USER --err NO_USER id "${NEW_USER}"
    if [[ ! $DRY_RUN == true ]] && [[ -n "${FOUND_USER}" ]]; then
        warning "User '${NEW_USER}' already exists"
        return 1
    fi
    [[ ! $DRY_RUN == true ]] && adduser "${NEW_USER}"
    run usermod -aG sudo "${NEW_USER}"
    return 0
}

until new_user; do
    # Retrying...
    sleep 0.1
done

success "User '${NEW_USER}' created and added to sudo group"

# Step 2: Set up SSH key authentication
section "Setting up SSH key authentication"

# Ask for SSH public key
request SSH_KEY "Please paste your SSH public key"

SSH_DIR="/home/${NEW_USER}/.ssh"
AUTH_KEYS="${SSH_DIR}/authorized_keys"

info "Creating '.ssh' directory if it doesn't exist"
run mkdir -p "${SSH_DIR}"

info "Adding public key to '${AUTH_KEYS}'"
[[ ! $DRY_RUN == true ]] && echo "${SSH_KEY}" >>"${AUTH_KEYS}"

info "Setting permissions for '${AUTH_KEYS}'"
run chmod 700 "${SSH_DIR}"
run chmod 600 "${AUTH_KEYS}"
run chown -R "${NEW_USER}:${NEW_USER}" "${SSH_DIR}"

success "SSH key added to '${AUTH_KEYS}'"

# Step 3: Harden SSH configuration
section "Hardening SSH configuration"

seek SSH_PORT "Enter custom SSH port (default: 22)"
SSH_PORT=${SSH_PORT:-"22"}

choose PERMIT_ROOT_LOGIN "Permit root login (default and safest: 'no')?" "no" "prohibit-password"

SSH_CONFIG="/etc/ssh/sshd_config"
SSH_CONFIG_DIR="/etc/ssh/sshd_config.d"
SSH_CUSTOM_CONFIG="${SSH_CONFIG_DIR}/90-servo-hardening.conf"

info "Creating modular SSH config directory if it doesn't exist"
run mkdir -p "${SSH_CONFIG_DIR}"

info "Creating modular SSH configuration at '${SSH_CUSTOM_CONFIG}'"
[[ ! $DRY_RUN == true ]] && cat >"${SSH_CUSTOM_CONFIG}" <<EOF
# Servo hardening configuration
Port ${SSH_PORT}
PermitRootLogin ${PERMIT_ROOT_LOGIN}
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM no
EOF

# Check if the main config includes the directory
if ! grep -q "^Include ${SSH_CONFIG_DIR}/\*.conf" "${SSH_CONFIG}"; then
    warning "The main SSH config doesn't seem to include files from '${SSH_CONFIG_DIR}'"
    info "Adding Include directive to '${SSH_CONFIG}'"
    run cp "${SSH_CONFIG}" "${SSH_CONFIG}.bak"
    run sed -i "'1i\Include ${SSH_CONFIG_DIR}/*.conf'" "${SSH_CONFIG}"
    run sed -i '1i\# Following line added by servo.sh' "${SSH_CONFIG}"
fi

success "SSH configuration hardened"

restart_ssh() {
    # Check if ssh.socket exists and is enabled (socket activation)
    if run systemctl is-enabled ssh.socket; then
        info "Socket activation detected, restarting ssh.socket"
        run systemctl daemon-reload
        run systemctl restart ssh.socket
    # Check if service exists with either name
    elif systemctl list-units --type=service | grep -q "ssh.service"; then
        info "SSH service detected as ssh.service"
        run systemctl restart ssh.service
    elif systemctl list-units --type=service | grep -q "sshd.service"; then
        info "SSH service detected as sshd.service"
        run systemctl restart sshd.service
    else
        throw "Could not determine SSH service name"
        exit 1
    fi
}

info "Restarting SSH service"
restart_ssh
success "SSH service restarted"

warning "Make sure port ${SSH_PORT} is open on the server's firewall!"

# Step 4: Update and upgrade the system
section "Updating and upgrading the system"

info "Updating packages and system"
spin "Updating the system..."
run apt update
check "System updated"
spin "Upgrading packages..."
run apt upgrade -y
check "Packages upgraded"

# Step 5: Install essential packages
section "Installing essential packages"

info "Installing build-essential, git, ufw, fail2ban"
spin "Installing packages..."
run apt install -y build-essential git ufw fail2ban
check "Packages installed"

# Step 6: Configure unattended upgrades
section "Configuring unattended upgrades (security patches only)"

info "Installing unattended-upgrades"
spin "Installing package..."
run apt install -y unattended-upgrades
check "Package installed"

info "Backing up existing configuration files"
run --err ERR cp /etc/apt/apt.conf.d/20auto-upgrades /etc/apt/apt.conf.d/20auto-upgrades.bak || true
run --err ERR cp /etc/apt/apt.conf.d/50unattended-upgrades /etc/apt/apt.conf.d/50unattended-upgrades.bak || true

info "Writing '/etc/apt/apt.conf.d/20auto-upgrades'"
[[ ! $DRY_RUN == true ]] && cat >/etc/apt/apt.conf.d/20auto-upgrades <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

info "Writing '/etc/apt/apt.conf.d/50unattended-upgrades'"
[[ ! $DRY_RUN == true ]] && cat >/etc/apt/apt.conf.d/50unattended-upgrades <<EOF
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}-security";
    "\${distro_id}ESMApps:\${distro_codename}-apps-security";
    "\${distro_id}ESM:\${distro_codename}-infra-security";
};
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

info "Enabling and restarting the service"
run systemctl enable --now unattended-upgrades

success "Unattended upgrades configured and enabled"

# Step 7: Configure fail2ban
section "Configuring fail2ban"

info "Creating the local jail configuration file"
run touch /etc/fail2ban/jail.local

# Update fail2ban configuration
[[ ! $DRY_RUN == true ]] && cat >/etc/fail2ban/jail.local <<EOF
[sshd]
enabled = true
mode = aggressive
EOF

info "Enabling and restarting fail2ban"
run systemctl enable --now fail2ban
success "fail2ban configured and started"

# Step 8: Configure firewall
section "Configuring firewall (ufw)"

info "Resetting UFW default policies"

# Reset UFW rules
run ufw --force reset

# Set default policies
run ufw default deny incoming
run ufw default allow outgoing

info "Allowing SSH on port ${SSH_PORT}"

# Allow SSH
run ufw allow "${SSH_PORT}/tcp"

info "Opening ports 80 and 443"
run ufw allow http
run ufw allow https

info "Enabling UFW"
run ufw --force enable

success "UFW enabled"

# Summary and next steps
section "Summary"

pen green "Server hardening completed!"
line
pen "The following security measures have been applied:"
pen "  - Created non-root user: ${NEW_USER}"
pen "  - SSH hardened (root login disabled, password auth disabled)"
pen "  - Custom SSH port: ${SSH_PORT}"
pen "  - System updated and essential packages installed"
pen "  - fail2ban configured for protection against brute force attacks"
pen "  - UFW firewall enabled and configured"
line

run --out IP curl ipinfo.io/ip

warning "IMPORTANT"
pen "Before leaving this session you should first check that you can login correctly"
pen "with your new user. To manually test your SSH connection (from another terminal):"
pen 245 "    ssh -p ${SSH_PORT} ${NEW_USER}@${IP}"

# Audit
section "Audit"

pen "You can run a quick security audit on https://auditvps.com/, or locally by running:"
pen 245 "    curl -s https://auditvps.com/audit.sh | bash"
pen "    (you might have to \`$(pen 245 "apt install -y jq")\` first)."

line
line
pen purple "================================================================================"
pen purple "=                                                                              ="
pen purple "=                      Thank you for using Servo script!                       ="
pen purple "=                                                                              ="
pen purple "================================================================================"
line
