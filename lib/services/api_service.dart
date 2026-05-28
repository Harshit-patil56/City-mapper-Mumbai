import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Custom exception for API errors with structured error information.
class ApiException implements Exception {
  final String code;
  final String message;
  final int? statusCode;

  const ApiException({
    required this.code,
    required this.message,
    this.statusCode,
  });

  @override
  String toString() => 'ApiException($code, $statusCode): $message';
}

/// Parsed live train entry from the station live board API.
class LiveTrainEntry {
  final String trainNumber;
  final String trainName;
  final String? trainType;
  final String sourceStation;
  final String destinationStation;
  final List<String> runDays;

  final int stopSequence;
  final String? scheduledArrival;
  final String? scheduledDeparture;
  final int? stopDay;
  final double? distanceFromSource;

  /// One of: "at-station", "upcoming", "departed", "scheduled"
  final String liveType;
  final String? startDate;
  final int? delayMinutes;

  /// ISO 8601 timestamp — present when liveType == "at-station"
  final String? expectedDepartureTime;

  /// ISO 8601 timestamp — present when liveType == "upcoming"
  final String? expectedArrivalTime;

  /// ISO 8601 timestamp — present when liveType == "departed"
  final String? departedAt;

  const LiveTrainEntry({
    required this.trainNumber,
    required this.trainName,
    this.trainType,
    required this.sourceStation,
    required this.destinationStation,
    required this.runDays,
    required this.stopSequence,
    this.scheduledArrival,
    this.scheduledDeparture,
    this.stopDay,
    this.distanceFromSource,
    required this.liveType,
    this.startDate,
    this.delayMinutes,
    this.expectedDepartureTime,
    this.expectedArrivalTime,
    this.departedAt,
  });

