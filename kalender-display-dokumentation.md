# Raspberry Pi Wochenkalender-Display

Dokumentation für das Schreinerei-Kalender-Display auf Basis eines Raspberry Pi 4 und Microsoft 365.

**Repository:** https://github.com/sg-vpbx/atis-kalenderanzeige

---

## 1. Überblick

Ein Raspberry Pi 4 zeigt im Vollbild-Modus den Wochenkalender des Ressourcenpostfachs `schreinerei@atissa.ch` an. Die Anzeige aktualisiert sich automatisch alle zwei Minuten und startet ohne manuelles Zutun, sobald der Pi mit Strom versorgt wird.

### Funktionen

- **Aktuelle Woche** — Standardansicht mit 7-Tage-Kalender
- **4-Wochen-Übersicht** — 4 Wochen als 2×2-Grid (je ein Viertel des Displays)
- **2-Monats-Übersicht (aktuell + nächster Monat)** — Outlook-Stil, Kacheln pro Tag mit Termintiteln (ohne Zeit)
- **2-Monats-Übersicht (übernächster + folgender Monat)** — gleicher Stil, Monate +2 und +3
- **Pfeiltasten-Navigation** — Wechsel zwischen den Ansichten per Tastatur
- **Kategorienfarben** — Termine farblich nach Outlook-Kategorie
- **Live-Uhrzeit** und **"Jetzt"-Linie** im heutigen Tag

### Architektur

- **Backend (Python/Flask):** Authentifiziert sich via Microsoft Graph API (Client Credentials Flow) und holt die Kalenderereignisse
- **Frontend (HTML/JavaScript):** Rendert den Kalender mit nebeneinander angeordneten Parallelterminen, Kategorienfarben und Live-Uhrzeit
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

System:

```
python3-pip, python3-venv, python3-full, git,
chromium, swayidle
```

Python (in `venv`):

```
flask, msal, requests, pytz, python-dotenv
```

---

## 4. Projekt-Struktur

### Repository

```
atis-kalenderanzeige/
├── app.py                    # Flask Backend
├── index.html                # Wochenkalender-Frontend
├── requirements.txt          # Python-Abhängigkeiten
├── install.sh                # Automatisches Installations-Script
├── .env.example              # Vorlage für Zugangsdaten
├── protect.sh                # SD-Karten-Schutz (lock/unlock)
├── update.sh                 # Update-Script (Git pull + Service-Neustart)
├── config/
│   ├── kalender.service      # systemd-Service
│   ├── labwc-autostart       # Chromium Kiosk-Autostart
│   ├── labwc-environment     # Cursor-Grösse (1px Fallback)
│   ├── labwc-rc.xml          # labwc Basis-Config
│   └── kiosk-policy.json     # Chromium-Policies
└── kalender-display-dokumentation.md
```

### Auf dem Raspberry Pi

```
/home/admin/kalender-display/
├── .env                      # Azure-Zugangsdaten (chmod 600)
├── app.py                    # Flask Backend
├── index.html                # Wochenkalender-Frontend
├── requirements.txt          # Python-Abhängigkeiten
└── venv/                     # Python Virtual Environment
```

### Systemdateien (vom Install-Script angelegt)

```
/etc/systemd/system/kalender.service          # Backend-Service
/home/admin/.config/labwc/autostart           # Chromium-Autostart
/home/admin/.config/labwc/rc.xml              # Cursor-Verhalten
/etc/chromium/policies/managed/kiosk-policy.json  # Chromium-Policies
```

---

## 5. Installation

### Schnellinstallation (empfohlen)

Auf dem Raspberry Pi als User `admin`:

```bash
# Repository klonen
cd ~
git clone https://github.com/sg-vpbx/atis-kalenderanzeige.git kalender-display
cd kalender-display

# Zugangsdaten eintragen
cp .env.example .env
nano .env
# → TENANT_ID, CLIENT_ID, CLIENT_SECRET eintragen

# Installation starten
chmod +x install.sh
./install.sh

# Neustart
sudo reboot
```

Nach dem Reboot startet der Kalender automatisch im Vollbild.

### Manuelle Installation

Falls das Install-Script nicht verwendet wird:

1. **Pakete installieren:**
   ```bash
   sudo apt-get update
   sudo apt-get install -y python3-pip python3-venv python3-full git chromium swayidle
   ```

2. **Repository klonen und venv einrichten:**
   ```bash
   cd ~
   git clone https://github.com/sg-vpbx/atis-kalenderanzeige.git kalender-display
   cd kalender-display
   python3 -m venv venv
   venv/bin/pip install -r requirements.txt
   ```

3. **Zugangsdaten:**
   ```bash
   cp .env.example .env
   nano .env
   chmod 600 .env
   ```

