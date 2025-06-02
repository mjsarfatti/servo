#!/usr/bin/env bash
set -euo pipefail

readonly _q='?'
readonly _a='❯'
readonly _o='◌'
readonly _O='●'
readonly _mark='✓'
readonly _warn='!'
readonly _cross='✗'
readonly _info='ℹ'
readonly _spinner='⣷⣯⣟⡿⢿⣻⣽⣾' # See for alternatives: https://antofthy.gitlab.io/info/ascii/Spinners.txt
readonly _spinner_frame_duration=0.1

up() {
    printf "\033[A"
}
down() {
    printf "\033[B"
}
bol() {
    printf "\r"
}
eol() {
    printf "\033[999C"
}
cl() {
    printf "\033[2K"
}
upclear() {
    up; bol; cl
}
line() {
    printf "\n"
}
show_cursor() {
    printf "\033[?25h"
}
hide_cursor() {
    printf "\033[?25l"
}

pen() {
    local new_line="\n"
    local text="${*: -1}"
    local args=("${@:1:$#-1}")
    local format_code=""
    local reset_code="\033[0m"
    for arg in "${args[@]}"; do
        arg=${arg,,}
        case "$arg" in
        -n) new_line="" ;;
        bold) format_code+="\033[1m" ;;
        italic) format_code+="\033[3m" ;;
        underline) format_code+="\033[4m" ;;
        black) format_code+="\033[30m" ;;
        red) format_code+="\033[31m" ;;
        green) format_code+="\033[32m" ;;
        yellow) format_code+="\033[33m" ;;
        blue) format_code+="\033[34m" ;;
        purple) format_code+="\033[35m" ;;
        cyan) format_code+="\033[36m" ;;
        white) format_code+="\033[37m" ;;
        grey | gray) format_code+="\033[90m" ;;
        [0-9]*)
            if [[ "$arg" =~ ^[0-9]+$ ]] && [ "$arg" -ge 0 ] && [ "$arg" -le 255 ]; then
                format_code+="\033[38;5;${arg}m"
            fi
            ;;
        *) ;;
        esac
    done
    printf "%b%s%b%b" "${format_code}" "${text}" "${reset_code}" "${new_line}"
}

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
    [[ -n "${outvar_name}" ]] && local -n outvar="${outvar_name}"
    [[ -n "${errvar_name}" ]] && local -n errvar="${errvar_name}"
    local stdout_file stderr_file
    stdout_file=$(mktemp)
    stderr_file=$(mktemp)
    "${cmd[@]}" >"${stdout_file}" 2>"${stderr_file}"
    local exit_code=$?
    [[ -n "${outvar_name}" ]] && outvar="$(<"$stdout_file")"
    [[ -n "${errvar_name}" ]] && errvar="$(<"$stderr_file")"
    rm -f "${stdout_file}" "${stderr_file}"
    return $exit_code
}

check() {
    if spinning; then
        spop
        upclear
    fi
    pen -n green "${_mark:-✓} "
    pen "$@"
}

repen() {
    upclear
    pen "$@"
}

