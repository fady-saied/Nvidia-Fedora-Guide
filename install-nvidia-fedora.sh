#!/usr/bin/env bash
set -Eeuo pipefail

STATE_DIR="${HOME}/.cache/fedora-atomic-nvidia-installer"
PHASE_FILE="${STATE_DIR}/phase"
CONFIG_FILE="${STATE_DIR}/config"
KEYS_REPO_DIR="${STATE_DIR}/silverblue-akmods-keys"

mkdir -p "$STATE_DIR"

log() {
    printf '\n==> %s\n' "$*"
}

warn() {
    printf '\nWARNING: %s\n' "$*" >&2
}

die() {
    printf '\nERROR: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

sudo_available() {
    sudo -n true >/dev/null 2>&1 || sudo -v
}

get_phase() {
    if [[ -f "$PHASE_FILE" ]]; then
        cat "$PHASE_FILE"
    else
        echo "prepare"
    fi
}

set_phase() {
    printf '%s\n' "$1" > "$PHASE_FILE"
}

prompt_reboot() {
    local message="${1:-Reboot is required to proceed.}"
    log "$message"
    read -rp "Do you want to reboot now? [Y/n]: " choice
    case "${choice,,}" in
        n|no)
            log "Reboot aborted. Please reboot manually, then rerun this script."
            exit 0
            ;;
        *)
            log "Rebooting system..."
            systemctl reboot
            ;;
    esac
}

detect_system() {
    [[ -f /etc/os-release ]] || die "/etc/os-release not found."
    source /etc/os-release

    [[ "${ID:-}" == "fedora" ]] || die "This script requires Fedora Atomic."
    command -v rpm-ostree >/dev/null 2>&1 || die "rpm-ostree was not found."

    if [[ ! -e /run/ostree-booted ]]; then
        die "This does not appear to be an active Fedora Atomic/rpm-ostree deployment."
    fi

    FEDORA_VERSION="$(rpm -E %fedora)"
    [[ "$FEDORA_VERSION" =~ ^[0-9]+$ ]] || die "Could not determine Fedora release version."

    FEDORA_VARIANT="${VARIANT_ID:-${VARIANT:-unknown}}"
    log "Detected Fedora Atomic Variant: ${FEDORA_VARIANT} (Release ${FEDORA_VERSION})"
}

is_sway_variant() {
    [[ "${FEDORA_VARIANT,,}" =~ (sway|sericea) ]]
}

detect_secure_boot() {
    SECURE_BOOT="disabled"
    if command -v mokutil >/dev/null 2>&1; then
        if mokutil --sb-state 2>/dev/null | grep -qi enabled; then
            SECURE_BOOT="enabled"
        fi
    fi
    log "Secure Boot status: ${SECURE_BOOT}"
}

detect_luks() {
    HAS_LUKS="no"
    if lsblk -rno FSTYPE 2>/dev/null | grep -Eiq '^(crypto_LUKS|luks)$'; then
        HAS_LUKS="yes"
    fi
    log "LUKS encryption detected: ${HAS_LUKS}"
}

detect_laptop() {
    IS_LAPTOP="no"
    local chassis
    chassis="$(hostnamectl chassis 2>/dev/null || true)"
    case "${chassis,,}" in
        laptop|notebook|convertible|tablet)
            IS_LAPTOP="yes"
            ;;
    esac
    log "Laptop hardware: ${IS_LAPTOP}"
}

detect_cpu() {
    CPU_VENDOR="unknown"
    IGPU_DRIVER=""

    if grep -qi 'GenuineIntel' /proc/cpuinfo; then
        CPU_VENDOR="Intel"
    elif grep -qi 'AuthenticAMD' /proc/cpuinfo; then
        CPU_VENDOR="AMD"
    fi

    # Detect secondary display controllers (VGA = 0300, Display = 0380)
    local secondary_vga
    secondary_vga="$(lspci -nn -d 8086::0300 2>/dev/null; lspci -nn -d 8086::0380 2>/dev/null || true)"
    if [[ -n "$secondary_vga" ]]; then
        # Check active kernel driver or default to platform standards
        if lsmod | grep -qw "xe"; then
            IGPU_DRIVER="xe"
        else
            IGPU_DRIVER="i915"
        fi
    fi

    local secondary_amd
    secondary_amd="$(lspci -nn -d 1002::0300 2>/dev/null; lspci -nn -d 1002::0380 2>/dev/null || true)"
    if [[ -n "$secondary_amd" ]]; then
        IGPU_DRIVER="amdgpu"
    fi

    log "CPU vendor: ${CPU_VENDOR} (Detected iGPU driver: ${IGPU_DRIVER:-None})"
}

