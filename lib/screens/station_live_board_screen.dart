import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../data/mumbai_stations.dart';
import '../services/api_service.dart';

/// Full-screen live departure board for a single Mumbai station.
///
/// Shows real-time train arrivals/departures with color-coded delay
/// indicators, auto-refreshes every 60 seconds, and supports
/// pull-to-refresh.
class StationLiveBoardScreen extends StatefulWidget {
  final String stationCode;
  final String stationName;
  final List<TrainLine> lines;

  const StationLiveBoardScreen({
    super.key,
    required this.stationCode,
    required this.stationName,
    required this.lines,
  });

  @override
  State<StationLiveBoardScreen> createState() => _StationLiveBoardScreenState();
}

class _StationLiveBoardScreenState extends State<StationLiveBoardScreen> {
  final RailGadiApiService _apiService = RailGadiApiService();

  StationLiveBoardResponse? _liveBoardData;
  bool _isLoading = true;
  String? _errorMessage;
  String? _errorCode;
  DateTime? _lastUpdated;
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    _fetchLiveBoard();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _apiService.dispose();
    super.dispose();
  }

  void _startAutoRefresh() {
    _autoRefreshTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _fetchLiveBoard(),
    );
  }

  Future<void> _fetchLiveBoard() async {
    if (!mounted) return;

    setState(() {
      _isLoading = _liveBoardData == null;
      _errorMessage = null;
      _errorCode = null;
    });

    try {
      final response =
          await _apiService.getStationLiveBoard(widget.stationCode, hours: 4);

      if (!mounted) return;

      setState(() {
        _liveBoardData = response;
        _isLoading = false;
        _lastUpdated = DateTime.now();
      });
    } on ApiException catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = e.message;
        _errorCode = e.code;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = 'An unexpected error occurred.';
        _errorCode = 'UNKNOWN';
      });
    }
  }

  String _getTimeSinceUpdate() {
    if (_lastUpdated == null) return '';
    final diff = DateTime.now().difference(_lastUpdated!);
    if (diff.inSeconds < 10) return 'Just now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    return '${diff.inMinutes}m ago';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: Column(
        children: [
          // Green header
          _buildHeader(context),

          // Updated timestamp strip
          if (_lastUpdated != null) _buildTimestampStrip(),

          // Content area
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF19A66E),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 16, 16),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.stationName,
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: widget.lines
                          .map((line) => Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: _buildLineBadge(line),
                              ))
                          .toList(),
                    ),
                  ],
                ),
              ),
              // Live indicator
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'LIVE',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLineBadge(TrainLine line) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: line.color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        line.shortCode,
        style: GoogleFonts.outfit(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildTimestampStrip() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFFE8F5E9),
      child: Row(
        children: [
          const Icon(
            LucideIcons.refreshCw,
            size: 14,
            color: Color(0xFF2E7D32),
          ),
          const SizedBox(width: 8),
          Text(
            'Updated ${_getTimeSinceUpdate()}',
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF2E7D32),
            ),
          ),
          const Spacer(),
          Text(
            'Next 4 hours',
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF66BB6A),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    // Loading state
    if (_isLoading) {
      return _buildLoadingSkeleton();
    }

    // Error state with no cached data
    if (_errorMessage != null && _liveBoardData == null) {
      return _buildErrorState();
    }

    // Empty state
    if (_liveBoardData != null && _liveBoardData!.trains.isEmpty) {
      return _buildEmptyState();
    }

    // Data loaded (possibly with a background error banner)
    return Column(
      children: [
        // Offline/error banner when we have cached data but latest fetch failed
        if (_errorMessage != null && _liveBoardData != null)
          _buildOfflineBanner(),

        Expanded(
          child: RefreshIndicator(
            onRefresh: _fetchLiveBoard,
            color: const Color(0xFF19A66E),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: _liveBoardData!.trains.length,
              itemBuilder: (context, index) {
                return _buildTrainCard(_liveBoardData!.trains[index]);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingSkeleton() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: List.generate(
          5,
          (i) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              height: 88,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 180,
                      height: 14,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE0E0E0),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: 120,
                      height: 12,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEEEEE),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 80,
                      height: 12,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    IconData icon;
    String title;
    String subtitle;

    switch (_errorCode) {
      case 'NOT_FOUND':
        icon = LucideIcons.searchX;
        title = 'Station Not Found';
        subtitle = _errorMessage ?? 'This station could not be found.';
        break;
      case 'SERVICE_UNAVAILABLE':
        icon = LucideIcons.serverOff;
        title = 'Service Unavailable';
        subtitle = _errorMessage ?? 'Please try again in a moment.';
        break;
      case 'TIMEOUT':
      case 'NETWORK_ERROR':
        icon = LucideIcons.wifiOff;
        title = 'No Connection';
        subtitle = 'Check your internet and try again.';
        break;
      default:
        icon = LucideIcons.alertTriangle;
        title = 'Something Went Wrong';
        subtitle = _errorMessage ?? 'An unexpected error occurred.';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: const Color(0xFFBDBDBD)),
            const SizedBox(height: 16),
            Text(
              title,
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF424242),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 14,
                color: const Color(0xFF9E9E9E),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _fetchLiveBoard,
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: Text(
                'Retry',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF19A66E),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.train, size: 56,
                color: Color(0xFFBDBDBD)),
            const SizedBox(height: 16),
            Text(
              'No Departures',
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF424242),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'No trains departing from this station\nin the next 4 hours.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 14,
                color: const Color(0xFF9E9E9E),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOfflineBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: const Color(0xFFFFF3E0),
      child: Row(
        children: [
          const Icon(LucideIcons.wifiOff, size: 16, color: Color(0xFFE65100)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Offline — showing last update',
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: const Color(0xFFE65100),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrainCard(LiveTrainEntry train) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Train number + name + status badge
            Row(
              children: [
                // Train number pill
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    train.trainNumber,
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF616161),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    train.trainName,
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF212121),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _buildStatusBadge(train),
              ],
            ),

            const SizedBox(height: 8),

            // Row 2: Source & Destination + scheduled/expected times
            Row(
              children: [
                const Icon(
                  LucideIcons.gitCommit,
                  size: 14,
                  color: Color(0xFF9E9E9E),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          MumbaiStationData.getStationNameByCode(train.sourceStation),
                          style: GoogleFonts.outfit(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF757575),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          Icons.arrow_forward,
                          size: 11,
                          color: Color(0xFF9E9E9E),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          MumbaiStationData.getStationNameByCode(train.destinationStation),
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF212121),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildTimeDisplay(train),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(LiveTrainEntry train) {
    Color bgColor;
    Color textColor;
    String text;

    switch (train.liveType) {
      case 'at-station':
        bgColor = const Color(0xFFE3F2FD);
        textColor = const Color(0xFF1565C0);
        text = 'At Station';
        break;
      case 'departed':
        bgColor = const Color(0xFFF5F5F5);
        textColor = const Color(0xFF757575);
        text = 'Departed';
        break;
      case 'upcoming':
        if (train.isOnTime) {
          bgColor = const Color(0xFFE8F5E9);
          textColor = const Color(0xFF2E7D32);
          text = 'On Time';
        } else if (train.isMinorDelay) {
          bgColor = const Color(0xFFFFF8E1);
          textColor = const Color(0xFFF9A825);
          text = 'Late ${train.delayMinutes}m';
        } else {
          bgColor = const Color(0xFFFFEBEE);
          textColor = const Color(0xFFC62828);
          text = 'Late ${train.delayMinutes}m';
        }
        break;
      case 'scheduled':
      default:
        bgColor = const Color(0xFFF5F5F5);
        textColor = const Color(0xFF9E9E9E);
        text = 'Scheduled';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: GoogleFonts.outfit(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
      ),
    );
  }

  String _formatTo12Hour(String timeStr) {
    if (timeStr.isEmpty) return '';
    try {
      if (timeStr.contains('T')) {
        final dt = DateTime.parse(timeStr);
        int hour = dt.hour;
        final int minute = dt.minute;
        final String period = hour >= 12 ? 'PM' : 'AM';
        hour = hour % 12;
        if (hour == 0) hour = 12;
        final String minStr = minute.toString().padLeft(2, '0');
        return '$hour:$minStr $period';
      }

      final parts = timeStr.trim().split(':');
      if (parts.length >= 2) {
        int hour = int.parse(parts[0]);
        final int minute = int.parse(parts[1]);
        final String period = hour >= 12 ? 'PM' : 'AM';
        hour = hour % 12;
        if (hour == 0) hour = 12;
        final String minStr = minute.toString().padLeft(2, '0');
        return '$hour:$minStr $period';
      }
    } catch (_) {}
    return timeStr;
  }

  Widget _buildTimeDisplay(LiveTrainEntry train) {
    final String? scheduled = train.scheduledDeparture ?? train.scheduledArrival;

    if (scheduled == null) {
      return const SizedBox.shrink();
    }

    final formattedScheduled = _formatTo12Hour(scheduled);

    // For upcoming trains with delay, show both scheduled and expected
    if (train.liveType == 'upcoming' && !train.isOnTime) {
      final String? expected = train.expectedArrivalTime;
      final String expectedShort =
          expected != null ? _formatTo12Hour(expected) : '';

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            formattedScheduled,
            style: GoogleFonts.outfit(
              fontSize: 13,
              color: const Color(0xFFBDBDBD),
              decoration: TextDecoration.lineThrough,
            ),
          ),
          if (expectedShort.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(
              expectedShort,
              style: GoogleFonts.outfit(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: train.isMajorDelay
                    ? const Color(0xFFC62828)
                    : const Color(0xFFF9A825),
              ),
            ),
          ],
        ],
      );
    }

    // For departed trains, show departure time
    if (train.liveType == 'departed' && train.departedAt != null) {
      return Text(
        _formatTo12Hour(train.departedAt!),
        style: GoogleFonts.outfit(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF757575),
        ),
      );
    }

    // Default: show scheduled time
    return Text(
      formattedScheduled,
      style: GoogleFonts.outfit(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: const Color(0xFF212121),
      ),
    );
  }
}
