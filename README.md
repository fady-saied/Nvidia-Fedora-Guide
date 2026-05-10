# NVIDIA on Fedora desktops

This guide will help you to install the proprietary NVIDIA drivers replacing the open source Nouveau drivers for both Fedora Workstation (Gnome, KDE and Cosmic spins) and Atomic desktops (Silverblue, Kinoite and Sway).


## What you need to know

The hardest part is getting the drivers to load with Secure Boot. Secure Boot blocks the driver's modules from loading unless we sign them.

Run the following command in the terminal to check Secure Boot status:

```bash
mokutil --sb-state
```

If enabled, you will need to follow some extra (but simple) steps. Don't disable Secure Boot if it was already enabled to improve your security. However, if you followed the steps and the driver modules failed to load, disable secure boot to fix the problem.

> [!NOTE]
> If you are using a hybrid laptop and connect an external monitor to the Nvidia GPU (HDMI), you will experience severe lag on the external display with the Nvidia drivers. You can either use the MUX switch to disable the iGPU or follow the following guide for a workaround after you install the drivers: https://crstl.me/blog/solving-low-fps-on-external-monitor-linux/

All you need to do is follow the guide and *hopefully* everything works smoothly! 

Please check if your Desktop Environment is compatible with the Nvidia drivers since there are more steps needed for some that may not be listed here. This is not a problem for KDE, Gnome, Sway and Cosmic but may be a problem for some of the spins. If you find any, please create an issue with the details.

You will mostly need to just copy and paste commands into the terminal. But, make sure to read everything carefully!

If you find any mistake or want to add some missing information, create a pull request with the changes or just create an issue. All help is appreciated!

At the end you will find a quick survey, taking it will help me maintain this guide especially if you faced a failure in the installation process. Thanks!

Consult the official documentation (Sources listed below) if more information is needed.


## Identify your system

This guide is made STRICTLY for Fedora Workstation and all it's spins (KDE and Cosmic) and Fedora Atomic (Silverblue, Kinoite and Sway).

> [!NOTE]
> For users with encrypted drives using LUKS, you will follow some extra steps after installation to avoid issues after rebooting (steps listed below appropriately).

> [!NOTE]
> **Sway Users:** For users of Sway and Sway Atomic (Sericea), you will need to open `/etc/sway/environment` and uncomment or add the following two lines:
>
> ```env
> SWAY_EXTRA_ARGS="$SWAY_EXTRA_ARGS --unsupported-gpu"
> WLR_NO_HARDWARE_CURSORS=1
> ```

Please scroll down to the relevant section related to your Fedora installation or choose from table of contents:

## Table of Contents