  /// Parses a single train entry from the `/stations/{code}/live` response.
  factory LiveTrainEntry.fromJson(Map<String, dynamic> json) {
    final train = json['train'] as Map<String, dynamic>;
    final stop = json['stop'] as Map<String, dynamic>;
    final live = json['live'] as Map<String, dynamic>;

    return LiveTrainEntry(
      trainNumber: train['number'] as String,
      trainName: train['name'] as String,
      trainType: train['type'] as String?,
      sourceStation: train['source'] as String,
      destinationStation: train['destination'] as String,
      runDays: (train['runDays'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      stopSequence: stop['sequence'] as int,
      scheduledArrival: stop['arrival'] as String?,
      scheduledDeparture: stop['departure'] as String?,
      stopDay: stop['day'] as int?,
      distanceFromSource: () {
        final dist = stop['distance'];
        if (dist is num) return dist.toDouble();
        if (dist is String) return double.tryParse(dist);
        return null;
      }(),
      liveType: live['type'] as String,
      startDate: live['startDate'] as String?,
      delayMinutes: live['delayMinutes'] as int?,
      expectedDepartureTime: live['expectedDepartureTime'] as String?,
      expectedArrivalTime: live['expectedArrivalTime'] as String?,
      departedAt: live['departedAt'] as String?,
    );
  }

  /// Parses a single train entry from the static timetable `/stations/{code}/trains` response.
  factory LiveTrainEntry.fromStationBoardJson(Map<String, dynamic> json) {
    final train = json['train'] as Map<String, dynamic>;
    final stop = json['stop'] as Map<String, dynamic>;

    // Source and destination can be objects (StationRef) or strings. Let's support both.
    final sourceCode = (train['source'] is Map)
        ? train['source']['code'] as String
        : train['source'] as String;
    final destCode = (train['destination'] is Map)
        ? train['destination']['code'] as String
        : train['destination'] as String;

    return LiveTrainEntry(
      trainNumber: train['number'] as String,
      trainName: train['name'] as String,
      trainType: train['type'] as String?,
      sourceStation: sourceCode,
      destinationStation: destCode,
      runDays: (train['runDays'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      stopSequence: stop['sequence'] as int? ?? 0,
      scheduledArrival: stop['arrival'] as String?,
      scheduledDeparture: stop['departure'] as String?,
      stopDay: stop['departureDay'] as int?,
      distanceFromSource: (stop['distance'] as num?)?.toDouble(),
      liveType: 'scheduled', // no live status for static board
    );
  }

  /// Whether this train is considered "on time" (delay <= 0 or null).
  bool get isOnTime => (delayMinutes ?? 0) <= 0;

  /// Whether the delay is considered minor (1-10 minutes).
  bool get isMinorDelay {
    final d = delayMinutes ?? 0;
    return d > 0 && d <= 10;
  }

  /// Whether the delay is considered major (>10 minutes).
  bool get isMajorDelay => (delayMinutes ?? 0) > 10;
}

/// A single stop on a train's route from the RailGadi /trains/{number} endpoint.
class RailGadiTrainStop {
  final int sequence;
  final String stationCode;
  final String stationName;
  final String? arrival;   // "HH:MM" or null for origin
  final String? departure; // "HH:MM" or null for terminus
  final double? distance;

  const RailGadiTrainStop({
    required this.sequence,
    required this.stationCode,
    required this.stationName,
    this.arrival,
    this.departure,
    this.distance,
  });

  factory RailGadiTrainStop.fromJson(Map<String, dynamic> json) {
    final stn = json['station'] as Map<String, dynamic>? ?? {};
    return RailGadiTrainStop(
      sequence: json['sequence'] as int? ?? 0,
      stationCode: stn['code'] as String? ?? '',
      stationName: stn['name'] as String? ?? '',
      arrival: json['arrival'] as String?,
      departure: json['departure'] as String?,
      distance: (json['distance'] as num?)?.toDouble(),
    );
  }
}

/// Response wrapper for the station live board.
class StationLiveBoardResponse {
  final String stationCode;
  final String stationName;
  final String windowFrom;
  final String windowTo;
  final int count;
  final List<LiveTrainEntry> trains;

  const StationLiveBoardResponse({
    required this.stationCode,
    required this.stationName,
    required this.windowFrom,
    required this.windowTo,
    required this.count,
    required this.trains,
  });

  factory StationLiveBoardResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>;
    final station = data['station'] as Map<String, dynamic>;
    final window = data['window'] as Map<String, dynamic>;
    final trainsList = data['trains'] as List<dynamic>;

    return StationLiveBoardResponse(
      stationCode: station['code'] as String,
      stationName: station['name'] as String,
      windowFrom: window['from'] as String,
      windowTo: window['to'] as String,
      count: data['count'] as int,
      trains:
          trainsList.map((t) => LiveTrainEntry.fromJson(t as Map<String, dynamic>)).toList(),
    );
  }
}

/// Centralized API client for the RailGadi train tracking API.
///
/// All methods return typed Dart objects or throw [ApiException].
class RailGadiApiService {
  static const String _baseUrl =
      'https://2fe4m4jegh2fuhgkk3u7v4sqv40qpago.lambda-url.ap-south-1.on.aws';

  static const Duration _timeout = Duration(seconds: 10);

  final http.Client _client;

  /// Creates a new API service instance.
  ///
  /// Accepts an optional [http.Client] for testing/injection.
  RailGadiApiService({http.Client? client}) : _client = client ?? http.Client();

  /// Fetches the live departure board for a station.
  ///
  /// [code] — Indian Railways station code (e.g. "CSTM", "BCT").
  /// [hours] — Hours ahead to look for trains. Allowed: 2, 4, 6, 8. Default: 4.
  ///
  /// Returns a [StationLiveBoardResponse] with all upcoming trains.
  /// Throws [ApiException] on network or API errors.
  Future<StationLiveBoardResponse> getStationLiveBoard(
    String code, {
    int hours = 4,
  }) async {
    final uri = Uri.parse('$_baseUrl/stations/$code/live?hours=$hours');

    final http.Response response;
    try {
      response = await _client.get(uri).timeout(_timeout);
    } on TimeoutException {
      throw const ApiException(
        code: 'TIMEOUT',
        message: 'Request timed out. Please check your connection.',
      );
    } catch (e) {
      throw ApiException(
        code: 'NETWORK_ERROR',
        message: 'Could not connect to server: $e',
      );
    }

    if (response.statusCode == 200) {
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;

      final bool success = body['success'] as bool? ?? false;
      if (!success) {
        final error = body['error'] as Map<String, dynamic>?;
        throw ApiException(
          code: error?['code'] as String? ?? 'UNKNOWN',
          message: error?['message'] as String? ?? 'Unknown error',
          statusCode: response.statusCode,
        );
      }

      return StationLiveBoardResponse.fromJson(body);
    } else if (response.statusCode == 404) {
      throw ApiException(
        code: 'NOT_FOUND',
        message: 'Station "$code" not found.',
        statusCode: 404,
      );
    } else if (response.statusCode == 503) {
      throw const ApiException(
        code: 'SERVICE_UNAVAILABLE',
        message: 'Train tracking service is temporarily unavailable.',
        statusCode: 503,
      );
    } else {
      throw ApiException(
        code: 'HTTP_ERROR',
        message: 'Server returned status ${response.statusCode}.',
        statusCode: response.statusCode,
      );
    }
  }

  /// Fetches the full stop-by-stop schedule for [trainNumber].
  ///
  /// Uses `/trains/{number}?haltsOnly=true` — confirmed working endpoint.
  /// Returns an empty list on failure so callers degrade gracefully.
  Future<List<RailGadiTrainStop>> getTrainSchedule(String trainNumber) async {
    final uri = Uri.parse('$_baseUrl/trains/$trainNumber?haltsOnly=true');
    try {
      final response = await _client.get(uri).timeout(_timeout);
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final success = body['success'] as bool? ?? false;
        if (success) {
          final data = body['data'] as Map<String, dynamic>?;
          final route = data?['route'] as List<dynamic>?;
          if (route != null) {
            return route
                .map((s) =>
                    RailGadiTrainStop.fromJson(s as Map<String, dynamic>))
                .toList();
          }
        }
      }
    } catch (_) {}
    return [];
  }

  /// Fetches the static timetable for a station.
  ///
  /// Uses `/stations/{code}/trains?includeIntermediate=false` endpoint.
  /// Returns a list of LiveTrainEntry representing the scheduled trains.
  Future<List<LiveTrainEntry>> getStationTimetable(String code) async {
    final uri = Uri.parse('$_baseUrl/stations/$code/trains?includeIntermediate=false');
    try {
      final response = await _client.get(uri).timeout(_timeout);
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final success = body['success'] as bool? ?? false;
        if (success) {
          final data = body['data'] as Map<String, dynamic>;
          final trainsList = data['trains'] as List<dynamic>;
          return trainsList
              .map((t) => LiveTrainEntry.fromStationBoardJson(t as Map<String, dynamic>))
              .toList();
        }
      }
    } catch (_) {}
    return [];
  }

  /// Disposes the underlying HTTP client.
  void dispose() {
    _client.close();
  }
}

// ============================================================
// mIndicator API — Data Models
// ============================================================

/// One stop in a train's route with scheduled + live timing.
class MIndicatorStationStop {
  final String stationCode;
  final String stationName;
  final String? scheduledArrival;
  final String? scheduledDeparture;
  final String? actualArrivalTime;
  final String? actualDepartureTime;
  final int? delayArr;
  final int? delayDep;
  final bool isArrived;
  final bool isDeparted;
  final String? platform;
  final int? distance;

