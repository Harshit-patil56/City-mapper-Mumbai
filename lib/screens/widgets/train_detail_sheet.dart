import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../services/api_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Citymapper-exact train detail sheet
//
// Layout:
//   • Green header strip  — train number badge, name, src→dst, status pill
//   • White body          — vertical stop timeline (green line + dots)
//   • Footer              — last-updated label, refresh button
//
// Data:
//   • Schedule  → RailGadi /trains/{number}?haltsOnly=true  ✅ confirmed
//   • Live      → mIndicator irgetrunningstatus (on-device; null-safe fallback)
// ─────────────────────────────────────────────────────────────────────────────

const _green    = Color(0xFF19A66E);
const _greenDk  = Color(0xFF117A52);
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

  late AnimationController _pulse;
  late Animation<double>   _pulseAnim;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.6, end: 1.0)
        .animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));

    _fetchAll();
    _refreshTimer = Timer.periodic(const Duration(seconds: 60),
        (_) => _fetchLive());
    _tickTimer = Timer.periodic(const Duration(seconds: 10),
        (_) { if (mounted) setState(() {}); });
  }

  @override
  void dispose() {
    _pulse.dispose();
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
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _scrollToCurrent());
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

  // ── Helpers ───────────────────────────────────────────────

  /// Index of the "current" stop based on wall clock vs schedule.
  int get _currentIdx {
    if (_stops.isEmpty) return 0;
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
      return (label: 'RUNNING', bg: _greenDk);
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
          _buildHeader(),
          Expanded(child: _buildBody()),
          _buildFooter(),
        ],
      ),
    );
  }

  // ── Green header strip ────────────────────────────────────

  Widget _buildHeader() {
    final chip = _statusChip;

    return Container(
      color: _green,
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: badge + name + close
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Train-number badge
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.35)),
                ),
                child: Text(widget.train.trainNumber,
                    style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.5)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.train.trainName,
                  style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(LucideIcons.x,
                    size: 20, color: Colors.white70),
                padding: EdgeInsets.zero,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),

          const SizedBox(height: 4),

          // Row 2: src → dst
          Row(
            children: [
              Flexible(
                child: Text(widget.train.sourceStation,
                    style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.8)),
                    overflow: TextOverflow.ellipsis),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.arrow_forward,
                    size: 12,
                    color: Colors.white.withValues(alpha: 0.6)),
              ),
              Expanded(
                child: Text(widget.train.destinationStation,
                    style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Row 3: status pill + live dot
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: chip.bg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(chip.label,
                    style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.4)),
              ),
              if (_live != null && !_live!.isCancelled) ...[
                const SizedBox(width: 8),
                const _LivePill(),
              ],
              if (_live?.platform != null &&
                  _live!.platform!.isNotEmpty) ...[
                const SizedBox(width: 8),
                _HeaderChip(
                    icon: LucideIcons.layoutTemplate,
                    label: 'Pf ${_live!.platform}'),
              ],
              if ((_live?.speed ?? 0) > 0) ...[
                const SizedBox(width: 6),
                _HeaderChip(
                    icon: LucideIcons.zap,
                    label: '${_live!.speed} km/h'),
              ],
            ],
          ),

          // Live current station
          if (_live?.currentStation != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(LucideIcons.mapPin,
                    size: 13, color: Colors.white70),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    'At ${_live!.currentStation!}'
                    '${_live!.nextStation != null ? '  →  ${_live!.nextStation}' : ''}',
                    style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.9)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── White body (timeline) ─────────────────────────────────

  Widget _buildBody() {
    if (_loadingSchedule) {
      return const Center(
          child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(_green),
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

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
      itemCount: _stops.length,
      itemBuilder: (ctx, i) => _stopRow(_stops, i, cur),
    );
  }

  // ── Individual stop row (Citymapper-exact) ────────────────
  //
  // Layout:
  //
  //   [dot]   Station Name                    09:24
  //    │      Platform 3 ←(small chip)
  //
  // The vertical green line is drawn by stacking a 2px-wide
  // container above and below the dot.

  Widget _stopRow(List<RailGadiTrainStop> stops, int i, int cur) {
    final stop    = stops[i];
    final isFirst = i == 0;
    final isLast  = i == stops.length - 1;
    final isCur   = i == cur;
    final isPast  = i < cur;

    // Time string
    final time = isFirst
        ? (stop.departure ?? '')
        : isLast
            ? (stop.arrival ?? '')
            : (stop.arrival ?? stop.departure ?? '');

    // Dot styling
    final double dotR = isCur ? 7 : 5;

    // Text colours
    final Color nameColor = isCur
        ? _ink
        : isPast
            ? _inkFaint
            : _ink;
    final FontWeight nameWeight =
        isCur ? FontWeight.w700 : FontWeight.w500;
    final Color timeColor = isCur ? _green : _inkMid;

    // Line colours
    final Color lineColorTop  = isPast ? _inkFaint : _green;
    final Color lineColorBot  = (i >= cur) ? _green : _inkFaint;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Timeline column (28 px wide)
          SizedBox(
            width: 28,
            child: Column(
              children: [
                // Top segment
                if (!isFirst)
                  Expanded(
                    child: Center(
                      child: Container(width: 2, color: lineColorTop),
                    ),
                  )
                else
                  const SizedBox(height: 6),

                // Dot
                isCur
                    ? AnimatedBuilder(
                        animation: _pulseAnim,
                        builder: (ctx, child) => Container(
                          width: dotR * 2 * _pulseAnim.value,
                          height: dotR * 2 * _pulseAnim.value,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _green,
                            boxShadow: [
                              BoxShadow(
                                  color: _green.withValues(alpha: 0.4),
                                  blurRadius: 8,
                                  spreadRadius: 2),
                            ],
                          ),
                        ),
                      )
                    : Container(
                        width: dotR * 2,
                        height: dotR * 2,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isPast ? _inkFaint : _bg,
                          border: isPast
                              ? null
                              : Border.all(color: _green, width: 2),
                        ),
                      ),

                // Bottom segment
                if (!isLast)
                  Expanded(
                    child: Center(
                      child: Container(width: 2, color: lineColorBot),
                    ),
                  )
                else
                  const SizedBox(height: 6),
              ],
            ),
          ),

          // ── Content column
          Expanded(
            child: Padding(
              padding:
                  EdgeInsets.symmetric(vertical: isCur ? 10 : 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
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
                  // Delay badge (from live data if available)
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
                ],
              ),
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
            icon: const Icon(LucideIcons.refreshCw,
                size: 13, color: _green),
            label: Text('Refresh',
                style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _green)),
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
// Small reusable widgets
// ─────────────────────────────────────────────────────────────────────────────

/// Pulsing "LIVE" pill shown in the header.
class _LivePill extends StatefulWidget {
  const _LivePill();
  @override
  State<_LivePill> createState() => _LivePillState();
}

class _LivePillState extends State<_LivePill>
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
              color: Colors.white.withValues(alpha: _a.value),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text('LIVE',
            style: GoogleFonts.outfit(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Colors.white.withValues(alpha: 0.85),
                letterSpacing: 1.0)),
      ],
    );
  }
}

/// Small translucent chip in the green header for platform/speed.
class _HeaderChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _HeaderChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: Colors.white70),
          const SizedBox(width: 4),
          Text(label,
              style: GoogleFonts.outfit(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white)),
        ],
      ),
    );
  }
}