1.  [Fedora Workstation & KDE (with spins)](#installing-nvidia-drivers-on-fedora-workstation-and-its-spins)

2.  [Fedora Atomic (Silverblue, Kinoite and Sway)](#installing-nvidia-drivers-on-fedora-atomic)

3.  [LUKS Encrypted Drives](#encrypted-drives)
   
4.  [Common Problems](#common-problems)

5.  [Sources](#sources)
---

# Installing NVIDIA drivers on Fedora Workstation and it's spins

## 0. Before we get started!

If you have Secure Boot disabled, Skip step 2.
Otherwise, it's still easy to get the drivers with Secure Boot. 

> [!NOTE]
> If your drive is encrypted with LUKS. You will need to follow some extra steps before final reboot to avoid a black screen on startup.

> [!NOTE]
> If you have an older 600/700 series GPU (Kepler, Quadro), you will need to use the X11 session alongside the older 470 Nvidia driver (Setup covered in steps). Meaning Gnome 49 or later will NOT be an option and you must use KDE or any other Window Manager supporting X11. Please verify that 

## 1. Preparation

* **Update your system:** Ensure your installation is up-to-date:

```bash
sudo dnf update
```

* **Enable RPM Fusion:** This provides access to the NVIDIA drivers.

```bash
sudo dnf install https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
```

## 2. Secure Boot key enrollment
> [!TIP]
> If you have Secure Boot disabled, Skip this step. Proceed directly to Step 3.

* **Install these packages:**

```bash
sudo dnf install kmodtool akmods mokutil openssl
```

* **Generate a default key:**

> [!NOTE]
> If you get the message: "WARNING: EXISTING KEY PAIR.", add `--force` to the end of the command and run it again.

```bash
sudo kmodgenca -a
```

* **Enroll the key in MOK:**

After running the command, you will be asked for a password. Create a short password (ex: 0000) and remember it for a later step!

```bash
sudo mokutil --import /etc/pki/akmods/certs/public_key.der
```

* Reboot to enroll

> [!WARNING]
> The keyboard is mapped to QWERTY in the MOK screen, regardless of your system layout. Use a simple password like 0000.

On the next boot MOK Management is launched, press enter then you have to choose "Enroll MOK" (MOK management is a blue screen on startup)

Choose "Continue" to enroll the key.

Enroll by selecting "Yes".

You will need to enter the password you created earlier. After that select reboot.

```bash
systemctl reboot
```

## 3. Installing the drivers

You will need to identify your GPU to choose which drivers to install. Run this command to find your GPU if you need to confirm:

```bash
lspci | grep -iE 'VGA|3D|nvidia'
```
Accordingly, choose which driver to download below:

## For NVIDIA GPUs from 2017 or later (Current GeForce/Quadro/Tesla):
>[!NOTE]
>Since driver v590 and later on Fedora 44, support for GTX 800/900/10 were dropped and need to use the v580 drivers listed below this one. Please confirm compatibility.

```bash
sudo dnf install cuda-drivers
```

## For Legacy GTX 800/900/10 (After Fedora 44)
>[!NOTE]
>This driver is suitable for any NVIDIA Maxwell and Pascal GPU found between 2014 and 2017 

```bash
sudo dnf install xorg-x11-drv-nvidia-580xx akmod-nvidia-580xx
sudo dnf install xorg-x11-drv-nvidia-580xx-cuda # Required for nvidia-smi and CUDA support
```

## For legacy NVIDIA GPUs like GeForce 600/700 series (Kepler, Quadro) [DRIVER v470]:
>[!NOTE]
>Any GPUs starting with 'K' are Kepler GPUs and require this legacy driver.
>Some GTX 700 Series GPUs like GTX 780 Ti, 780, 770, 760 are based on the Older Kepler architecture, therefore require this legacy driver
>All GTX 600 series GPU require this legacy driver


```bash
sudo dnf install xorg-x11-drv-nvidia-470xx akmod-nvidia-470xx
sudo dnf install xorg-x11-drv-nvidia-470xx-cuda # Required for nvidia-smi and CUDA support
```

Additionally, for this driver (DRIVER v470 ONLY) you need to install X11 session on KDE:

KDE:
```bash
sudo dnf install plasma-workspace-x11 xorg-x11-drivers xorg-x11-xinit
```
> [!IMPORTANT]
> After the final reboot, make sure to use the **X11 session** when logging into KDE (Legacy driver only!) (found bottom left of the login screen).

## For even older NVIDIA GPUs before 2012 like 400/500 series (Fermi) [DRIVER v390]:
>[!WARNING]
>It should be noted that v390 is increasingly difficult to run with Fedora 40/41, NVIDIA has abandoned this driver in 2022, and RPM Fusion Maintainers are the ones maintaining it. Which makes it experimental and end-of-line.
>The Driver also has no support for Wayland, therefore an X11 compatible desktop is required.

> [!NOTE]
>All 400/500 series are based on the Fermi Architecture and use driver v390.
>Some Non-Standard GPUs from 600/700 series also use the Fermi Architecture.
>Please make sure to know about your GPU architecture, and if it uses Fermi.

```bash
sudo dnf install xorg-x11-drv-nvidia-390xx akmod-nvidia-390xx
sudo dnf install xorg-x11-drv-nvidia-390xx-cuda # Required for nvidia-smi and CUDA support
```

## 4. Verify Installation & Reboot

Now that we installed the driver, confirm that it's built by running:

```bash
modinfo -F version nvidia
```
In the output you should see the driver version number (e.g., `570.xx.xx`).

> [!CAUTION]
> **Do NOT reboot if you see an error.** If the command returns "modinfo: ERROR: Module nvidia not found", the kernel module is still building. This takes **5-10 minutes** depending on your system. Wait and retry the command until it succeeds before rebooting.
>
> **PLEASE NOTE!!** There are reports of the command not outputting success even after a lot of time. If that happens attempt restarting anyways.

> [!IMPORTANT]
> **LUKS Encrypted Drives:** If your drive is encrypted, you **MUST** complete the steps in [LUKS Encrypted Drives](#encrypted-drives) **BEFORE** rebooting, or you may get a black screen on startup.

* **Reboot**

Finally, reboot your system.

If you see "Nvidia modules failed to load" on startup, then the secure boot step was unsuccessful. You can try and disable secure boot to solve this problem.

After booting, run the following in the terminal to check your GPU's status:

```bash
nvidia-smi
```
NOTE: If this command fails with \"command not found\", you need to install the CUDA package: `sudo dnf install xorg-x11-drv-nvidia-cuda`

**Please take this quick survey to help me know if the guide worked or didn't work for you:** https://forms.gle/J44beNvnPh5x9fHs5

**If you have any problems, check the Common Problems section or create an issue in this repository and I will try to help.**


------------------------------------------------------------------------------------------


# Installing NVIDIA Drivers on Fedora Atomic

## 0. Before we get started!

Due to Fedora Atomic's immutable nature, we will need to use a "trick" to get the drivers correctly working with Secure Boot. 
Thanks to CheariX for providing the fix to everyone: https://github.com/CheariX/silverblue-akmods-keys

> [!TIP]
> With Atomic, you can **revert easily** if anything gets messed up! See the [official Fedora documentation](https://docs.fedoraproject.org/en-US/fedora-silverblue/updates-upgrades-rollbacks/) to learn how.

> [!NOTE]
> Sway users need to perform two extra steps, one is listed in "Identify your system" above and the other is below when adding the kernel arguments. [Notes provided by shdwpunk].

> [!NOTE]
> If your drive is encrypted with LUKS. You will need to follow some extra steps before final reboot to avoid a black screen on startup.

## 1. Preparation

* **Update your system:** Ensure your Silverblue installation is up-to-date:

```bash
sudo rpm-ostree update
```

* **Install necessary packages:**

```bash
sudo rpm-ostree install rpmdevtools akmods
```

* **Enable RPM Fusion:** This provides access to the NVIDIA drivers.

```bash
sudo rpm-ostree install https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
```

* **Reboot:** Reboot to apply the RPM Fusion changes.

```bash
systemctl reboot
```

## 2. Set up the Secure Boot key (Secure Boot enabled only!)

* **Generate a Machine Owner Key (MOK):**

> [!NOTE]
> If you get the message: "WARNING: EXISTING KEY PAIR.", add `--force` to the end of the command and run it again.
```bash
sudo kmodgenca -a
```

* **Import the key:**

After running the command, you will be asked for a password. Create a short password (ex: 0000) and remember it for a later step!

```bash
sudo mokutil --import /etc/pki/akmods/certs/public_key.der
```

## 3. Install `akmods-keys` (Secure Boot enabled only!)

* **Clone the repository:**

```bash
git clone https://github.com/CheariX/silverblue-akmods-keys
cd silverblue-akmods-keys
```

* **Build and install:**

```bash
sudo bash setup.sh
sudo rpm-ostree install akmods-keys-*.rpm
```

## 4. Install NVIDIA Drivers (For current GeForce, Tesla and Quadro GPUs)

Install the driver and Cuda. Last command will blacklist the Nouveau driver and nova_core. For Sway users, You will need to also add an additional kernel arg listed below: 

* **Install the Nvidia driver with Cuda for Kinoite and Silverblue**

```bash
sudo rpm-ostree install akmod-nvidia xorg-x11-drv-nvidia xorg-x11-drv-nvidia-cuda
sudo rpm-ostree kargs --append=rd.driver.blacklist=nouveau,nova_core --append=modprobe.blacklist=nouveau,nova_core --append=nvidia-drm.modeset=1 
```

* **Install the Nvidia driver with Cuda for Sway Atomic**

```bash
sudo rpm-ostree install akmod-nvidia xorg-x11-drv-nvidia xorg-x11-drv-nvidia-cuda
sudo rpm-ostree kargs --append=rd.driver.blacklist=nouveau,nova_core --append=modprobe.blacklist=nouveau,nova_core --append=nvidia-drm.modeset=1 --append=initcall_blacklist=simpledrm_platform_driver_init
```

> [!IMPORTANT]
> **LUKS Encrypted Drives:** If your drive is encrypted, you **MUST** complete the steps in [LUKS Encrypted Drives](#encrypted-drives) **BEFORE** rebooting, or you may get a black screen on startup.

## 5. Reboot and Enroll the Key (Secure Boot only)

> [!WARNING]
> The keyboard is mapped to QWERTY in the MOK screen, regardless of your system layout.

* 🔄 **Reboot:**

For Secure Boot enabled systems, on the next boot MOK Management is launched press Enter then:

1. Choose "Enroll MOK"
2. Choose "Continue" to enroll the key
3. Confirm enrollment by selecting "Yes"
4. Enter the password you created earlier.  After that select reboot.

For Secure Boot disabled: You will not see a MOK enrollment screen - simply restart.

```bash
systemctl reboot
```

## 6. Verify Installation

Now that we installed the driver, confirm that it's built by running:

```bash
modinfo -F version nvidia
```
In the output you should see the driver version number.

> [!NOTE]
> If you see "Nvidia modules failed to load" on startup, then the secure boot step was unsuccessful. You can try and disable secure boot to solve this problem.

After booting, run the following in the terminal to check your GPU's status:

```bash
nvidia-smi
```
> [!NOTE]
> If it failed then you didn't install Nvidia Cuda from the steps above.

**If you have any problems, check the Common Problems section or create an issue in this repository and I will try to help.**

**Please take this quick survey to help me know if the guide worked or didn't work for you:** https://forms.gle/J44beNvnPh5x9fHs5

## Important Note (Atomic)

> [!TIP]
> **RPM Fusion Unlock:** Enabling the RPM Fusion repo alone will enable it in a "fixed" state. After a major Fedora update (42 → 43), the repos won't be updated! Run the command below to "unlock" them (recommended).

```bash
sudo rpm-ostree update \
    --uninstall rpmfusion-free-release \
    --uninstall rpmfusion-nonfree-release \
    --install rpmfusion-free-release \
    --install rpmfusion-nonfree-release
```

After that, reboot!

```bash
reboot
```

For more information, see the [official documentation](https://docs.fedoraproject.org/en-US/fedora-silverblue/tips-and-tricks/#_enabling_rpm_fusion_repos).

# Encrypted Drives

## LUKS-Encrypted Drives

If your drive is encrypted with LUKS, perform these steps before rebooting to ensure the password prompt appears correctly.

### Step 1: Add the Plymouth Kernel Argument

Run the following to tell Plymouth to use a basic display driver for the boot screen:

```bash
sudo grubby --update-kernel=ALL --args='plymouth.use-simpledrm=1'
```

### Step 2: Configure Driver Loading (Fix Black Screen)

This ensures the Nvidia driver is available early enough to show the LUKS prompt, while preventing integrated graphics from causing conflicts.

Force-load Nvidia:

```Bash
printf '%s\n' 'force_drivers+=" nvidia nvidia_modeset nvidia_uvm nvidia_drm "' | sudo tee /etc/dracut.conf.d/nvidia.conf
```

### Step 3: iGPU Only (Optional): If you have a CPU with integrated graphics and are on Desktop, prevent it from "stealing" the display before Nvidia takes over:

>[!CAUTION]
>**Laptop Users:** **SKIP THIS STEP.** Most laptops route their internal screen through the integrated Intel or AMD graphics (Optimus/Hybrid). If you omit the iGPU driver, your screen will remain black because the >NVIDIA card has no "path" to the display.
>
>**Desktop Users:** If your monitor is plugged directly into the NVIDIA GPU and you want to prevent the iGPU from interfering, you may run:

```bash
echo 'omit_drivers+=" amdgpu "' | sudo tee /etc/dracut.conf.d/omit-amdgpu.conf
```

> [!NOTE]
> Intel iGPU users experiencing the same issue can substitute `amdgpu` with `i915`.

### Step 4: Apply Changes & Rebuild Initramfs
You **must** run the command below that matches your system type to apply the new settings into your boot image.

*   **For Atomic Systems (Silverblue, Cosmic, Kinoite):**
    This enables local boot-image builds (necessary for the drivers to be detected).
    
    ```bash
    sudo rpm-ostree initramfs --enable
    ```
*   **For Workstation / DNF-based Systems:**
    This manually regenerates your current boot image.
    
    ```bash
    sudo dracut --force
    ```

> [!NOTE]
> **Atomic Users:** After enabling this, your next reboot and all future system updates will take a few minutes longer as the system builds a custom boot image tailored to your hardware.

#### Step 5: Reboot
Once the command in Step 4 finishes, you can safely reboot. If Secure Boot is enabled, follow the MOK enrollment steps upon restarting.

**If you faced issues, please create an issue and I will try to help.**

**Please take this quick survey:** https://forms.gle/J44beNvnPh5x9fHs5

# Common Problems

## NVIDIA-SMI has failed because it couldn’t communicate with the NVIDIA driver. Make sure the latest NVIDIA driver is installed and running

If you get that message when running nvidia-smi, it could be Secure Boot preventing the modules from loading. Try re-doing the Secure Boot steps again or preferably disable Secure Boot and see if it's fixed.

This could also be caused by a version mismatch between the Cuda and main driver packages. If so the main drivers could actually be running and working properly but nvidia-smi can't report it. You can check your system information in the settings and check the reported GPUs. I don't have enough information on why this sometimes happens but it was reported multiple times in form submissions and can be fixed by manually specifying the versions when installing the packages.

## Nvidia drivers failing due to package version mismatch (Black screen on startup, Nvidia SMI failure and no hardware acceleration)

Check issue 18: https://github.com/Comprehensive-Wall28/Nvidia-Fedora-Guide/issues/18

## Nvidia modules failed to load (on startup)

If you got this message after installation, the Secure Boot enrollment was not done properly. Please retry the Secure Boot steps mentioned for your Fedora installation or disable Secure Boot.

> [!TIP]
> No need to reinstall the drivers themselves!

## Black screen after booting up

This means the installed drivers were the incorrect version for your GPU (was Kepler but installed GeForce instead, or vice versa).

> [!CAUTION]
> If this happens, boot into TTY by rebooting and pressing `CTRL+ALT+F2` repeatedly, then remove the NVIDIA packages manually:

For workstation and it's spins:

```bash
sudo dnf remove "*nvidia*" "*akmod-nvidia*" "*xorg-x11-drv-nvidia*"

sudo dracut -f --regenerate-all
```

For Atomic desktops:

```bash
rpm-ostree override reset "*nvidia*"
```

> [!CAUTION]
> **LUKS users:** This can also happen if your drive was encrypted. To recover, follow these steps:

1. Reboot the computer.
2. When the GRUB menu appears, press `e` to edit.
3. Find the line that starts with `linux`.
4. Remove `rhgb` and `quiet` if present, go to the very end of that line, add a space, then add `3`.
5. Press `Ctrl+X` to boot. This gets you to a text-based login where you can enter the LUKS password, then your Fedora username and password.

After that, follow the steps in [LUKS Encrypted Drives](#encrypted-drives).

## For users running GTX 800/900/10 and updated to Fedora 44, you need to downgrade your driver version to 580 as 590 dropped support

```bash
sudo dnf update
sudo dnf remove xorg-x11-drv-nvidia\* akmod-nvidia\*
sudo dnf install akmod-nvidia-580xx xorg-x11-drv-nvidia-580xx
sudo dnf install xorg-x11-drv-nvidia-580xx-cuda
```

## For Atomic users who updated to kernel 6.15 and had the drivers fail

> [!WARNING]
> If you installed the drivers and updated to kernel 6.15, you need to add `nova_core` to the blacklist alongside `nouveau`. Ignore this if it's working properly—this is only for those who followed the steps before `nova_core` was added to the commands.

If you ran the older command, run:

```bash
sudo rpm-ostree kargs --append=rd.driver.blacklist=nouveau,nova_core --append=modprobe.blacklist=nouveau,nova_core
```

This should fix the issue with the drivers.

# Contributers

* shdwpunk [Provided additional Sway setup commands]
* Poid-bit [Provided additional steps for encrypted drives]
* Sarthak Sidhant [Provided additional information for older GPU drivers]
* kw6423 [Details and fix for packages version mismatch from updates]

# Sources
Configuring RPMFusion:
* https://rpmfusion.org/Configuration
  
RPMFusion Nvidia Documentation:
* https://rpmfusion.org/Howto/NVIDIA

RPMFusion Secureboot Documentation:
* https://rpmfusion.org/Howto/Secure%20Boot

Nvidia drivers for Sway Atomic
* https://docs.fedoraproject.org/en-US/fedora-sericea/troubleshooting/#_using_nvidia_drivers




