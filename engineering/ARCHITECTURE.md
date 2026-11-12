# Architecture Audit & Interdependency Map

## 1. System Role & Scope

`droidspaces-package` is the central packaging, distribution, and hardware configuration repository for the Droidspaces container ecosystem on Android. It bridges:

1. **Host Kernel (Linux 4.14)** ↔ **Container Init (systemd 257)**:
   - Modern systemd requires cgroup v2 unified hierarchy and kernel >= 5.3 netlink nexthops.
   - Kernel 4.14 only supports cgroups v1 reliably on Android (`force_cgroupv1=1`).
   - `droidspaces-package` provides the patchset (`patches/0001-droidspaces-old-kernel-compat.patch`) that allows Arch Linux ARM, Debian 13, Ubuntu 26.04, and Fedora 43/44 to boot and manage services smoothly inside Droidspaces.

2. **Hardware Acceleration (Qualcomm Adreno 618)** ↔ **Container Graphics (Wayland/Xwayland/Mesa)**:
   - Snapdragon 732G uses Adreno 618 (`SM6150`).
   - Under custom ROM Android with kernel 4.14, `/dev/dri/card0` DRM/KMS device nodes are absent; access must proceed via `/dev/kgsl-3d0` (Qualcomm KGSL driver).
   - `droidspaces-package` builds, packages, and configures Mesa via `droidspaces-gpu.sh` and `install-mesa.sh`, managing KGSL, Zink, LLVMpipe, Turnip, and Lavapipe paths.

3. **Desktop Environment & Session Bridges (`anland`)**:
   - Packages custom patched KWin/Xwayland (KDE), Mutter/Xwayland (GNOME), Niri, Hyprland, Mango, Denial, and Next session.
   - Manages package holds across APT, DNF, and Pacman to prevent upstream distribution updates from clobbering container-specific Wayland patches.

4. **Container Runtime Control & User Experience (`droidspaces-tui`)**:
   - Interactive TUI providing component installation, updates, mirror switching, storage reclaim (`fstrim`), and GPU switching.

---

## 2. Component Layout

```
droidspaces-package/
├── patches/
│   ├── 0001-droidspaces-old-kernel-compat.patch     # systemd old kernel compat (cgroup v1 + nexthop)
│   └── 0002-systemd-257.9-linux-7.0-errno-aliases.patch # errno alias compatibility
├── vendor/
│   ├── arch/                                        # Arch PKGBUILD and systemd pacman hooks
│   └── fedora/                                      # Fedora systemd spec and macros
├── scripts/
│   ├── build-arch.sh                                # Arch Linux ARM package builder
│   ├── build-deb.sh                                 # Debian / Ubuntu DEB package builder
│   ├── build-rpm.sh                                 # Fedora RPM package builder
│   ├── build-anland-session-package.sh              # Anland Next session packager
│   ├── stage-anland-session-vendor.sh               # Staged vendor tree builder (bubblewrap, xwayland)
│   ├── lib.sh                                       # Common packaging helper functions
│   └── tui/                                         # Container-side runtime utilities
│       ├── droidspaces-tui.sh                       # Interactive container management TUI (2,267 lines)
│       ├── droidspaces-gpu.sh                       # GPU configuration helper (285 lines)
│       ├── install-tui.sh                           # Bootstrap updater for TUI
│       ├── install-mesa.sh                          # Mesa + MediaCodec VA-API driver installer
│       ├── install-anland-kde.sh                    # Anland KDE Wayland installer
│       ├── install-anland-gnome.sh                  # Anland GNOME installer
│       ├── install-anland-niri.sh                   # Anland Niri installer
│       ├── install-anland-hyprland.sh               # Anland Hyprland installer
│       ├── install-anland-mango.sh                  # Anland Mango installer
│       ├── install-anland-denial.sh                 # Anland Denial installer
│       ├── install-anland-next.sh                   # Anland Next session installer
│       ├── install-hangover-wine.sh                 # Hangover-Wine installer
│       └── install-winefonts.sh                     # Wine fonts installer
└── .github/workflows/                               # Automated CI/CD and release pipelines
```

---

## 3. Critical Execution Paths & Bottleneck Analysis

### Execution Path 1: GPU Path Query (`droidspaces-gpu.sh --status`)
- **Call flow**: `TUI menu loop` → `gpu_status_display()` (4 calls per frame) → `bash droidspaces-gpu.sh --status` → `gpu_vk_label()` → `gpu_manifest_matches()` → `python3 - <<'PY' ...`
- **Identified Bottleneck**: Spawning Python 3 for each manifest check inside the container consumes **232ms to 660ms** and 15–25 MB RSS memory per call. Doing this across 4 calls per frame creates massive CPU stalls, swap thrashing, and burns global PIDs towards the 65,535 bionic crash limit.
- **Architectural Fix**: Pure-bash in-memory JSON regex validation. Zero subprocess forks. Execution latency drops to **0.5ms**. Source GPU functions directly in `droidspaces-tui.sh` when present to eliminate external `bash` forks.

### Execution Path 2: Package Version Discovery (`droidspaces-tui.sh` startup)
- **Call flow**: `detect_desktop_component` + `start_component_version_checks` → `managed_component_installed()` → `detected_component_package_version()` → `pacman -Q <pkg>` (or `dpkg-query -W` / `rpm -q`) called sequentially 15–20 times.
- **Identified Bottleneck**: Each `pacman -Q` invocation initializes libalpm and disk indexes. Sequential queries take **1.39s to 2.5s** on mobile UFS 2.2 storage. Furthermore, the query is executed twice (once for detection, once for recording).
- **Architectural Fix**: Single batched package query (`pacman -Q pkg1 pkg2 ... 2>/dev/null`) taking **0.11s** (**12.4x speedup**), with results cached in an associative array.

### Execution Path 3: Qualcomm SM6150 / Adreno 618 Hardware Acceleration
- **Call flow**: `droidspaces-gpu.sh --set opengl kgsl` → writes `/etc/environment`
- **Identified Bottleneck**: Sets `MESA_LOADER_DRIVER_OVERRIDE=kgsl` and `GALLIUM_DRIVER=kgsl`, but omits `FD_FORCE_KGSL=1` and `KWIN_COMPOSE=O2ES`. Without `FD_FORCE_KGSL=1`, Freedreno fails to open `/dev/kgsl-3d0` when DRM render nodes are missing.
- **Architectural Fix**: Add hardware profile persistence for KGSL ensuring `FD_FORCE_KGSL=1` and `KWIN_COMPOSE=O2ES` are written atomically.

### Execution Path 4: Container Memory Pressure & Redundant Services
- **Call flow**: Container boot → systemd starts background units (`systemd-networkd`, `systemd-udevd`, desktop indexers).
- **Identified Bottleneck**: In `mikasa`, `systemd-networkd` and `systemd-udevd` repeatedly crash and restart because network and udev are owned by the host Android kernel. Meanwhile, desktop indexers churn swap at 6.5–7.7 MB/s.
- **Architectural Fix**: Introduce a dedicated **Container Performance & Memory Profile Optimizer** in `droidspaces-tui.sh` and CLI allowing one-click masking of failing services, ZRAM compaction, and memory trimming.
