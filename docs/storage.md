# Storage: the worker's disks, as a worked example

The author's worker is a retired desktop with one 500 GB NVMe, a 2 TB hard drive and an old
NTFS drive. This page is how those disks are laid out, why each filesystem was picked, and
the outage that rewrote the rules. Copy the parts that fit your hardware.

```
nvme0n1  465 GB
├─p1     1 GB     vfat    /boot                 EFI system partition
├─p2     125 GB   btrfs   / /home /var/log /var/cache/pacman/pkg
└─p3     340 GB   LVM PV -> VG vgwork -> VDO pool (340 GB real, 660 GB virtual)
                           -> LV work, XFS      /mnt/work  (bind-mounted into ~)
sda      2 TB     ext4    /mnt/bulk             bulk data, snapshots, archives (nofail)
sdb2     580 GB   ntfs    /mnt/vault            irreplaceable data, READ-ONLY
zram0    16 GB    swap                          compressed RAM swap
```

| mount | filesystem | holds | agents may write |
| --- | --- | --- | --- |
| `/boot` | vfat | kernels, GRUB | no |
| `/`, `/home` | btrfs | the OS, your home, configs | yes, small things only |
| `/mnt/work` | XFS on LVM VDO | repos, worktrees, package stores, SDKs, ML envs | yes, code and environments |
| `/mnt/bulk` | ext4 | downloads, media, snapshots, archives | yes, anything big |
| `/mnt/vault` | NTFS, read-only | irreplaceable files | never |

## The system partition: btrfs with subvolumes

125 GB of btrfs with four subvolumes, all mounted `compress=zstd:3`:

| subvolume | mount | why its own subvolume |
| --- | --- | --- |
| `@` | `/` | the thing you snapshot and roll back |
| `@home` | `/home` | rolling back the OS must not roll back your files |
| `@log` | `/var/log` | logs from the failed boot survive a rollback, so you can read why |
| `@pkg` | `/var/cache/pacman/pkg` | the package cache stays out of snapshots; it is also what makes a downgrade without network possible |

```fstab
UUID=<root-uuid>  /                      btrfs  rw,relatime,compress=zstd:3,ssd,discard=async,space_cache=v2,subvol=/@     0 0
UUID=<root-uuid>  /home                  btrfs  rw,relatime,compress=zstd:3,ssd,discard=async,space_cache=v2,subvol=/@home 0 0
UUID=<root-uuid>  /var/log               btrfs  rw,relatime,compress=zstd:3,ssd,discard=async,space_cache=v2,subvol=/@log  0 0
UUID=<root-uuid>  /var/cache/pacman/pkg  btrfs  rw,relatime,compress=zstd:3,ssd,discard=async,space_cache=v2,subvol=/@pkg  0 0
```

zstd level 3 costs little CPU and saves real space on text-heavy system files.

**Rollback snapshots before deep updates.** The OS update work order takes a read-only snapshot
of `@` before it touches a package. When the update is proven, older snapshots are exported off
the NVMe so they stop pinning space on a small partition. The hard drive is ext4, so they go
over as compressed `btrfs send` streams:

```bash
sudo btrfs subvolume snapshot -r / /@snapshot-deep-<date>          # before the transaction
sudo btrfs send /@snapshot-deep-<date> | zstd -T0 > /mnt/bulk/btrfs-snapshots/@snapshot-deep-<date>.btrfs.zst
sudo btrfs subvolume delete /@snapshot-deep-<date>                 # once a newer one exists
```

Restore from a live USB if `@` won't boot:

```bash
mount -o subvolid=5 /dev/<root-partition> /mnt
zstd -dc /mnt/bulk/btrfs-snapshots/<name>.btrfs.zst | btrfs receive /mnt
btrfs property set -ts /mnt/<name> ro false      # received copies are read-only
mv /mnt/@ /mnt/@broken-<date>
btrfs subvolume snapshot /mnt/<name> /mnt/@
```

Keep the latest snapshot on the NVMe too. It is the fast rollback; the exported streams are
the slow one. Put a README next to the streams with these restore steps, so whoever is at the
box with a USB stick does not have to find this page.

## The work volume: XFS on LVM with VDO

