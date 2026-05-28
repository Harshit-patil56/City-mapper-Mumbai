import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:lucide_icons/lucide_icons.dart';
import '../../data/mumbai_stations.dart';
import '../../services/api_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Citymapper-exact Singapore Circle Line MRT Style Train Detail Sheet
//
// Layout:
//   • Route Map at the Top  — draws polyline + station markers
//   • Colored line header   — source - destination ∨ (matches Singapore MRT style)
//   • White body            — route info card + vertical stop timeline
//                             (thick line color matching line + Singapore active halo dot)
//   • Footer                — last-updated label, refresh button
// ─────────────────────────────────────────────────────────────────────────────

const _bg       = Colors.white;
const _ink      = Color(0xFF1E293B);   // primary text
const _inkMid   = Color(0xFF64748B);   // secondary text
const _inkFaint = Color(0xFFCBD5E1);   // disabled / past
const _surface  = Color(0xFFF8FAFC);   // slight tint for footer

class TrainDetailSheet extends StatefulWidget {
  final LiveTrainEntry train;
  const TrainDetailSheet({super.key, required this.train});

  @override
  State<TrainDetailSheet> createState() => _TrainDetailSheetState();
}

class _TrainDetailSheetState extends State<TrainDetailSheet>
    with SingleTickerProviderStateMixin {
  final _railGadi   = RailGadiApiService();
  final _mIndicator = MIndicatorApiService();

  List<RailGadiTrainStop> _stops      = [];
  MIndicatorRunningStatus? _live;
  bool   _loadingSchedule = true;
  bool   _loadingLive     = true;
  DateTime? _lastRefresh;
  Timer? _refreshTimer;
  Timer? _tickTimer;

  final MapController _mapController = MapController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchAll();
    _refreshTimer = Timer.periodic(const Duration(seconds: 60),
        (_) => _fetchLive());
    _tickTimer = Timer.periodic(const Duration(seconds: 10),
        (_) { if (mounted) setState(() {}); });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tickTimer?.cancel();
    _scroll.dispose();
    _railGadi.dispose();
    _mIndicator.dispose();
    super.dispose();
  }

  // ── Data fetching ─────────────────────────────────────────

  Future<void> _fetchAll() =>
      Future.wait([_fetchSchedule(), _fetchLive()]);

  Future<void> _fetchSchedule() async {
    if (!mounted) return;
    setState(() => _loadingSchedule = true);
    final stops =
        await _railGadi.getTrainSchedule(widget.train.trainNumber);
    if (!mounted) return;
    setState(() { _stops = stops; _loadingSchedule = false; });
    if (stops.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToCurrent();
        _fitMapToRoute();
      });
    }
  }

  Future<void> _fetchLive() async {
    if (!mounted) return;
    setState(() => _loadingLive = true);
    final live =
        await _mIndicator.getRunningStatus(widget.train.trainNumber);
    if (!mounted) return;
    setState(() { _live = live; _loadingLive = false;
                  _lastRefresh = DateTime.now(); });
  }

  void _scrollToCurrent() {
    if (!_scroll.hasClients || _stops.isEmpty) return;
    final idx = _currentIdx;
    if (idx <= 1) return;
    final target = (idx * 62.0)
        .clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(target,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOut);
  }

  void _fitMapToRoute() {
    if (_stops.isEmpty) return;
    final points = _stops
        .map((s) => _getStationLatLng(s.stationCode, s.stationName))
        .whereType<LatLng>()
        .toList();
    if (points.isEmpty) return;

    try {
      final bounds = LatLngBounds.fromPoints(points);
      _mapController.fitCamera(CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(24),
      ));
    } catch (_) {}
  }

  // ── Helpers ───────────────────────────────────────────────

  /// Resolve train line
  TrainLine get _line {
    if (_stops.isNotEmpty) {
      for (final stop in _stops) {
        for (final station in MumbaiStationData.allStations) {
          if (station.code.toUpperCase() == stop.stationCode.toUpperCase()) {
            return station.line;
          }
        }
      }
    }
    if (widget.train.trainNumber.startsWith('9')) return TrainLine.western;
    return TrainLine.central;
  }

  LatLng? _getStationLatLng(String code, String name) {
    final cleanCode = code.trim().toUpperCase();
    final cleanName = name.trim().toUpperCase();
    for (final station in MumbaiStationData.allStations) {
      if (station.code.toUpperCase() == cleanCode ||
          station.name.toUpperCase() == cleanName) {
        return LatLng(station.lat, station.lng);
      }
    }
    return null;
  }

  List<TrainLine> _getInterchangeLines(String stationName) {
    final cleanName = stationName.trim().toUpperCase();
    final lines = <TrainLine>{};
    for (final station in MumbaiStationData.allStations) {
      if (station.name.toUpperCase() == cleanName) {
        lines.add(station.line);
      }
    }
    lines.remove(_line);
    return lines.toList();
  }

  /// Whether the train has not started yet
  bool get _isNotStarted {
    if (_live != null) {
      if (_live!.currentStation == null && _live!.nextStation == null) {
        return true;
      }
    }
    if (_stops.isNotEmpty) {
      final first = _stops.first;
      final raw = first.departure ?? first.arrival;
      if (raw != null) {
        final now = TimeOfDay.now();
        final parts = raw.split(':');
        if (parts.length >= 2) {
          final h = int.tryParse(parts[0]) ?? 0;
          final m = int.tryParse(parts[1]) ?? 0;
          if (now.hour < h || (now.hour == h && now.minute < m)) {
            return true;
          }
        }
      }
    }
    return false;
  }

  /// Index of the "current" stop based on wall clock vs schedule or live status.
  int get _currentIdx {
    if (_stops.isEmpty) return 0;
    if (_isNotStarted) return 0; // highlight the first station if not started yet

    if (_live?.currentStation != null) {
      final idx = _stops.indexWhere((s) =>
          s.stationName.toUpperCase() == _live!.currentStation!.toUpperCase() ||
          s.stationCode.toUpperCase() == _live!.currentStation!.toUpperCase());
      if (idx != -1) return idx;
    }

    final now = TimeOfDay.now();
    int best = 0;
    for (int i = 0; i < _stops.length; i++) {
      final raw = _stops[i].departure ?? _stops[i].arrival;
      if (raw == null) continue;
      final p = raw.split(':');
      if (p.length < 2) continue;
      final h = int.tryParse(p[0]) ?? 0;
      final m = int.tryParse(p[1]) ?? 0;
      if (h < now.hour || (h == now.hour && m <= now.minute)) { best = i; }
    }
    return best;
  }

  String get _elapsedLabel {
    if (_lastRefresh == null) return '';
    final d = DateTime.now().difference(_lastRefresh!);
    if (d.inSeconds < 60) return 'Live · ${d.inSeconds}s ago';
    return 'Live · ${d.inMinutes}m ago';
  }

  // ── Status for the header pill ────────────────────────────

  ({String label, Color bg}) get _statusChip {
    if (_isNotStarted) {
      return (label: 'NOT STARTED', bg: const Color(0xFF475569));
    }
    if (_live != null) {
      if (_live!.isCancelled) {
        return (label: 'CANCELLED', bg: const Color(0xFFDC2626));
      }
      if (_live!.isAtStation) {
        return (label: 'AT PLATFORM ${_live!.platform ?? ''}',
                bg: const Color(0xFF2563EB));
      }
      if (_live!.isDelayed) {
        return (label: 'DELAYED ${_live!.delay} MIN',
                bg: const Color(0xFFD97706));
      }
      return (label: 'RUNNING', bg: const Color(0xFF16A34A));
    }
    // RailGadi-derived
    return switch (widget.train.liveType) {
      'at-station' => (label: 'AT STATION', bg: const Color(0xFF2563EB)),
      'departed'   => (label: 'DEPARTED',   bg: _inkMid),
      _            => (label: 'SCHEDULED',  bg: _inkMid),
    };
  }

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          _buildMapHeader(),
          _buildColoredHeaderStrip(),
          Expanded(child: _buildBody()),
          _buildFooter(),
        ],
      ),
    );
  }

  // ── Route Map at the Top ──────────────────────────────────

  Widget _buildMapHeader() {
    final routePoints = _stops
        .map((s) => _getStationLatLng(s.stationCode, s.stationName))
        .whereType<LatLng>()
        .toList();

    return SizedBox(
      height: 220,
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(19.0760, 72.8777),
              initialZoom: 11.5,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.quntanix.citymappermumbai',
              ),
              if (routePoints.isNotEmpty) ...[
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: routePoints,
                      color: _line.color,
                      strokeWidth: 5.0,
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: _stops.map((stop) {
                    final latLng = _getStationLatLng(stop.stationCode, stop.stationName);
                    if (latLng == null) return null;

                    final isCur = _stops.indexOf(stop) == _currentIdx;

                    return Marker(
                      point: latLng,
                      width: isCur ? 24 : 12,
                      height: isCur ? 24 : 12,
                      child: isCur
                          ? Container(
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0x3D2F80ED), // 24% opacity blue halo
                              ),
                              child: Center(
                                child: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color(0xFF2F80ED), // active blue dot
                                  ),
                                ),
                              ),
                            )
                          : Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                                border: Border.all(
                                  color: _line.color,
                                  width: 2.5,
                                ),
                              ),
                            ),
                    );
                  }).whereType<Marker>().toList(),
                ),
              ],
            ],
          ),
          // Floating close button
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: IconButton(
                icon: const Icon(LucideIcons.x, size: 16, color: Colors.black87),
                onPressed: () => Navigator.of(context).pop(),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Colored header strip (Singapore MRT style) ────────────

  Widget _buildColoredHeaderStrip() {
    return Container(
      color: _line.color,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              '${widget.train.sourceStation} · ${widget.train.destinationStation}',
              style: GoogleFonts.outfit(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          const Icon(
            LucideIcons.chevronDown,
            size: 16,
            color: Colors.white,
          ),
        ],
      ),
    );
  }

  // ── Timeline body ─────────────────────────────────────────

  Widget _buildBody() {
    if (_loadingSchedule) {
      return const Center(
          child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(_inkMid),
              strokeWidth: 2));
    }

    if (_stops.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.train,
                  size: 40, color: _inkFaint),
              const SizedBox(height: 14),
              Text('Schedule unavailable',
                  style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _inkMid)),
              const SizedBox(height: 4),
              Text(
                'Train ${widget.train.trainNumber} is not found '
                'in the RailGadi database.',
                style: GoogleFonts.outfit(
                    fontSize: 12, color: _inkFaint),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final cur = _currentIdx;

    return Column(
      children: [
        _buildRouteInfoCard(),
        const Divider(height: 1, color: Color(0xFFF1F5F9)),
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
            itemCount: _stops.length,
            itemBuilder: (ctx, i) => _stopRow(_stops, i, cur),
          ),
        ),
      ],
    );
  }

  Widget _buildRouteInfoCard() {
    final chip = _statusChip;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Train number badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                decoration: BoxDecoration(
                  color: _line.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _line.color.withValues(alpha: 0.3)),
                ),
                child: Text(
                  widget.train.trainNumber,
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: _line.color,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.train.trainName,
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                decoration: BoxDecoration(
                  color: chip.bg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  chip.label,
                  style: GoogleFonts.outfit(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              if (_live != null && !_live!.isCancelled) ...[
                const SizedBox(width: 8),
                _LiveLabel(lineColor: _line.color),
              ],
              if (_live?.platform != null && _live!.platform!.isNotEmpty) ...[
                const SizedBox(width: 8),
                _InfoChip(icon: LucideIcons.layoutTemplate, label: 'Pf ${_live!.platform}', lineColor: _line.color),
              ],
              if ((_live?.speed ?? 0) > 0) ...[
                const SizedBox(width: 6),
                _InfoChip(icon: LucideIcons.zap, label: '${_live!.speed} km/h', lineColor: _line.color),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ── Individual stop row (Singapore MRT style) ────────────

  Widget _stopRow(List<RailGadiTrainStop> stops, int i, int cur) {
    final stop    = stops[i];
    final isFirst = i == 0;
    final isLast  = i == stops.length - 1;
    final isCur   = i == cur;
    final isPast  = i < cur;

    final time = isFirst
        ? (stop.departure ?? '')
        : isLast
            ? (stop.arrival ?? '')
            : (stop.arrival ?? stop.departure ?? '');

    final Color nameColor = isCur
        ? _ink
        : isPast
            ? _inkFaint
            : _ink;
    final FontWeight nameWeight =
        isCur ? FontWeight.w700 : FontWeight.w500;
    final Color timeColor = isCur ? const Color(0xFF2F80ED) : _inkMid;

    final interchangeLines = _getInterchangeLines(stop.stationName);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Timeline column with custom painter for ticks, vertical line and active dot
          CustomPaint(
            size: const Size(32, 0),
            painter: TimelinePainter(
              lineColor: _line.color,
              pastColor: _inkFaint,
              isFirst: isFirst,
              isLast: isLast,
              isCur: isCur,
              isPast: isPast,
            ),
          ),

          // Content column
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              stop.stationName.isNotEmpty
                                  ? stop.stationName
                                  : stop.stationCode,
                              style: GoogleFonts.outfit(
                                fontSize: isCur ? 15 : 14,
                                fontWeight: nameWeight,
                                color: nameColor,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // Connection badges (like Paya Lebar EW badge in screenshot)
                          if (interchangeLines.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            ...interchangeLines.map((line) => Container(
                              margin: const EdgeInsets.only(right: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: line.color,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                line.shortCode,
                                style: GoogleFonts.outfit(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            )),
                          ],
                        ],
                      ),
                    ),
                    if (time.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(time,
                          style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: isCur
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: timeColor,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ])),
                    ],
                  ],
                ),
                if (isCur && (_live?.delay ?? 0) > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${_live!.delay} min late',
                    style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFD97706)),
                  ),
                ],
                const SizedBox(height: 14),
                // Divider line below the station (only right of timeline)
                const Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Footer ────────────────────────────────────────────────

  Widget _buildFooter() {
    return Container(
      color: _surface,
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 24),
      child: Row(
        children: [
          const Icon(LucideIcons.clock4, size: 12, color: _inkFaint),
          const SizedBox(width: 5),
          Text(
            _loadingLive
                ? 'Fetching live…'
                : _lastRefresh == null
                    ? 'Schedule only'
                    : _elapsedLabel,
            style: GoogleFonts.outfit(
                fontSize: 12, color: _inkMid),
          ),
          if (_stops.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text('· ${_stops.length} stops',
                style: GoogleFonts.outfit(
                    fontSize: 12, color: _inkFaint)),
          ],
          const Spacer(),
          TextButton.icon(
            onPressed:
                (_loadingSchedule || _loadingLive) ? null : _fetchAll,
            icon: Icon(LucideIcons.refreshCw,
                size: 13, color: _line.color),
            label: Text('Refresh',
                style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _line.color)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 6),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small UI helpers
// ─────────────────────────────────────────────────────────────────────────────

class _LiveLabel extends StatefulWidget {
  final Color lineColor;
  const _LiveLabel({required this.lineColor});
  @override
  State<_LiveLabel> createState() => _LiveLabelState();
}

class _LiveLabelState extends State<_LiveLabel>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;
  late Animation<double> _a;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
    _a = Tween<double>(begin: 0.3, end: 1.0).animate(_c);
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _a,
          builder: (ctx, child) => Container(
            width: 7, height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.lineColor.withValues(alpha: _a.value),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text('LIVE',
            style: GoogleFonts.outfit(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: widget.lineColor.withValues(alpha: 0.85),
                letterSpacing: 1.0)),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color lineColor;
  const _InfoChip({required this.icon, required this.label, required this.lineColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: lineColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: lineColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: lineColor),
          const SizedBox(width: 4),
          Text(label,
              style: GoogleFonts.outfit(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: lineColor)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Timeline Painter matching Singapore Circle Line MRT Style
// ─────────────────────────────────────────────────────────────────────────────

class TimelinePainter extends CustomPainter {
  final Color lineColor;
  final Color pastColor;
  final bool isFirst;
  final bool isLast;
  final bool isCur;
  final bool isPast;

  TimelinePainter({
    required this.lineColor,
    required this.pastColor,
    required this.isFirst,
    required this.isLast,
    required this.isCur,
    required this.isPast,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double centerX = size.width / 2;
    final double centerY = 24.0; // Fixed vertical height for ticks and active dot
    final double lineThickness = 5.0;

    // Draw top line segment (if not the first station)
    if (!isFirst) {
      final paint = Paint()
        ..color = isPast ? pastColor : lineColor
        ..strokeWidth = lineThickness
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(centerX, 0), Offset(centerX, centerY), paint);
    }

    // Draw bottom line segment (if not the last station)
    if (!isLast) {
      final paint = Paint()
        ..color = (isPast && !isCur) ? pastColor : lineColor
        ..strokeWidth = lineThickness
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(centerX, centerY), Offset(centerX, size.height), paint);
    }

    // Draw tick or active dot
    if (isCur) {
      // 24% opacity blue halo
      final haloPaint = Paint()
        ..color = const Color(0x3D2F80ED)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(centerX, centerY), 10.0, haloPaint);

      // Solid blue center dot
      final dotPaint = Paint()
        ..color = const Color(0xFF2F80ED)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(centerX, centerY), 5.0, dotPaint);
    } else {
      // Draw horizontal tick sticking to the right (length 6, thickness 3.5)
      final tickPaint = Paint()
        ..color = isPast ? pastColor : lineColor
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round;
      
      canvas.drawLine(
        Offset(centerX, centerY),
        Offset(centerX + 6.0, centerY),
        tickPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant TimelinePainter oldDelegate) {
    return oldDelegate.lineColor != lineColor ||
        oldDelegate.pastColor != pastColor ||
        oldDelegate.isFirst != isFirst ||
        oldDelegate.isLast != isLast ||
        oldDelegate.isCur != isCur ||
        oldDelegate.isPast != isPast;
  }
}
