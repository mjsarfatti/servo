#!/usr/bin/env bash
# shellcheck disable=all
#
# servo.sh - Setting up and hardening a fresh Ubuntu VPS
# Version: v0.0.1
#
# Copyright © 2025 Manuele Sarfatti
# Licensed under the MIT license
# See https://github.com/mjsarfatti/servo

readonly _q='?'
readonly _a='❯'
readonly _o='◌'
readonly _O='●'
readonly _mark='✓'
readonly _warn='!'
readonly _cross='✗'
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
    local old_settings=$-
    set +e # Don't immediately exit on error
    "${cmd[@]}" >"${stdout_file}" 2>"${stderr_file}"
    local exit_code=$?
    [[ -n "${outvar_name}" ]] && outvar="$(<"$stdout_file")"
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
    if [[ $old_settings == *e* ]]; then set -e; else set +e; fi
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
        sleep "$_frame_duration"
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
    local old_settings=$-
    set +e # Don't immediately exit on error
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
    if [[ $old_settings == *e* ]]; then set -e; else set +e; fi
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
    trap 'show_cursor' EXIT TERM
    trap "show_cursor; exit 130" INT # Exit on Ctrl+C
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
            ((++index))
        done
        read -s -r -n1 key
        if [[ $key == $'\e' ]]; then
            read -s -r -n2 -t 0.0001 escape
            key+="$escape"
        fi
        case "$key" in
        $'\e[A' | 'k')
            ((--current))
            [[ $current -lt 0 ]] && current=$((count - 1))
            ;;
        $'\e[B' | 'j')
            ((++current))
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
    trap "exit 130" INT # Exit on Ctrl+C
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
    trap "exit 130" INT # Exit on Ctrl+C
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
    trap "exit 130" INT # Exit on Ctrl+C
    read -r -p "$prompt" answer
    outvar="$answer"
}

set -eo pipefail
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
    [[ -n "${outvar_name}" ]] && outvar="$(<"$stdout_file")"
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
    set -e 
    return $exit_code
}
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
section() {
    line
    pen blue bold "▶ $1"
    pen blue bold "$(printf '–%.0s' {1..80})"
}
success() {
    check "$1"
}
info() {
    pen -n cyan "${_info:-ℹ} "
    pen "$1"
}
warning() {
    warn "$1"
}
if [[ "${EUID}" -ne 0 ]]; then
    throw "This script must be run as root"
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
    sleep 0.1
done
success "User '${NEW_USER}' created and added to sudo group"
section "Setting up SSH key authentication"
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
Port ${SSH_PORT}
PermitRootLogin ${PERMIT_ROOT_LOGIN}
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM no
EOF
if ! grep -q "^Include ${SSH_CONFIG_DIR}/\*.conf" "${SSH_CONFIG}"; then
    warning "The main SSH config doesn't seem to include files from '${SSH_CONFIG_DIR}'"
    info "Adding Include directive to '${SSH_CONFIG}'"
    run cp "${SSH_CONFIG}" "${SSH_CONFIG}.bak"
    run sed -i "'1i\Include ${SSH_CONFIG_DIR}/*.conf'" "${SSH_CONFIG}"
    run sed -i '1i\# Following line added by servo.sh' "${SSH_CONFIG}"
fi
success "SSH configuration hardened"
restart_ssh() {
    if run systemctl is-enabled ssh.socket; then
        info "Socket activation detected, restarting ssh.socket"
        run systemctl daemon-reload
        run systemctl restart ssh.socket
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
section "Updating and upgrading the system"
info "Updating packages and system"
spin "Updating the system..."
run apt update
check "System updated"
spin "Upgrading packages..."
run apt upgrade -y
check "Packages upgraded"
section "Installing essential packages"
info "Installing build-essential, git, ufw, fail2ban"
spin "Installing packages..."
run apt install -y build-essential git ufw fail2ban
check "Packages installed"
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
section "Configuring fail2ban"
info "Creating the local jail configuration file"
run touch /etc/fail2ban/jail.local
[[ ! $DRY_RUN == true ]] && cat >/etc/fail2ban/jail.local <<EOF
[sshd]
enabled = true
mode = aggressive
EOF
info "Enabling and restarting fail2ban"
run systemctl enable --now fail2ban
success "fail2ban configured and started"
section "Configuring firewall (ufw)"
info "Resetting UFW default policies"
run ufw --force reset
run ufw default deny incoming
run ufw default allow outgoing
info "Allowing SSH on port ${SSH_PORT}"
run ufw allow "${SSH_PORT}/tcp"
info "Opening ports 80 and 443"
run ufw allow http
run ufw allow https
info "Enabling UFW"
run ufw --force enable
success "UFW enabled"
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
