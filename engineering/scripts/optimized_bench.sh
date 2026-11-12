#!/usr/bin/env bash
# Optimized benchmark script for droidspaces-package
set -euo pipefail

CONTAINER_NAME="mikasa"

echo "=== DROIDSPACES-PACKAGE OPTIMIZED BENCHMARK ==="
echo "Timestamp: $(date -Iseconds)"
echo "Kernel: $(uname -r)"
echo "SoC: Qualcomm SM6150 (Snapdragon 732G)"

su -c "
  cp /data/data/com.termux/files/home/development/repo/droidspaces-package/scripts/tui/droidspaces-gpu.sh /data/local/tmp/bench_gpu_opt.sh
  cp /data/data/com.termux/files/home/development/repo/droidspaces-package/scripts/tui/droidspaces-tui.sh /data/local/tmp/bench_tui_opt.sh
  chmod 755 /data/local/tmp/bench_gpu_opt.sh /data/local/tmp/bench_tui_opt.sh
"

# 1. Measure GPU manifest validation (Optimized Pure Bash)
echo ""
echo "--- 1. GPU Manifest Validation Latency (Optimized Pure Bash) ---"
su -c "PATH=\$PATH:/data/local/Droidspaces/bin droidspaces --name=$CONTAINER_NAME run -- bash -c '
  export VK_DRIVER_FILES=/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json
  TOTAL=0
  RUNS=10
  echo \"Running \$RUNS iterations of optimized droidspaces-gpu.sh --status current vulkan...\"
  for i in \$(seq 1 \$RUNS); do
    START=\$(date +%s%N)
    bash /data/local/tmp/bench_gpu_opt.sh --status current vulkan >/dev/null
    END=\$(date +%s%N)
    DIFF=\$(( (END - START) / 1000000 ))
    TOTAL=\$(( TOTAL + DIFF ))
    echo \"  Run \$i: \${DIFF}ms\"
  done
  AVG=\$(( TOTAL / RUNS ))
  echo \"Average GPU status latency (optimized): \${AVG}ms\"
'"

# 2. Measure Package Detection Latency (Optimized Batched Package Query)
echo ""
echo "--- 2. Package Detection Latency (Optimized Batched Query) ---"
su -c "PATH=\$PATH:/data/local/Droidspaces/bin droidspaces --name=$CONTAINER_NAME run -- bash -c '
  source /data/local/tmp/bench_tui_opt.sh
  detect_system
  TOTAL=0
  RUNS=3
  echo \"Running \$RUNS iterations of batched package discovery...\"
  for i in \$(seq 1 \$RUNS); do
    START=\$(date +%s%N)
    invalidate_package_cache
    populate_package_cache
    for comp in kde mesa hangover anland-next; do
      detected_component_package_version \"\$comp\" >/dev/null 2>&1 || true
    done
    END=\$(date +%s%N)
    DIFF=\$(( (END - START) / 1000000 ))
    TOTAL=\$(( TOTAL + DIFF ))
    echo \"  Run \$i: \${DIFF}ms\"
  done
  AVG=\$(( TOTAL / RUNS ))
  echo \"Average batched package discovery latency (optimized): \${AVG}ms\"
'"

# 3. Measure System Resources
echo ""
echo "--- 3. System Optimized Telemetry ---"
su -c "
  echo -n 'Battery Capacity: '; cat /sys/class/power_supply/battery/capacity 2>/dev/null || echo 'N/A'
  echo -n 'Battery Temp: '; awk '{print \$1/10 \"°C\"}' /sys/class/power_supply/battery/temp 2>/dev/null || echo 'N/A'
  echo -n 'Current pid_max: '; cat /proc/sys/kernel/pid_max
  echo -n 'MemAvailable: '; awk '/MemAvailable/{print \$2 \" kB\"}' /proc/meminfo
  echo -n 'SwapFree: '; awk '/SwapFree/{print \$2 \" kB\"}' /proc/meminfo
"
