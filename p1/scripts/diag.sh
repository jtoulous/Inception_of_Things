#!/bin/bash
# diag.sh - collect everything needed to debug a failed build into p1/diag.log
# plus console screenshots (p1/consoleS.png, p1/consoleSW.png), all on the
# shared folder so they are readable from the host. Run inside the iot VM:
#   bash scripts/diag.sh
P1_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${P1_DIR}/diag.log"
export VAGRANT_DOTFILE_PATH="$HOME/.vagrant"
export VAGRANT_DEFAULT_PROVIDER="virtualbox"

{
    echo "=== date ===";    date
    echo "=== memory ===";  free -h
    echo "=== load ===";    uptime
    echo "=== VirtualBox VMs (running) ==="; VBoxManage list runningvms
    echo "=== VirtualBox VMs (all) ===";     VBoxManage list vms
    echo "=== OOM kills / kernel errors (smoking gun if a node died) ==="
    sudo dmesg -T 2>/dev/null | grep -iE 'oom|out of memory|killed process' | tail -n 20
    echo "=== vagrant status ==="
    cd "$P1_DIR" && vagrant status 2>&1

    # --- inside the nodes (skipped silently if a node is unreachable) ---
    echo "=== rsterinS: k3s service ==="
    vagrant ssh rsterinS -c '
        systemctl is-active k3s;
        echo "--- k3s journal (last 25) ---";
        sudo journalctl -u k3s --no-pager 2>/dev/null | tail -n 25;
        echo "--- node memory ---"; free -m;
        echo "--- port 6443 ---"; ss -ltn | grep 6443 || echo "NOT LISTENING"
    ' 2>&1
    echo "=== rsterinSW: k3s-agent service ==="
    vagrant ssh rsterinSW -c '
        systemctl is-active k3s-agent;
        echo "--- k3s-agent journal (last 20) ---";
        sudo journalctl -u k3s-agent --no-pager 2>/dev/null | tail -n 20;
        echo "--- node memory ---"; free -m
    ' 2>&1
} > "$OUT" 2>&1

# Console screenshots - show kernel panics / boot state even when SSH is dead.
VBoxManage controlvm rsterinS  screenshotpng "${P1_DIR}/consoleS.png"  2>/dev/null
VBoxManage controlvm rsterinSW screenshotpng "${P1_DIR}/consoleSW.png" 2>/dev/null

echo "Wrote $OUT (+ consoleS.png / consoleSW.png if the VMs are running)."
