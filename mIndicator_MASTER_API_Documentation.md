# 📱 m-Indicator Mumbai Local — MASTER API Documentation
### Complete Reference: All APIs, SDKs, Services & Offline Data

> **App:** m-Indicator: Mumbai Local  
> **Package:** `com.mobond.mindicator`  
> **Version:** 17.0.347 (Build 347)  
> **Source:** Reverse-engineered from APK DEX bytecode (`classes.dex`, `classes2.dex`) + APK asset files  
> **Servers Found:** 10 | **Total Endpoints:** 45+ | **SDKs:** 8  
> **Date:** May 2026

---

## 📑 Table of Contents

### Part A — Backend REST APIs
1. [Base URLs & Servers](#-part-a--base-urls--servers)
2. [Authentication](#-authentication)
3. [App Config API](#1-app-config-api)
4. [Device Registration API](#2-device-registration-api)
5. [Mumbai Local Train — Offline Data](#3-mumbai-local-train-offline-data)
6. [Live Train Running Status API](#4-live-train-running-status-api)
7. [Submit GPS / Manual Status](#5-submit-gps--manual-running-status)
8. [NTES — Indian Railways Official API](#6-ntes--indian-railways-official-api)
9. [PNR Check API](#7-pnr-check-api)
10. [Cancelled / Diverted / Rescheduled Trains](#8-cancelled--diverted--rescheduled-trains)
11. [Seat Availability API](#9-seat-availability-api)
12. [mTracker — Crowd Tracker](#10-mtracker--crowd-tracker)
13. [Bus Timings API](#11-bus-timings-api)
14. [Cab & Auto API](#12-cab--auto-api)
15. [Ferry Booking](#13-ferry-booking)
16. [Mumbai Metro](#14-mumbai-metro)
17. [MSRTC Bus Booking](#15-msrtc-bus-booking)
18. [Jobs & Resume API](#16-jobs--resume-api)
19. [Places, Food, Hotels & Shopping](#17-places-food-hotels--shopping)
20. [Entertainment & Events](#18-entertainment--events)
21. [News Alerts](#19-news-alerts)
22. [Ads API](#20-ads-api)
23. [Railofy Travel Guarantee](#21-railofy-travel-guarantee)
24. [Feedback, Chat & Misc](#22-feedback-chat--misc)
25. [CDN Endpoints](#23-cdn-endpoints)

### Part B — Live Train Tracking Deep-Dive
26. [Tracking Architecture](#-part-b--live-train-tracking-deep-dive)
27. [4-Layer Tracking System](#4-layer-tracking-system)
28. [Full Response Field Reference](#full-response-field-reference)
29. [Train Status & Coach Codes](#train-status-codes)
30. [How the App Resolves Status](#how-the-app-resolves-running-status)

### Part C — SDKs, WebViews & Integrations
31. [Firebase SDK](#-part-c--sdks-webviews--integrations)
32. [Google Maps & AdMob](#google-maps-api)
33. [WebView-Only External Sites](#webview-only-external-sites)
34. [Social / Share Integrations](#social--share-integrations)
35. [Background Services & Receivers](#background-services--broadcast-receivers)
36. [Activity → API Mapping](#activity--api-mapping)

### Part D — Reference Tables
37. [Complete URL Master List](#-part-d--reference-tables)
38. [Offline APK Assets](#complete-offline-data-apk-assets)
39. [Error Responses](#error-responses)
40. [City Codes](#city-codes-reference)

---

# 🌐 Part A — Base URLs & Servers

| # | Server | Base URL | Type | Purpose |
|---|--------|----------|------|---------|
| 1 | **Primary API** | `https://mobond.com` | REST | Main app backend |
| 2 | **Legacy API** | `http://m.mobond.com` | REST | Older endpoints (still active) |
| 3 | **HRD Server** | `https://mobondhrd.appspot.com` | REST | Running status / crowd data |
| 4 | **HRD Legacy** | `http://mobondhrd.appspot.com` | REST | Cancelled trains (HTTP) |
| 5 | **PNR Images** | `https://irailpnrcheck.appspot.com` | REST | PNR captcha images |
| 6 | **CDN** | `https://cdn.mobond.com` | Static | Config & HTML assets |
| 7 | **Jobs/Resume** | `https://api.resumedb.in` | REST | Resume upload & jobs |
| 8 | **Railofy** | `https://odinsword.railofy.com` | REST | Travel guarantee |
| 9 | **NTES (Govt)** | `https://enquiry.indianrail.gov.in` | REST | Official Indian Railways |
| 10 | **IR Legacy** | `http://www.indianrail.gov.in` | CGI/HTML | Old Indian Railways pages |
| 11 | **Firebase RT** | `https://mobondhrd.firebaseio.com` | WebSocket | Realtime push updates |

---

## 🔐 Authentication

The app does **not** use token-based auth headers. Instead:

- **Device registration** via `/registermindicatoronlinev2` — registers device, gets device ID
- **`regcheck?isping=true`** — heartbeat ping on every app launch
- **DeviceID in query params** — passed with all write/submission requests
- **Most read endpoints are public** — no auth header needed

```
No Authorization: Bearer header used.
Device identifier passed as ?deviceid= query param on write endpoints.
```

---

## 1. App Config API

### `GET https://cdn.mobond.com/mi/mi_config`

Fetches remote app configuration, feature flags, and transport options. Called at every app startup.

**Request:**
```http
GET /mi/mi_config HTTP/1.1
Host: cdn.mobond.com
```

**Response:** `200 OK` `application/json`
```json
{
  "version": "2018013101",
  "latlon": "19.0759840,72.8776560",
  "irversion": "1",
  "minversion": "86",
  "facilites": ["local","bus","express","msrtc","train chat","mono","metro","auto","cab","ferry","jobs","map"],
  "other": ["exhibition","natak","penalty","picnic","emergency","ambulance","police"],
  "other_header": ["Mumbai Exhibitions","Natak - Marathi Hindi Gujarati","Penalty - Traffic and Railway","Picnic","Emergency Contacts","Ambulance Booking","Police Station Locator"],
  "local": ["W","C","H","T","U","MM1WD","DPR","DVP","NM"],
  "bus": [
    { "name": "BEST",  "fullname": "BEST",                              "selected": "1" },
    { "name": "NMMT",  "fullname": "Navi Mumbai Muncipal Transport",    "selected": "0" },
    { "name": "TMT",   "fullname": "Thane Muncipal Transport",          "selected": "0" },
    { "name": "KDMT",  "fullname": "Kalyan Dombivali Muncipal Transport","selected": "0" },
    { "name": "MBMT",  "fullname": "Mira Bhayandar Muncipal Transport", "selected": "0" },
    { "name": "VVMT",  "fullname": "Virar Vasai Muncipal Transport",    "selected": "0" },
    { "name": "KMT",   "fullname": "Khopoli Muncipal Transport",        "selected": "0" }
  ],
  "auto": {
    "info": "TARIFF CARD FOR AUTORICKSHAW FOR MUMBAI METROPOLITAN REGION... Min Fare Rs.26.00, Rs.17.14/km",
    "bound1": "19.0759840, 72.8776560",
    "bound2": "19.3405388, 73.1076822",
    "complaint": [
      { "name": "Mumbai: Call from MTNL Phone", "no": "1800220110" },
      { "name": "MH-01 Tardeo RTO", "no": "02223532337" },
      { "name": "MH-02 Andheri RTO", "no": "02226366957" },
      { "name": "MH-03 Wadala RTO", "no": "02224036479" },
      { "name": "Thane: Call from MTNL Phone", "no": "1800225335" }
    ]
  },
  "taxi": {
    "info": "Tariff Card for Black and Yellow Meter Taxi... Min fare Rs.31.00, Rs.20.66/km | Coolcab Min Rs.48.00 for 1.5km",
    "bound1": "19.0759840, 72.8776560",
    "bound2": "19.3405388, 73.1076822"
  }
}
```

---

## 2. Device Registration API

### `GET https://mobond.com/regcheck`

Heartbeat ping to verify device is still registered. Called on every app launch.

```http
GET /regcheck?isping=true HTTP/1.1
Host: mobond.com
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `isping` | boolean | ✅ | Always `true` |

**Response:** `200 OK` `{ "status": "ok" }`

---

### `GET https://mobond.com/registermindicatoronlinev2`

Register or re-register the device. Called by `RegistrationFormUI` and `ThankyouActivity`.

```http
GET /registermindicatoronlinev2?city=mumbai&deviceid=DEVICE_ID&version=347&gcmid=FCM_TOKEN HTTP/1.1
Host: mobond.com
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `city` | string | ✅ | `mumbai`, `pune`, `delhi` |
| `deviceid` | string | ✅ | Unique device identifier |
| `version` | integer | ✅ | App version code (`347`) |
| `gcmid` | string | ⬜ | Firebase Cloud Messaging token |
| `os` | string | ⬜ | OS version string |

**Response:** `200 OK`
```json
{ "status": "registered", "deviceid": "abc123xyz" }
```

---

## 3. Mumbai Local Train — Offline Data

> **No API call needed.** All timetable data is bundled inside the APK.

**Asset path:** `assets/mumbai/local/<LINE>/<STATION_NAME>`

| Line Code | Railway Line |
|-----------|-------------|
| `W` | Western Railway |
| `C` | Central Railway |
| `H` | Harbour Line |
| `T` | Trans-Harbour Line |
| `U` | Uran Line |
| `MM1WD` | Monorail (Wadala–Jacob Circle) |
| `DPR` | DEMU Panvel–Roha |
| `DVP` | DEMU Vasai–Panvel |
| `NM` | Navi Mumbai |

**Station Index file:** `assets/mumbai/local/<LINE>/index` — binary list of all stations  
**Station Timetable file:** `assets/mumbai/local/<LINE>/<STATION_NAME>` — binary departure times

---

## 4. Live Train Running Status API

### `GET https://mobond.com/irgetrunningstatus` ← Primary

Crowd-sourced live running status. Called by `getRunningStatusFromMobondServer()`.  
Internal variable: `urlsForRunningStatus1URL`

```http
GET /irgetrunningstatus?trainno=12215 HTTP/1.1
Host: mobond.com
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `trainno` | string | ✅ | 5-digit train number |

**Response:** `200 OK`
```json
{
  "trainNo": "12215",
  "trainName": "SHATABDI EXPRESS",
  "trainSrc": "MMCT",
  "trainDstn": "PUNE",
  "status": "RUNNING",
  "delay": "10",
  "delayArr": "8",
  "delayDep": "10",
  "currentStation": "KARJAT",
  "nextStation": "KHOPOLI",
  "boardingStation": "MMCT",
  "platform": "3",
  "latitude": "18.9089",
  "longitude": "73.3188",
  "speed": "78",
  "timestamp": "1716896400",
  "volunteers": 4,
  "chartStatus": "CHART PREPARED",
  "stations": [
    {
      "stationCode": "MMCT",
      "stationName": "MUMBAI CSMT",
      "arrivalTime": "--",
      "departureTime": "06:25",
      "actualDepartureTime": "06:30",
      "delayDep": "5",
      "distance": 0,
      "dayCount": 1,
      "isTrain_Arrived": true,
      "isTrain_Departed": true,
      "platform": "7"
    },
    {
      "stationCode": "PUNE",
      "stationName": "PUNE JN",
      "arrivalTime": "10:20",
      "departureTime": "--",
      "actualArrivalTime": null,
      "actualDepartureTime": null,
      "delayArr": null,
      "delayDep": null,
      "distance": 193,
      "dayCount": 1,
      "isTrain_Arrived": false,
      "isTrain_Departed": false,
      "platform": null
    }
  ]
}
```

---

### `GET https://mobondhrd.appspot.com/irgetrunningstatus` ← Fallback

Same endpoint on the HRD server. Called when primary fails.  
Internal: `getRunningStatus()` / `urlsForRunningStatus2URL`

```http
GET /irgetrunningstatus?trainno=12215 HTTP/1.1
Host: mobondhrd.appspot.com
```

**Response:** Same schema as primary above.

---

## 5. Submit GPS / Manual Running Status

### `POST https://mobond.com/irputrunninggpsdata`

Users aboard a train submit their GPS location to crowd-source live position.  
Called by: `InsideLocalTrainService` background service.  
Internal: `uploadRunningStatustoMobond()`

```http
POST /irputrunninggpsdata HTTP/1.1
Host: mobond.com
Content-Type: application/x-www-form-urlencoded

trainno=12215&latitude=18.9089&longitude=73.3188&speed=78&timestamp=1716896400000&deviceid=abc123&stnCode=KARJAT&nextStnCode=KHOPOLI
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `trainno` | string | ✅ | Train number |
| `latitude` | float | ✅ | GPS latitude |
| `longitude` | float | ✅ | GPS longitude |
| `speed` | integer | ⬜ | Speed in km/h |
| `timestamp` | long | ✅ | Unix epoch in milliseconds |
| `deviceid` | string | ✅ | Device identifier |
| `stnCode` | string | ⬜ | Current known station code |
| `nextStnCode` | string | ⬜ | Next station code |

**Response:** `{ "status": "ok" }`

---

### `POST https://mobondhrd.appspot.com/irputrunningstatus`

Submit manually-observed delay (no GPS).  
Internal: `uploadRunningStatusToServer()`

```http
POST /irputrunningstatus HTTP/1.1
Host: mobondhrd.appspot.com
Content-Type: application/x-www-form-urlencoded

trainno=12215&stnCode=DADAR&delay=8&deviceid=abc123&timestamp=1716896400000
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `trainno` | string | ✅ | Train number |
| `stnCode` | string | ✅ | Station where observed |
| `delay` | integer | ✅ | Minutes late (`0` = on time, negative = early) |
| `deviceid` | string | ✅ | Device ID |
| `timestamp` | long | ⬜ | Unix epoch timestamp |

**Response:** `{ "status": "submitted" }`

---

## 6. NTES — Indian Railways Official API

> Government APIs at `enquiry.indianrail.gov.in` — called by `ActivityTrainSchedule`

### `GET /ntes/NTES?action=getTrainData&trainNo=` — Live Schedule

```http
GET /ntes/NTES?action=getTrainData&trainNo=12215 HTTP/1.1
Host: enquiry.indianrail.gov.in
```

**Response:**
```json
{
  "body": {
    "TrainNumber": "12215",
    "TrainName": "SHATABDI EXPRESS",
    "Source": "MMCT",
    "Destination": "PUNE",
    "TrainStartDate": "28-05-2026",
    "Stations": [
      {
        "StationCode": "MMCT",
        "StationName": "MUMBAI CSMT",
        "ArrivalTime": "Source",
        "DepartureTime": "06:25",
        "Distance": "0",
        "DayCount": "1",
        "HaltTime": "Source",
        "SerialNo": "1",
        "ActualArrivalTime": "--",
        "ActualDepartureTime": "06:30",
        "DelayInArrival": "0",
        "DelayInDeparture": "5",
        "Platform": "7",
        "isTrain_Arrived": true,
        "isTrain_Departed": true
      }
    ]
  },
  "responseCode": 200
}
```

---

### `GET /ntes/NTES?action=getTrnBwStns&stn1=&stn2=` — Trains Between Stations

```http
GET /ntes/NTES?action=getTrnBwStns&stn1=MMCT&stn2=PUNE HTTP/1.1
Host: enquiry.indianrail.gov.in
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `action` | string | ✅ | `getTrnBwStns` |
| `stn1` | string | ✅ | Source station code |
| `stn2` | string | ✅ | Destination station code |

---

### `GET /ntes/SearchTrain?trainNo=` — Search Train

```http
GET /ntes/SearchTrain?trainNo=12215 HTTP/1.1
Host: enquiry.indianrail.gov.in
```

---

### `GET /ntes/FutureTrain?action=getTrainData&trainNo=` — Future Schedule

```http
GET /ntes/FutureTrain?action=getTrainData&trainNo=12215 HTTP/1.1
Host: enquiry.indianrail.gov.in
```

---

### `GET /mntes/q?opt=TrainServiceSchedule&subOpt=show&trainNo=` — Mobile NTES

```http
GET /mntes/q?opt=TrainServiceSchedule&subOpt=show&trainNo=12215 HTTP/1.1
Host: enquiry.indianrail.gov.in
```

---

### `GET /crisntes/AppServAnd` — CRIS Android Service

```http
GET /crisntes/AppServAnd HTTP/1.1
Host: enquiry.indianrail.gov.in
```

---

### `GET /enquiry/FetchTrainData?_=` — Fetch Train Data

```http
GET /enquiry/FetchTrainData?_=<timestamp_ms> HTTP/1.1
Host: enquiry.indianrail.gov.in
```

---

### `GET /enquiry/FetchAutoComplete?_=` — Station Autocomplete

```http
GET /enquiry/FetchAutoComplete?_=<query> HTTP/1.1
Host: enquiry.indianrail.gov.in
```

---

### `GET /enquiry/CommonCaptcha?inputCaptcha=` — Captcha Verify

```http
GET /enquiry/CommonCaptcha?inputCaptcha=<user_input> HTTP/1.1
Host: enquiry.indianrail.gov.in
```

### Common Station Codes

| Station | Code | Station | Code |
|---------|------|---------|------|
| Mumbai CSMT | `MMCT` | Dadar | `DR` |
| Thane | `TNA` | Pune | `PUNE` |
| Lonavala | `LNL` | Kalyan | `KYN` |
| Borivali | `BVI` | Panvel | `PNVL` |

---

## 7. PNR Check API

### `GET http://m.mobond.com/pnrcheck`

Called by `GetPnrStatusService` and `PnrNotification2HoursBeforeActionReceiver`.

```http
GET /pnrcheck?pnr=1234567890 HTTP/1.1
Host: m.mobond.com
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `pnr` | string | ✅ | 10-digit PNR number |

**Response:** `200 OK`
```json
{
  "pnr": "1234567890",
  "trainNo": "12215",
  "trainName": "SHATABDI EXPRESS",
  "doj": "28-05-2026",
  "from": "MMCT",
  "to": "PUNE",
  "bookingStatus": "CNF",
  "currentStatus": "CNF",
  "coach": "CC",
  "berth": "34",
  "chartStatus": "CHART PREPARED",
  "boardingStnCode": "MMCT",
  "passengers": [
    {
      "name": "PASSENGER 1",
      "bookingStatus": "CNF/CC/34",
      "currentStatus": "CNF/CC/34",
      "bookingStatusDetails": "Confirmed",
      "currentStatusDetails": "Confirmed"
    }
  ]
}
```

---

### `GET https://irailpnrcheck.appspot.com/rcv_img` — PNR Captcha Image

```http
GET /rcv_img?<captcha_params> HTTP/1.1
Host: irailpnrcheck.appspot.com
```

Returns PNG/JPG captcha image for PNR verification.

---

## 8. Cancelled / Diverted / Rescheduled Trains

### `GET https://mobondhrd.appspot.com/irgetcancelledtrains`

Returns all disrupted trains for today. Called by `ActivityCancelledRescheduledTrains`.  
Also called at: `http://mobondhrd.appspot.com/irgetcancelledtrains` (HTTP fallback)

```http
GET /irgetcancelledtrains HTTP/1.1
Host: mobondhrd.appspot.com
```

> No query parameters required.

**Response:** `200 OK`
```json
{
  "allCancelledTrains": [
    {
      "trainNo": "11007",
      "trainName": "DECCAN EXPRESS",
      "date": "28-05-2026",
      "cancelledType": "CANCELLED",
      "reason": "Engineering Work"
    }
  ],
  "allPartiallyCancelledTrains": [
    {
      "trainNo": "12127",
      "trainName": "INTERCITY EXP",
      "date": "28-05-2026",
      "cancelledType": "PARTIALLY CANCELLED",
      "fromStnCode": "DR",
      "toStnCode": "PUNE",
      "reason": "Technical fault"
    }
  ],
  "allDivertedTrains": [
    {
      "trainNo": "12533",
      "trainName": "PUSHPAK EXPRESS",
      "date": "28-05-2026",
      "cancelledType": "DIVERTED",
      "divertedFrom": "NASHIK",
      "divertedTo": "IGATPURI",
      "reason": "Track maintenance"
    }
  ],
  "allRescheduledTrains": [
    {
      "trainNo": "22105",
      "trainName": "INDRAYANI EXPRESS",
      "date": "28-05-2026",
      "cancelledType": "RESCHEDULED",
      "originalDepartureTime": "06:15",
      "newDepartureTime": "08:30",
      "reason": "Late running of incoming rake"
    }
  ]
}
```

| `cancelledType` Value | Meaning |
|----------------------|---------|
| `CANCELLED` | Fully cancelled |
| `PARTIALLY CANCELLED` | Cancelled between certain stations |
| `DIVERTED` | Running via alternate route |
| `RESCHEDULED` | Departure time changed |
| `CANCELLED / MODIFIED` | Cancelled with partial changes |

---

## 9. Seat Availability API

### `GET http://m.mobond.com/irgetseatdata`

Crowd-sourced seat availability. Called by `ActivitySeatStatus`.

```http
GET /irgetseatdata?trainno=12215&coach=S1&date=20260528 HTTP/1.1
Host: m.mobond.com
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `trainno` | string | ✅ | Train number |
| `coach` | string | ⬜ | Coach code (`S1`, `B1`, `GN`, `CC`) |
| `date` | string | ⬜ | Date `YYYYMMDD` |

---

### `POST http://m.mobond.com/irputseatdata`

Submit crowd-sourced seat observation.

```http
POST /irputseatdata HTTP/1.1
Host: m.mobond.com
Content-Type: application/x-www-form-urlencoded

trainno=12215&coach=S1&seats=12&date=20260528&deviceid=abc123
```

---

## 10. mTracker — Crowd Tracker

### `GET https://mobond.com/mtracker/getvolunteers`

Get active volunteers on a train. Called by `PeopleSharing` activity.

```http
GET /mtracker/getvolunteers?trainno=12215&date=20260528 HTTP/1.1
Host: mobond.com
```

**Response:**
```json
{
  "trainno": "12215",
  "volunteers": [
    { "station": "BORIVALI", "count": 2, "last_seen": "2026-05-28T09:15:00" }
  ],
  "total": 5
}
```

---

### `POST https://mobond.com/mtracker/register`

Register as mTracker volunteer.

```http
POST /mtracker/register HTTP/1.1
Host: mobond.com
Content-Type: application/x-www-form-urlencoded

trainno=12215&from=BORIVALI&to=DADAR&deviceid=abc123&date=20260528
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `trainno` | string | ✅ | Train number |
| `from` | string | ✅ | Boarding station |
| `to` | string | ✅ | Destination station |
| `deviceid` | string | ✅ | Device identifier |
| `date` | string | ✅ | Date `YYYYMMDD` |

**Response:** `{ "status": "registered", "volunteer_id": "v_789" }`

---

### `POST https://mobond.com/mtracker/like`

Like a tracker report.

```http
POST /mtracker/like HTTP/1.1
Host: mobond.com
Content-Type: application/x-www-form-urlencoded

reportid=rpt_456&deviceid=abc123
```

**Response:** `{ "status": "ok", "likes": 14 }`

---

## 11. Bus Timings API

### `GET https://mobond.com/acbustimings.jsp`

AC Bus timings by route or bus number.

```http
GET /acbustimings.jsp?city=mumbai&busnumber=AC101 HTTP/1.1
GET /acbustimings.jsp?city=mumbai&routeid=RT_BEST_101 HTTP/1.1
Host: mobond.com
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `city` | string | ✅ | City code |
| `busnumber` | string | Cond. | Bus number (OR `routeid`) |
| `routeid` | string | Cond. | Route ID (OR `busnumber`) |

**Response:**
```json
{
  "busnumber": "AC101",
  "route": "Borivali - Colaba",
  "stops": ["BORIVALI", "KANDIVALI", "MALAD", "ANDHERI"],
  "timings": [
    { "stop": "BORIVALI", "time": "06:00" },
    { "stop": "KANDIVALI", "time": "06:15" }
  ]
}
```

> **Non-AC BEST/NMMT/TMT bus data** — stored offline in APK:  
> `assets/mumbai/bus/BEST/EN_b1`, `EN_b2` | `assets/pune/bus/PMPML/EN_b1`, `EN_b2`

---

## 12. Cab & Auto API

### `GET https://mobond.com/getcabs`

```http
GET /getcabs?city=mumbai&latitude=19.0759&longitude=72.8776 HTTP/1.1
Host: mobond.com
```

**Response:**
```json
{
  "cabs": [
    { "name": "Ola", "type": "Mini", "eta": "3 mins", "fare_estimate": "₹80 - ₹95", "deeplink": "olacabs://..." }
  ]
}
```

---

### `GET https://mobond.com/autotaxidriverrating`

Auto & taxi driver ratings for a city.

```http
GET /autotaxidriverrating?city=mumbai HTTP/1.1
Host: mobond.com
```

**Response:**
```json
{
  "city": "mumbai",
  "drivers": [
    { "vehicle_no": "MH-01-AB-1234", "driver_name": "RAJU SHARMA", "rating": 4.5, "trips": 230 }
  ]
}
```

> **Tariffs (from config.json):**  
> Auto: Min ₹26.00, ₹17.14/km (eff. 01.02.2025) | Night (12am–5am): +25%  
> Taxi: Min ₹31.00, ₹20.66/km | Coolcab: Min ₹48.00 / 1.5km

---

## 13. Ferry Booking

### `GET https://mobond.com/ferrybookingmumbai`

```http
GET /ferrybookingmumbai HTTP/1.1
Host: mobond.com
```

Returns HTML page (WebView). Ferry schedules offline in `assets/mumbai/ferry/`

---

## 14. Mumbai Metro

### `GET https://mobond.com/mumbaimetrorecharge`

```http
GET /mumbaimetrorecharge?city=mumbai HTTP/1.1
Host: mobond.com
```

Returns HTML (WebView). Metro timetables offline:
- Mumbai Metro Line 1: `assets/mumbai/local/MM1WD/`
- Pune Metro Aqua: `assets/pune/local/PN_AQUA/`
- Pune Metro Purple: `assets/pune/local/PN_PURPLE/`

---

## 15. MSRTC Bus Booking

### `GET https://mobond.com/msrtcbooking`

```http
GET /msrtcbooking?city=mumbai&mobondhandle=https://mobond.com HTTP/1.1
Host: mobond.com
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `city` | string | ✅ | City code |
| `mobondhandle` | string | ✅ | Callback scheme for the app |

> **`mobondhandle` callback values** (all found in DEX):

| Value | Triggered When |
|-------|---------------|
| `mobondhandle=map` | Map link tapped in WebView |
| `mobondhandle=places` | Places link opened |
| `mobondhandle=post` | Form submitted |
| `mobondhandle=system` | System-level callback |
| `mobondhandle=youtube` | YouTube link tapped |
| `mobondhandle=jobapplicationform` | Job form opened |
| `mobondhandle=jobnotification` | Job alert tapped |

---

## 16. Jobs & Resume API

### `GET https://mobond.com/jobs`

```http
GET /jobs?city=mumbai&category=it&page=1 HTTP/1.1
Host: mobond.com
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `city` | string | ✅ | City code |
| `category` | string | ⬜ | Filter category |
| `page` | integer | ⬜ | Page number (default 1) |

**Response:**
```json
{
  "jobs": [
    { "id": "job_001", "title": "Software Developer", "company": "TCS", "location": "Mumbai, Andheri", "salary": "₹6-10 LPA", "posted": "2026-05-27" }
  ],
  "total": 120,
  "page": 1
}
```

---

### `POST https://mobond.com/jobsformsubmitservlet`

```http
POST /jobsformsubmitservlet?jobid=job_001 HTTP/1.1
Host: mobond.com
Content-Type: application/x-www-form-urlencoded

name=John+Doe&email=john@email.com&phone=9876543210&jobid=job_001&resume_url=https://...
```

> Email footer in submissions: `Sent using Jobs Indicator, www.mobond.com`

---

### `POST https://api.resumedb.in/uploadresumegeturl`

Pre-signed URL for resume upload.  
**User-Agent header:** `ResumeDB/1.0`

```http
POST /uploadresumegeturl?contenttype=application%2Fpdf HTTP/1.1
Host: api.resumedb.in
User-Agent: ResumeDB/1.0
Content-Type: application/x-www-form-urlencoded

contenttype=application/pdf&filename=resume_johndoe.pdf
```

**Response:**
```json
{
  "upload_url": "https://storage.googleapis.com/resumedb/...",
  "public_url": "https://api.resumedb.in/resumes/johndoe_abc.pdf",
  "expires_in": 3600
}
```

---

## 17. Places, Food, Hotels & Shopping

All called from `https://mobond.com`:

| Method | Endpoint | Parameters | Description |
|--------|----------|------------|-------------|
| GET | `/places/i.jsp?city=` | `city` | Local tourist places |
| GET | `/food/i.jsp?city=` | `city` | Restaurants & food |
| GET | `/hotels/i.jsp?city=&latitude=&longitude=` | `city`, `latitude`, `longitude` | Hotels near location |
| GET | `/howtotravel/i.jsp?city=` | `city` | Travel guides |
| GET | `/picnicspots?city=` | `city` | Picnic destinations |
| GET | `/shopping/i.jsp?city=` | `city` | Shopping malls |

---

## 18. Entertainment & Events

### `GET https://mobond.com/getexhibitionlist`

```http
GET /getexhibitionlist?city=mumbai HTTP/1.1
Host: mobond.com
```

**Response:**
```json
{
  "exhibitions": [
    { "id": "ex_101", "name": "India Trade Fair", "venue": "MMRDA Grounds, BKC", "start_date": "2026-05-25", "end_date": "2026-06-05", "timing": "10:00 AM - 8:00 PM", "entry_fee": "₹50" }
  ]
}
```

---

### `GET https://mobond.com/manoranjan`

Marathi/Hindi natak, cinema, entertainment.

```http
GET /manoranjan?city=mumbai HTTP/1.1
Host: mobond.com
```

---

## 19. News Alerts

### `GET https://mobond.com/getnewsalerts`

Called by `News` (alert) Activity.

```http
GET /getnewsalerts?city=mumbai&type=transport HTTP/1.1
Host: mobond.com
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `city` | string | ✅ | City code |
| `type` | string | ⬜ | `transport`, `weather`, `general` |

**Response:**
```json
{
  "alerts": [
    { "id": "alert_001", "title": "Western Railway: Signal failure", "body": "Trains running 15-20 min late...", "type": "transport", "timestamp": "2026-05-28T08:45:00", "severity": "medium" }
  ]
}
```

---

## 20. Ads API

### `GET https://mobond.com/getads`

Called by `AdUI`. Also uses Google AdMob SDK.

```http
GET /getads?city=mumbai&screen=home&deviceid=abc123 HTTP/1.1
Host: mobond.com
```

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `city` | string | ✅ | City code |
| `screen` | string | ⬜ | `home`, `train`, `bus` |
| `deviceid` | string | ⬜ | Device ID for targeting |

**AdMob Placement IDs found in DEX:**

| Placement Constant | Screen |
|-------------------|--------|
| `ADTYPE_RAIL_TRACE_TRAIN_UI` | Live train tracking |
| `ADTYPE_RAIL_TRAINS_AT_STATION_UI` | Trains at station |
| `ADTYPE_RAIL_TRAINS_AT_STATION_UI_MERGED` | Merged station view |
| `ADTYPE_IR_TRAIN_DETAILS_RESULT` | Train detail results |
| `ADTYPE_IR_SELECT_STATION` | Station selection |
| `ADTYPE_BUS_ROUTE_UI` | Bus route screen |
| `ADTYPE_MSRTC_BUS_ROUTE` | MSRTC routes |
| `ADTYPE_MSRTC_BUS_ROUTE_DETAILS` | MSRTC details |
| `ADTYPE_TRAIN_CHAT` | Train chat screen |

---

## 21. Railofy Travel Guarantee

### `GET https://odinsword.railofy.com/v1/getRailofyTravelGuarantee/`

```http
GET /v1/getRailofyTravelGuarantee/?pnr=1234567890&trainno=12215 HTTP/1.1
Host: odinsword.railofy.com
```

**Response:**
```json
{
  "eligible": true,
  "guarantee_amount": 500,
  "coverage": "waitlisted_to_confirmed",
  "product_url": "https://railofy.com/guarantee?pnr=1234567890",
  "booking_status": "WL/14",
  "current_status": "WL/12",
  "chart_status": "CHART NOT PREPARED",
  "expiry": "2026-05-27T23:59:59"
}
```

---

## 22. Feedback, Chat & Misc

| Method | URL | Parameters | Description |
|--------|-----|------------|-------------|
| GET | `https://mobond.com/feedback` | `deviceid`, `version` | Feedback form (WebView) |
| GET | `https://mobond.com/chat` | `trainno`, `from`, `to` | Train commuter chat |
| GET | `https://mobond.com/terms.jsp` | — | Terms & Conditions |
| GET | `https://mobond.com/advertise.jsp` | — | Advertise with m-Indicator |
| GET | `https://m.mobond.com/advertise.jsp` | — | Advertise (legacy) |
| GET | `https://m.mobond.com/terms.xhtml` | — | Terms (legacy) |

---

## 23. CDN Endpoints

| Method | URL | Description |
|--------|-----|-------------|
| GET | `https://cdn.mobond.com/mi/mi_config` | App remote config JSON |
| GET | `https://cdn.mobond.com/mi/sbi_mmrad_mumbai1_card_info.html` | SBI MMRDA card info |
| GET | `https://cdn.mobond.com/map/` | Map tile data |
| GET | `http://cdn.mobond.com/map/` | Map tile data (HTTP) |
| GET | `http://cdn.mobond.com/mi/sbi_mmrad_mumbai1_card_info.html` | SBI card (HTTP) |
| GET | `https://m-indicator.mobond.com/desktop/index.html#contactus` | Contact page |
| GET | `https://m-indicator.mobond.com/desktop/images/logo_mobond.png` | App logo |

---

# 🚆 Part B — Live Train Tracking Deep-Dive

## 4-Layer Tracking System

```
┌─────────────────────────────────────────────────────────────────┐
│  Layer 1 → NTES (Indian Railways Official)                      │
│            enquiry.indianrail.gov.in — schedule + live status   │
├─────────────────────────────────────────────────────────────────┤
│  Layer 2 → mobond.com (Primary Crowd Server)                    │
│            Crowd-sourced GPS positions + delay reports          │
├─────────────────────────────────────────────────────────────────┤
│  Layer 3 → mobondhrd.appspot.com (Fallback Crowd Server)        │
│            Secondary crowd data + cancelled trains              │
├─────────────────────────────────────────────────────────────────┤
│  Layer 4 → mobondhrd.firebaseio.com (Firebase Realtime DB)      │
│            WebSocket push — no polling needed                   │
└─────────────────────────────────────────────────────────────────┘
```

**Internal method names found in DEX:**
- `getRunningStatus()`
- `getRunningStatusFromMobondServer()`
- `getRunningStatusFromWeb()`
- `getRunningStatusViaWeb()`
- `firstGetTrainDataThenRunningStatus()`
- `buildTimeTableJsonArrayFromRunningStatus()`
- `rebuildTimeTableJsonArrayFromRunningStatus()`
- `uploadRunningStatustoMobond()`
- `uploadRunningStatusToServer()`

**Firebase Realtime Database:**

```
Base: https://mobondhrd.firebaseio.com/

Known paths:
  /trains/<trainNo>/runningStatus   → Live running status
  /trains/<trainNo>/location        → Last GPS location
  /alerts                           → Disruption push alerts
  /cancelledTrains                  → Real-time cancelled feed
```

---

## Full Response Field Reference

### Train Identity
| Field | Type | Description |
|-------|------|-------------|
| `trainNo` / `trainNO` | string | Train number (e.g. `"12215"`) |
| `trainName` | string | Train name |
| `trainSrc` | string | Source station code |
| `trainDstn` / `dstnCode` | string | Destination station code |
| `trainType` | string | SHATABDI, EXPRESS, etc. |
| `trainNumber` | string | Alternate field for train number |
| `trainSchedule` | object | Full timetable object |
| `trainNum` | string | Short reference |

### Station Fields
| Field | Type | Description |
|-------|------|-------------|
| `stationCode` | string | Station code (e.g. `"MMCT"`) |
| `stationName` | string | Full station name |
| `stnCode` | string | Alternate station code field |
| `stnIndex` | integer | Station index in route |
| `fromStnCode` | string | Journey from station |
| `toStnCode` | string | Journey to station |
| `boardingStnCode` | string | Boarding station (PNR) |
| `nextStnCode` | string | Next station (live) |
| `currentStation` | string | Current station code |

### Timing Fields
| Field | Type | Description |
|-------|------|-------------|
| `arrivalTime` | string | Scheduled arrival `HH:MM` |
| `departureTime` | string | Scheduled departure `HH:MM` |
| `actualArrivalTime` | string | Actual arrival (live) |
| `actualDepartureTime` | string | Actual departure (live) |
| `delayArr` | integer | Arrival delay in minutes |
| `delayDep` | integer | Departure delay in minutes |
| `delay` | integer | General delay field |
| `distance` | integer | Distance from source (km) |
| `dayCount` | integer | Day of arrival (1 = same day) |
| `haltTime` | string | Halt time at station |

### Live Tracking Fields
| Field | Type | Description |
|-------|------|-------------|
| `isTrain_Arrived` | boolean | Has train arrived |
| `isTrain_Departed` | boolean | Has train departed |
| `latitude` | float | Train GPS latitude |
| `longitude` | float | Train GPS longitude |
| `speed` | integer | Speed in km/h |
| `timestamp` | long | Unix timestamp of last update |
| `platform` | string | Platform number |
| `volunteers` | integer | Number of crowd contributors |
| `isTrainAlert` | boolean | Disruption alert exists |

### Status Fields
| Field | Type | Description |
|-------|------|-------------|
| `status` | string | Overall train status |
| `chartStatus` | string | Chart preparation status |
| `bookingStatus` | string | Booking/berth status |
| `currentStatusDetails` | string | Detailed current status |
| `bookingStatusDetails` | string | Detailed booking info |
| `availablityStatus` | string | Seat availability |
| `cancelledType` | string | Disruption type |
| `divertedFrom` | string | Diverted from station |
| `divertedTo` | string | Diverted to station |

---

## Train Status Codes

| Status | Meaning |
|--------|---------|
| `RUNNING` | Train is currently en route |
| `AT STATION` | Train is currently at a station |
| `REACHED` | Train reached destination |
| `CANCELLED` | Fully cancelled |
| `PARTIALLY CANCELLED` | Some legs cancelled |
| `DIVERTED` | Running via alternate route |
| `RESCHEDULED` | Departure time changed |
| `CANCELLED / MODIFIED` | Cancelled with changes |
| `YES_TRACE` | Live GPS trace available |

| `chartStatus` | Meaning |
|--------------|---------|
| `CHART PREPARED` | Seat chart is final |
| `CHART NOT PREPARED` | Waitlisted passengers may still confirm |

---

## Coach Class Codes

| Code | Class |
|------|-------|
| `PAS:GN` | General |
| `PAS:SL` | Sleeper |
| `PAS:2S` | 2nd Sitting |
| `PAS:FC` | First Class |
| `YUVA:2A` | Yuva 2-Tier AC |
| `YUVA:3A` | Yuva 3-Tier AC |
| `YUVA:CC` | Yuva Chair Car |
| `YUVA:FC` | Yuva First Class |

---

## How the App Resolves Running Status

```
Step 1 → GET https://mobond.com/irgetrunningstatus?trainno=<N>
         (urlsForRunningStatus1URL)

Step 2 → If Step 1 fails/stale:
         GET https://mobondhrd.appspot.com/irgetrunningstatus?trainno=<N>
         (urlsForRunningStatus2URL)

Step 3 → firstGetTrainDataThenRunningStatus()
         GET https://enquiry.indianrail.gov.in/ntes/NTES?action=getTrainData&trainNo=<N>

Step 4 → buildTimeTableJsonArrayFromRunningStatus()
         Merges NTES schedule + crowd-sourced delay data

Step 5 → Firebase WebSocket subscription
         wss://mobondhrd.firebaseio.com/trains/<N>/runningStatus

Step 6 → Background: InsideLocalTrainService submits user GPS
         POST https://mobond.com/irputrunninggpsdata
         → Feeds real-time updates for all watchers of that train
```

**Auto-refresh triggers:**
- App opens train tracking screen
- Every ~60 seconds (while screen is active)
- Firebase push notification received
- Network connectivity restored after disconnect

**Internal broadcast action (found in DEX):**
```
com.mobond.mindicator.ui.livetrain.trainutils.InsideLocalTrainService.broadcast
```

**Internal SharedPreferences key:** `mobondrunstatus`

---

# 📦 Part C — SDKs, WebViews & Integrations

## Firebase SDK

| Module | Purpose |
|--------|---------|
| Firebase Analytics | Usage & screen tracking across all activities |
| Firebase Cloud Messaging (FCM) | Push notifications for train alerts, PNR updates |
| Firebase Remote Config | Remote feature flags, A/B testing |
| Firebase Auth | User account authentication |
| Firebase Crashlytics | Crash reporting and diagnostics |
| Firebase Realtime DB | Live train position updates via WebSocket |

---

## Google Maps API

| API | Endpoint | Purpose |
|-----|----------|---------|
| Directions API | `https://maps.googleapis.com/maps/api/directions/json?origin=` | Route directions between stations |
| Maps Viewer | `https://www.google.com/maps/d/u/0/viewer?mid=...` | Static map embeds |

---

## Google AdMob

Loaded via AdMob SDK at:
- `https://googleads.g.doubleclick.net`
- Banner, interstitial, native ad types

---

## WebView-Only External Sites

These are opened inside the app's in-app browser — **not REST API calls**:

| URL | Screen | Purpose |
|-----|--------|---------|
| `https://www.irctc.co.in` | IRCTC screen (`openIrctcBooking`) | Ticket booking |
| `https://transit.sbi/swift/customerportal?pagename=mmrda` | Metro screen | SBI MMRDA Metro card recharge |
| `https://www.mhpolice.maharashtra.gov.in/` | Police screen | Police station locator |
| `https://www.mmmocl.co.in/card-reload.html` | Monorail screen | Monorail card reload |
| `https://www.mmmocl.co.in/fare-table.php` | Monorail screen | Monorail fare table |
| `https://www.mmmocl.co.in/offences-penalties.html` | Monorail screen | Monorail penalties |
| `https://webview-3829e.firebaseapp.com/` | Auth screen | Firebase auth WebView |
| `https://enquiry.indianrail.gov.in/ntes/i.html` | IR screen | NTES mobile web |
| `http://enquiry.indianrail.gov.in/mntes/enquiry?opt=TrainServiceSchedule&subOpt=show&trainNo=12215` | IR screen | Train service schedule |
| `http://www.indianrail.gov.in/pnr_Enq.html` | PNR screen | Legacy PNR page |
| `http://www.indianrail.gov.in/enquiry/PNR/PnrEnquiry.html?locale=en` | PNR screen | PNR enquiry (new) |
| `http://www.indianrail.gov.in/enquiry/SEAT/SeatAvailability.html` | Seat screen | Seat availability |
| `http://www.indianrail.gov.in/fare_Enq.html` | Fare screen | Fare enquiry |
| `http://www.indianrail.gov.in/train_Schedule.html` | Schedule screen | Train schedule |

---

## Social / Share Integrations

Called via Android Intents (not HTTP):

| Platform | URL Pattern | Purpose |
|----------|-------------|---------|
| WhatsApp | `https://wa.me/` | Share train status |
| Twitter | `https://twitter.com/m_indicator_app` | App's Twitter page |
| Facebook | `https://www.facebook.com/m.indicator.official` | App's Facebook page |
| Instagram | `http://instagram.com/_u/` | Instagram profile link |

---

## Background Services & Broadcast Receivers

| Component | API Used | Trigger |
|-----------|---------|---------|
| `InsideLocalTrainService` | `POST /irputrunninggpsdata` | User boarding a tracked train |
| `GetPnrStatusService` | `GET /pnrcheck` | Every ~5 min in background |
| `PnrNotification2HoursBeforeActionReceiver` | PNR check | 2 hours before train departure |
| FCM Receiver | Firebase | On any push notification |
| `STATIONALARM` | GPS + local data | Station proximity alarm |
| Boot receiver (`RECEIVE_BOOT_COMPLETED`) | Restarts services | Device reboot |

**Broadcast Action String (from DEX):**
```
com.mobond.mindicator.ui.livetrain.trainutils.InsideLocalTrainService.broadcast
```

---

## Activity → API Mapping

| Activity / Class | APIs Called |
|-----------------|-------------|
| `BaseAppCompatActivity` | `regcheck?isping=true`, `mi_config` |
| `RegistrationFormUI` | `registermindicatoronlinev2` |
| `ThankyouActivity` | `registermindicatoronlinev2` completion |
| `AdUI` | `getads`, AdMob SDK |
| `FeedbackUI` | `/feedback` |
| `ChatScreenHSV` | `/chat` |
| `ActivityTrainSchedule` | NTES `getTrainData`, `FutureTrain`, cancelled trains |
| `ActivityCancelledRescheduledTrains` | `irgetcancelledtrains`, NTES cancelled feeds |
| `ActivitySeatStatus` | NTES Seat, `irgetseatdata`, `irputseatdata` |
| `ActivityStationSelectionHotels` | `/hotels/i.jsp` |
| `GetPnrStatusService` | `pnrcheck`, NTES PNR, `irailpnrcheck.appspot.com/rcv_img` |
| `PnrNotification2HoursBeforeActionReceiver` | PNR background check |
| `InsideLocalTrainService` | `irputrunninggpsdata`, Firebase Realtime DB |
| `PeopleSharing` | `mtracker/getvolunteers`, `register`, `like` |
| `News` (alert) | `getnewsalerts` |
| `SelectLineUI` | Offline assets only (no API) |
| `FareActivity` | Offline fare tables only (no API) |
| `StationMap` | Google Maps SDK |
| `RailRouteFinderSearchResultActivity` | Offline route data |
| `TestActivity` | Development testing only |

---

## API Call Frequency

| Frequency | API / Service |
|-----------|--------------|
| Every app launch | `regcheck?isping=true`, `cdn.mobond.com/mi/mi_config` |
| On feature screen open | All feature-specific endpoints |
| Every ~60 seconds | `irgetrunningstatus` (while on tracking screen) |
| Every ~5 minutes (background) | `GetPnrStatusService` PNR check |
| On GPS update (train ride) | `POST /irputrunninggpsdata` |
| Real-time WebSocket | `mobondhrd.firebaseio.com` |

---

# 📊 Part D — Reference Tables

## Complete URL Master List

| # | Method | URL | Activity / Service | Purpose |
|---|--------|-----|-------------------|---------|
| 1 | GET | `https://cdn.mobond.com/mi/mi_config` | Startup | App config |
| 2 | GET | `https://mobond.com/regcheck?isping=true` | `BaseAppCompatActivity` | Heartbeat |
| 3 | GET | `https://mobond.com/registermindicatoronlinev2?` | `RegistrationFormUI` | Register device |
| 4 | GET | `https://mobond.com/irgetrunningstatus` | Train Tracker | Running status (primary) |
| 5 | GET | `https://mobondhrd.appspot.com/irgetrunningstatus?trainno=` | Train Tracker | Running status (fallback) |
| 6 | POST | `https://mobond.com/irputrunninggpsdata` | `InsideLocalTrainService` | Submit GPS |
| 7 | POST | `https://mobondhrd.appspot.com/irputrunningstatus` | Train Tracker | Submit manual delay |
| 8 | GET | `https://enquiry.indianrail.gov.in/ntes/NTES?action=getTrainData&trainNo=` | `ActivityTrainSchedule` | NTES live data |
| 9 | GET | `https://enquiry.indianrail.gov.in/ntes/NTES?action=getTrnBwStns&stn1=&stn2=` | Train between stations | Trains between 2 stations |
| 10 | GET | `https://enquiry.indianrail.gov.in/ntes/SearchTrain?trainNo=` | Search | Search train |
| 11 | GET | `https://enquiry.indianrail.gov.in/ntes/FutureTrain?action=getTrainData&trainNo=` | `ActivityTrainSchedule` | Future schedule |
| 12 | GET | `https://enquiry.indianrail.gov.in/mntes/q?opt=TrainServiceSchedule&subOpt=show&trainNo=` | WebView | Mobile NTES |
| 13 | GET | `https://enquiry.indianrail.gov.in/crisntes/AppServAnd` | Train Tracker | CRIS Android |
| 14 | GET | `https://enquiry.indianrail.gov.in/enquiry/FetchTrainData?_=` | Train search | Fetch train data |
| 15 | GET | `https://enquiry.indianrail.gov.in/enquiry/FetchAutoComplete?_=` | Search | Station autocomplete |
| 16 | GET | `https://enquiry.indianrail.gov.in/enquiry/CommonCaptcha?inputCaptcha=` | PNR | Captcha verify |
| 17 | GET | `https://mobondhrd.appspot.com/irgetcancelledtrains` | `ActivityCancelledRescheduledTrains` | Cancelled trains |
| 18 | GET | `http://m.mobond.com/pnrcheck?pnr=` | `GetPnrStatusService` | PNR check |
| 19 | GET | `https://irailpnrcheck.appspot.com/rcv_img?` | PNR screen | PNR captcha image |
| 20 | GET | `http://m.mobond.com/irgetseatdata` | `ActivitySeatStatus` | Seat availability |
| 21 | POST | `http://m.mobond.com/irputseatdata` | `ActivitySeatStatus` | Submit seat data |
| 22 | GET | `https://mobond.com/mtracker/getvolunteers` | `PeopleSharing` | mTracker volunteers |
| 23 | POST | `https://mobond.com/mtracker/register` | `PeopleSharing` | Register volunteer |
| 24 | POST | `https://mobond.com/mtracker/like` | `PeopleSharing` | Like report |
| 25 | GET | `https://mobond.com/acbustimings.jsp?&busnumber=` | Bus screen | AC bus by number |
| 26 | GET | `https://mobond.com/acbustimings.jsp?&routeid=` | Bus screen | AC bus by route |
| 27 | GET | `https://mobond.com/getcabs?` | Cab screen | Cab listings |
| 28 | GET | `https://mobond.com/autotaxidriverrating?city=` | Auto/Taxi screen | Driver ratings |
| 29 | GET | `https://mobond.com/ferrybookingmumbai` | Ferry screen | Ferry booking |
| 30 | GET | `https://mobond.com/mumbaimetrorecharge?` | Metro screen | Metro recharge |
| 31 | GET | `https://mobond.com/msrtcbooking?&mobondhandle=http` | MSRTC screen | MSRTC booking |
| 32 | GET | `https://mobond.com/jobs?city=` | Jobs screen | Job listings |
| 33 | POST | `https://mobond.com/jobsformsubmitservlet?` | Jobs screen | Apply for job |
| 34 | POST | `https://api.resumedb.in/uploadresumegeturl?contenttype=` | Jobs screen | Resume upload URL |
| 35 | GET | `https://mobond.com/places/i.jsp?city=` | Places | Tourist places |
| 36 | GET | `https://mobond.com/food/i.jsp?city=` | Food | Restaurants |
| 37 | GET | `https://mobond.com/hotels/i.jsp?city=&latitude=` | `ActivityStationSelectionHotels` | Hotels |
| 38 | GET | `https://mobond.com/howtotravel/i.jsp?city=` | Travel guide | How to travel |
| 39 | GET | `https://mobond.com/picnicspots?city=` | Picnic | Picnic spots |
| 40 | GET | `https://mobond.com/shopping/i.jsp?city=` | Shopping | Malls & shops |
| 41 | GET | `https://mobond.com/getexhibitionlist?city=` | Events | Exhibitions |
| 42 | GET | `https://mobond.com/manoranjan?city=` | Entertainment | Natak / Shows |
| 43 | GET | `https://mobond.com/getnewsalerts?` | `News` | Alerts |
| 44 | GET | `https://mobond.com/getads?` | `AdUI` | Native ads |
| 45 | GET | `https://odinsword.railofy.com/v1/getRailofyTravelGuarantee/?` | PNR screen | Travel guarantee |
| 46 | GET | `https://mobond.com/feedback` | `FeedbackUI` | App feedback |
| 47 | GET | `https://mobond.com/chat?` | `ChatScreenHSV` | Train chat |
| 48 | WS | `https://mobondhrd.firebaseio.com/` | `InsideLocalTrainService` | Realtime push |
| 49 | GET | `https://maps.googleapis.com/maps/api/directions/json?origin=` | `StationMap` | Route directions |

---

## Complete Offline Data (APK Assets)

| Asset Path | Content |
|-----------|---------|
| `assets/mumbai/local/W/<STATION>` | Western Railway timetable |
| `assets/mumbai/local/C/<STATION>` | Central Railway timetable |
| `assets/mumbai/local/H/<STATION>` | Harbour Line timetable |
| `assets/mumbai/local/T/<STATION>` | Trans-Harbour timetable |
| `assets/mumbai/local/U/<STATION>` | Uran Line timetable |
| `assets/mumbai/local/MM1WD/<STATION>` | Monorail timetable |
| `assets/mumbai/local/DPR/<STATION>` | DEMU Panvel–Roha |
| `assets/mumbai/local/DVP/<STATION>` | DEMU Vasai–Panvel |
| `assets/pune/local/P/<STATION>` | Pune local train timetable |
| `assets/pune/local/PN_AQUA/<STATION>` | Pune Metro Aqua Line |
| `assets/pune/local/PN_PURPLE/<STATION>` | Pune Metro Purple Line |
| `assets/mumbai/bus/BEST/EN_b1`, `EN_b2` | BEST bus routes |
| `assets/pune/bus/PMPML/EN_b1`, `EN_b2` | PMPML bus routes |
| `assets/mumbai/ferry/` | Ferry schedules |
| `assets/mumbai/taxi/` | Taxi tariff |
| `assets/mumbai/auto/` | Auto tariff |
| `assets/mumbai/penalty/railway` | Railway penalty charges |
| `assets/mumbai/penalty/traffic` | Traffic penalty charges |
| `assets/pune/penalty/railway` | Pune railway penalties |
| `assets/pune/penalty/traffic` | Pune traffic penalties |
| `assets/mumbai/emergency/` | Mumbai emergency contacts |
| `assets/pune/emergency/` | Pune emergency contacts |
| `assets/delhi/` | Delhi transit data |
| `assets/msrtc/` | MSRTC bus schedules |
| `assets/ir/` | Indian Railways offline reference |
| `assets/ibt` | Inter-city bus timetable |
| `assets/policedb` | Police station database (all cities) |
| `assets/mumbai/config.json` | Mumbai city config (tariffs, bus operators) |
| `assets/pune/config.json` | Pune city config |
| `assets/TC.txt` | Terms & Conditions text |
| `assets/error.html` | Offline error page |
| `assets/lostandfound.html` | Lost & Found page |
| `assets/safety/safetyhowitworks.html` | Safety feature guide |
| `assets/tourguide/tourguide.html` | App tour guide |

---

## Error Responses

| Status | Meaning | Example Body |
|--------|---------|--------------|
| `200` | Success | Varies by endpoint |
| `400` | Bad Request | `{ "error": "Missing required parameter: city" }` |
| `401` | Unauthorized | `{ "error": "Device not registered" }` |
| `404` | Not Found | `{ "error": "Train not found" }` |
| `429` | Rate Limited | `{ "error": "Too many requests. Retry after 60s" }` |
| `500` | Server Error | `{ "error": "Internal server error" }` |
| `503` | Maintenance | `{ "error": "Server under maintenance" }` |

---

## City Codes Reference

| Code | City |
|------|------|
| `mumbai` | Mumbai (MMR) |
| `pune` | Pune |
| `delhi` | Delhi (NCR) |

---

## App Contact

```
Email: support@mobond.com
Twitter: @m_indicator_app  (https://twitter.com/m_indicator_app)
Facebook: https://www.facebook.com/m.indicator.official
```

---

*This is a MASTER document — merged from all 3 analysis passes of the m-Indicator APK.*  
*Source: `com.mobond.mindicator` v17.0.347 — `classes.dex`, `classes2.dex`, APK asset files.*  
*Method: DEX bytecode string extraction, class hierarchy analysis, URL pattern matching.*  
*No official API documentation was referenced. All content reverse-engineered.*
