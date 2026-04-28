#!/bin/bash
# =============================================================================
# Kalender-Display Installationsscript
# Automatisierte Einrichtung auf Raspberry Pi OS (Debian Trixie, 64-bit)
# =============================================================================
set -e

APP_DIR="/home/admin/kalender-display"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
USER="admin"

# --- Farbige Ausgabe ---
info()  { echo -e "\e[34m[INFO]\e[0m  $1"; }
ok()    { echo -e "\e[32m[OK]\e[0m    $1"; }
warn()  { echo -e "\e[33m[WARN]\e[0m  $1"; }
error() { echo -e "\e[31m[ERROR]\e[0m $1"; exit 1; }

# --- Root-Check ---
if [ "$EUID" -eq 0 ]; then
    error "Bitte NICHT als root ausführen. Starte das Script als User 'admin'."
fi

if [ "$(whoami)" != "$USER" ]; then
    warn "Script wird als '$(whoami)' ausgeführt, erwartet '$USER'."
fi

echo ""
echo "============================================="
echo "  Kalender-Display Installation"
echo "============================================="
echo ""

# =============================================================================
# 1. Raspberry Pi Grundkonfiguration
# =============================================================================
info "Raspberry Pi Grundkonfiguration..."
if command -v raspi-config &> /dev/null; then
    # Desktop-Modus mit Auto-Login aktivieren
    sudo raspi-config nonint do_boot_behaviour B4
    ok "Boot-Modus: Desktop GUI mit Auto-Login"

    # Zeitzone setzen
    sudo timedatectl set-timezone Europe/Zurich
    ok "Zeitzone: Europe/Zurich"

    # Tastaturlayout Schweiz
    sudo raspi-config nonint do_configure_keyboard ch 2>/dev/null || true
    ok "Tastaturlayout: ch"

    # Screen Blanking deaktivieren
    sudo raspi-config nonint do_blanking 1 2>/dev/null || true
    ok "Screen Blanking deaktiviert"
else
    warn "raspi-config nicht gefunden — Pi-Grundkonfiguration manuell vornehmen"
    warn "  → Boot: Desktop GUI + Auto-Login"
    warn "  → Zeitzone: Europe/Zurich"
    warn "  → Tastatur: ch"
fi

# =============================================================================
# 2. Systempakete installieren
# =============================================================================
info "Systempakete installieren..."
sudo apt-get update -qq
sudo apt-get install -y -qq python3-pip python3-venv python3-full git chromium swayidle
ok "Systempakete installiert"

# =============================================================================
# 3. Projektverzeichnis einrichten
# =============================================================================
info "Projektverzeichnis einrichten..."
if [ "$SCRIPT_DIR" != "$APP_DIR" ]; then
    mkdir -p "$APP_DIR"
    cp "$SCRIPT_DIR/app.py" "$APP_DIR/"
    cp "$SCRIPT_DIR/index.html" "$APP_DIR/"
    cp "$SCRIPT_DIR/requirements.txt" "$APP_DIR/"
    ok "Dateien nach $APP_DIR kopiert"
else
    ok "Script wird bereits aus $APP_DIR ausgeführt"
fi

# =============================================================================
# 4. .env prüfen
# =============================================================================
if [ ! -f "$APP_DIR/.env" ]; then
    if [ -f "$SCRIPT_DIR/.env" ]; then
        cp "$SCRIPT_DIR/.env" "$APP_DIR/.env"
    else
        cp "$SCRIPT_DIR/.env.example" "$APP_DIR/.env"
        warn ".env wurde aus .env.example erstellt — bitte Werte eintragen!"
        warn "Datei: $APP_DIR/.env"
    fi
fi
chmod 600 "$APP_DIR/.env"
ok ".env vorhanden (chmod 600)"

# =============================================================================
# 5. Python Virtual Environment & Abhängigkeiten
# =============================================================================
info "Python venv einrichten..."
if [ ! -d "$APP_DIR/venv" ]; then
    python3 -m venv "$APP_DIR/venv"
fi
"$APP_DIR/venv/bin/pip" install --quiet --upgrade pip
"$APP_DIR/venv/bin/pip" install --quiet -r "$APP_DIR/requirements.txt"
ok "Python-Abhängigkeiten installiert"

# =============================================================================
# 6. systemd-Service einrichten
# =============================================================================
info "systemd-Service einrichten..."
sudo cp "$SCRIPT_DIR/config/kalender.service" /etc/systemd/system/kalender.service
sudo systemctl daemon-reload
sudo systemctl enable kalender.service
sudo systemctl restart kalender.service
ok "kalender.service aktiviert und gestartet"

# =============================================================================
# 7. labwc Konfiguration (Autostart + Cursor)
# =============================================================================
info "labwc Konfiguration einrichten..."
LABWC_DIR="/home/$USER/.config/labwc"
mkdir -p "$LABWC_DIR"

# Autostart: bestehende Datei sichern, dann unsere setzen
if [ -f "$LABWC_DIR/autostart" ] && ! grep -q "kalender" "$LABWC_DIR/autostart" 2>/dev/null; then
    cp "$LABWC_DIR/autostart" "$LABWC_DIR/autostart.bak"
    warn "Bestehende autostart gesichert als autostart.bak"
fi
cp "$SCRIPT_DIR/config/labwc-autostart" "$LABWC_DIR/autostart"
chmod +x "$LABWC_DIR/autostart"

# rc.xml
cp "$SCRIPT_DIR/config/labwc-rc.xml" "$LABWC_DIR/rc.xml"

# environment: Cursor minimal (1px Fallback)
cp "$SCRIPT_DIR/config/labwc-environment" "$LABWC_DIR/environment"

ok "labwc Autostart, Cursor und Environment installiert"

# =============================================================================
# 8. Chromium Kiosk-Policies
# =============================================================================
info "Chromium Policies einrichten..."
sudo mkdir -p /etc/chromium/policies/managed
sudo cp "$SCRIPT_DIR/config/kiosk-policy.json" /etc/chromium/policies/managed/kiosk-policy.json
ok "Chromium Kiosk-Policies installiert"

# =============================================================================
# 9. Backend-Test
# =============================================================================
info "Warte auf Backend-Start..."
sleep 3
if curl -s --max-time 5 http://localhost:5000/api/events > /dev/null 2>&1; then
    ok "Backend antwortet auf http://localhost:5000"
else
    warn "Backend antwortet noch nicht — prüfe mit: sudo systemctl status kalender.service"
fi

# =============================================================================
# Fertig
# =============================================================================
echo ""
echo "============================================="
echo "  Installation abgeschlossen!"
echo "============================================="
echo ""
echo "Nächste Schritte:"
echo "  1. .env-Datei prüfen:  nano $APP_DIR/.env"
echo "  2. Service neustarten: sudo systemctl restart kalender.service"
echo "  3. Browser testen:     http://localhost:5000"
echo "  4. Neustart:           sudo reboot"
echo ""
echo "Bedienung:"
echo "  Pfeiltaste rechts  → Nächste Ansicht"
echo "  Pfeiltaste links   → Vorherige Ansicht"
echo "  Ansichten: Aktuelle Woche → 4-Wochen → 8-Wochen (W1–8) → 8-Wochen (W9–16)"
echo ""