  const MIndicatorStationStop({
    required this.stationCode,
    required this.stationName,
    this.scheduledArrival,
    this.scheduledDeparture,
    this.actualArrivalTime,
    this.actualDepartureTime,
    this.delayArr,
    this.delayDep,
    this.isArrived = false,
    this.isDeparted = false,
    this.platform,
    this.distance,
  });

  static String? _cleanTime(String? t) {
    if (t == null || t == '--' || t.isEmpty) return null;
    return t;
  }

  static int? _parseInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is String) return int.tryParse(v);
    if (v is double) return v.toInt();
    return null;
  }

  factory MIndicatorStationStop.fromJson(Map<String, dynamic> json) {
    return MIndicatorStationStop(
      stationCode: json['stationCode'] as String? ?? '',
      stationName: json['stationName'] as String? ?? '',
      scheduledArrival: _cleanTime(json['arrivalTime'] as String?),
      scheduledDeparture: _cleanTime(json['departureTime'] as String?),
      actualArrivalTime: json['actualArrivalTime'] as String?,
      actualDepartureTime: json['actualDepartureTime'] as String?,
      delayArr: _parseInt(json['delayArr']),
      delayDep: _parseInt(json['delayDep']),
      isArrived: json['isTrain_Arrived'] as bool? ?? false,
      isDeparted: json['isTrain_Departed'] as bool? ?? false,
      platform: json['platform'] as String?,
      distance: _parseInt(json['distance']),
    );
  }
}

/// Full live running status of a train from the mIndicator API.
class MIndicatorRunningStatus {
  final String trainNo;
  final String trainName;
  final String? trainSrc;
  final String? trainDstn;
  final String? status;
  final int? delay;
  final String? currentStation;
  final String? nextStation;
  final String? platform;
  final double? latitude;
  final double? longitude;
  final int? speed;
  final int? volunteers;
  final List<MIndicatorStationStop> stops;

  const MIndicatorRunningStatus({
    required this.trainNo,
    required this.trainName,
    this.trainSrc,
    this.trainDstn,
    this.status,
    this.delay,
    this.currentStation,
    this.nextStation,
    this.platform,
    this.latitude,
    this.longitude,
    this.speed,
    this.volunteers,
    required this.stops,
  });