The rest of the NVMe holds what agents churn through: every repo, T3 worktrees, the pnpm
store, ROCm, the Android SDK, ML environments. That data is full of duplicates (five worktrees
of one repo, each with its own `node_modules`), so it sits on
[VDO](https://docs.kernel.org/admin-guide/device-mapper/vdo.html), which deduplicates and
compresses at the block layer. 340 GB of real space is presented as a 660 GB virtual device, and
it runs at roughly 40 to 55% space saving.

```bash
sudo pvcreate /dev/<nvme>p3
sudo vgcreate vgwork /dev/<nvme>p3
sudo lvcreate --type vdo --name work --size 338G --virtualsize 660G vgwork/vpool0
sudo mkfs.xfs -K -L work /dev/vgwork/work       # -K: skip the discard pass on a thin device
```

```fstab
UUID=<work-uuid>  /mnt/work  xfs  defaults,noatime,nofail,x-systemd.requires=lvm2-monitor.service  0 0
```

`nofail` means a missing volume never blocks boot. The `lvm2-monitor` ordering makes sure the
VDO stack is active before the mount is attempted.

**Surfaced at the usual paths.** Nothing should need to know `/mnt/work` exists. Each directory
is bind-mounted from fstab onto the path tools already expect:

```fstab
/mnt/work/dev           /home/<user>/dev                   none  bind,nofail  0 0
/mnt/work/t3-worktrees  /home/<user>/.t3/worktrees         none  bind,nofail  0 0
/mnt/work/pnpm-store    /home/<user>/.local/share/pnpm/store none bind,nofail 0 0
/mnt/work/rocm          /opt/rocm                          none  bind,nofail  0 0
/mnt/work/android/sdk   /home/<user>/Android               none  bind,nofail  0 0
/mnt/work/android/gradle /home/<user>/.gradle              none  bind,nofail  0 0
/mnt/work/android/dot-android /home/<user>/.android        none  bind,nofail  0 0
```

ML virtualenvs and llama.cpp are symlinks instead (`~/ml-gpu -> /mnt/work/ml-gpu`), which is
fine for directories nothing walks up from. `pnpm install` finds its store, Gradle finds its
cache, and `~/dev/<repo>` stays the path every doc uses. A oneshot unit runs `ldconfig` after
`/opt/rocm` is mounted so the ROCm libraries are in the linker cache. A `CLAUDE.md` and
`AGENTS.md` at the volume root tell an agent working there what the volume is for.

### The VDO incident

Someone downloaded a pile of encrypted game packages to the work volume. Encrypted data neither
compresses nor deduplicates, so every byte cost a real byte. The VDO pool hit 100% physical
while `df` still showed about 250 GB free. XFS got ENOSPC writing its own log and shut the
filesystem down, taking `~/dev`, every T3 worktree, the pnpm store and ROCm offline until a
reboot.

Recovery: grow the pool by the last free extents in the volume group, reboot so XFS replays its
log, move the downloads to the hard drive, then `fstrim` so VDO gets the freed blocks back.

The rules it left behind:

- **No bulk or incompressible data on the work volume.** Downloads, media, archives, disk
  images and model weights go to the hard drive.
- **`df` lies on VDO.** Judge free space with `sudo vdostats --human-readable`, which reports
  physical use.
- **Deleting does not free space until you trim.** `sudo fstrim -v /mnt/work`, or enable
  `fstrim.timer`.
- **Plan to rebuild as plain XFS.** VDO's savings are real, but a disk whose free space you
  cannot read at a glance will catch someone out again. A full copy sits on the hard drive for
  that rebuild. If you are building fresh, plain XFS or btrfs with compression is the simpler
  choice.

## The hard drive: bulk, snapshots, archives

2 TB of ext4, labelled, mounted so the box boots without it:

```fstab
LABEL=<bulk-label>  /mnt/bulk  ext4  defaults,noatime,nofail,x-systemd.device-timeout=60s  0 2
```

`x-systemd.device-timeout=60s` bounds the wait for a drive that died. Without `nofail`, a dead
disk drops a headless box into emergency mode, where nobody can reach it.

It holds:

- `snapshots/`: nightly full-system rsync snapshots (below).
- `btrfs-snapshots/`: the exported rollback streams.
- `archive/`: retired projects, removed tools, anything kept "just in case".
- Downloads and media: anything big or incompressible.

### Nightly full-system snapshots

A root systemd timer at 03:00 with `Persistent=true` runs rsync from `/` into
`snapshots/<date>`, hard-linked against `snapshots/latest`, so unchanged files cost nothing:

```bash
rsync -aAXH --delete \
  --exclude={/proc/*,/sys/*,/dev/*,/run/*,/tmp/*,/mnt/*,/media/*,/lost+found} \
  --exclude='/home/*/.cache/*' --exclude='/var/cache/pacman/pkg/*' \
  --link-dest=/mnt/bulk/snapshots/latest  /  /mnt/bulk/snapshots/<date>/
```

Then it saves the explicit and AUR package lists next to the snapshot and repoints `latest`.

- **Exit 24 is success.** It means files vanished mid-copy, normal on a live system (a browser's
  WAL file). Treat any other non-zero code as failure and leave `latest` alone.
- **Retention is 3 days, by the date in the directory name.** rsync copies `/`'s mtime onto each
  snapshot directory, so pruning by mtime deletes the wrong ones.
- **Never delete what `latest` points to.** A week of failed runs must not prune you down to
  zero snapshots.
- `/mnt/*` is excluded, but the bind mounts under `/home` are not, so `~/dev` and the other
  work-volume paths are swept in through their home-side paths. The raw `/mnt/work` volume is
  not copied twice.

This saved real work once. After a hard freeze zeroed a repo's `.git/config`, the copy from that
morning's snapshot restored it.

## The read-only drive

An old NTFS drive holds files that exist nowhere else. It is mounted read-only, so no agent can
write or delete there, even by mistake:

```fstab
UUID=<ntfs-uuid>  /mnt/vault  ntfs-3g  ro,uid=1000,gid=1000,noatime  0 0
```

To write deliberately: `sudo mount -o remount,rw /mnt/vault`, do the one thing, remount `ro`.
The rules file tells every agent never to stage transfers there. Leave the OEM recovery
partition on the same disk unmounted.

## Swap

zram, about half of RAM, compressed in memory (`zram-generator`). No swap file on the NVMe.
With agents capped by systemd slices and earlyoom killing dev servers first, zram covers short
memory spikes without writing to disk.

## Rules agents get

These go in the worker's rules file and `CLAUDE.md` at the volume root:

- Big work data (repos, worktrees, environments) goes on the work volume through its usual home
  path. Anything bulk or incompressible goes to `/mnt/bulk`.
- The system partition is small. Never stage a large transfer in `$HOME`.
- Never write to `/mnt/vault`.
- Check work-volume space with `vdostats`, not `df`.
