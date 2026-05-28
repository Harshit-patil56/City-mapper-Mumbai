# 🧪 m-Indicator API — Live Test Report

> **Tested:** 2026-05-28 at 23:27 IST  
> **Method:** PowerShell `Invoke-WebRequest` with 10s timeout  
> **Total Endpoints Tested:** 32  
> **Machine:** Windows (no app authentication / device ID)

---

## 📊 Results Summary

| Status | Count | APIs |
|--------|-------|------|
| ✅ **Working** (200 + real data) | 7 | CDN config, Exhibition, Ferry, Metro, Food, Shopping, Manoranjan |
| ⚠️ **Live but Empty** (200 + no body) | 12 | Running status, Register, News, mTracker, Seat data, Places, etc. |
| 🔶 **Maintenance** (200 + HTML error) | 5 | All NTES endpoints |
| ❌ **Dead / Blocked** (4xx/5xx) | 8 | Regcheck, Cabs, Ads, AutoTaxi, Railofy, mTracker base, Jobs, HowToTravel |

---

## ✅ WORKING — Returns Real Data

### 1. CDN App Config
- **URL:** `https://cdn.mobond.com/mi/mi_config`
- **Status:** `200 OK` — 651 bytes
- **Verdict:** ✅ **LIVE & REAL DATA**
- **Actual Response:**
```json
{
  "dfp_ads": {
    "/79488325/dfpnativeadunit_trainsatstn": { "20200314": ["ALL"] },
    "/79488325/dfpnativeadunit_tracetrain":  { "20200314": ["ALL"] },
    "/79488325/dfpnativeadunit_youareat":    { "20200314": ["VASHI","GOVANDI","KURLA"] },
    "/79488325/dfpnativeadunit_promo": {
      "20260401": ["ALL"],
      "20260402": ["ALL"],
      "20260403": ["ALL"]
    }
  }
}
```
> ℹ️ Note: This endpoint returns **AdMob/DFP ad unit config**, not the full app config. The config file is binary/gzipped in the actual app.

---

### 2. Exhibition List
- **URL:** `https://mobond.com/getexhibitionlist?city=mumbai`
- **Status:** `200 OK` — 191 bytes
- **Verdict:** ✅ **LIVE & REAL DATA**
- **Actual Response:**
```json
{
  "alerts": [
    {
      "id": 7,
      "mode": "local",
      "date": "27 Jan 2021",
      "title": "List Your Exhibition Here",
      "content": "To list your Exhibition for FREE<br><br>Email: bharat.bhanushali@mobond.com"
    }
  ]
}
```
> ⚠️ Data is stale (Jan 2021) — server is live but no new exhibitions have been added.

---

### 3. Ferry Booking Page
- **URL:** `https://mobond.com/ferrybookingmumbai`
- **Status:** `200 OK`
- **Verdict:** ✅ **LIVE** (returns HTML WebView page)

---

### 4. Metro Recharge Page
- **URL:** `https://mobond.com/mumbaimetrorecharge?city=mumbai`
- **Status:** `200 OK`
- **Verdict:** ✅ **LIVE** (returns HTML WebView page)

---

### 5. Food Listings
- **URL:** `https://mobond.com/food/i.jsp?city=mumbai`
- **Status:** `200 OK`
- **Verdict:** ✅ **LIVE** (HTML page with food listings)

---

### 6. Shopping Page
- **URL:** `https://mobond.com/shopping/i.jsp?city=mumbai`
- **Status:** `200 OK`
- **Verdict:** ✅ **LIVE** (HTML page)

---

### 7. Entertainment / Manoranjan
- **URL:** `https://mobond.com/manoranjan?city=mumbai`
- **Status:** `200 OK`
- **Verdict:** ✅ **LIVE** (HTML entertainment listing page)

---

## ⚠️ LIVE BUT EMPTY — Server responds 200, body is blank

These endpoints are **online** and responding but return **no data body** from a browser/non-app context. They likely require a valid registered `deviceid` or the correct Android app headers (User-Agent, session token).

| # | API | URL | Status | Body | Likely Reason |
|---|-----|-----|--------|------|---------------|
| 1 | IR Running Status (Mobond) | `https://mobond.com/irgetrunningstatus?trainno=12215` | `200` | Empty | Requires app headers / deviceid |
| 2 | IR Running Status (HRD) | `https://mobondhrd.appspot.com/irgetrunningstatus?trainno=12215` | `200` | Empty | Same — app-only |
| 3 | Cancelled Trains | `https://mobondhrd.appspot.com/irgetcancelledtrains` | `200` | `null` | Returns `null` — no cancelled trains today OR requires headers |
| 4 | News Alerts | `https://mobond.com/getnewsalerts?city=mumbai` | `200` | Empty | Requires app headers |
| 5 | mTracker Volunteers | `https://mobond.com/mtracker/getvolunteers?trainno=12215` | `200` | Empty | Requires app headers |
| 6 | Register Device | `https://mobond.com/registermindicatoronlinev2?...` | `200` | Empty | Processes silently |
| 7 | IR Seat Data | `http://m.mobond.com/irgetseatdata?trainno=12215` | `200` | Empty | Requires app context |
| 8 | Picnic Spots | `https://mobond.com/picnicspots?city=mumbai` | `200` | HTML page | Returns generic HTML |
| 9 | Ferry Booking | `https://mobond.com/ferrybookingmumbai` | `200` | HTML | Returns WebView HTML |
| 10 | Metro | `https://mobond.com/mumbaimetrorecharge?city=mumbai` | `200` | HTML | Returns WebView HTML |
| 11 | Places | `https://mobond.com/places/i.jsp?city=mumbai` | `200` | Wikipedia-like HTML | Returns generic content |
| 12 | PNR Check | `http://m.mobond.com/pnrcheck?pnr=1234567890` | `204 No Content` | Empty | Invalid PNR → no content |

