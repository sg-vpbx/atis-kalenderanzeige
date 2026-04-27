#!/bin/bash
# =============================================================================
# SD-Karten-Schutz für Kalender-Display
#
# Verwendet OverlayFS von Raspberry Pi OS, um das Dateisystem
# schreibgeschützt zu machen. Schützt die SD-Karte vor Korruption
# bei Stromunterbrüchen.
#
# Verwendung:
#   ./protect.sh lock     → Schreibschutz aktivieren (nach Reboot aktiv)
#   ./protect.sh unlock   → Schreibschutz deaktivieren (nach Reboot aktiv)
#   ./protect.sh status   → Aktuellen Status anzeigen
# =============================================================================
set -e

# --- Farbige Ausgabe ---
info()  { echo -e "\e[34m[INFO]\e[0m  $1"; }
ok()    { echo -e "\e[32m[OK]\e[0m    $1"; }
warn()  { echo -e "\e[33m[WARN]\e[0m  $1"; }
error() { echo -e "\e[31m[ERROR]\e[0m $1"; exit 1; }

# --- Prüfe ob raspi-config vorhanden ---
if ! command -v raspi-config &> /dev/null; then
    error "raspi-config nicht gefunden. Dieses Script funktioniert nur auf Raspberry Pi OS."
fi

# --- Status prüfen ---
get_status() {
    if grep -q "boot=overlay" /boot/firmware/cmdline.txt 2>/dev/null || \
       grep -q "boot=overlay" /boot/cmdline.txt 2>/dev/null; then
        echo "locked"
    else
        echo "unlocked"
    fi
}

show_status() {
    local status=$(get_status)
    echo ""
    echo "============================================="
    echo "  SD-Karten-Schutz: Status"
    echo "============================================="
    echo ""
    if [ "$status" = "locked" ]; then
        ok "Schreibschutz ist AKTIV (OverlayFS)"
        echo ""
        echo "  Das Dateisystem ist schreibgeschützt."
        echo "  Alle Änderungen gehen beim Neustart verloren."
        echo "  Die SD-Karte ist vor Stromunterbrüchen geschützt."
        echo ""
        echo "  Zum Entsperren:  ./protect.sh unlock"
    else
        warn "Schreibschutz ist INAKTIV"
        echo ""
        echo "  Das Dateisystem ist beschreibbar."
        echo "  Änderungen werden direkt auf die SD-Karte geschrieben."
        echo ""
        echo "  Zum Sichern:     ./protect.sh lock"
    fi
    echo ""
}

do_lock() {
    echo ""
    echo "============================================="
    echo "  SD-Karten-Schutz aktivieren"
    echo "============================================="
    echo ""

    local status=$(get_status)
    if [ "$status" = "locked" ]; then
        ok "Schreibschutz ist bereits aktiv. Nichts zu tun."
        return
    fi

    info "Aktiviere OverlayFS (Read-Only Dateisystem)..."
    sudo raspi-config nonint do_overlayfs 0
    ok "OverlayFS aktiviert"

    info "Aktiviere Boot-Partition Schreibschutz..."
    sudo raspi-config nonint do_boot_ro 0 2>/dev/null || true
    ok "Boot-Partition schreibgeschützt"

    echo ""
    echo "============================================="
    echo "  Schreibschutz wird nach Neustart aktiv!"
    echo "============================================="
    echo ""
    echo "  Neustart mit:  sudo reboot"
    echo ""
    echo "  Nach dem Neustart:"
    echo "  - SD-Karte ist vor Stromunterbrüchen geschützt"
    echo "  - Alle Änderungen gehen beim Neustart verloren"
    echo "  - Der Kalender funktioniert normal weiter"
    echo ""
    warn "Für Wartung (Updates, .env ändern etc.) zuerst entsperren:"
    echo "  ./protect.sh unlock && sudo reboot"
    echo ""
}

do_unlock() {
    echo ""
    echo "============================================="
    echo "  SD-Karten-Schutz deaktivieren"
    echo "============================================="
    echo ""

    local status=$(get_status)
    if [ "$status" = "unlocked" ]; then
        ok "Schreibschutz ist bereits deaktiviert. Nichts zu tun."
        return
    fi

    info "Deaktiviere OverlayFS..."
    sudo raspi-config nonint do_overlayfs 1
    ok "OverlayFS deaktiviert"

    info "Deaktiviere Boot-Partition Schreibschutz..."
    sudo raspi-config nonint do_boot_ro 1 2>/dev/null || true
    ok "Boot-Partition beschreibbar"

    echo ""
    echo "============================================="
    echo "  Schreibschutz wird nach Neustart deaktiviert!"
    echo "============================================="
    echo ""
    echo "  Neustart mit:  sudo reboot"
    echo ""
    echo "  Nach dem Neustart:"
    echo "  - Dateisystem ist wieder beschreibbar"
    echo "  - Updates und Änderungen möglich"
    echo "  - git pull, .env bearbeiten etc."
    echo ""
    warn "Nach der Wartung wieder sichern:"
    echo "  ./protect.sh lock && sudo reboot"
    echo ""
}

# --- Hauptprogramm ---
case "${1:-}" in
    lock)
        do_lock
        ;;
    unlock)
        do_unlock
        ;;
    status)
        show_status
        ;;
    *)
        echo ""
        echo "Verwendung:  ./protect.sh <befehl>"
        echo ""
        echo "Befehle:"
        echo "  lock     Schreibschutz aktivieren (SD-Karte sichern)"
        echo "  unlock   Schreibschutz deaktivieren (für Wartung)"
        echo "  status   Aktuellen Status anzeigen"
        echo ""
        echo "Beispiel:"
        echo "  ./protect.sh lock && sudo reboot"
        echo ""
        ;;
esac