trap "spop; show_cursor" EXIT INT TERM
_spinner_pid=""
_frame_duration="${_spinner_frame_duration:-0.1}"
spin() {
    local message=("$@")
    local spinner="${_spinner:-⣷⣯⣟⡿⢿⣻⣽⣾}"
    if spinning; then
        spop --keep-cursor-hidden
    fi
    (
        hide_cursor
        trap "exit 0" USR1
        pen -n cyan "${spinner:0:1} "
        pen "${message[@]}"
        while true; do
            for ((i = 0; i < ${#spinner}; i++)); do
                frame="${spinner:$i:1}"
                up
                bol
                pen -n cyan "${frame} "
                pen "${message[@]}"
                sleep "$_frame_duration"
            done
        done
    ) &
    _spinner_pid=$!
}
spop() {
    local keep_cursor_hidden=false
    [[ "$1" == "--keep-cursor-hidden" ]] && keep_cursor_hidden=true
    if spinning; then
        kill -USR1 "${_spinner_pid}" 2>/dev/null
        sleep "$_frame_duration"
        if ps -p "${_spinner_pid}" >/dev/null 2>&1; then
            kill "${_spinner_pid}" 2>/dev/null
        fi
        if [[ "$keep_cursor_hidden" == false ]]; then
            show_cursor
        fi
        _spinner_pid=""
    fi
}
spinning() {
    [[ -n "${_spinner_pid}" ]]
}

throw() {
    if spinning; then
        spop
        upclear
    fi
    pen -n red "${_cross:-✗} "
    pen "$@"
}

warn() {
    if spinning; then
        spop
        upclear
    fi
    pen -n yellow bold italic "${_warn:-!} "
    pen italic "$@"
}

choose() {
    local -n outvar="$1"
    local prompt
    local options=("${@:3}")
    local current=0
    local count=${#options[@]}
    prompt=$(
        pen -n blue "${_q:-?} "
        pen -n "${2} "
        pen gray "[↑↓]"
    )
    hide_cursor
    trap 'show_cursor; return' INT TERM
    pen "$prompt"
    while true; do
        local index=0
        for item in "${options[@]}"; do
            if ((index == current)); then
                pen -n blue "${_O:-●} "
                pen "${item}"
            else
                pen gray "${_o:-◌} ${item}"
            fi
            ((index++))
        done
        read -s -r -n1 key
        if [[ $key == $'\e' ]]; then
            read -s -r -n2 -t 0.0001 escape
            key+="$escape"
        fi
        case "$key" in
        $'\e[A' | 'k')
            ((current--))
            [[ $current -lt 0 ]] && current=$((count - 1))
            ;;
        $'\e[B' | 'j')
            ((current++))
            [[ $current -ge "$count" ]] && current=0
            ;;
        '')
            break
            ;;
        esac
        echo -en "\e[${count}A\e[J"
    done
    outvar="${options[$current]}"
}

confirm() {
    local default="y"
    local hint="[Y/n]"
    local prompt
    local response
    while [[ $# -gt 0 ]]; do
        case "$1" in
        --default-no)
            default="n"
            hint="[y/N]"
            shift
            ;;
        --default-yes)
            shift
            ;;
        *) break ;;
        esac
    done
    prompt=$(
        pen -n blue "${_q:-?} "
        pen -n "$1"
        pen gray " $hint"
        pen -n blue "${_a:-❯} "
    )
    show_cursor
    while true; do
        read -r -p "$prompt" response
        response="${response:-$default}"
        case "$response" in
        [Yy] | [Yy][Ee][Ss])
            upclear
            pen -n blue "${_a:-❯} "
            pen "yes"
            return 0
            ;;
        [Nn] | [Nn][Oo])
            upclear
            pen -n blue "${_a:-❯} "
            pen "no"
            return 1
            ;;
        *)
            echo
            warn "Please answer yes or no."
            ;;
        esac
    done
}

request() {
    local -n outvar="$1"
    local prompt
    local answer
    prompt=$(
        pen -n blue "${_q:-?} "
        pen "${2}"
        pen -n blue "${_a:-❯} "
    )
    show_cursor
    while true; do
        read -r -p "$prompt" answer
        case "$answer" in
        "")
            echo
            warn "Please type your answer."
            ;;
        *) break ;;
        esac
    done
    outvar="$answer"
}

seek() {
    local -n outvar="$1"
    local prompt
    local answer
    prompt=$(
        pen -n blue "${_q:-?} "
        pen "${2}"
        pen -n blue "${_a:-❯} "
    )
    show_cursor
    read -r -p "$prompt" answer
    outvar="$answer"
}

# Check if script is run as root (except in dry-run mode)
if [[ $EUID -ne 0 && $DRY_RUN == false ]]; then
    throw "This script must be run as root"
    exit 1
fi

pen magenta "============================================"
pen magenta "=      Ubuntu Server Hardening Script      ="
pen magenta "============================================"

# Function to print section headers
section() {
    line
    pen blue bold "▶ $1"
    pen blue bold "$(printf '=%.0s' {1..50})"
}

# Function to print success messages
success() {
    if [ "$DRY_RUN" = true ]; then
        pen -n yellow "[DRY-RUN]: "
    fi
    check "$1"
}