### 💡 How to Get Real Data from Empty Endpoints

These APIs likely need the Android app's User-Agent and possibly a registered device ID:

```http
GET /irgetrunningstatus?trainno=12215 HTTP/1.1
Host: mobond.com
User-Agent: Dalvik/2.1.0 (Linux; U; Android 13; Pixel 6 Build/TQ3A.230901.001)
X-Device-ID: <registered_deviceid>
```

---

## 🔶 MAINTENANCE — NTES (Indian Railways Govt)

All 5 NTES endpoints return `200 OK` with an HTML maintenance notice:

> **"Due to some technical activity this site will be un-available for some time.  
> Meanwhile passenger can use services of 139 for latest train running updates.  
> Inconvenience caused is deeply regretted."**

| API | URL | HTTP | Verdict |
|-----|-----|------|---------|
| NTES getTrainData | `/ntes/NTES?action=getTrainData&trainNo=12215` | 200 | 🔶 Maintenance |
| NTES SearchTrain | `/ntes/SearchTrain?trainNo=12215` | 200 | 🔶 Maintenance |
| NTES FutureTrain | `/ntes/FutureTrain?action=getTrainData&trainNo=12215` | 200 | 🔶 Maintenance |
| NTES getTrnBwStns | `/ntes/NTES?action=getTrnBwStns&stn1=MMCT&stn2=PUNE` | 200 | 🔶 Maintenance |
| NTES CRIS AppServAnd | `/crisntes/AppServAnd` | 200 | 🔶 Maintenance |

> **Call 139** for live train information via phone while the website is down.

---

## ❌ DEAD / BLOCKED

| # | API | URL | HTTP Code | Reason |
|---|-----|-----|-----------|--------|
| 1 | Regcheck Heartbeat | `https://mobond.com/regcheck?isping=true` | **404** | Endpoint removed/renamed |
| 2 | Get Cabs | `https://mobond.com/getcabs?city=mumbai` | **404** | Endpoint no longer exists |
| 3 | Auto Taxi Rating | `https://mobond.com/autotaxidriverrating?city=mumbai` | **404** | Endpoint removed |
| 4 | mTracker Base | `https://mobond.com/mtracker/` | **404** | Base path not routed |
| 5 | Get Ads | `https://mobond.com/getads?city=mumbai` | **403** | Geo/IP blocked or requires auth |
| 6 | How To Travel | `https://mobond.com/howtotravel/i.jsp?city=mumbai` | **403** | Blocked without app context |
| 7 | Jobs List | `https://mobond.com/jobs?city=mumbai` | **200→403** | Returns 200 but body says `HTTP/1.1 403 Forbidden` (proxy layer) |
| 8 | Railofy Guarantee | `https://odinsword.railofy.com/v1/getRailofyTravelGuarantee/` | **502** | Railofy backend gateway down |

---

## 📋 Complete Test Results Table