  bool get isDelayed => (delay ?? 0) > 0;
  bool get isCancelled => status?.toUpperCase().contains('CANCEL') ?? false;
  bool get isAtStation => status?.toUpperCase().contains('AT STATION') ?? false;
  bool get isRunning => status?.toUpperCase() == 'RUNNING';

  factory MIndicatorRunningStatus.fromJson(Map<String, dynamic> json) {
    double? parseDouble(dynamic v) {
      if (v == null) return null;
      if (v is double) return v;
      if (v is int) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    int? parseInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is String) return int.tryParse(v);
      if (v is double) return v.toInt();
      return null;
    }

    final rawStops = json['stations'] as List<dynamic>?;
    return MIndicatorRunningStatus(
      trainNo: json['trainNo'] as String? ?? json['trainNO'] as String? ?? '',
      trainName: json['trainName'] as String? ?? '',
      trainSrc: json['trainSrc'] as String?,
      trainDstn: json['trainDstn'] as String? ?? json['dstnCode'] as String?,
      status: json['status'] as String?,
      delay: parseInt(json['delay']),
      currentStation: json['currentStation'] as String?,
      nextStation: json['nextStation'] as String?,
      platform: json['platform'] as String?,
      latitude: parseDouble(json['latitude']),
      longitude: parseDouble(json['longitude']),
      speed: parseInt(json['speed']),
      volunteers: parseInt(json['volunteers']),
      stops: rawStops
              ?.map((s) =>
                  MIndicatorStationStop.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

/// A cancelled / diverted / rescheduled train from mIndicator.
class MIndicatorCancelledTrain {
  final String trainNo;
  final String trainName;
  final String cancelledType;
  final String? reason;
  final String? fromStnCode;
  final String? toStnCode;
  final String? originalDepartureTime;
  final String? newDepartureTime;

  const MIndicatorCancelledTrain({
    required this.trainNo,
    required this.trainName,
    required this.cancelledType,
    this.reason,
    this.fromStnCode,
    this.toStnCode,
    this.originalDepartureTime,
    this.newDepartureTime,
  });

  factory MIndicatorCancelledTrain.fromJson(Map<String, dynamic> json) {
    return MIndicatorCancelledTrain(
      trainNo: json['trainNo'] as String? ?? '',
      trainName: json['trainName'] as String? ?? '',
      cancelledType: json['cancelledType'] as String? ?? 'CANCELLED',
      reason: json['reason'] as String?,
      fromStnCode: json['fromStnCode'] as String?,
      toStnCode: json['toStnCode'] as String?,
      originalDepartureTime: json['originalDepartureTime'] as String?,
      newDepartureTime: json['newDepartureTime'] as String?,
    );
  }

  bool get isCancelled => cancelledType.contains('CANCELLED');
  bool get isDiverted => cancelledType.contains('DIVERTED');
  bool get isRescheduled => cancelledType.contains('RESCHEDULED');
}

/// A transport alert / news item from mIndicator.
class MIndicatorAlert {
  final String? id;
  final String title;
  final String body;
  final String? severity;
  final String? timestamp;

  const MIndicatorAlert({
    this.id,
    required this.title,
    required this.body,
    this.severity,
    this.timestamp,
  });

  factory MIndicatorAlert.fromJson(Map<String, dynamic> json) {
    return MIndicatorAlert(
      id: json['id']?.toString(),
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? json['content'] as String? ?? '',
      severity: json['severity'] as String?,
      timestamp: json['timestamp'] as String?,
    );
  }
}

// ============================================================
// mIndicator API Service
// ============================================================

/// API client for mIndicator (mobond.com) — Mumbai's most popular commuter app.
///
/// Uses Android-style headers so the server returns real data.
/// Falls back to RailGadi where mIndicator returns empty responses.
class MIndicatorApiService {
  static const String _primaryUrl = 'https://mobond.com';
  static const String _hrdUrl = 'https://mobondhrd.appspot.com';

  static const Duration _timeout = Duration(seconds: 12);

  /// Android headers that unlock mIndicator's real data.
  static const Map<String, String> _headers = {
    'User-Agent':
        'Dalvik/2.1.0 (Linux; U; Android 13; Pixel 7 Build/TQ3A.230901.001)',
    'X-Requested-With': 'com.mobond.mindicator',
    'Accept': 'application/json',
  };

  final http.Client _client;
  String? _deviceId;
  bool _registered = false;

  MIndicatorApiService({http.Client? client})
      : _client = client ?? http.Client();

  // ── Device ID ──────────────────────────────────────────────

  Future<String> _getDeviceId() async {
    if (_deviceId != null) return _deviceId!;
    try {
      final prefs = await SharedPreferences.getInstance();
      String? stored = prefs.getString('mi_deviceid');
      if (stored == null) {
        stored = _generateId();
        await prefs.setString('mi_deviceid', stored);
      }
      _deviceId = stored;
    } catch (_) {
      _deviceId = _generateId();
    }
    return _deviceId!;
  }

  String _generateId() {
    // 16-char hex using dart:math — no extra package needed
    final now = DateTime.now().millisecondsSinceEpoch;
    return now.toRadixString(16).padLeft(16, '0').substring(0, 16);
  }

  Future<void> _ensureRegistered() async {
    if (_registered) return;
    final id = await _getDeviceId();
    try {
      final uri = Uri.parse(
          '$_primaryUrl/registermindicatoronlinev2?city=mumbai&deviceid=$id&version=347');
      await _client.get(uri, headers: _headers).timeout(_timeout);
    } catch (_) {
      // Non-fatal — continue without registration
    }
    _registered = true;
  }

  // ── Helper: parse and validate response ───────────────────

  Map<String, dynamic>? _parseJson(http.Response resp) {
    if (resp.statusCode != 200) return null;
    final body = resp.body.trim();
    if (body.isEmpty || body == 'null' || body == '[]') return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic> && decoded.isNotEmpty) return decoded;
    } catch (_) {}
    return null;
  }

  // ── Public API Methods ─────────────────────────────────────

  /// Live running status for [trainNo].
  /// Returns null if mIndicator returns empty (caller can use RailGadi data).
  Future<MIndicatorRunningStatus?> getRunningStatus(String trainNo) async {
    await _ensureRegistered();
    final id = await _getDeviceId();

    // Primary server
    try {
      final uri = Uri.parse(
          '$_primaryUrl/irgetrunningstatus?trainno=$trainNo&deviceid=$id');
      final resp =
          await _client.get(uri, headers: _headers).timeout(_timeout);
      final data = _parseJson(resp);
      if (data != null) return MIndicatorRunningStatus.fromJson(data);
    } catch (_) {}

    // Fallback HRD server
    try {
      final uri = Uri.parse('$_hrdUrl/irgetrunningstatus?trainno=$trainNo');
      final resp =
          await _client.get(uri, headers: _headers).timeout(_timeout);
      final data = _parseJson(resp);
      if (data != null) return MIndicatorRunningStatus.fromJson(data);
    } catch (_) {}

    return null;
  }

  /// Today's cancelled, diverted, and rescheduled trains.
  Future<List<MIndicatorCancelledTrain>> getCancelledTrains() async {
    try {
      final uri = Uri.parse('$_hrdUrl/irgetcancelledtrains');
      final resp =
          await _client.get(uri, headers: _headers).timeout(_timeout);
      if (resp.statusCode == 200 &&
          resp.body.isNotEmpty &&
          resp.body.trim() != 'null') {
        final data = jsonDecode(resp.body);
        if (data is Map<String, dynamic>) {
          final result = <MIndicatorCancelledTrain>[];
          for (final key in [
            'allCancelledTrains',
            'allPartiallyCancelledTrains',
            'allDivertedTrains',
            'allRescheduledTrains',
          ]) {
            final list = data[key] as List<dynamic>?;
            if (list != null) {
              result.addAll(list.map((e) => MIndicatorCancelledTrain.fromJson(
                  e as Map<String, dynamic>)));
            }
          }
          return result;
        }
      }
    } catch (_) {}
    return [];
  }

  /// Transport news alerts for Mumbai.
  Future<List<MIndicatorAlert>> getNewsAlerts() async {
    try {
      final uri =
          Uri.parse('$_primaryUrl/getnewsalerts?city=mumbai&type=transport');
      final resp =
          await _client.get(uri, headers: _headers).timeout(_timeout);
      if (resp.statusCode == 200 && resp.body.isNotEmpty) {
        final data = jsonDecode(resp.body);
        if (data is Map<String, dynamic>) {
          final alerts = data['alerts'] as List<dynamic>?;
          if (alerts != null) {
            return alerts
                .map((e) =>
                    MIndicatorAlert.fromJson(e as Map<String, dynamic>))
                .toList();
          }
        }
      }
    } catch (_) {}
    return [];
  }

  /// Number of mTracker volunteers currently tracking [trainNo].
  Future<int?> getVolunteerCount(String trainNo) async {
    try {
      final uri = Uri.parse(
          '$_primaryUrl/mtracker/getvolunteers?trainno=$trainNo');
      final resp =
          await _client.get(uri, headers: _headers).timeout(_timeout);
      final data = _parseJson(resp);
      return data?['total'] as int?;
    } catch (_) {}
    return null;
  }

  void dispose() => _client.close();
}

