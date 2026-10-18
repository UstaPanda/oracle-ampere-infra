# Runbook: Live Storage Expansion and Volume Performance Tuning

**Languages:** [English](storage-expansion-vpu-tuning.md) | [Türkçe](storage-expansion-vpu-tuning.tr.md)

## 1. Overview

When my 50 GB boot volume started running low on space, I needed to expand it to 100 GB without shutting down the VM or interrupting active containers. On Oracle Cloud (OCI), block and boot volumes can be resized online while the instance stays running.

This runbook records how I expanded the live ext4 root partition using `growpart` and `resize2fs`, and how I adjusted OCI Volume Performance Units (VPUs) to increase disk IOPS and throughput.

## 2. Live Expansion Steps

### Step 1: Resize the Volume in the OCI Console
1. Open the OCI Web Console.
2. Navigate to **Storage** > **Block Volumes** or **Boot Volumes**.
3. Click on the attached boot volume and select **Edit**.
4. Increase the volume size (for example, from 50 GB to 100 GB) and save the changes. The hypervisor immediately sends a SCSI capacity update event to the Linux kernel.

### Step 2: Expand the Partition and Filesystem Inside the VM

I put the guest resize commands into a helper script (`scripts/setup-storage.sh`) so I do not have to look up partition flags manually:

```bash
sudo ./scripts/setup-storage.sh
```

Or run the underlying commands directly:

```bash
sudo growpart /dev/sda 1
sudo resize2fs /dev/sda1
df -h /
```

What each command does:
- `growpart /dev/sda 1`: Updates the GPT partition table in memory so partition 1 spans the newly allocated sectors on `/dev/sda`.
- `resize2fs /dev/sda1`: Tells the ext4 driver to claim the new blocks. Because ext4 supports online resizing, this finishes in a few seconds while the root filesystem stays mounted.

## 3. OCI Volume Performance Units (VPU)

OCI block storage throughput scales with both volume size and the assigned VPU tier:
- Lower Cost (0 VPUs per GB): Basic throughput for cold storage and backups
- Balanced (10 VPUs per GB): Default OCI tier for standard boot and container volumes
- Higher Performance (20 VPUs per GB): Higher IOPS ceiling for heavier disk writes
- Ultra High Performance (30 to 120 VPUs per GB): Maximum IOPS and throughput ceiling

Along with expanding the volume to 100 GB, I bumped the drive setting to 30 VPUs in the OCI Console to reduce disk write latency during heavy world saves and container image extraction. VPU changes apply online within seconds without detaching the volume.