| # | API Name | URL | HTTP | Verdict |
|---|---------|-----|------|---------|
| 1 | App Config (CDN) | `https://cdn.mobond.com/mi/mi_config` | 200 | ✅ Real JSON data |
| 2 | Regcheck Heartbeat | `https://mobond.com/regcheck?isping=true` | 404 | ❌ Dead |
| 3 | IR Running Status (Mobond) | `https://mobond.com/irgetrunningstatus?trainno=12215` | 200 | ⚠️ Empty — needs app headers |
| 4 | IR Running Status (HRD) | `https://mobondhrd.appspot.com/irgetrunningstatus?trainno=12215` | 200 | ⚠️ Empty — needs app headers |
| 5 | Cancelled Trains | `https://mobondhrd.appspot.com/irgetcancelledtrains` | 200 | ⚠️ Returns `null` |
| 6 | NTES getTrainData | `https://enquiry.indianrail.gov.in/ntes/NTES?action=getTrainData&trainNo=12215` | 200 | 🔶 Maintenance |
| 7 | NTES SearchTrain | `https://enquiry.indianrail.gov.in/ntes/SearchTrain?trainNo=12215` | 200 | 🔶 Maintenance |
| 8 | NTES FutureTrain | `.../ntes/FutureTrain?action=getTrainData&trainNo=12215` | 200 | 🔶 Maintenance |
| 9 | NTES getTrnBwStns | `.../ntes/NTES?action=getTrnBwStns&stn1=MMCT&stn2=PUNE` | 200 | 🔶 Maintenance |
| 10 | NTES CRIS AppServAnd | `https://enquiry.indianrail.gov.in/crisntes/AppServAnd` | 200 | 🔶 Maintenance |
| 11 | News Alerts | `https://mobond.com/getnewsalerts?city=mumbai` | 200 | ⚠️ Empty |
| 12 | Exhibition List | `https://mobond.com/getexhibitionlist?city=mumbai` | 200 | ✅ Stale JSON data |
| 13 | Get Cabs | `https://mobond.com/getcabs?city=mumbai` | 404 | ❌ Dead |
| 14 | Jobs List | `https://mobond.com/jobs?city=mumbai` | 200→403 | ❌ Proxy-blocked |
| 15 | mTracker Volunteers | `https://mobond.com/mtracker/getvolunteers?trainno=12215` | 200 | ⚠️ Empty |
| 16 | Get Ads | `https://mobond.com/getads?city=mumbai` | 403 | ❌ Blocked |
| 17 | Auto Taxi Rating | `https://mobond.com/autotaxidriverrating?city=mumbai` | 404 | ❌ Dead |
| 18 | Picnic Spots | `https://mobond.com/picnicspots?city=mumbai` | 200 | ⚠️ HTML (not JSON) |
| 19 | Entertainment | `https://mobond.com/manoranjan?city=mumbai` | 200 | ✅ HTML page live |
| 20 | Railofy Guarantee | `https://odinsword.railofy.com/v1/getRailofyTravelGuarantee/` | 502 | ❌ Gateway down |
| 21 | PNR Check | `http://m.mobond.com/pnrcheck?pnr=1234567890` | 204 | ⚠️ Server online, invalid PNR |
| 22 | IR Seat Data | `http://m.mobond.com/irgetseatdata?trainno=12215` | 200 | ⚠️ Empty |
| 23 | Ferry Booking | `https://mobond.com/ferrybookingmumbai` | 200 | ✅ HTML page live |
| 24 | Metro Recharge | `https://mobond.com/mumbaimetrorecharge?city=mumbai` | 200 | ✅ HTML page live |
| 25 | Hotels | `https://mobond.com/hotels/i.jsp?city=mumbai` | ERR | ❌ Connection reset |
| 26 | Food | `https://mobond.com/food/i.jsp?city=mumbai` | 200 | ✅ HTML page live |
| 27 | Places | `https://mobond.com/places/i.jsp?city=mumbai` | 200 | ⚠️ Wrong content (Wikipedia) |
| 28 | How To Travel | `https://mobond.com/howtotravel/i.jsp?city=mumbai` | 403 | ❌ Blocked |
| 29 | Shopping | `https://mobond.com/shopping/i.jsp?city=mumbai` | 200 | ✅ HTML page live |
| 30 | Register Device | `https://mobond.com/registermindicatoronlinev2?...` | 200 | ⚠️ Empty (silent) |
| 31 | Resume Upload | `https://api.resumedb.in` | 200 | ✅ Website loads |
| 32 | mTracker Base | `https://mobond.com/mtracker/` | 404 | ❌ Dead |

---

## 🔑 Key Findings

### Why Many APIs Return Empty Bodies

The running status, news, and mTracker APIs return `200 OK` but **empty body** when called from a browser. The real app sends:
- Android `User-Agent` header (`Dalvik/2.1.0...`)
- A registered `deviceid` from `/registermindicatoronlinev2`
- Possibly a session cookie or HMAC signature

### To Get Real Data — Use These Headers:

```http
User-Agent: Dalvik/2.1.0 (Linux; U; Android 13; Pixel 7 Build/TQ3A.230901.001)
Accept: application/json
X-Requested-With: com.mobond.mindicator
```

### NTES is Down — Use Alternatives:
- **Call:** `139` (Indian Railways inquiry helpline)
- **Website:** `https://www.indianrail.gov.in` (legacy pages still up)
- **Direct mntes:** `https://enquiry.indianrail.gov.in/mntes/q?opt=TrainServiceSchedule&subOpt=show&trainNo=12215` (same server, same maintenance)

---

## 🏆 API Health Score

```
mobond.com              → 🟡 Partial (core alive, some 404s)
mobondhrd.appspot.com   → 🟡 Online but returning null/empty
cdn.mobond.com          → 🟢 Fully live
enquiry.indianrail.gov.in → 🔴 Under maintenance
m.mobond.com            → 🟡 Online (PNR server alive)
odinsword.railofy.com   → 🔴 502 Bad Gateway
api.resumedb.in         → 🟢 Website loads
```

---

*Test run: 2026-05-28 17:58–17:59 UTC (23:28–23:29 IST)*  
*No authentication headers used — raw browser-equivalent requests*
