# Raspberry Pi Wochenkalender-Display

Dokumentation für das Schreinerei-Kalender-Display auf Basis eines Raspberry Pi 4 und Microsoft 365.

---

## 1. Überblick

Ein Raspberry Pi 4 zeigt im Vollbild-Modus den Wochenkalender des Ressourcenpostfachs `schreinerei@atissa.ch` an. Die Anzeige aktualisiert sich automatisch alle zwei Minuten und startet ohne manuelles Zutun, sobald der Pi mit Strom versorgt wird.

### Architektur

- **Backend (Python/Flask):** Authentifiziert sich via Microsoft Graph API (Client Credentials Flow) und holt die Kalenderereignisse der aktuellen Woche
- **Frontend (HTML/JavaScript):** Rendert einen Wochenkalender mit nebeneinander angeordneten Parallelterminen, Kategorienfarben und Live-Uhrzeit
- **Chromium Kiosk:** Startet automatisch beim Boot und zeigt das Frontend im Vollbild
- **systemd-Service:** Hält das Backend permanent am Laufen und startet es nach Reboots automatisch

### Datenfluss

```
Outlook / Teams  →  Microsoft 365  →  Graph API  →  Pi Backend  →  Browser  →  Monitor
```

---

## 2. Azure / Microsoft 365 Konfiguration

### App Registration

Im Azure Portal (`portal.azure.com`) unter *Microsoft Entra ID → App registrations* wurde die App **"Raspberry Pi Kalender Display"** registriert.

| Eigenschaft | Wert |
|---|---|
| Name | Raspberry Pi Kalender Display |
| Supported account types | Single tenant |
| Tenant ID | *(siehe `.env`-Datei auf dem Pi)* |
| Client ID | *(siehe `.env`-Datei auf dem Pi)* |
| Client Secret | *(siehe `.env`-Datei auf dem Pi)* |
| Secret-Ablauf | 24 Monate ab Erstellung |

### API-Berechtigungen

| Berechtigung | Typ | Status |
|---|---|---|
| `Calendars.Read` | Application | ✅ Admin consent erteilt |

Die App kann damit technisch alle Kalender im Tenant lesen, wird aber im Code auf `schreinerei@atissa.ch` festgenagelt.

### Ressourcenpostfach-Einstellungen

Für den Schreinerei-Kalender sind folgende Einstellungen aktiv (gesetzt per Exchange Online PowerShell):

```powershell
Set-CalendarProcessing -Identity "schreinerei@atissa.ch" `
  -AllowConflicts $true `
  -AllowRecurringMeetings $true `
  -BookingWindowInDays 365

Set-MailboxFolderPermission -Identity "schreinerei@atissa.ch:\Calendar" `
  -User Default `
  -AccessRights Editor
```

**Bedeutung:**
- `AllowConflicts = True` — Überlappende Termine sind erlaubt (mehrere Projekte parallel)
- `Default = Editor` — Alle Mitarbeitenden im Tenant können Termine anlegen, bearbeiten und löschen

---

## 3. Raspberry Pi Setup

### Hardware

- Raspberry Pi 4 Model B
- microSD-Karte
- Offizielles USB-C Netzteil
- Micro-HDMI → HDMI Kabel
- LAN-Kabel
- Monitor (via HDMI0, der Port näher am Strom-Anschluss)

### Betriebssystem

- **Raspberry Pi OS (64-bit)** auf Debian 13 (Trixie) Basis
- Window-Manager: **labwc** (Wayland)
- Hostname: `kalender-pi`
- Benutzername: `admin`

### System-Konfiguration

| Einstellung | Wert |
|---|---|
| Boot-Modus | Desktop GUI |
| Auto-Login | Aktiv (als `admin`) |
| Screen Blanking | Deaktiviert |
| Zeitzone | Europe/Zurich |
| Tastaturlayout | ch |

### Installierte Pakete

```
python3-pip, python3-venv, python3-full, git,
chromium, unclutter, swayidle
```

Python-Pakete (in `~/kalender-display/venv`):

```
flask, msal, requests, python-dateutil, pytz, python-dotenv
```

---

## 4. Projekt-Struktur

```
/home/admin/kalender-display/
├── .env                      # Azure-Zugangsdaten (chmod 600)
├── app.py                    # Flask Backend
├── venv/                     # Python Virtual Environment
└── templates/
    └── index.html            # Wochenkalender-Frontend
