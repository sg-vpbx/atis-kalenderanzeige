from flask import Flask, jsonify, render_template
from msal import ConfidentialClientApplication
from dotenv import load_dotenv
import requests
import os
from datetime import datetime, timedelta
import pytz

load_dotenv()

TENANT_ID     = os.getenv("TENANT_ID")
CLIENT_ID     = os.getenv("CLIENT_ID")
CLIENT_SECRET = os.getenv("CLIENT_SECRET")
CALENDAR_USER = os.getenv("CALENDAR_USER")
TIMEZONE      = "Europe/Zurich"

AUTHORITY = f"https://login.microsoftonline.com/{TENANT_ID}"
SCOPE     = ["https://graph.microsoft.com/.default"]

app = Flask(__name__)
msal_app = ConfidentialClientApplication(
    CLIENT_ID, authority=AUTHORITY, client_credential=CLIENT_SECRET
)

def get_token():
    result = msal_app.acquire_token_silent(SCOPE, account=None)
    if not result:
        result = msal_app.acquire_token_for_client(scopes=SCOPE)
    if "access_token" not in result:
        raise RuntimeError(f"Token-Fehler: {result.get('error_description')}")
    return result["access_token"]

def get_week_range():
    tz = pytz.timezone(TIMEZONE)
    now = datetime.now(tz)
    monday = now - timedelta(days=now.weekday())
    monday = monday.replace(hour=0, minute=0, second=0, microsecond=0)
    sunday = monday + timedelta(days=7)
    monday_utc = monday.astimezone(pytz.UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
    sunday_utc = sunday.astimezone(pytz.UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
    return monday_utc, sunday_utc

@app.route("/api/events")
def api_events():
    try:
        token = get_token()
        start, end = get_week_range()
        url = (
            f"https://graph.microsoft.com/v1.0/users/{CALENDAR_USER}/calendarView"
            f"?startDateTime={start}&endDateTime={end}"
            f"&$select=subject,start,end,location,organizer,isAllDay,categories,bodyPreview"
            f"&$orderby=start/dateTime&$top=200"
        )
        headers = {
            "Authorization": f"Bearer {token}",
            "Prefer": f'outlook.timezone="{TIMEZONE}"'
        }
        r = requests.get(url, headers=headers, timeout=15)
        r.raise_for_status()
        events = []
        for e in r.json().get("value", []):
            events.append({
                "subject":    (e.get("subject") or "").strip() or "(ohne Titel)",
                "start":      e["start"]["dateTime"],
                "end":        e["end"]["dateTime"],
                "location":   (e.get("location") or {}).get("displayName", ""),
                "organizer":  ((e.get("organizer") or {}).get("emailAddress") or {}).get("name", ""),
                "isAllDay":   e.get("isAllDay", False),
                "categories": e.get("categories", []),
                "preview":    e.get("bodyPreview", ""),
            })
        return jsonify({"ok": True, "events": events,
                        "weekStart": start, "weekEnd": end})
    except Exception as ex:
        return jsonify({"ok": False, "error": str(ex)}), 500

@app.route("/")
def index():
    return render_template("index.html")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
