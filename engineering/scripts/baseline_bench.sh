#!/usr/bin/env bash
# Baseline benchmark script for droidspaces-package
set -euo pipefail

CONTAINER_NAME="mikasa"
TMP_DIR="/data/local/tmp"

echo "=== DROIDSPACES-PACKAGE BASELINE BENCHMARK ==="
echo "Timestamp: $(date -Iseconds)"
echo "Kernel: $(uname -r)"
echo "SoC: Qualcomm SM6150 (Snapdragon 732G)"

# 1. Measure GPU manifest validation (python3 invocation)
echo ""
echo "--- 1. GPU Manifest Validation Latency (Current Implementation) ---"
su -c "
  cp /data/data/com.termux/files/home/development/repo/droidspaces-package/scripts/tui/droidspaces-gpu.sh /data/local/tmp/bench_gpu_orig.sh
  chmod 755 /data/local/tmp/bench_gpu_orig.sh
"

# Run 10 iterations inside container and calculate stats
su -c "PATH=\$PATH:/data/local/Droidspaces/bin droidspaces --name=$CONTAINER_NAME run -- bash -c '
  export VK_DRIVER_FILES=/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json
  TOTAL=0
  RUNS=10
  echo \"Running \$RUNS iterations of droidspaces-gpu.sh --status current vulkan...\"
  for i in \$(seq 1 \$RUNS); do
    START=\$(date +%s%N)
    bash /data/local/tmp/bench_gpu_orig.sh --status current vulkan >/dev/null
    END=\$(date +%s%N)
    DIFF=\$(( (END - START) / 1000000 ))
    TOTAL=\$(( TOTAL + DIFF ))
    echo \"  Run \$i: \${DIFF}ms\"
  done
  AVG=\$(( TOTAL / RUNS ))
  echo \"Average GPU status latency (orig): \${AVG}ms\"
'"

# 2. Measure Package Detection Latency (Sequential pacman -Q queries)
echo ""
echo "--- 2. Package Detection Latency (Current Implementation) ---"
su -c "PATH=\$PATH:/data/local/Droidspaces/bin droidspaces --name=$CONTAINER_NAME run -- bash -c '
  TOTAL=0
  RUNS=5
  echo \"Running \$RUNS iterations of sequential package queries...\"
  for i in \$(seq 1 \$RUNS); do
    START=\$(date +%s%N)
    pacman -Q kwin-wayland 2>/dev/null || true
    pacman -Q kwin-x11 2>/dev/null || true
    pacman -Q kwin-common 2>/dev/null || true
    pacman -Q kwin 2>/dev/null || true
    pacman -Q niri-anland 2>/dev/null || true
    pacman -Q mutter 2>/dev/null || true
    pacman -Q hyprland-anland 2>/dev/null || true
    pacman -Q mango-anland 2>/dev/null || true
    pacman -Q denial 2>/dev/null || true
    pacman -Q anland-session 2>/dev/null || true
    pacman -Q mesa 2>/dev/null || true
    pacman -Q hangover-wine 2>/dev/null || true
    END=\$(date +%s%N)
    DIFF=\$(( (END - START) / 1000000 ))
    TOTAL=\$(( TOTAL + DIFF ))
    echo \"  Run \$i: \${DIFF}ms\"
  done
  AVG=\$(( TOTAL / RUNS ))
  echo \"Average sequential package query latency (orig): \${AVG}ms\"
'"

# 3. Measure System Resources
echo ""
echo "--- 3. System Baseline Telemetry ---"
su -c "
  echo -n 'Battery Capacity: '; cat /sys/class/power_supply/battery/capacity 2>/dev/null || echo 'N/A'
  echo -n 'Battery Temp: '; awk '{print \$1/10 \"°C\"}' /sys/class/power_supply/battery/temp 2>/dev/null || echo 'N/A'
  echo -n 'Current pid_max: '; cat /proc/sys/kernel/pid_max
  echo -n 'MemAvailable: '; awk '/MemAvailable/{print \$2 \" kB\"}' /proc/meminfo
  echo -n 'SwapFree: '; awk '/SwapFree/{print \$2 \" kB\"}' /proc/meminfo
"