select_gpu_package() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        if [[ -n "${NVIDIA_PACKAGE_BRANCH:-}" ]]; then
            return 0
        fi
    fi

    require_command lspci
    local nvidia_lines
    nvidia_lines="$(lspci -nn 2>/dev/null | grep -iE 'NVIDIA|VGA compatible controller|3D controller' | grep -i 'NVIDIA' || true)"
    [[ -n "$nvidia_lines" ]] || die "No NVIDIA GPU detected via lspci."

    local detected_gpu
    detected_gpu="$(printf '%s\n' "$nvidia_lines" | sed -E 's/^.*NVIDIA Corporation ([^[]+).*/\1/' | head -n1)"
    log "Detected GPU hardware: ${detected_gpu}"

    echo ""
    echo "Select your NVIDIA GPU architecture according to the README specifications:"
    echo "1) Current GPUs: 2017 or later (RTX series 2xxx/3xxx/4xxx/5xxx, modern GTX)"
    echo "2) Maxwell or Pascal: GTX 800/900/10 series (Uses 580xx branch on Fedora 44+)"
    echo "3) Kepler: GeForce 600/700 series, Quadro K-series (v470xx; requires X11 session)"
    echo "4) Fermi: GeForce 400/500 series (v390xx; experimental legacy driver)"
    echo ""

    local choice
    while true; do
        read -rp "Enter choice [1-4]: " choice
        case "$choice" in
            1)
                NVIDIA_PACKAGE_BRANCH="current"
                break
                ;;
            2)
                if (( FEDORA_VERSION >= 44 )); then
                    NVIDIA_PACKAGE_BRANCH="580xx"
                else
                    NVIDIA_PACKAGE_BRANCH="current"
                fi
                break
                ;;
            3)
                NVIDIA_PACKAGE_BRANCH="470xx"
                warn "Kepler GPUs require an X11 desktop session. Wayland environments are unsupported."
                break
                ;;
            4)
                NVIDIA_PACKAGE_BRANCH="390xx"
                warn "Fermi driver (v390) is end-of-life and experimental."
                break
                ;;
            *)
                echo "Invalid selection. Enter 1, 2, 3, or 4."
                ;;
        esac
    done

    printf 'NVIDIA_PACKAGE_BRANCH="%s"\n' "$NVIDIA_PACKAGE_BRANCH" > "$CONFIG_FILE"
    log "Configured package branch: ${NVIDIA_PACKAGE_BRANCH}"
}

phase_prepare() {
    log "Phase 1: Updating system and staging RPM Fusion repositories."

    sudo rpm-ostree update

    local base_pkgs=("rpmdevtools" "akmods")
    if [[ "$SECURE_BOOT" == "enabled" ]]; then
        base_pkgs+=("git")
    fi

    sudo rpm-ostree install "${base_pkgs[@]}" \
        "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VERSION}.noarch.rpm" \
        "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VERSION}.noarch.rpm"

    set_phase "install-driver"
    prompt_reboot "RPM Fusion staging deployment completed."
}

