#!/bin/bash
# =============================================================================
# Kalender-Display Update-Script
#
# Zieht neue Änderungen aus dem Git-Repo, installiert sie und startet
# den Service neu. Berücksichtigt automatisch den OverlayFS-Schreibschutz:
#
# - Wenn gesperrt:    entsperrt + Neustart, danach Script erneut ausführen
# - Wenn entsperrt:   Update durchführen, am Ende optional wieder sperren
#
# Verwendung:
#   ./update.sh
# =============================================================================
set -e

APP_DIR="/home/admin/kalender-display"
USER="admin"

# --- Schutz gegen Selbstmodifikation während git pull ---
# Bash liest Scripts in Blöcken; wenn sich das Script während pull ändert,
# kann das undefiniertes Verhalten geben. Daher einmal nach /tmp kopieren
# und von dort re-exec'en. SCRIPT_DIR wird via env vom Original übernommen.
if [ "${UPDATE_SH_INTMP:-}" != "1" ]; then
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    TMPCOPY="/tmp/update.sh.$$"
    cp "$0" "$TMPCOPY"
    chmod +x "$TMPCOPY"
    UPDATE_SH_INTMP=1 SCRIPT_DIR="$SCRIPT_DIR" exec "$TMPCOPY" "$@"
fi
# Ab hier: wir laufen aus /tmp, SCRIPT_DIR zeigt aufs Repo (via env).
trap 'rm -f "$0"' EXIT

# --- Farbige Ausgabe ---
info()  { echo -e "\e[34m[INFO]\e[0m  $1"; }
ok()    { echo -e "\e[32m[OK]\e[0m    $1"; }
warn()  { echo -e "\e[33m[WARN]\e[0m  $1"; }
error() { echo -e "\e[31m[ERROR]\e[0m $1"; exit 1; }

# --- Root-Check ---
if [ "$EUID" -eq 0 ]; then
    error "Bitte NICHT als root ausführen. Starte das Script als User '$USER'."
fi

# --- Lock-Status prüfen ---
# Wir prüfen den TATSÄCHLICH aktiven Mount, nicht nur die cmdline.txt-Config.
# Wenn das Root-FS auf "overlay" läuft, gehen alle Änderungen beim Reboot verloren —
# das ist die einzig zuverlässige Quelle der Wahrheit.
get_lock_status() {
    if [ "$(findmnt -no FSTYPE / 2>/dev/null)" = "overlay" ]; then
        echo "locked"
    else
        echo "unlocked"
    fi
}

echo ""
echo "============================================="
echo "  Kalender-Display Update"
echo "============================================="
echo ""

LOCK_STATUS=$(get_lock_status)

# =============================================================================
# Phase 1: Wenn gesperrt → entsperren + Reboot
# =============================================================================
if [ "$LOCK_STATUS" = "locked" ]; then
    warn "SD-Karten-Schutz ist AKTIV — Update nicht möglich."
    echo ""
    echo "  Der Schreibschutz wird jetzt deaktiviert und der Pi startet neu."
    echo "  Nach dem Neustart bitte erneut ausführen:"
    echo ""
    echo "      cd $SCRIPT_DIR && ./update.sh"
    echo ""
    read -p "Fortfahren? [j/N] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Jj]$ ]]; then
        info "Abgebrochen."
        exit 0
    fi

    info "Deaktiviere Schreibschutz..."
    "$SCRIPT_DIR/protect.sh" unlock

    info "Pi startet in 5 Sekunden neu..."
    sleep 5
    sudo reboot
    exit 0
fi

# =============================================================================
# Phase 2: Entsperrt → Update durchführen
# =============================================================================
ok "Schreibschutz ist inaktiv — Update kann durchgeführt werden."
echo ""

# --- Git Pull ---
info "Hole Änderungen aus Git..."
cd "$SCRIPT_DIR"
git fetch
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse @{u} 2>/dev/null || echo "")

if [ -z "$REMOTE" ]; then
    error "Kein Remote-Branch konfiguriert. Bitte 'git pull' manuell prüfen."
fi

if [ "$LOCAL" = "$REMOTE" ]; then
    ok "Repo ist bereits auf dem neuesten Stand."
else
    git pull
    ok "Git-Pull erfolgreich"
fi

# --- Dateien immer kopieren ---
# Auch wenn Git aktuell ist: das App-Verzeichnis kann veraltet sein
# (z.B. wenn vorher manuell gepullt wurde). Kopieren ist günstig und idempotent.
info "Kopiere App-Dateien nach $APP_DIR..."
cp "$SCRIPT_DIR/app.py" "$APP_DIR/"
cp "$SCRIPT_DIR/index.html" "$APP_DIR/"
cp "$SCRIPT_DIR/requirements.txt" "$APP_DIR/"
ok "App-Dateien aktualisiert"

info "Prüfe Python-Abhängigkeiten..."
"$APP_DIR/venv/bin/pip" install --quiet -r "$APP_DIR/requirements.txt"
ok "Python-Abhängigkeiten aktuell"

info "Aktualisiere Konfigurationsdateien..."
sudo cp "$SCRIPT_DIR/config/kalender.service" /etc/systemd/system/kalender.service
sudo mkdir -p /etc/chromium/policies/managed
sudo cp "$SCRIPT_DIR/config/kiosk-policy.json" /etc/chromium/policies/managed/kiosk-policy.json

LABWC_DIR="/home/$USER/.config/labwc"
mkdir -p "$LABWC_DIR"
cp "$SCRIPT_DIR/config/labwc-autostart" "$LABWC_DIR/autostart"
chmod +x "$LABWC_DIR/autostart"
cp "$SCRIPT_DIR/config/labwc-rc.xml" "$LABWC_DIR/rc.xml"
cp "$SCRIPT_DIR/config/labwc-environment" "$LABWC_DIR/environment"
ok "Konfigurationsdateien aktualisiert"

info "Starte kalender.service neu..."
sudo systemctl daemon-reload
sudo systemctl restart kalender.service
sleep 3

if curl -s --max-time 5 http://localhost:5000/api/events > /dev/null 2>&1; then
    ok "Backend antwortet auf http://localhost:5000"
else
    warn "Backend antwortet noch nicht — prüfe mit:"
    warn "  sudo systemctl status kalender.service"
    warn "  journalctl -u kalender.service -n 50"
fi

# =============================================================================
# Phase 3: Schreibschutz wieder aktivieren?
# =============================================================================
echo ""
echo "============================================="
echo "  Update abgeschlossen"
echo "============================================="
echo ""
echo "Bitte jetzt das Display prüfen:"
echo "  - Alle 3 Ansichten testen (Pfeiltasten)"
echo "  - Termine werden korrekt angezeigt"
echo "  - Keine Fehlermeldungen"
echo ""
read -p "Schreibschutz wieder aktivieren? [j/N] " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Jj]$ ]]; then
    info "Aktiviere Schreibschutz..."
    "$SCRIPT_DIR/protect.sh" lock

    echo ""
    read -p "Pi jetzt neu starten? [j/N] " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Jj]$ ]]; then
        info "Pi startet in 5 Sekunden neu..."
        sleep 5
        sudo reboot
    else
        warn "Schreibschutz wird erst nach Neustart aktiv:  sudo reboot"
    fi
else
    warn "Schreibschutz bleibt INAKTIV."
    warn "Für Produktivbetrieb später aktivieren:  ./protect.sh lock && sudo reboot"
fi

echo ""