# Function to print info messages
info() {
    if [ "$DRY_RUN" = true ]; then
        pen -n yellow "[DRY-RUN]: "
    fi
    pen -n cyan "${_info:-✓} "
    pen "$i"
}

# Function to print warning messages
warning() {
    if [ "$DRY_RUN" = true ]; then
        pen -n yellow "[DRY-RUN]: "
    fi
    warn "$1"
}

# Step 1: Create non-root user
section "Creating a non-root user"

new_user() {
    set +e  # Temporarily disable
    request NEW_USER "Enter username for the new non-root user"
    if id "$NEW_USER" &>/dev/null; then
        warning "User '$NEW_USER' already exists"
        return 1
    else
        set -e  # Re-enable
        run "adduser $NEW_USER"
        run "usermod -aG sudo $NEW_USER"
        return 0
    fi
}

until new_user; do
    # Retrying...
    sleep 0.1
done

success "User '$NEW_USER' created and added to sudo group"

# Step 2: Set up SSH key authentication
section "Setting up SSH key authentication"

# Ask for SSH public key
request SSH_KEY "Please paste your SSH public key"

SSH_DIR="/home/$NEW_USER/.ssh"
AUTH_KEYS="$SSH_DIR/authorized_keys"

info "Creating .ssh directory if it doesn't exist"
run "mkdir -p \"$SSH_DIR\""

info "Adding public key to \"$AUTH_KEYS\""
run "echo \"$SSH_KEY\" >> \"$AUTH_KEYS\""

info "Setting permissions for \"$AUTH_KEYS\""
run "chmod 700 \"$SSH_DIR\""
run "chmod 600 \"$AUTH_KEYS\""
run "chown -R \"$NEW_USER:$NEW_USER\" \"$SSH_DIR\""

success "SSH key added to $AUTH_KEYS"

# Step 3: Harden SSH configuration
section "Hardening SSH configuration"

seek SSH_PORT "Enter custom SSH port (default: 22)"
SSH_PORT=${SSH_PORT:-"22"}

choose PERMIT_ROOT_LOGIN "Permit root login (default and safest: 'no')?" "no" "prohibit-password"

SSH_CONFIG="/etc/ssh/sshd_config"
SSH_CONFIG_DIR="/etc/ssh/sshd_config.d"
SSH_CUSTOM_CONFIG="$SSH_CONFIG_DIR/90-servo-hardening.conf"

info "Creating modular SSH config directory if it doesn't exist"
run "mkdir -p \"$SSH_CONFIG_DIR\""

info "Creating modular SSH configuration at $SSH_CUSTOM_CONFIG"
run "cat > \"$SSH_CUSTOM_CONFIG\" << EOF
# Servo hardening configuration
Port $SSH_PORT
PermitRootLogin $PERMIT_ROOT_LOGIN
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM no
EOF"

# Check if the main config includes the directory
if ! grep -q "^Include $SSH_CONFIG_DIR/\*.conf" "$SSH_CONFIG"; then
    warning "The main SSH config doesn't seem to include files from $SSH_CONFIG_DIR"
    info "Adding Include directive to $SSH_CONFIG"
    run "cp \"$SSH_CONFIG\" \"$SSH_CONFIG.bak\""
    run "sed -i '1i\Include $SSH_CONFIG_DIR/*.conf' $SSH_CONFIG"
    run "sed -i '1i\# Following line added by servo.sh' $SSH_CONFIG"
fi

success "SSH configuration hardened"


restart_ssh() {
    # Check if ssh.socket exists and is enabled (socket activation)
    if systemctl is-enabled ssh.socket &>/dev/null; then
        info "Socket activation detected, restarting ssh.socket"
        systemctl daemon-reload
        systemctl restart ssh.socket
    # Check if service exists with either name
    elif systemctl list-units --type=service | grep -q "ssh.service"; then
        info "SSH service detected as ssh.service"
        systemctl restart ssh.service
    elif systemctl list-units --type=service | grep -q "sshd.service"; then
        info "SSH service detected as sshd.service"
        systemctl restart sshd.service
    else
        throw "Could not determine SSH service name"
        exit 1
    fi
}

info "Restarting SSH service"
restart_ssh
success "SSH service restarted"