```

### Wichtige Systemdateien

```
/etc/systemd/system/kalender.service          # Backend-Service
/home/admin/.config/labwc/autostart           # Chromium-Autostart
/home/admin/.config/labwc/rc.xml              # Cursor-Verhalten
/etc/chromium/policies/managed/kiosk-policy.json  # Chromium-Policies
```

---

## 5. Konfigurationsdateien

### `.env`

```
TENANT_ID=<Azure Tenant ID>
CLIENT_ID=<App Client ID>
CLIENT_SECRET=<Client Secret>
CALENDAR_USER=schreinerei@atissa.ch
```

Rechte: `chmod 600 .env` (nur `admin` kann lesen).

### `/etc/systemd/system/kalender.service`

```ini
[Unit]
Description=Kalender Backend
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=admin
WorkingDirectory=/home/admin/kalender-display
EnvironmentFile=/home/admin/kalender-display/.env
ExecStart=/home/admin/kalender-display/venv/bin/python /home/admin/kalender-display/app.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

### `~/.config/labwc/autostart`

```bash
# Bildschirm nicht in Standby schicken
swayidle -w timeout 1 'echo idle_disabled' &

# 15 Sekunden warten, dann Chromium im Kiosk-Modus starten
(sleep 15 && chromium \
  --kiosk \
  --noerrdialogs \
  --disable-infobars \
  --disable-session-crashed-bubble \
  --disable-features=Translate,TranslateUI \
  --disable-translate \
  --no-first-run \
  --no-default-browser-check \
  --check-for-update-interval=31536000 \
  --start-fullscreen \
  --password-store=basic \
  --lang=de-CH \
  http://localhost:5000) &
```

### `~/.config/labwc/rc.xml`

```xml
<?xml version="1.0" ?>
<labwc_config>
  <cursor>
    <hideOnKeypress>yes</hideOnKeypress>
    <hideInactive>yes</hideInactive>
    <hideInactiveDelay>1</hideInactiveDelay>
  </cursor>
</labwc_config>
```

### `/etc/chromium/policies/managed/kiosk-policy.json`

```json
{
  "TranslateEnabled": false,
  "DefaultBrowserSettingEnabled": false,
  "MetricsReportingEnabled": false
}
```

---

## 6. Betrieb & Bedienung

### Anzeigezeit

- Wochenansicht Montag bis Sonntag
- Zeitbereich: **6:00 bis 20:00 Uhr** (konfigurierbar in `index.html` via `START_HOUR` und `END_HOUR`)
- Live-Anzeige der aktuellen Uhrzeit oben rechts
- "Jetzt"-Linie (rot) im heutigen Tag
- Heutiger Tag farblich hervorgehoben

### Aktualisierung

- Daten werden alle **2 Minuten** neu geladen
- Die ganze Seite wird stündlich neu geladen (Sicherheitsmassnahme gegen Browser-Memory-Leaks)

### Termine eintragen

Die Mitarbeiter fügen `schreinerei@atissa.ch` als zusätzlichen Kalender in Outlook hinzu:

1. Outlook öffnen → Kalender
2. "Kalender hinzufügen" / "Add calendar"
3. "Aus Verzeichnis" / "From directory"
4. `schreinerei@atissa.ch` eingeben

Danach können sie direkt im Schreinerei-Kalender Termine anlegen, verschieben und löschen.

### Kategorienfarben

Im Frontend sind folgende Outlook-Standardkategorien mit Farben verknüpft:

| Outlook-Kategorie | Farbe im Display |
|---|---|
| Rot | Rosa-Rot |
| Orange | Orange |
| Gelb | Gelb |
| Grün | Grün |
| Blau (Standard) | Hellblau |
| Violett | Violett |
| Türkis | Türkis |
| Grau | Grau |

Termine ohne Kategorie werden standardmässig blau dargestellt.

**Eigene Kategorien hinzufügen:** In `templates/index.html` das `CATEGORY_COLORS`-Objekt erweitern:

```javascript
const CATEGORY_COLORS = {
  "Projekt Meier": "#ff5733",
  ...
};
```

---

## 7. Wartung & Troubleshooting

### Status prüfen

SSH-Verbindung zum Pi:

```bash
ssh admin@<Pi-IP>
```

Backend-Status:

```bash
sudo systemctl status kalender.service
```

Backend-Logs live mitverfolgen:

```bash
sudo journalctl -u kalender.service -f
```

API-Test direkt auf dem Pi:

```bash
curl http://localhost:5000/api/events
```

### Backend neu starten

```bash
sudo systemctl restart kalender.service
```

### Chromium neu laden (ohne Reboot)

Tastatur am Pi anschliessen und **F5** drücken.

### Kompletter Reboot

```bash
sudo reboot
```

### Code ändern

**Nach Änderungen in `app.py`:**

```bash
sudo systemctl restart kalender.service
```

**Nach Änderungen in `templates/index.html`:**
Kein Neustart nötig — im Browser einfach F5 drücken oder den nächsten automatischen Reload abwarten (max. 1 Stunde).