setup_secure_boot_keys() {
    [[ "$SECURE_BOOT" == "enabled" ]] || return 0

    log "Configuring Machine Owner Key (MOK) for Secure Boot."

    require_command mokutil

    if ! sudo kmodgenca -a; then
        warn "Existing key pair warning detected. Re-running with --force."
        sudo kmodgenca -a --force
    fi

    echo ""
    warn "A temporary password is required to import the key into UEFI MOK."
    warn "Use a simple password (e.g. 0000). On the next boot, the blue MOK screen uses a QWERTY layout."
    echo ""
    sudo mokutil --import /etc/pki/akmods/certs/public_key.der

    log "Building and layering silverblue-akmods-keys."
    rm -rf "$KEYS_REPO_DIR"
    git clone --depth=1 https://github.com/CheariX/silverblue-akmods-keys.git "$KEYS_REPO_DIR"

    pushd "$KEYS_REPO_DIR" >/dev/null
    sudo bash setup.sh

    shopt -s nullglob
    local key_rpms=(akmods-keys-*.rpm)
    shopt -u nullglob

    ((${#key_rpms[@]} > 0)) || die "silverblue-akmods-keys failed to produce an RPM package."

    sudo rpm-ostree install "${key_rpms[@]}"
    popd >/dev/null
}

install_nvidia_packages() {
    log "Layering NVIDIA driver packages (${NVIDIA_PACKAGE_BRANCH})."
    log "Note: akmods kernel module compilation executes synchronously during this rpm-ostree transaction."

    case "$NVIDIA_PACKAGE_BRANCH" in
        current)
            sudo rpm-ostree install akmod-nvidia xorg-x11-drv-nvidia xorg-x11-drv-nvidia-cuda
            ;;
        580xx)
            sudo rpm-ostree install akmod-nvidia-580xx xorg-x11-drv-nvidia-580xx xorg-x11-drv-nvidia-580xx-cuda
            ;;
        470xx)
            sudo rpm-ostree install akmod-nvidia-470xx xorg-x11-drv-nvidia-470xx xorg-x11-drv-nvidia-470xx-cuda
            ;;
        390xx)
            sudo rpm-ostree install akmod-nvidia-390xx xorg-x11-drv-nvidia-390xx xorg-x11-drv-nvidia-390xx-cuda
            ;;
        *)
            die "Unknown package branch: $NVIDIA_PACKAGE_BRANCH"
            ;;
    esac
}

