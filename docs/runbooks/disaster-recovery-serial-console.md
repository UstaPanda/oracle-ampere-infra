# Runbook: Out of Band Serial Console Recovery

**Languages:** [English](disaster-recovery-serial-console.md) | [Türkçe](disaster-recovery-serial-console.tr.md)

## 1. Background and Failure Analysis

While experimenting with local firewall rules on my OCI instance, I accidentally locked myself out of SSH. Because cloud images behave differently from desktop Linux installs, fixing this without deleting the VM took some deep bootloader troubleshooting. 

The lockout happened because of a frustrating cloud deadlock:
- Port 22 connections timed out because my local iptables rules dropped incoming TCP packets before they reached the SSH service.
- When I opened the OCI Serial Console, it gave me a standard login prompt (`ubuntu login:`). However, Ubuntu cloud images ship without a local password to force SSH key usage. Any guessed password failed.
- OCI Run Command could not rescue the host because the guest agent (`oracle-cloud-agent`) polls OCI via the link local metadata IP `169.254.169.254`. Because my firewall rules also blocked that metadata IP, commands stayed stuck on `ACCEPTED` and never ran.
- On the cloud networking side, a missing route rule directing `0.0.0.0/0` to an Internet Gateway can also drop external traffic.

This runbook documents how I recovered the host through the GRUB bootloader without reboot loops, data loss, or rebuilding the instance.

## 2. Recovery Procedure

### Step 1: Open the Cloud Shell Serial Connection

1. In the OCI Console, go to **Compute** > **Instances** and click the instance.
2. Scroll down to **Resources** on the bottom left and click **Console connection**.
3. Click **Launch Cloud Shell connection**.
4. Keep the Cloud Shell terminal open side by side with your browser window.

### Step 2: Interrupt the Boot Sequence

1. On the instance details page, click **Reboot** (use **Force Reboot** if the guest operating system ignores ACPI shutdown signals).
2. Click into the Cloud Shell terminal immediately.
3. Tap the **Esc** key repeatedly while the machine powers up.
4. If you hit the UEFI Boot Manager screen, select the primary Ubuntu drive, hit **Enter**, and immediately press the **Down Arrow** or **Esc** key to stop the GRUB countdown timer.

### Step 3: Boot to a Root Shell from GRUB

When you reach the `grub>` command prompt, enter these lines in order:

```text
set root=(hd0,gpt1)
linux /boot/vmlinuz root=/dev/sda1 rw init=/bin/bash
initrd /boot/initrd.img
boot
```

If `/boot/vmlinuz` is not found, remove the `/boot` prefix and use `/vmlinuz` and `/initrd.img`.

Here is how these boot arguments work together:
- `set root=(hd0,gpt1)` points GRUB to partition 1 on the primary virtual drive where the Ubuntu filesystem lives.
- `linux /boot/vmlinuz root=/dev/sda1` loads the kernel binary into memory and tells it where the root filesystem is located.
- `rw` mounts the root partition read write from the first second. If omitted, the root filesystem mounts read only, which blocks updating passwords or saving firewall rules until you run a manual remount.
- `init=/bin/bash` tells the kernel to launch an interactive bash shell as PID 1 instead of handing off control to systemd (`/sbin/init`). This bypasses user authentication, startup targets, and password prompts completely.
- `initrd /boot/initrd.img` loads the initial ramdisk containing the SCSI storage drivers needed to access the virtualized root disk.
- `boot` starts execution.

### Step 4: Clear the Lockout from the Root Shell

Within a few seconds, the console will drop into a passwordless root prompt (`root@...:/#`). Run these commands:

```bash
passwd ubuntu
iptables -F
iptables-save > /etc/iptables/rules.v4
reboot -f
```

Why each line is critical here:
- `passwd ubuntu`: Cloud images do not have a default password because they rely on SSH keys. Setting a local password here ensures that if you ever need the serial console again, you can log in through the normal prompt without interrupting the bootloader. This does not open SSH to brute force attempts because `PasswordAuthentication no` remains strictly enforced in `/etc/ssh/sshd_config.d/60-cloudimg-settings.conf`.
- `iptables -F`: Clears all active firewall rules in memory that were dropping port 22 or blocking the local metadata IP `169.254.169.254`.
- `iptables-save > /etc/iptables/rules.v4`: In single user mode, system boot scripts have not run, so the bad firewall rules sitting in `/etc/iptables/rules.v4` on disk were never loaded into memory. Running `iptables -F` only empties the active table. Overwriting `/etc/iptables/rules.v4` ensures the clean state is saved to disk so `netfilter-persistent` does not reload the old broken rules on normal boot.
- `reboot -f`: Standard commands like `systemctl reboot` fail because systemd is not running. The `-f` flag tells the kernel to force an immediate hardware reset.

### Step 5: Verify OCI VCN Network Routes and Security Lists

If inbound SSH connections still time out after the normal reboot, the packet drop is happening in the OCI virtual network rather than inside the VM:

1. In the OCI Console, go to **Networking** > **Virtual Cloud Networks** and click your VCN.
2. Under **Resources**, confirm that an **Internet Gateway** exists and is Available.
3. Open **Route Tables** and click the route table attached to your subnet.
4. Verify that a route rule points `0.0.0.0/0` to your Internet Gateway. Without this rule, return traffic from the VM cannot route back out to public clients.
5. Open the **Security List** attached to the subnet (or check your **Network Security Group**).
6. Verify an Ingress Rule exists for `0.0.0.0/0`, IP Protocol `TCP`, and Destination Port Range `22`. Without this rule, the OCI virtual network drops incoming packets before they touch the instance virtual NIC.