warning "Make sure port $SSH_PORT is open on the server's firewall!"

# Step 4: Update and upgrade the system
section "Updating and upgrading the system"

run "apt update && apt upgrade -y"
success "System updated and upgraded"

# Step 5: Install essential packages
section "Installing essential packages"

info "Installing build-essential, git, ufw, fail2ban"

run "apt install -y build-essential git ufw fail2ban"
success "Essential packages installed"

# Step 6: Configure unattended upgrades
section "Configuring unattended upgrades (security patches only)"

run "apt install -y unattended-upgrades"

info "Backing up existing configuration files"
run "cp /etc/apt/apt.conf.d/20auto-upgrades /etc/apt/apt.conf.d/20auto-upgrades.bak 2>/dev/null || true"
run "cp /etc/apt/apt.conf.d/50unattended-upgrades /etc/apt/apt.conf.d/50unattended-upgrades.bak 2>/dev/null || true"

info "Writing /etc/apt/apt.conf.d/20auto-upgrades"
run "cat > /etc/apt/apt.conf.d/20auto-upgrades << EOF
APT::Periodic::Update-Package-Lists \"1\";
APT::Periodic::Unattended-Upgrade \"1\";
APT::Periodic::AutocleanInterval \"7\";
EOF"

info "Writing /etc/apt/apt.conf.d/50unattended-upgrades"
run "cat > /etc/apt/apt.conf.d/50unattended-upgrades << EOF
Unattended-Upgrade::Allowed-Origins {
\"\\\${distro_id}:\\\${distro_codename}-security\";
\"\\\${distro_id}ESMApps:\\\${distro_codename}-apps-security\";
\"\\\${distro_id}ESM:\\\${distro_codename}-infra-security\";
};
Unattended-Upgrade::Remove-Unused-Kernel-Packages \"true\";
Unattended-Upgrade::Remove-Unused-Dependencies \"true\";
Unattended-Upgrade::Automatic-Reboot \"false\";
EOF"

info "Enabling and restarting the service"
run "systemctl enable --now unattended-upgrades"

success "Unattended upgrades configured and enabled"

# Step 7: Configure fail2ban
section "Configuring fail2ban"

info "Creating the local jail configuration file"
run "touch /etc/fail2ban/jail.local"

# Update fail2ban configuration
run "cat > /etc/fail2ban/jail.local << EOF
[sshd]
enabled = true
mode = aggressive
EOF"

run "systemctl enable fail2ban"
run "systemctl restart fail2ban"
success "fail2ban configured and started"

# Step 8: Configure firewall
section "Configuring firewall (ufw)"

info "Resetting UFW default policies"

# Reset UFW rules
run "ufw --force reset"

# Set default policies
run "ufw default deny incoming"
run "ufw default allow outgoing"

info "Allowing SSH on port $SSH_PORT"

# Allow SSH
run "ufw allow \"$SSH_PORT/tcp\""

info "Opening ports 80 and 443"
run "ufw allow http"
run "ufw allow https"

info "Enabling UFW"
run "ufw --force enable"

# Show UFW status
ufw status verbose

success "UFW enabled"

# Summary and next steps
section "Summary"

pen green "Server hardening completed!"
line
info "The following security measures have been applied:"
pen "  - Created non-root user: $NEW_USER"
pen "  - SSH hardened (root login disabled, password auth disabled)"
pen "  - Custom SSH port: $SSH_PORT"
pen "  - System updated and essential packages installed"
pen "  - fail2ban configured for protection against brute force attacks"
pen "  - UFW firewall enabled and configured"
line

run ---out IP "curl ipinfo.io/ip"

warning "IMPORTANT: Before leaving this session you should first check that you can login"
warning "correctly with your new user. To manually test your SSH connection (from another terminal):"
pen "  ssh -p $SSH_PORT $NEW_USER@$IP"

# Audit
section "Audit"

info "You can run a quick security audit online on https://auditvps.com/, or locally by running"
info "'curl -s https://auditvps.com/audit.sh | bash' (you might have to 'apt install -y jq' first)."

line
pen magenta "============================================"
pen magenta "=    Thank you for using Servo script!     ="
pen magenta "============================================"
line
