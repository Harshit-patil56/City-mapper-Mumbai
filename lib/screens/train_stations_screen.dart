import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:lucide_icons/lucide_icons.dart';
import '../data/mumbai_stations.dart';
import '../services/api_service.dart';
import 'widgets/train_detail_sheet.dart';

/// Full-screen train stations explorer with two tabs:
///   - **Stations**: Nearby stations sorted by GPS distance
///   - **Lines**: Stations grouped by railway line (Western/Central/Harbour)
///
/// Pushed from the home screen when the user taps the Train icon.
class TrainStationsScreen extends StatefulWidget {
  /// The user's current GPS position for calculating nearby stations.
  /// If null, falls back to a default Mumbai location (CSMT).
  final LatLng? userPosition;

  const TrainStationsScreen({super.key, this.userPosition});

  @override
  State<TrainStationsScreen> createState() => _TrainStationsScreenState();
}

class _TrainStationsScreenState extends State<TrainStationsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final RailGadiApiService _apiService = RailGadiApiService();
  final Map<String, List<LiveTrainEntry>> _stationDepartures = {};
  final Map<String, bool> _stationLoading = {};
  final Map<String, String?> _stationErrors = {};

  /// Nearby stations with distance, computed on init.
  late List<({MumbaiStation station, double distanceMeters})> _nearbyStations;

  final ValueNotifier<double> _sheetSizeNotifier = ValueNotifier<double>(0.18);
  final DraggableScrollableController _sheetController = DraggableScrollableController();

  /// Expanded state for each line section in the Lines tab.
  final Map<TrainLine, bool> _lineExpanded = {
    TrainLine.western: true,
    TrainLine.central: false,
    TrainLine.harbour: false,
  };

  /// Effective user position (actual GPS or fallback).
  late LatLng _effectivePosition;

  /// True if the user is located far from Mumbai.
  bool _isOutsideMumbai = false;

  final MapController _mapController = MapController();
  final MIndicatorApiService _mIndicatorService = MIndicatorApiService();
  MumbaiStation? _selectedStation;
  List<LiveTrainEntry> _selectedStationDepartures = [];
  bool _isLoadingDepartures = false;
  String? _departuresError;
  Timer? _departuresRefreshTimer;

  bool _isTimetableMode = false;
  List<LiveTrainEntry> _selectedStationTimetable = [];
  bool _isLoadingTimetable = false;
  String? _timetableError;

  // mIndicator disruption data for the selected station
  List<MIndicatorAlert> _stationAlerts = [];
  List<MIndicatorCancelledTrain> _cancelledTrains = [];
  Set<String> _dismissedAlertIds = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });

    final userPos = widget.userPosition ?? const LatLng(18.9398, 72.8355);

    // Find nearby stations to check if the user is in Mumbai.
    final tempNearby = MumbaiStationData.findNearbyStations(
      userPos.latitude,
      userPos.longitude,
      limit: 1,
    );

    _isOutsideMumbai = tempNearby.isNotEmpty && tempNearby.first.distanceMeters > 50000;

    if (_isOutsideMumbai) {
      // Center the map on CSMT, Mumbai, instead of San Francisco/etc.
      _effectivePosition = const LatLng(18.9398, 72.8355);
    } else {
      _effectivePosition = userPos;
    }

    _nearbyStations = MumbaiStationData.findNearbyStations(
      _effectivePosition.latitude,
      _effectivePosition.longitude,
      limit: 10,
    );

    _loadDeparturesForNearby();
  }

  void _loadDeparturesForNearby() {
    for (final entry in _nearbyStations.take(10)) {
      final code = entry.station.code;
      setState(() {
        _stationLoading[code] = true;
        _stationErrors[code] = null;
      });

      _apiService.getStationLiveBoard(code, hours: 2).then((response) {
        if (mounted) {
          setState(() {
            _stationDepartures[code] = response.trains;
            _stationLoading[code] = false;
          });
        }
      }).catchError((error) {
        if (mounted) {
          setState(() {
            _stationLoading[code] = false;
            _stationErrors[code] = error.toString();
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _sheetSizeNotifier.dispose();
    _departuresRefreshTimer?.cancel();
    _mIndicatorService.dispose();
    super.dispose();
  }

  void _selectStation(MumbaiStation station) {
    setState(() {
      _selectedStation = station;
      _selectedStationDepartures = [];
      _isTimetableMode = false;
      _selectedStationTimetable = [];
      _isLoadingTimetable = false;
      _timetableError = null;
    });
    
    // Zoom and center map to selected station
    _mapController.move(LatLng(station.lat, station.lng), 15.5);
    
    // Animate draggable sheet to middle snap point (0.55) to show details beautifully
    if (_sheetController.isAttached) {
      _sheetController.animateTo(
        0.55,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
    
    _fetchSelectedStationDepartures();
    _startSelectedStationAutoRefresh();
    _loadStationAlerts(); // mIndicator: fetch cancellations + alerts
  }

  Future<void> _fetchSelectedStationDepartures() async {
    final station = _selectedStation;
    if (station == null) return;

    setState(() {
      _isLoadingDepartures = true;
      _departuresError = null;
    });

    try {
      final response = await _apiService.getStationLiveBoard(station.code, hours: 4);
      if (_selectedStation?.code != station.code) return; // stale request
      setState(() {
        _selectedStationDepartures = response.trains;
        _isLoadingDepartures = false;
      });
    } catch (e) {
      if (_selectedStation?.code != station.code) return; // stale request
      setState(() {
        _departuresError = e.toString();
        _isLoadingDepartures = false;
      });
    }
  }

  Future<void> _fetchSelectedStationTimetable() async {
    final station = _selectedStation;
    if (station == null) return;

    setState(() {
      _isLoadingTimetable = true;
      _timetableError = null;
    });

    try {
      final response = await _apiService.getStationTimetable(station.code);
      if (_selectedStation?.code != station.code) return; // stale request
      setState(() {
        _selectedStationTimetable = response;
        _isLoadingTimetable = false;
      });
    } catch (e) {
      if (_selectedStation?.code != station.code) return; // stale request
      setState(() {
        _timetableError = e.toString();
        _isLoadingTimetable = false;
      });
    }
  }

  void _startSelectedStationAutoRefresh() {
    _departuresRefreshTimer?.cancel();
    _departuresRefreshTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _fetchSelectedStationDepartures(),
    );
  }

  /// Fetches mIndicator disruption data (cancelled trains + news alerts).
  Future<void> _loadStationAlerts() async {
    try {
      final results = await Future.wait([
        _mIndicatorService.getCancelledTrains(),
        _mIndicatorService.getNewsAlerts(),
      ]);
      if (!mounted) return;
      setState(() {
        _cancelledTrains = results[0] as List<MIndicatorCancelledTrain>;
        _stationAlerts   = results[1] as List<MIndicatorAlert>;
        _dismissedAlertIds = {}; // reset dismissals on new station
      });
    } catch (_) {}
  }

  bool isLocalTrain(LiveTrainEntry train) {
    final type = (train.trainType ?? '').trim().toLowerCase();
    final name = train.trainName.toLowerCase();
    
    // If it contains local/emu/memu/demu/suburban/sub/slow/fast
    if (type.contains('local') ||
        type.contains('emu') ||
        type.contains('memu') ||
        type.contains('demu') ||
        type.contains('suburban') ||
        type.contains('sub') ||
        name.contains('local') ||
        name.contains('emu') ||
        name.contains('suburban') ||
        name.contains('memu') ||
        name.contains('slow') ||
        name.contains('fast')) {
      return true;
    }
    
    if (type.contains('express') ||
        type.contains('superfast') ||
        type.contains('mail') ||
        type.contains('passenger') ||
        type.contains('sf') ||
        type.contains('duronto') ||
        type.contains('rajdhani') ||
        type.contains('shatabdi')) {
      return false;
    }
    
    return true; // default to Local for Mumbai Local train app!
  }

  void _navigateToLiveBoard(MumbaiStation station) {
    _selectStation(station);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5), // Light gray background
      body: Stack(
        children: [
          // 1. Map section in the background (occupies top 85% of the screen)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.of(context).size.height * 0.85,
            child: ValueListenableBuilder<double>(
              valueListenable: _sheetSizeNotifier,
              builder: (context, sheetSize, child) {
                // Parallax logic: map shifts up as sheet size goes from 0.18 to 1.0
                final dragProgress = (sheetSize - 0.18) / (1.0 - 0.18);
                final mapTranslationY = -dragProgress.clamp(0.0, 1.0) * 120.0;

                return Transform.translate(
                  offset: Offset(0, mapTranslationY),
                  child: child,
                );
              },
              child: _buildMapSection(), // Capped builder child to prevent map rebuild lag
            ),
          ),

          // 2. Sliding sheet container overlapping the map
          Positioned.fill(
            child: NotificationListener<DraggableScrollableNotification>(
              onNotification: (notification) {
                _sheetSizeNotifier.value = notification.extent;
                return true;
              },
              child: DraggableScrollableSheet(
                controller: _sheetController,
                initialChildSize: 0.18,
                minChildSize: 0.18,
                maxChildSize: 1.0, // Scroll at the full top
                snap: true,
                snapSizes: const [0.18, 0.55, 1.0], // Collapsed, Middle, or full top
                builder: (context, scrollController) {
                  return Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFF19A66E), // Green main card
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(12),
                        topRight: Radius.circular(12),
                      ),
                    ),
                    child: _selectedStation != null
                        ? _buildSelectedStationView(scrollController)
                        : Column(
                            children: [
                              // Drag indicator handle and Tab Header
                              // Wrapped in a GestureDetector using DraggableScrollableController to make it perfectly draggable and snappy
                              GestureDetector(
                                onVerticalDragUpdate: (details) {
                                  final currentExtent = _sheetController.size;
                                  final newExtent = currentExtent -
                                      details.primaryDelta! /
                                          MediaQuery.of(context).size.height;
                                  _sheetController.jumpTo(newExtent.clamp(0.18, 1.0));
                                },
                                onVerticalDragEnd: (details) {
                                  final currentSize = _sheetController.size;
                                  
                                  // Find nearest snap point from [0.18, 0.55, 1.0]
                                  const snaps = [0.18, 0.55, 1.0];
                                  double targetSize = snaps[0];
                                  double minDiff = (currentSize - snaps[0]).abs();
                                  for (int i = 1; i < snaps.length; i++) {
                                    final diff = (currentSize - snaps[i]).abs();
                                    if (diff < minDiff) {
                                      minDiff = diff;
                                      targetSize = snaps[i];
                                    }
                                  }

                                  _sheetController.animateTo(
                                    targetSize,
                                    duration: const Duration(milliseconds: 250),
                                    curve: Curves.easeOutCubic,
                                  );
                                },
                                behavior: HitTestBehavior.opaque,
                                child: Column(
                                  children: [
                                    _buildTabHeader(),
                                  ],
                                ),
                              ),

                              // TabBarView content
                              Expanded(
                                child: Container(
                                  color: const Color(0xFF19A66E),
                                  child: TabBarView(
                                    controller: _tabController,
                                    children: [
                                      _buildStationsTab(scrollController),
                                      _buildLinesTab(scrollController),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                  );
                },
              ),
            ),
          ),

          // 3. Floating Persistent Back Button
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(left: 12, top: 4),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back,
                        size: 18, color: Color(0xFF334155)),
                    onPressed: () {
                      if (_selectedStation != null) {
                        setState(() {
                          _selectedStation = null;
                          _selectedStationDepartures = [];
                          _departuresRefreshTimer?.cancel();
                        });
                        _mapController.move(_effectivePosition, 13.0);
                      } else {
                        Navigator.of(context).pop();
                      }
                    },
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Map Section
  // ---------------------------------------------------------------------------

  Widget _buildMapSection() {
    return SizedBox(
      height: double.infinity,
      child: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: _effectivePosition,
          initialZoom: 13.0,
          minZoom: 10.0,
          maxZoom: 18.0,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all,
          ),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.quntanix.citymappermumbai',
          ),
          // Station markers
          MarkerLayer(
            markers: _nearbyStations
                .map(
                  (entry) {
                    final isSelected = entry.station.code == _selectedStation?.code;
                    return Marker(
                      point: LatLng(entry.station.lat, entry.station.lng),
                      width: isSelected ? 38 : 28,
                      height: isSelected ? 38 : 28,
                      child: GestureDetector(
                        onTap: () => _selectStation(entry.station),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            color: entry.station.line.color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? const Color(0xFFFFEB3B) : Colors.white,
                              width: isSelected ? 3.5 : 2.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: isSelected
                                    ? Colors.black.withValues(alpha: 0.4)
                                    : Colors.black.withValues(alpha: 0.2),
                                blurRadius: isSelected ? 8 : 4,
                                spreadRadius: isSelected ? 2 : 0,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Icon(
                              LucideIcons.train,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                )
                .toList(),
          ),
          // User position marker
          if (widget.userPosition != null && !_isOutsideMumbai)
            MarkerLayer(
              markers: [
                Marker(
                  point: widget.userPosition!,
                  width: 22,
                  height: 22,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: const BoxDecoration(
                          color: Color(0xFF2F80ED),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab Header
  // ---------------------------------------------------------------------------

  Widget _buildTabHeader() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF19A66E),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: Column(
        children: [
          // Train icon row (matches screenshot with pink train card)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE91E63), // Pink MRT style
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        LucideIcons.train,
                        size: 18,
                        color: Colors.white,
                      ),
                      Text(
                        'MRT',
                        style: GoogleFonts.outfit(
                          fontSize: 7.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Tab buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFF11754D), // Solid dark green base like the "Now" control
                borderRadius: BorderRadius.circular(8),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: Colors.white, // White active capsule, like "Now"
                  borderRadius: BorderRadius.circular(8),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: const Color(0xFF11754D), // Green active text
                unselectedLabelColor: Colors.white.withValues(alpha: 0.8), // White unselected text
                labelStyle: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelStyle: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(LucideIcons.mapPin, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          'Stations',
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(LucideIcons.gitBranch, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          'Lines',
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Stations Tab — Nearby stations sorted by distance
  // ---------------------------------------------------------------------------

  Widget _buildStationsTab(ScrollController sheetController) {
    if (_nearbyStations.isEmpty) {
      return Center(
        child: Text(
          'No stations found nearby.',
          style: GoogleFonts.outfit(
            fontSize: 15,
            color: const Color(0xFF9E9E9E),
          ),
        ),
      );
    }

    return Column(
      children: [
        if (_isOutsideMumbai)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 2),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFE0F7FA),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFB2EBF2)),
            ),
            child: Row(
              children: [
                const Icon(
                  LucideIcons.info,
                  color: Color(0xFF00838F),
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "You're outside Mumbai. Showing central stations.",
                    style: GoogleFonts.outfit(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF00838F),
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              _loadDeparturesForNearby();
              await Future.delayed(const Duration(milliseconds: 800));
            },
            color: const Color(0xFF19A66E),
            backgroundColor: Colors.white,
            child: ListView.builder(
              controller: _tabController.index == 0 ? sheetController : null,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: _nearbyStations.length,
              itemBuilder: (context, index) {
                final entry = _nearbyStations[index];
                final lines =
                    MumbaiStationData.getLinesForStation(entry.station.code);

                return _buildStationCard(
                  station: entry.station,
                  distanceText:
                      MumbaiStationData.formatDistance(entry.distanceMeters),
                  lines: lines,
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStationCard({
    required MumbaiStation station,
    required String distanceText,
    required List<TrainLine> lines,
  }) {
    final code = station.code;
    final isLoading = _stationLoading[code] ?? false;
    final departures = _stationDepartures[code] ?? [];
    final error = _stationErrors[code];

    return GestureDetector(
      onTap: () => _navigateToLiveBoard(station),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Station Header Row
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // MRT Icon container (pink card with train + MRT text)
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE91E63), // Pink MRT style
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          LucideIcons.train,
                          size: 16,
                          color: Colors.white,
                        ),
                        Text(
                          'MRT',
                          style: GoogleFonts.outfit(
                            fontSize: 7.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Station Name & Lines
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          station.name,
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: lines
                              .map((line) => Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: line.color,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        line.shortCode,
                                        style: GoogleFonts.outfit(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ))
                              .toList(),
                        ),
                      ],
                    ),
                  ),

                  // Distance
                  Text(
                    distanceText,
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),

            // Divider if there are departures or loading
            const Divider(height: 1, color: Color(0xFFF1F5F9)),

            if (isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF19A66E)),
                    ),
                  ),
                ),
              )
            else if (error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Could not load live schedules',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    color: const Color(0xFF94A3B8),
                  ),
                ),
              )
            else if (departures.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: Text(
                    'No current departures',
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
                ),
              )
            else
              Column(
                children: departures.take(4).map((train) {
                  return _buildDepartureRow(train, station);
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDepartureRow(LiveTrainEntry train, MumbaiStation station) {
    final String? scheduled = train.scheduledDeparture ?? train.scheduledArrival;
    
    // Determine the text to display on the right
    String timeText = scheduled ?? '';
    if (train.liveType == 'at-station') {
      timeText = 'At Platform';
    } else {
      final String? expectedStr = train.expectedDepartureTime ?? train.expectedArrivalTime;
      if (expectedStr != null) {
        try {
          final expectedTime = DateTime.parse(expectedStr);
          final difference = expectedTime.difference(DateTime.now());
          if (difference.inMinutes <= 0) {
            timeText = 'Due';
          } else if (difference.inMinutes < 60) {
            timeText = 'In ${difference.inMinutes} min';
          } else {
            timeText = '${expectedTime.hour.toString().padLeft(2, '0')}:${expectedTime.minute.toString().padLeft(2, '0')}';
          }
        } catch (_) {}
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Color(0xFFF1F5F9),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Line badge (square)
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: station.line.color,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Text(
                station.line.shortCode,
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Destination station & line code underneath
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        MumbaiStationData.getStationNameByCode(train.sourceStation),
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF64748B),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        Icons.arrow_forward,
                        size: 11,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        MumbaiStationData.getStationNameByCode(train.destinationStation),
                        style: GoogleFonts.outfit(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1E293B),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  station.line.shortCode,
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),

          // Departure time/status
          Text(
            timeText,
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF475569),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------

  Widget _buildLinesTab(ScrollController sheetController) {
    return ListView(
      controller: _tabController.index == 1 ? sheetController : null,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: TrainLine.values.map((line) {
        final stations = MumbaiStationData.getStationsByLine(line);
        final isExpanded = _lineExpanded[line] ?? false;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              // Line header (tappable to expand/collapse)
              GestureDetector(
                onTap: () {
                  setState(() {
                    _lineExpanded[line] = !isExpanded;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      // Line color dot
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: line.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${line.displayName} Line',
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF334155),
                          ),
                        ),
                      ),
                      Icon(
                        isExpanded
                            ? LucideIcons.chevronUp
                            : LucideIcons.chevronDown,
                        size: 16,
                        color: const Color(0xFF64748B),
                      ),
                    ],
                  ),
                ),
              ),

              // Station list for this line (only if expanded)
              if (isExpanded)
                Container(
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: Color(0xFFF0F0F0),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Column(
                    children: stations.asMap().entries.map((entry) {
                      final index = entry.key;
                      final station = entry.value;
                      final isLast = index == stations.length - 1;

                      return GestureDetector(
                        onTap: () => _navigateToLiveBoard(station),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 11),
                          decoration: BoxDecoration(
                            border: isLast
                                ? null
                                : const Border(
                                    bottom: BorderSide(
                                      color: Color(0xFFF5F5F5),
                                      width: 1,
                                    ),
                                  ),
                          ),
                          child: Row(
                            children: [
                              // Route line indicator
                              SizedBox(
                                width: 20,
                                child: Column(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: station.isJunction
                                            ? line.color
                                            : Colors.white,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color:
                                              line.color,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  station.name,
                                  style: GoogleFonts.outfit(
                                    fontSize: 14,
                                    fontWeight: station.isJunction
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: const Color(0xFF424242),
                                  ),
                                ),
                              ),
                              if (station.isJunction)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF5F5F5),
                                    borderRadius:
                                        BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Junction',
                                    style: GoogleFonts.outfit(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF9E9E9E),
                                    ),
                                  ),
                                ),
                              const SizedBox(width: 8),
                              const Icon(
                                LucideIcons.chevronRight,
                                size: 14,
                                color: Color(0xFFBDBDBD),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSelectedStationView(ScrollController scrollController) {
    final station = _selectedStation!;
    final lines = MumbaiStationData.getLinesForStation(station.code);
    
    // Group the departures into Local and Express
    final localTrains = _selectedStationDepartures.where((t) => isLocalTrain(t)).toList();
    final expressTrains = _selectedStationDepartures.where((t) => !isLocalTrain(t)).toList();

    return Column(
      children: [
        // 1. Station Name Header
        GestureDetector(
          onVerticalDragUpdate: (details) {
            final currentExtent = _sheetController.size;
            final newExtent = currentExtent -
                details.primaryDelta! /
                    MediaQuery.of(context).size.height;
            _sheetController.jumpTo(newExtent.clamp(0.18, 1.0));
          },
          onVerticalDragEnd: (details) {
            final currentSize = _sheetController.size;
            
            // Find nearest snap point from [0.18, 0.55, 1.0]
            const snaps = [0.18, 0.55, 1.0];
            double targetSize = snaps[0];
            double minDiff = (currentSize - snaps[0]).abs();
            for (int i = 1; i < snaps.length; i++) {
              final diff = (currentSize - snaps[i]).abs();
              if (diff < minDiff) {
                minDiff = diff;
                targetSize = snaps[i];
              }
            }

            _sheetController.animateTo(
              targetSize,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
            );
          },
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                // MRT / Station Icon
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE91E63), // Pink style
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        LucideIcons.train,
                        size: 16,
                        color: Colors.white,
                      ),
                      Text(
                        'MRT',
                        style: GoogleFonts.outfit(
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                
                // Station Name & Active Lines
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        station.name,
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: lines
                            .map((line) => Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: line.color,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1),
                                    ),
                                    child: Text(
                                      line.shortCode,
                                      style: GoogleFonts.outfit(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ))
                            .toList(),
                      ),
                    ],
                  ),
                ),

                // Close / Back button in card
                IconButton(
                  icon: const Icon(LucideIcons.x, color: Colors.white, size: 20),
                  onPressed: () {
                    setState(() {
                      _selectedStation = null;
                      _selectedStationDepartures = [];
                      _departuresRefreshTimer?.cancel();
                      _isTimetableMode = false;
                      _selectedStationTimetable = [];
                      _isLoadingTimetable = false;
                      _timetableError = null;
                    });
                    _mapController.move(_effectivePosition, 13.0);
                  },
                ),
              ],
            ),
          ),
        ),

        // 2. Custom segmented tabs capsule: Now / Timetable
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Container(
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFF11754D), // Capsule background
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _isTimetableMode = false;
                      });
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: !_isTimetableMode ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          'Now',
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: !_isTimetableMode ? const Color(0xFF11754D) : Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _isTimetableMode = true;
                      });
                      if (_selectedStationTimetable.isEmpty) {
                        _fetchSelectedStationTimetable();
                      }
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: _isTimetableMode ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          'Timetable',
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _isTimetableMode ? const Color(0xFF11754D) : Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // 3. Departures List / Timetable List
        Expanded(
          child: Container(
            color: const Color(0xFF19A66E), // Match parent green background
            child: !_isTimetableMode
                ? RefreshIndicator(
                    onRefresh: _fetchSelectedStationDepartures,
                    color: const Color(0xFF19A66E),
                    backgroundColor: Colors.white,
                    child: ListView(
                      controller: scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      children: [
                        if (_isLoadingDepartures && _selectedStationDepartures.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 40),
                            child: Center(
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                          )
                        else if (_departuresError != null && _selectedStationDepartures.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 40),
                            child: Center(
                              child: Column(
                                children: [
                                  const Icon(LucideIcons.wifiOff, color: Colors.white70, size: 36),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Failed to load live schedule',
                                    style: GoogleFonts.outfit(
                                      fontSize: 14,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _departuresError!,
                                    style: GoogleFonts.outfit(
                                      fontSize: 12,
                                      color: Colors.white70,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          )
                        else ...[
                          // mIndicator disruption banner (if any active alerts/cancellations)
                          _buildDisruptionBanner(),

                          // Group 1: Local Trains
                          _buildGroupCard('Local Trains', localTrains),

                          // Group 2: Express Trains
                          _buildGroupCard('Express Trains', expressTrains),
                          
                          if (localTrains.isEmpty && expressTrains.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 40),
                              child: Center(
                                child: Text(
                                  'No upcoming departures found.',
                                  style: GoogleFonts.outfit(
                                    fontSize: 14,
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _fetchSelectedStationTimetable,
                    color: const Color(0xFF19A66E),
                    backgroundColor: Colors.white,
                    child: _buildTimetableListView(scrollController),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildGroupCard(String title, List<LiveTrainEntry> trains) {
    if (trains.isEmpty) return const SizedBox.shrink();
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Group Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC), // Lighter slate gray
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Text(
              title,
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF475569),
                letterSpacing: 0.5,
              ),
            ),
          ),
          
          // Train departures list under this group
          ...trains.map((train) => _buildSelectedStationDepartureRow(train)),
        ],
      ),
    );
  }

  Widget _buildTimetableListView(ScrollController scrollController) {
    if (_isLoadingTimetable && _selectedStationTimetable.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
      );
    }
    
    if (_timetableError != null && _selectedStationTimetable.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.wifiOff, color: Colors.white70, size: 36),
              const SizedBox(height: 12),
              Text(
                'Failed to load timetable',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _timetableError!,
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: Colors.white70,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _fetchSelectedStationTimetable,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF19A66E),
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_selectedStationTimetable.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Text(
            'No scheduled trains found.',
            style: GoogleFonts.outfit(
              fontSize: 14,
              color: Colors.white70,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
    }

    // Divide into morning (< 12) and evening (>= 12)
    final morningTrains = <LiveTrainEntry>[];
    final eveningTrains = <LiveTrainEntry>[];

    for (final train in _selectedStationTimetable) {
      final timeStr = train.scheduledDeparture ?? train.scheduledArrival ?? '';
      if (timeStr.isEmpty) continue;
      final parts = timeStr.split(':');
      if (parts.isNotEmpty) {
        final hour = int.tryParse(parts[0]) ?? 0;
        if (hour < 12) {
          morningTrains.add(train);
        } else {
          eveningTrains.add(train);
        }
      }
    }

    // Sort chronologically
    int timeCompare(LiveTrainEntry a, LiveTrainEntry b) {
      final timeA = a.scheduledDeparture ?? a.scheduledArrival ?? '';
      final timeB = b.scheduledDeparture ?? b.scheduledArrival ?? '';
      return timeA.compareTo(timeB);
    }
    morningTrains.sort(timeCompare);
    eveningTrains.sort(timeCompare);

    return ListView(
      controller: scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _buildTimetableSection('Morning Section (AM)', morningTrains, LucideIcons.sun),
        const SizedBox(height: 16),
        _buildTimetableSection('Evening Section (PM)', eveningTrains, LucideIcons.moon),
      ],
    );
  }

  Widget _buildTimetableSection(String title, List<LiveTrainEntry> trains, IconData icon) {
    if (trains.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 16, color: const Color(0xFF475569)),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF475569),
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Text(
                  '${trains.length} trains',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
          ...trains.map((train) => _buildSelectedStationDepartureRow(train)),
        ],
      ),
    );
  }

  Widget _buildSelectedStationDepartureRow(LiveTrainEntry train) {
    final String? scheduled = train.scheduledDeparture ?? train.scheduledArrival;
    
    // Determine the text to display on the right
    String timeText = scheduled ?? '';
    if (train.liveType == 'at-station') {
      timeText = 'At Platform';
    } else {
      final String? expectedStr = train.expectedDepartureTime ?? train.expectedArrivalTime;
      if (expectedStr != null) {
        try {
          final expectedTime = DateTime.parse(expectedStr);
          final difference = expectedTime.difference(DateTime.now());
          if (difference.inMinutes <= 0) {
            timeText = 'Due';
          } else if (difference.inMinutes < 60) {
            timeText = 'In ${difference.inMinutes} min';
          } else {
            timeText = '${expectedTime.hour.toString().padLeft(2, '0')}:${expectedTime.minute.toString().padLeft(2, '0')}';
          }
        } catch (_) {}
      }
    }

    // Get the line color and shortCode based on the train's line if possible, or fallback to the selected station's line
    final line = _selectedStation?.line ?? TrainLine.central;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            useSafeArea: true,
            builder: (_) => DraggableScrollableSheet(
              initialChildSize: 0.65,
              minChildSize: 0.4,
              maxChildSize: 0.95,
              expand: false,
              builder: (_, sc) => TrainDetailSheet(train: train),
            ),
          );
        },
        borderRadius: BorderRadius.circular(0),
        child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Color(0xFFF1F5F9),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Line badge (square)
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: line.color,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Text(
                line.shortCode,
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Destination station & line code underneath
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        MumbaiStationData.getStationNameByCode(train.sourceStation),
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF64748B),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        Icons.arrow_forward,
                        size: 11,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        MumbaiStationData.getStationNameByCode(train.destinationStation),
                        style: GoogleFonts.outfit(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF1E293B),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${train.trainNumber} • ${train.trainName}',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF94A3B8),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Departure time/status
          Text(
            timeText,
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF475569),
            ),
          ),
        ],
      ),
        ), // Container
      ), // InkWell
    ); // Material
  }

  /// Builds persistent disruption banners from mIndicator data.
  /// Shows amber alerts for news and red banners for cancellations.
  Widget _buildDisruptionBanner() {
    final visibleAlerts = _stationAlerts
        .where((a) => !_dismissedAlertIds.contains(a.id ?? a.title))
        .take(2)
        .toList();
    final visibleCancelled = _cancelledTrains.take(2).toList();

    if (visibleAlerts.isEmpty && visibleCancelled.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        ...visibleAlerts.map((alert) => _AlertBanner(
              icon: LucideIcons.alertTriangle,
              color: const Color(0xFFD97706),
              bgColor: const Color(0xFFFEF3C7),
              message: alert.title.isNotEmpty ? alert.title : alert.body,
              onDismiss: () => setState(() =>
                  _dismissedAlertIds.add(alert.id ?? alert.title)),
            )),
        ...visibleCancelled.map((c) {
          String msg;
          if (c.isCancelled) { msg = '${c.trainNo} ${c.trainName} — CANCELLED'; }
          else if (c.isDiverted) { msg = '${c.trainNo} DIVERTED — ${c.reason ?? ''}'; }
          else { msg = '${c.trainNo} RESCHEDULED to ${c.newDepartureTime ?? ''}'; }
          return _AlertBanner(
            icon: LucideIcons.xCircle,
            color: const Color(0xFFDC2626),
            bgColor: const Color(0xFFFEE2E2),
            message: msg,
            onDismiss: null, // cancellations not dismissable
          );
        }),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Small inline disruption banner widget.
class _AlertBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color bgColor;
  final String message;
  final VoidCallback? onDismiss;

  const _AlertBanner({
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.message,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onDismiss != null) ...[
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onDismiss,
              child: Icon(Icons.close, size: 14, color: color),
            ),
          ],
        ],
      ),
    );
  }
}