**Nach Änderungen in `.env`:**

```bash
sudo systemctl restart kalender.service
```

### Häufige Probleme

| Problem | Ursache | Lösung |
|---|---|---|
| Seite zeigt "Fehler: ..." | Backend läuft nicht oder hat Auth-Problem | `systemctl status kalender.service` prüfen, Logs anschauen |
| `AADSTS700016` im Log | Client/Tenant-ID vertauscht | `.env` prüfen |
| `401 Unauthorized` im Log | Client Secret abgelaufen | Neues Secret in Azure erstellen, `.env` aktualisieren |
| `403 Forbidden` im Log | Admin consent fehlt | Im Azure Portal bei API permissions "Grant admin consent" klicken |
| `404 Not Found` im Log | Kalender-User-Adresse falsch | `CALENDAR_USER` in `.env` prüfen |
| Bildschirm schwarz | Screen Blanking aktiv | `sudo raspi-config` → Display Options → Screen Blanking → No |
| Kalender veraltet | Browser-Cache | Autorefresh läuft stündlich, manuell F5 |

---

## 8. Wichtige Termine

### Client Secret Ablauf

**Das Client Secret läuft 24 Monate nach Erstellung ab.** Notiere dir den Ablauftermin und richte einen Erinnerungstermin **2 Wochen vor Ablauf** ein.

Bei Ablauf schlägt die Authentifizierung fehl und das Display zeigt einen Fehler. Dann:

1. Im Azure Portal unter *App Registration → Certificates & secrets* ein neues Secret erstellen
2. Value sofort kopieren (wird nur einmal angezeigt!)
3. Auf dem Pi in `.env` den alten Wert bei `CLIENT_SECRET` ersetzen
4. `sudo systemctl restart kalender.service`

---

## 9. Sicherheit

### Was gut geschützt ist

- `.env` ist `chmod 600` — nur `admin` kann die Zugangsdaten lesen
- SSH-Passwort statt Standardpasswort
- Backend hört nur lokal (`0.0.0.0:5000`) — nicht aus dem Internet erreichbar
- Client Secret statt Zertifikat ist OK, solange die SD-Karte physisch sicher liegt

### Was man zusätzlich tun könnte

- **SSH auf Key-Authentifizierung umstellen** (sicherer als Passwort)
- **Firewall (`ufw`) einrichten**, nur SSH und Port 5000 im lokalen Netz erlauben
- **ApplicationAccessPolicy in Exchange** auf genau `schreinerei@atissa.ch` einschränken (aktuell nicht gesetzt — die App könnte technisch auf alle Kalender zugreifen, wenn jemand den Code manipuliert)
- **Fail2ban** gegen SSH-Brute-Force

---

## 10. Stromausfall & Datensicherheit

Der Pi ist eine reine Anzeige — **alle Kalenderdaten liegen bei Microsoft**, nicht lokal. Bei einem Stromausfall können nur Systemdateien auf der SD-Karte beschädigt werden.

**Empfehlungen:**
- Hochwertige SD-Karte verwenden (High Endurance / Industrial)
- Nach fertiger Einrichtung ein **Image der SD-Karte** ziehen (mit Win32DiskImager oder Raspberry Pi Imager), als Backup auf Windows-PC aufbewahren
- Bei Problemen: Image einfach zurückflashen — kein Neuaufbau der Konfiguration nötig
- Optional: USV (Unterbrechungsfreie Stromversorgung) für den Pi

---

## 11. Quick Reference

### SSH-Zugriff
```bash
ssh admin@<Pi-IP>
```

### Service-Verwaltung
```bash
sudo systemctl status kalender.service
sudo systemctl restart kalender.service
sudo systemctl stop kalender.service
sudo systemctl start kalender.service
```

### Logs
```bash
sudo journalctl -u kalender.service -f
sudo journalctl -u kalender.service --since "1 hour ago"
```

### Browser im Kiosk steuern (mit Tastatur am Pi)
- **F5** — Seite neu laden
- **F11** — Vollbild toggeln
- **Alt+F4** — Chromium schliessen (Autostart bringt ihn beim Reboot zurück)
- **Strg+Alt+T** — Terminal öffnen (falls XTerm installiert)

### Browser-URL
```
http://localhost:5000
```

### Vom Windows-PC aus testen (im selben Netz)
```
http://<Pi-IP>:5000
```

---

## 12. Kontakte & Ressourcen

- **Microsoft Graph API Docs:** https://learn.microsoft.com/en-us/graph/api/calendar-list-calendarview
- **Azure Portal:** https://portal.azure.com
- **Microsoft 365 Admin Center:** https://admin.microsoft.com
- **Raspberry Pi Dokumentation:** https://www.raspberrypi.com/documentation/