4. **systemd-Service:**
   ```bash
   sudo cp config/kalender.service /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable kalender.service
   sudo systemctl start kalender.service
   ```

5. **labwc Konfiguration:**
   ```bash
   mkdir -p ~/.config/labwc
   cp config/labwc-autostart ~/.config/labwc/autostart
   chmod +x ~/.config/labwc/autostart
   cp config/labwc-rc.xml ~/.config/labwc/rc.xml
   ```

6. **Chromium Policies:**
   ```bash
   sudo mkdir -p /etc/chromium/policies/managed
   sudo cp config/kiosk-policy.json /etc/chromium/policies/managed/
   ```

7. **Screen Blanking deaktivieren:**
   ```bash
   sudo raspi-config nonint do_blanking 1
   ```

8. **Neustart:**
   ```bash
   sudo reboot
   ```

### Update vom Git-Repository

```bash
cd ~/kalender-display
git pull
sudo systemctl restart kalender.service
# Browser lädt automatisch nach spätestens 1 Stunde neu,
# oder F5 drücken für sofortigen Reload
```

---

## 6. Konfigurationsdateien

### `.env`

```
TENANT_ID=<Azure Tenant ID>
CLIENT_ID=<App Client ID>
CLIENT_SECRET=<Client Secret>
CALENDAR_USER=schreinerei@atissa.ch
```

Rechte: `chmod 600 .env` (nur `admin` kann lesen).

### `config/kalender.service`

systemd-Service-Definition. Startet das Flask-Backend beim Boot und hält es am Laufen.

### `config/labwc-autostart`

Startet nach 15 Sekunden Boot-Verzögerung Chromium im Kiosk-Modus. Deaktiviert Screen-Standby via `swayidle`.

### `config/labwc-environment`

Setzt `XCURSOR_SIZE=1` — macht den Cursor systemweit so klein wie möglich (1 Pixel). Dient als Fallback, falls der CSS-basierte Cursor-Hiding nicht greift (z.B. in den 15 Sekunden vor dem Chromium-Start). Innerhalb von Chromium wird der Cursor über die CSS-Regel `cursor: none !important` in `index.html` komplett versteckt.

### `config/labwc-rc.xml`

Basis-Konfiguration für labwc. Cursor-Hiding wird **nicht** über rc.xml gesteuert (labwc unterstützt keine Cursor-Optionen in rc.xml), sondern über die `environment`-Datei und CSS.

### `config/kiosk-policy.json`

Deaktiviert Chromium-Features die im Kiosk-Modus stören (Übersetzung, Standardbrowser-Abfrage, Telemetrie).

---

## 7. Betrieb & Bedienung

### Ansichten

| Ansicht | Beschreibung |
|---|---|
| Aktuelle Woche | Standardansicht, Montag bis Sonntag der aktuellen Woche |
| 4-Wochen-Übersicht | 4 Wochen als 2×2-Grid, je ein Viertel des Displays |
| 2-Monats-Übersicht (Monat 1+2) | Outlook-Stil: aktueller + nächster Monat als Kacheln-Raster, Termintitel ohne Zeit |
| 2-Monats-Übersicht (Monat 3+4) | Gleicher Stil, übernächster + folgender Monat |

### Navigation (Pfeiltasten)

- **Pfeiltaste rechts:** Aktuelle Woche → 4-Wochen → Monat 1+2 → Monat 3+4 → Aktuelle Woche
- **Pfeiltaste links:** umgekehrte Reihenfolge

Die aktuelle Ansicht wird im Header angezeigt.

### Anzeigezeit

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

**Eigene Kategorien hinzufügen:** In `index.html` das `CATEGORY_COLORS`-Objekt erweitern:

```javascript
const CATEGORY_COLORS = {
  "Projekt Meier": "#ff5733",
  ...
};
```

---

## 8. Wartung & Troubleshooting

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

**Nach Änderungen in `index.html`:**
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

## 9. Wichtige Termine

### Client Secret Ablauf

**Das Client Secret läuft 24 Monate nach Erstellung ab.** Notiere dir den Ablauftermin und richte einen Erinnerungstermin **2 Wochen vor Ablauf** ein.

Bei Ablauf schlägt die Authentifizierung fehl und das Display zeigt einen Fehler. Dann:

1. Im Azure Portal unter *App Registration → Certificates & secrets* ein neues Secret erstellen
2. Value sofort kopieren (wird nur einmal angezeigt!)
3. Auf dem Pi in `.env` den alten Wert bei `CLIENT_SECRET` ersetzen
4. `sudo systemctl restart kalender.service`

---

## 10. Sicherheit

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

## 11. SD-Karten-Schutz (OverlayFS)

Der Pi ist eine reine Anzeige — **alle Kalenderdaten liegen bei Microsoft**, nicht lokal. Bei einem Stromausfall können jedoch Systemdateien auf der SD-Karte beschädigt werden.

