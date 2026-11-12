# Baseline Performance & Telemetry Report

**Document ID:** BASELINE-DROIDSPACES-PACKAGE-20261110  
**Device:** Xiaomi Redmi Note 10 Pro (`sweet` / `sweetin`)  
**SoC:** Qualcomm SM6150 (Snapdragon 732G) | 8 Cores (2x Kryo 470 Gold @ 2.3 GHz + 6x Kryo 470 Silver @ 1.8 GHz)  
**RAM:** 5.4 GiB physical | **ZRAM:** 3.0 GiB (lz4)  
**Host OS:** Android 15 (LineageOS-family reforge) | Kernel 4.14.357-reforge  
**Target Container:** `mikasa` (Arch Linux ARM64, systemd 257.9-2 patched)  
**Baseline Date:** 2026-11-10  

---

## 1. Baseline Measurements

### 1.1 GPU Manifest Validation Latency (`gpu_manifest_matches`)
- **Workload:** Validating Vulkan ICD manifest `/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json` against driver mode `turnip` (freedreno).
- **Mechanism:** `python3 - "$path" "$driver" <<'PY' ...` (current implementation in `droidspaces-gpu.sh`).
- **Measurements (10 consecutive iterations inside container `mikasa`):**
  - Run 1 (cold/unpaged): 445 ms
  - Run 2: 176 ms
  - Run 3: 77 ms
  - Run 4: 115 ms
  - Run 5: 216 ms
  - Run 6: 186 ms
  - Run 7: 215 ms
  - Run 8: 177 ms
  - Run 9: 604 ms
  - Run 10 (peak stall): 1444 ms
- **Arithmetic Mean Latency:** **365 ms**
- **Process Fork Overhead:** 2 forks per validation (1 subshell for heredoc + 1 `python3` process invocation).
- **Memory Footprint:** Spawns Python 3 runtime (~18–25 MB RSS) per call. Under 72%+ swap pressure, this triggers minor page faults and swap-in activity.
- **PID Impact:** 2 PIDs consumed per call, accelerating counter towards the 32-bit Bionic 65,535 limit.

---

### 1.2 Package Discovery Latency (`detected_component_package_version`)
- **Workload:** Querying installed status across 12 target desktop/graphics package candidates (`kwin-wayland`, `kwin-x11`, `kwin-common`, `kwin`, `niri-anland`, `mutter`, `hyprland-anland`, `mango-anland`, `denial`, `anland-session`, `mesa`, `hangover-wine`).
- **Mechanism:** Sequential `pacman -Q <package>` queries (current implementation in `droidspaces-tui.sh`).
- **Measurements (3 consecutive iterations inside container `mikasa`):**
  - Run 1: 1454 ms
  - Run 2: 962 ms
  - Run 3: 848 ms
- **Arithmetic Mean Latency:** **1088 ms** (1.088 seconds)
- **Process Fork Overhead:** 12 sequential process forks.
- **Startup Impact:** TUI startup calls package detection multiple times during `detect_desktop_component` and `start_component_version_checks`, creating an initial UI freeze of 2.0–2.5 seconds.

---

### 1.3 GPU Status Frame Redraw Latency
- **Workload:** 4 consecutive calls to `gpu_status_display` during TUI Mesa menu render (`current opengl`, `saved opengl`, `current vulkan`, `saved vulkan`).
- **Mechanism:** 4 independent subshell spawns: `bash "$helper" --status <scope> <api>`.
- **Latency:** **91 ms** per frame.
- **Process Fork Overhead:** 4 bash subshells + multiple manifest validations per redraw.

---

### 1.4 Baseline System Telemetry
- **Battery Capacity:** 63%
- **Battery Temperature:** 33.0°C
- **Host `pid_max`:** 65535 (pinned via `/data/adb/service.d/99-audio-forensics.sh`)
- **MemAvailable:** 1,690,896 kB (~1.61 GiB)
- **SwapFree:** 1,269,516 kB (~1.21 GiB free out of 3.0 GiB)
- **Active Container Services in `mikasa`:** 55 processes, KDE Plasma 6.8 + Wayland + PipeWire.
- **Identified Service Defects in Container:**
  - `plasma-ksplash.service` failed (timed out waiting for splash screen).
  - `systemd-networkd` restart limit hit (conflicts with Android host networking).
  - `systemd-udevd` restart limit hit (conflicts with Android kernel devtmpfs).