configure_kernel_arguments() {
    log "Configuring kernel boot arguments."

    local existing_kargs
    existing_kargs="$(rpm-ostree kargs 2>/dev/null || true)"

    local required_args=(
        "rd.driver.blacklist=nouveau,nova_core"
        "modprobe.blacklist=nouveau,nova_core"
        "nvidia-drm.modeset=1"
    )

    if is_sway_variant; then
        required_args+=("initcall_blacklist=simpledrm_platform_driver_init")
    fi

    if [[ "$HAS_LUKS" == "yes" ]]; then
        required_args+=("plymouth.use-simpledrm=1")
    fi

    local pending_args=()
    for arg in "${required_args[@]}"; do
        if ! grep -Fq -- "$arg" <<<"$existing_kargs"; then
            pending_args+=("--append=${arg}")
        fi
    done

    if ((${#pending_args[@]} > 0)); then
        sudo rpm-ostree kargs "${pending_args[@]}"
    else
        log "All designated kernel arguments are already active."
    fi
}

configure_sway_environment() {
    is_sway_variant || return 0

    log "Configuring Sway desktop environment variables."
    local sway_env="/etc/sway/environment"
    sudo mkdir -p "$(dirname "$sway_env")"

    if [[ ! -f "$sway_env" ]] || ! grep -qE '^[[:space:]]*SWAY_EXTRA_ARGS=.*--unsupported-gpu' "$sway_env"; then
        echo 'SWAY_EXTRA_ARGS="$SWAY_EXTRA_ARGS --unsupported-gpu"' | sudo tee -a "$sway_env" >/dev/null
    fi

    if [[ ! -f "$sway_env" ]] || ! grep -qE '^[[:space:]]*WLR_NO_HARDWARE_CURSORS=1' "$sway_env"; then
        echo "WLR_NO_HARDWARE_CURSORS=1" | sudo tee -a "$sway_env" >/dev/null
    fi
}

configure_luks_dracut() {
    [[ "$HAS_LUKS" == "yes" ]] || return 0

    log "Configuring Dracut and initramfs for LUKS disk encryption."
    printf '%s\n' 'force_drivers+=" nvidia nvidia_modeset nvidia_uvm nvidia_drm "' | \
        sudo tee /etc/dracut.conf.d/nvidia.conf >/dev/null

    detect_laptop
    detect_cpu

    if [[ "$IS_LAPTOP" == "no" && -n "$IGPU_DRIVER" ]]; then
        echo ""
        echo "Desktop installation with an integrated ${CPU_VENDOR} GPU detected."
        echo "If your monitor is plugged directly into the NVIDIA discrete GPU, you can"
        echo "prevent the iGPU (${IGPU_DRIVER}) from interfering with the display during boot."
        read -rp "Omit ${IGPU_DRIVER} from initramfs? [y/N]: " igpu_choice
        case "${igpu_choice,,}" in
            y|yes)
                printf '%s\n' "omit_drivers+=\" ${IGPU_DRIVER} \"" | \
                    sudo tee "/etc/dracut.conf.d/omit-${IGPU_DRIVER}.conf" >/dev/null
                log "Configured omission of ${IGPU_DRIVER} in initramfs."
                ;;
            *)
                log "Retaining ${IGPU_DRIVER} in initramfs."
                ;;
        esac
    fi

    log "Enabling client-side initramfs regeneration."
    sudo rpm-ostree initramfs --enable
}

unlock_rpmfusion() {
    log "Unlocking RPM Fusion repositories for automatic future major release upgrades."
    sudo rpm-ostree update \
        --uninstall rpmfusion-free-release \
        --uninstall rpmfusion-nonfree-release \
        --install rpmfusion-free-release \
        --install rpmfusion-nonfree-release
}

phase_install_driver() {
    select_gpu_package
    setup_secure_boot_keys
    install_nvidia_packages
    configure_kernel_arguments
    configure_sway_environment
    configure_luks_dracut
    unlock_rpmfusion

    set_phase "verify"

    if [[ "$SECURE_BOOT" == "enabled" ]]; then
        echo ""
        log "SECURE BOOT MOK ENROLLMENT REQUIRED UPON REBOOT:"
        echo "1. The system will start into the blue MOK Management screen."
        echo "2. Press Enter, then select 'Enroll MOK'."
        echo "3. Select 'Continue', then choose 'Yes' to confirm enrollment."
        echo "4. Enter the password configured during this run, then select 'Reboot'."
        echo ""
    fi

    prompt_reboot "Driver deployment staged."
}

phase_verify() {
    log "Phase 3: Verifying NVIDIA kernel module and driver status."

    if ! grep -qw '^nvidia' /proc/modules; then
        if [[ "$SECURE_BOOT" == "enabled" ]]; then
            warn "NVIDIA kernel module is present on disk but not loaded by the kernel."
            warn "UEFI Secure Boot rejected the signature or MOK enrollment was not completed."
            die "MOK enrollment failed. Boot into UEFI MOK Manager and enroll the key."
        else
            die "NVIDIA kernel module failed to insert. Review 'journalctl -b -k -g nvidia'."
        fi
    fi

    local version
    version="$(cat /sys/module/nvidia/version 2>/dev/null || modinfo -F version nvidia 2>/dev/null || echo "Unknown")"
    log "NVIDIA module loaded successfully (Version: ${version})."

    if command -v nvidia-smi >/dev/null 2>&1; then
        nvidia-smi
    else
        warn "nvidia-smi utility was not found. Verify CUDA package installation."
    fi

    rm -f "$PHASE_FILE" "$CONFIG_FILE"
    log "NVIDIA installation and validation complete."
}

main() {
    require_command rpm
    require_command rpm-ostree
    require_command lsblk
    sudo_available

    detect_system
    detect_secure_boot
    detect_luks

    case "$(get_phase)" in
        prepare)
            phase_prepare
            ;;
        install-driver)
            phase_install_driver
            ;;
        verify)
            phase_verify
            ;;
        *)
            die "Unknown deployment phase: $(get_phase)"
            ;;
    esac
}

main "$@"