### Lösung: Read-Only Dateisystem

Das mitgelieferte Script `protect.sh` nutzt OverlayFS von Raspberry Pi OS, um das gesamte Dateisystem schreibgeschützt zu machen. Alle Schreibvorgänge landen in einem temporären RAM-Overlay und gehen beim Neustart verloren — die SD-Karte wird nie beschrieben.

### Sichern (nach fertiger Konfiguration)

```bash
cd ~/kalender-display
./protect.sh lock
sudo reboot
```

Nach dem Reboot ist die SD-Karte geschützt. Der Kalender funktioniert normal weiter, da er nur Daten von Microsoft liest und nichts lokal speichert.

### Entsperren (für Wartung)

Wenn Updates, .env-Änderungen oder andere Wartung nötig ist:

```bash
cd ~/atis-kalenderanzeige
./protect.sh unlock
sudo reboot
# ... Änderungen vornehmen ...
./protect.sh lock
sudo reboot
```

**Tipp:** Für reine Code-Updates (neue Version aus Git) gibt es das Script `update.sh`, das den ganzen Ablauf automatisiert — siehe nächster Abschnitt.

### Status prüfen

```bash
./protect.sh status
```

### Zusätzliche Empfehlungen

- Hochwertige SD-Karte verwenden (High Endurance / Industrial)
- Nach fertiger Einrichtung ein **Image der SD-Karte** ziehen (mit Win32DiskImager oder Raspberry Pi Imager), als Backup auf Windows-PC aufbewahren
- Bei Problemen: Image einfach zurückflashen — kein Neuaufbau der Konfiguration nötig

---

## 11a. Updates einspielen (`update.sh`)

Wenn am Code Änderungen gemacht und ins Git-Repo gepusht wurden, lassen sich diese mit `update.sh` auf den Pi bringen. Das Script kümmert sich automatisch um den OverlayFS-Schreibschutz.

### Workflow

**Am PC:** Änderungen committen und pushen.

```bash
git add .
git commit -m "..."
git push
```

**Am Pi (per SSH):**

```bash
cd ~/atis-kalenderanzeige
./update.sh
```

### Was das Script macht

1. **Status prüfen:** Ist der Schreibschutz aktiv?
   - **Wenn ja:** Schreibschutz deaktivieren + Reboot. Nach dem Neustart `update.sh` einfach erneut ausführen.
   - **Wenn nein:** weiter mit Schritt 2.
2. **Git Pull** im Repo-Verzeichnis.
3. **App-Dateien kopieren** (`app.py`, `index.html`, `requirements.txt`) nach `/home/admin/kalender-display/`.
4. **Python-Abhängigkeiten** aktualisieren (falls `requirements.txt` geändert wurde).
5. **Config-Dateien** aktualisieren (systemd-Service, labwc, Chromium-Policies).
6. **kalender.service** neustarten und Backend testen.
7. **Schreibschutz wieder aktivieren?** — interaktive Abfrage am Ende. Bei „ja" → lock + reboot.

### Beispiel-Ablauf bei aktivem Schreibschutz

```bash
$ ./update.sh
[WARN]  SD-Karten-Schutz ist AKTIV — Update nicht möglich.
Fortfahren? [j/N] j
[INFO]  Deaktiviere Schreibschutz...
[INFO]  Pi startet in 5 Sekunden neu...
# → Pi rebootet, neu einloggen, nochmal ausführen:

$ ./update.sh
[OK]    Schreibschutz ist inaktiv — Update kann durchgeführt werden.
[INFO]  Hole Änderungen aus Git...
...
Schreibschutz wieder aktivieren? [j/N] j
Pi jetzt neu starten? [j/N] j
```

---

## 12. Quick Reference

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

### SD-Karten-Schutz
```bash
./protect.sh status    # Status anzeigen
./protect.sh lock      # Schreibschutz aktivieren (+ reboot)
./protect.sh unlock    # Schreibschutz deaktivieren (+ reboot)
```

### Updates einspielen
```bash
cd ~/atis-kalenderanzeige
./update.sh            # Git pull + Service-Neustart (Schreibschutz wird automatisch berücksichtigt)
```

### Browser im Kiosk steuern (mit Tastatur am Pi)
- **Pfeiltaste rechts** — Nächste Ansicht
- **Pfeiltaste links** — Vorherige Ansicht
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

## 13. Kontakte & Ressourcen

- **Repository:** https://github.com/sg-vpbx/atis-kalenderanzeige
- **Microsoft Graph API Docs:** https://learn.microsoft.com/en-us/graph/api/calendar-list-calendarview
- **Azure Portal:** https://portal.azure.com
- **Microsoft 365 Admin Center:** https://admin.microsoft.com
- **Raspberry Pi Dokumentation:** https://www.raspberrypi.com/documentation/
