import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:lucide_icons/lucide_icons.dart';
import '../data/mumbai_stations.dart';
import '../services/api_service.dart';
import 'widgets/train_detail_sheet.dart';
import 'station_search_screen.dart';

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
  String _selectedDirection = 'ALL';
  ScrollController? _timetableScrollController;

  // mIndicator disruption data for the selected station
  List<MIndicatorAlert> _stationAlerts = [];
  List<MIndicatorCancelledTrain> _cancelledTrains = [];
  Set<String> _dismissedAlertIds = {};

  // Route Planner State
  MumbaiStation? _routeFromStation;
  MumbaiStation? _routeToStation;
  bool _isLoadingRoutes = false;
  String? _routesError;
  List<PlannedTripItinerary> _plannedTrips = [];
  bool _selectedFilterAC = false;
  bool _selectedFilterFast = false;
  bool _selectedFilterLadies = false;
  final Set<String> _expandedLegKeys = {};
  final Map<String, List<RailGadiTrainStop>> _trainStopsCache = {};
  final Map<String, bool> _loadingStops = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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

    if (_nearbyStations.isNotEmpty) {
      _routeFromStation = _nearbyStations.first.station;
    }

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
      _selectedDirection = 'ALL';
      _timetableScrollController = null;
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
      final sortedFiltered = _getSortedFilteredTimetable();
      _scrollToCurrentTimetable(sortedFiltered);
    } catch (e) {
      if (_selectedStation?.code != station.code) return; // stale request
      setState(() {
        _timetableError = e.toString();
        _isLoadingTimetable = false;
      });
    }
  }

  String getTrainDirection(LiveTrainEntry train, MumbaiStation selectedStation) {
    final lineStations = MumbaiStationData.getStationsByLine(selectedStation.line);
    final selectedIdx = lineStations.indexWhere((s) => s.code.toUpperCase() == selectedStation.code.toUpperCase());
    final destIdx = lineStations.indexWhere((s) => s.code.toUpperCase() == train.destinationStation.toUpperCase());
    
    if (selectedIdx != -1 && destIdx != -1) {
      if (destIdx < selectedIdx) {
        return 'UP';
      } else if (destIdx > selectedIdx) {
        return 'DOWN';
      }
    }
    
    final destUpper = train.destinationStation.toUpperCase();
    if (destUpper == 'CSMT' || destUpper == 'CSTM' || destUpper == 'CCG' || destUpper == 'BYC' || destUpper == 'DR' || destUpper == 'DDR' || destUpper == 'CLA' || destUpper == 'VDLR') {
      return 'UP';
    }
    return 'DOWN';
  }

  int _findNextUpcomingTrainIndex(List<LiveTrainEntry> trains) {
    final now = DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;
    for (int i = 0; i < trains.length; i++) {
      final timeStr = trains[i].scheduledDeparture ?? trains[i].scheduledArrival ?? '';
      if (_getMinutesSinceMidnight(timeStr) >= nowMinutes) {
        return i;
      }
    }
    return 0;
  }

  void _scrollToCurrentTimetable(List<LiveTrainEntry> filteredTrains) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final sc = _timetableScrollController;
      if (sc != null && sc.hasClients) {
        final upcomingIdx = _findNextUpcomingTrainIndex(filteredTrains);
        if (upcomingIdx > 0) {
          final target = (44.0 + (upcomingIdx * 68.0)).clamp(0.0, sc.position.maxScrollExtent);
          sc.animateTo(
            target,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
          );
        }
      }
    });
  }

  List<LiveTrainEntry> _getSortedFilteredTimetable() {
    final sortedTrains = List<LiveTrainEntry>.from(_selectedStationTimetable);
    sortedTrains.sort((a, b) {
      final timeA = a.scheduledDeparture ?? a.scheduledArrival ?? '';
      final timeB = b.scheduledDeparture ?? b.scheduledArrival ?? '';
      return _getMinutesSinceMidnight(timeA).compareTo(_getMinutesSinceMidnight(timeB));
    });

    if (_selectedDirection == 'ALL') {
      return sortedTrains;
    }

    return sortedTrains.where((train) {
      final dir = getTrainDirection(train, _selectedStation!);
      return dir == _selectedDirection;
    }).toList();
  }

  List<LiveTrainEntry> _getSortedFilteredTimetableForDir(String dir) {
    final sortedTrains = List<LiveTrainEntry>.from(_selectedStationTimetable);
    sortedTrains.sort((a, b) {
      final timeA = a.scheduledDeparture ?? a.scheduledArrival ?? '';
      final timeB = b.scheduledDeparture ?? b.scheduledArrival ?? '';
      return _getMinutesSinceMidnight(timeA).compareTo(_getMinutesSinceMidnight(timeB));
    });

    if (dir == 'ALL') {
      return sortedTrains;
    }

    return sortedTrains.where((train) {
      final trainDir = getTrainDirection(train, _selectedStation!);
      return trainDir == dir;
    }).toList();
  }

  Widget _buildDirectionFilterChips() {
    final line = _selectedStation?.line ?? TrainLine.central;
    final String upLabel = line == TrainLine.western ? 'Towards Churchgate' : 'Towards CSMT';
    final String downLabel = line == TrainLine.western 
        ? 'Towards Virar/Dahanu' 
        : (line == TrainLine.central ? 'Towards Kasara/Karjat' : 'Towards Panvel/Goregaon');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF19A66E),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildFilterChip('ALL', 'All Directions', line.color),
            const SizedBox(width: 8),
            _buildFilterChip('UP', upLabel, line.color),
            const SizedBox(width: 8),
            _buildFilterChip('DOWN', downLabel, line.color),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String value, String label, Color lineColor) {
    final isSelected = _selectedDirection == value;
    return GestureDetector(
      onTap: () {
        final filtered = _getSortedFilteredTimetableForDir(value);
        setState(() {
          _selectedDirection = value;
        });
        _scrollToCurrentTimetable(filtered);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? lineColor : const Color(0xFF11754D),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? Colors.white.withValues(alpha: 0.8) : Colors.transparent,
            width: 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: lineColor.withValues(alpha: 0.4),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              value == 'ALL'
                  ? LucideIcons.compass
                  : (value == 'UP' ? LucideIcons.arrowDown : LucideIcons.arrowUp),
              size: 14,
              color: Colors.white,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
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

  bool isFastLocal(LiveTrainEntry train) {
    final type = (train.trainType ?? '').trim().toLowerCase();
    final name = train.trainName.toLowerCase();
    
    if (!isLocalTrain(train)) return false;

    if (type.contains('fast') ||
        type.contains('sf') ||
        name.contains('fast') ||
        name.contains(' sf') ||
        name.contains('(f)') ||
        name.contains('semi-fast') ||
        name.contains('semifast')) {
      return true;
    }
    return false;
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
                        topLeft: Radius.circular(10),
                        topRight: Radius.circular(10),
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
                                      _buildRoutePlannerTab(scrollController),
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
            markers: () {
              final Map<String, MumbaiStation> uniqueStations = {};
              for (final station in MumbaiStationData.allStations) {
                uniqueStations.putIfAbsent(station.code, () => station);
              }
              return uniqueStations.values.map((station) {
                final isSelected = station.code == _selectedStation?.code;
                return Marker(
                  point: LatLng(station.lat, station.lng),
                  width: isSelected ? 38 : 28,
                  height: isSelected ? 38 : 28,
                  child: GestureDetector(
                    onTap: () => _selectStation(station),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        color: station.line.color,
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
              }).toList();
            }(),
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
          topLeft: Radius.circular(10),
          topRight: Radius.circular(10),
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
                    borderRadius: BorderRadius.circular(10),
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
                borderRadius: BorderRadius.circular(10),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: Colors.white, // White active capsule, like "Now"
                  borderRadius: BorderRadius.circular(10),
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
                        const Icon(LucideIcons.navigation, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          'Route',
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
          borderRadius: BorderRadius.circular(10),
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
                      borderRadius: BorderRadius.circular(10),
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

  bool _isWithin2Hours(LiveTrainEntry train) {
    final String? expectedStr = train.expectedDepartureTime ?? train.expectedArrivalTime;
    DateTime? trainTime;
    if (expectedStr != null) {
      trainTime = DateTime.tryParse(expectedStr);
    }
    if (trainTime == null) {
      final String? scheduled = train.scheduledDeparture ?? train.scheduledArrival;
      if (scheduled != null) {
        trainTime = DateTime.tryParse(scheduled);
        if (trainTime == null) {
          final parts = scheduled.trim().split(':');
          if (parts.length >= 2) {
            final hour = int.tryParse(parts[0]);
            final minute = int.tryParse(parts[1]);
            if (hour != null && minute != null) {
              final now = DateTime.now();
              trainTime = DateTime(now.year, now.month, now.day, hour, minute);
            }
          }
        }
      }
    }
    
    if (trainTime == null) return true; // Default to showing it

    final now = DateTime.now();
    // Allow trains that departed up to 10 minutes ago up to 2 hours from now
    final minTime = now.subtract(const Duration(minutes: 10));
    final maxTime = now.add(const Duration(hours: 2));
    
    return trainTime.isAfter(minTime) && trainTime.isBefore(maxTime);
  }

  int _getMinutesSinceMidnight(String timeStr) {
    if (timeStr.isEmpty) return 0;
    try {
      if (timeStr.contains('T')) {
        final dt = DateTime.tryParse(timeStr);
        if (dt != null) {
          return dt.hour * 60 + dt.minute;
        }
      }
      final parts = timeStr.trim().split(':');
      if (parts.length >= 2) {
        final hour = int.tryParse(parts[0]) ?? 0;
        final minute = int.tryParse(parts[1]) ?? 0;
        return hour * 60 + minute;
      }
    } catch (_) {}
    return 0;
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

  Widget _buildDepartureRow(LiveTrainEntry train, MumbaiStation station) {
    final String? scheduled = train.scheduledDeparture ?? train.scheduledArrival;
    
    // Determine the text to display on the right
    String timeText = scheduled != null ? _formatTo12Hour(scheduled) : '';
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
            timeText = _formatTo12Hour(expectedStr);
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

          // Align F/S badges vertically by wrapping in a fixed-width container
          SizedBox(
            width: 32,
            child: isLocalTrain(train)
                ? Center(
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: () {
                          final name = train.trainName.toUpperCase();
                          if (name.contains('AC') || name.contains('A.C.')) {
                            return const Color(0xFF2F80ED); // AC Blue
                          } else if (name.contains('LADIES') || name.contains('LADY') || name.contains('LDS')) {
                            return const Color(0xFFE91E63); // Ladies Pink
                          } else {
                            return isFastLocal(train) ? const Color(0xFFEF4444) : const Color(0xFF10B981);
                          }
                        }(),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Center(
                        child: Text(
                          isFastLocal(train) ? 'F' : 'S',
                          style: GoogleFonts.outfit(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(width: 8),

          // Align departure times vertically by wrapping in a fixed-width container
          SizedBox(
            width: 80,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                timeText,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF475569),
                ),
                maxLines: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------

  Widget _buildLinesTab(ScrollController sheetController) {
    return ListView(
      controller: _tabController.index == 2 ? sheetController : null,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: TrainLine.values.map((line) {
        final stations = MumbaiStationData.getStationsByLine(line);
        final isExpanded = _lineExpanded[line] ?? false;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
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
    
    // Group the departures into Local and Express, filtering to only show trains from now to 2 hours
    final localTrains = _selectedStationDepartures.where((t) => isLocalTrain(t) && _isWithin2Hours(t)).toList();
    final expressTrains = _selectedStationDepartures.where((t) => !isLocalTrain(t) && _isWithin2Hours(t)).toList();

    return Column(
      children: [
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
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Station Name Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Row(
                  children: [
                    // MRT / Station Icon
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE91E63), // Pink style
                        borderRadius: BorderRadius.circular(10),
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

              // 2. Custom segmented tabs capsule: Now / Timetable
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFF11754D), // Capsule background
                    borderRadius: BorderRadius.circular(10),
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
                              borderRadius: BorderRadius.circular(10),
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
                              _selectedDirection = 'ALL';
                            });
                            if (_selectedStationTimetable.isEmpty) {
                              _fetchSelectedStationTimetable();
                            } else {
                              final sortedFiltered = _getSortedFilteredTimetable();
                              _scrollToCurrentTimetable(sortedFiltered);
                            }
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: _isTimetableMode ? Colors.white : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
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
            ],
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
        borderRadius: BorderRadius.circular(10),
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
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
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
    _timetableScrollController = scrollController;

    if (_isLoadingTimetable && _selectedStationTimetable.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
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
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final filteredTrains = _getSortedFilteredTimetable();
    final line = _selectedStation?.line ?? TrainLine.central;

    return Column(
      children: [
        _buildDirectionFilterChips(),
        Expanded(
          child: filteredTrains.isEmpty
              ? ListView(
                  controller: scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.4,
                      child: Center(
                        child: Text(
                          'No scheduled trains match this direction.',
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            color: Colors.white70,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : SingleChildScrollView(
                  controller: scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
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
                              topLeft: Radius.circular(10),
                              topRight: Radius.circular(10),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(LucideIcons.calendar, size: 16, color: line.color),
                              const SizedBox(width: 8),
                              Text(
                                'Full Schedule',
                                style: GoogleFonts.outfit(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF475569),
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${filteredTrains.length} trains',
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: const Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                          ),
                        ),
                        ...filteredTrains.map((train) => _buildSelectedStationDepartureRow(train)),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildSelectedStationDepartureRow(LiveTrainEntry train) {
    final String? scheduled = train.scheduledDeparture ?? train.scheduledArrival;
    
    // Determine the text to display on the right
    String timeText = scheduled != null ? _formatTo12Hour(scheduled) : '';
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
            timeText = _formatTo12Hour(expectedStr);
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
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TrainDetailScreen(train: train),
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

          // Align F/S badges vertically by wrapping in a fixed-width container
          SizedBox(
            width: 32,
            child: isLocalTrain(train)
                ? Center(
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: () {
                          final name = train.trainName.toUpperCase();
                          if (name.contains('AC') || name.contains('A.C.')) {
                            return const Color(0xFF2F80ED); // AC Blue
                          } else if (name.contains('LADIES') || name.contains('LADY') || name.contains('LDS')) {
                            return const Color(0xFFE91E63); // Ladies Pink
                          } else {
                            return isFastLocal(train) ? const Color(0xFFEF4444) : const Color(0xFF10B981);
                          }
                        }(),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Center(
                        child: Text(
                          isFastLocal(train) ? 'F' : 'S',
                          style: GoogleFonts.outfit(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(width: 8),

          // Align departure times vertically by wrapping in a fixed-width container
          SizedBox(
            width: 80,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                timeText,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF475569),
                ),
                maxLines: 1,
              ),
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

  // ===========================================================================
  // Route Planner Tab & Helper Methods
  // ===========================================================================

  Widget _buildRoutePlannerTab(ScrollController scrollController) {
    final filteredTrips = _plannedTrips.where((trip) {
      if (_selectedFilterAC) {
        final anyNonAC = trip.legItineraries.any((leg) {
          final name = leg.train.trainName.toUpperCase();
          return !name.contains('AC') && !name.contains('A.C.');
        });
        if (anyNonAC) return false;
      }
      if (_selectedFilterFast) {
        final anySlow = trip.legItineraries.any((leg) => !isFastLocal(leg.train));
        if (anySlow) return false;
      }
      if (_selectedFilterLadies) {
        final anyNonLadies = trip.legItineraries.any((leg) {
          final name = leg.train.trainName.toUpperCase();
          return !name.contains('LADIES') && !name.contains('LADY') && !name.contains('LDS');
        });
        if (anyNonLadies) return false;
      }
      return true;
    }).toList();

    return ListView(
      controller: _tabController.index == 1 ? scrollController : null,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        _buildUberSearchCard(),
        _buildFilterChips(),
        if (_isLoadingRoutes)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          )
        else if (_routesError != null)
          _buildErrorState(_routesError!)
        else if (_routeFromStation == null || _routeToStation == null)
          _buildEmptyRouteState(
            icon: LucideIcons.search,
            message: "Select start and destination stations to plan your journey",
          )
        else if (_plannedTrips.isEmpty)
          _buildEmptyRouteState(
            icon: LucideIcons.train,
            message: "No connections found. Try swapping directions or checking other stations.",
          )
        else if (filteredTrips.isEmpty)
          _buildEmptyRouteState(
            icon: LucideIcons.filter,
            message: "No connections match your filters. Try disabling some filters.",
          )
        else
          ...filteredTrips.map((trip) => _buildTripItineraryCard(trip)),
      ],
    );
  }

  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        children: [
          _buildRouteFilterChip(
            label: "AC Locals",
            icon: LucideIcons.snowflake,
            selected: _selectedFilterAC,
            onTap: () {
              setState(() {
                _selectedFilterAC = !_selectedFilterAC;
              });
            },
          ),
          const SizedBox(width: 8),
          _buildRouteFilterChip(
            label: "Fast Trains",
            icon: LucideIcons.zap,
            selected: _selectedFilterFast,
            onTap: () {
              setState(() {
                _selectedFilterFast = !_selectedFilterFast;
              });
            },
          ),
          const SizedBox(width: 8),
          _buildRouteFilterChip(
            label: "Ladies Special",
            icon: LucideIcons.heart,
            selected: _selectedFilterLadies,
            onTap: () {
              setState(() {
                _selectedFilterLadies = !_selectedFilterLadies;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRouteFilterChip({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final activeColor = const Color(0xFF19A66E);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? activeColor : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? activeColor : const Color(0xFFCBD5E1),
            width: 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: activeColor.withValues(alpha: 0.2),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected ? Colors.white : const Color(0xFF64748B),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: selected ? Colors.white : const Color(0xFF475569),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUberSearchCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Column(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Color(0xFF10B981),
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(
                width: 2,
                height: 36,
                child: Column(
                  children: List.generate(4, (index) => Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      width: 2,
                      color: const Color(0xFFCBD5E1),
                    ),
                  )),
                ),
              ),
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Color(0xFFEF4444),
                  shape: BoxShape.rectangle,
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () async {
                    final selected = await Navigator.push<MumbaiStation>(
                      context,
                      MaterialPageRoute(
                        builder: (context) => StationSearchScreen(
                          title: "Select Start Station",
                          userPosition: widget.userPosition,
                        ),
                      ),
                    );
                    if (selected != null) {
                      setState(() {
                        _routeFromStation = selected;
                      });
                      _calculateRouteItineraries();
                    }
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'FROM',
                          style: GoogleFonts.outfit(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF94A3B8),
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _routeFromStation?.name ?? 'Select starting station...',
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: _routeFromStation != null ? const Color(0xFF1E293B) : const Color(0xFF94A3B8),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final selected = await Navigator.push<MumbaiStation>(
                      context,
                      MaterialPageRoute(
                        builder: (context) => StationSearchScreen(
                          title: "Select Destination",
                          userPosition: widget.userPosition,
                        ),
                      ),
                    );
                    if (selected != null) {
                      setState(() {
                        _routeToStation = selected;
                      });
                      _calculateRouteItineraries();
                    }
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TO',
                          style: GoogleFonts.outfit(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF94A3B8),
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _routeToStation?.name ?? 'Select destination station...',
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: _routeToStation != null ? const Color(0xFF1E293B) : const Color(0xFF94A3B8),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(LucideIcons.arrowUpDown, color: Color(0xFF1E293B)),
            onPressed: () {
              setState(() {
                final temp = _routeFromStation;
                _routeFromStation = _routeToStation;
                _routeToStation = temp;
              });
              _calculateRouteItineraries();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyRouteState({required IconData icon, required String message}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 40, color: Colors.white.withValues(alpha: 0.7)),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 14,
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.alertCircle, color: Color(0xFFDC2626)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Error loading connections: $error',
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: const Color(0xFFDC2626),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTripItineraryCard(PlannedTripItinerary trip) {
    final firstLeg = trip.legItineraries.first;
    final lastLeg = trip.legItineraries.last;
    
    final depTime12 = _formatTo12Hour(firstLeg.departureTime);
    final arrTime12 = _formatTo12Hour(lastLeg.arrivalTime);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(LucideIcons.clock, size: 14, color: Color(0xFF64748B)),
                    const SizedBox(width: 6),
                    Text(
                      '${trip.totalDurationMinutes} mins',
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                  ],
                ),
                Text(
                  '$depTime12 → $arrTime12',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF19A66E),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildHorizontalPathPreview(trip),
            const SizedBox(height: 12),
            const Divider(color: Color(0xFFF1F5F9), height: 1),
            const SizedBox(height: 12),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: trip.legItineraries.length,
              separatorBuilder: (context, index) {
                final nextLeg = trip.legItineraries[index + 1];
                final junctionName = nextLeg.leg.start.name;
                final l1 = trip.legItineraries[index].leg.line;
                final l2 = nextLeg.leg.line;

                String guidanceText = "Walk across foot overbridge (FOB) to change platforms.";
                if (junctionName.toLowerCase().contains("dadar")) {
                  if (l1 == TrainLine.central && l2 == TrainLine.western) {
                    guidanceText = "Walk across FOB (Central Platforms 3-6 to Western Platforms 1-4) — ~4 min walk.";
                  } else if (l1 == TrainLine.western && l2 == TrainLine.central) {
                    guidanceText = "Walk across FOB (Western Platforms 1-4 to Central Platforms 3-6) — ~4 min walk.";
                  }
                } else if (junctionName.toLowerCase().contains("kurla")) {
                  if (l1 == TrainLine.central && l2 == TrainLine.harbour) {
                    guidanceText = "Walk across FOB (Central Platforms 7-8 to Harbour Platforms 1-2) — ~3 min walk.";
                  } else if (l1 == TrainLine.harbour && l2 == TrainLine.central) {
                    guidanceText = "Walk across FOB (Harbour Platforms 1-2 to Central Platforms 7-8) — ~3 min walk.";
                  }
                } else if (junctionName.toLowerCase().contains("bandra")) {
                  guidanceText = "Walk across FOB to transfer between Western and Harbour lines — ~3 min walk.";
                }

                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Color(0xFF64748B),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(LucideIcons.repeat, size: 12, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Transfer at $junctionName',
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF1E293B),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              guidanceText,
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                color: const Color(0xFF475569),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
              itemBuilder: (context, index) {
                final legItin = trip.legItineraries[index];
                final leg = legItin.leg;
                final train = legItin.train;
                final name = train.trainName.toUpperCase();
                
                final isAC = name.contains('AC') || name.contains('A.C.');
                final isLadies = name.contains('LADIES') || name.contains('LADY') || name.contains('LDS');
                final isFast = isFastLocal(train);

                Color badgeColor = const Color(0xFF10B981);
                if (isAC) {
                  badgeColor = const Color(0xFF2F80ED);
                } else if (isLadies) {
                  badgeColor = const Color(0xFFE91E63);
                } else if (isFast) {
                  badgeColor = const Color(0xFFEF4444);
                }

                final legKey = "${train.trainNumber}_${leg.start.code}_${leg.end.code}";
                final isExpanded = _expandedLegKeys.contains(legKey);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: InkWell(
                        onTap: () => _toggleLegExpanded(train.trainNumber, leg.start.code, leg.end.code),
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 4.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 52,
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  _formatTo12Hour(legItin.departureTime),
                                  style: GoogleFonts.outfit(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF475569),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: _getLineColor(leg.line),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '${leg.start.name} → ${leg.end.name}',
                                            style: GoogleFonts.outfit(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: const Color(0xFF1E293B),
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(LucideIcons.externalLink, size: 14, color: Color(0xFF64748B)),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) => TrainDetailScreen(train: train),
                                              ),
                                            );
                                          },
                                        ),
                                        const SizedBox(width: 4),
                                        Icon(
                                          isExpanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                                          size: 14,
                                          color: const Color(0xFF64748B),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: badgeColor,
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            isFast ? 'FAST' : 'SLOW',
                                            style: GoogleFonts.outfit(
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            '${train.trainNumber} ${train.trainName} (${leg.stopsCount} stops, ~${leg.stopsCount * 2}m)',
                                            style: GoogleFonts.outfit(
                                              fontSize: 12,
                                              color: const Color(0xFF64748B),
                                              fontWeight: FontWeight.w500,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    _buildLegStopsTimeline(leg, train),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHorizontalPathPreview(PlannedTripItinerary trip) {
    final List<Widget> children = [];

    // Add first station
    final firstStation = trip.legItineraries.first.leg.start;
    children.add(_buildPathStationCode(firstStation.code));

    for (final legItin in trip.legItineraries) {
      final leg = legItin.leg;
      final color = _getLineColor(leg.line);
      final lineLetter = leg.line == TrainLine.western
          ? 'W'
          : leg.line == TrainLine.central
              ? 'C'
              : 'H';

      children.add(
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 2,
                  color: color,
                ),
              ),
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  lineLetter,
                  style: GoogleFonts.outfit(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  height: 2,
                  color: color,
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: 14,
                color: Color(0xFF94A3B8),
              ),
            ],
          ),
        ),
      );

      children.add(_buildPathStationCode(leg.end.code));
    }

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: children,
      ),
    );
  }

  Widget _buildPathStationCode(String code) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFE2E8F0),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        code,
        style: GoogleFonts.outfit(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: const Color(0xFF334155),
        ),
      ),
    );
  }

  Color _getLineColor(TrainLine line) {
    switch (line) {
      case TrainLine.western:
        return const Color(0xFF2F80ED);
      case TrainLine.central:
        return const Color(0xFFEF4444);
      case TrainLine.harbour:
        return const Color(0xFF10B981);
    }
  }

  Future<void> _toggleLegExpanded(String trainNumber, String startCode, String endCode) async {
    final legKey = "${trainNumber}_${startCode}_$endCode";
    
    if (_expandedLegKeys.contains(legKey)) {
      setState(() {
        _expandedLegKeys.remove(legKey);
      });
      return;
    }

    setState(() {
      _expandedLegKeys.add(legKey);
    });

    if (_trainStopsCache.containsKey(trainNumber)) {
      return; // Already loaded and cached
    }

    setState(() {
      _loadingStops[trainNumber] = true;
    });

    try {
      final schedule = await _apiService.getTrainSchedule(trainNumber);
      if (mounted) {
        setState(() {
          _trainStopsCache[trainNumber] = schedule;
          _loadingStops[trainNumber] = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingStops[trainNumber] = false;
        });
      }
    }
  }

  List<RailGadiTrainStop> _getIntermediateHalts(
    List<RailGadiTrainStop> fullSchedule,
    String startCode,
    String endCode,
  ) {
    if (fullSchedule.isEmpty) return [];

    int startIdx = fullSchedule.indexWhere((s) => s.stationCode.toUpperCase() == startCode.toUpperCase());
    int endIdx = fullSchedule.indexWhere((s) => s.stationCode.toUpperCase() == endCode.toUpperCase());

    // Fallback: search by Dadar DR/DDR variants
    if (startIdx == -1 && (startCode == 'DDR' || startCode == 'DR')) {
      startIdx = fullSchedule.indexWhere((s) => s.stationCode == 'DDR' || s.stationCode == 'DR');
    }
    if (endIdx == -1 && (endCode == 'DDR' || endCode == 'DR')) {
      endIdx = fullSchedule.indexWhere((s) => s.stationCode == 'DDR' || s.stationCode == 'DR');
    }

    if (startIdx == -1 || endIdx == -1) {
      return [];
    }

    if (startIdx <= endIdx) {
      return fullSchedule.sublist(startIdx, endIdx + 1);
    } else {
      return fullSchedule.sublist(endIdx, startIdx + 1).reversed.toList();
    }
  }

  Widget _buildLegStopsTimeline(PlannedRouteLeg leg, LiveTrainEntry train) {
    final trainNumber = train.trainNumber;
    final legKey = "${trainNumber}_${leg.start.code}_${leg.end.code}";

    if (!_expandedLegKeys.contains(legKey)) {
      return const SizedBox.shrink();
    }

    if (_loadingStops[trainNumber] == true) {
      return Container(
        margin: const EdgeInsets.only(left: 68, right: 16, top: 4, bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF19A66E)),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              "Loading halts...",
              style: GoogleFonts.outfit(
                fontSize: 12,
                color: const Color(0xFF64748B),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    final fullSchedule = _trainStopsCache[trainNumber] ?? [];
    final halts = _getIntermediateHalts(fullSchedule, leg.start.code, leg.end.code);

    if (halts.isEmpty) {
      return Container(
        margin: const EdgeInsets.only(left: 68, right: 16, top: 4, bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          "Halt details unavailable.",
          style: GoogleFonts.outfit(
            fontSize: 12,
            color: const Color(0xFF64748B),
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    final lineColor = _getLineColor(leg.line);

    return Container(
      margin: const EdgeInsets.only(left: 68, right: 16, top: 4, bottom: 8),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: halts.length,
        itemBuilder: (context, index) {
          final halt = halts[index];
          final isFirst = index == 0;
          final isLast = index == halts.length - 1;
          final haltTime = halt.arrival ?? halt.departure ?? '';
          final formattedHaltTime = _formatTo12Hour(haltTime);

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 16,
                child: Column(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isFirst || isLast ? lineColor : Colors.white,
                        border: Border.all(color: lineColor, width: 2),
                        shape: BoxShape.circle,
                      ),
                    ),
                    if (!isLast)
                      Container(
                        width: 2,
                        height: 24,
                        color: lineColor.withValues(alpha: 0.5),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          halt.stationName,
                          style: GoogleFonts.outfit(
                            fontSize: 12.5,
                            fontWeight: isFirst || isLast ? FontWeight.bold : FontWeight.w500,
                            color: isFirst || isLast ? const Color(0xFF1E293B) : const Color(0xFF475569),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        formattedHaltTime,
                        style: GoogleFonts.outfit(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<PlannedRouteLeg> _calculateRouteLegs(MumbaiStation from, MumbaiStation to) {
    if (from.code == to.code) return [];

    if (from.line == to.line) {
      final list = MumbaiStationData.getStationsByLine(from.line);
      final idxStart = list.indexWhere((s) => s.code == from.code);
      final idxEnd = list.indexWhere((s) => s.code == to.code);
      final stopsCount = idxStart != -1 && idxEnd != -1 ? (idxEnd - idxStart).abs() : 5;
      
      return [
        PlannedRouteLeg(
          line: from.line,
          start: from,
          end: to,
          description: "Take the ${from.line.displayName} Line direct.",
          stopsCount: stopsCount,
        ),
      ];
    }

    TrainLine l1 = from.line;
    TrainLine l2 = to.line;

    String junctionName = "Dadar";
    String codeL1 = "DDR";
    String codeL2 = "DR";

    if ((l1 == TrainLine.western && l2 == TrainLine.central) ||
        (l1 == TrainLine.central && l2 == TrainLine.western)) {
      junctionName = "Dadar";
      codeL1 = (l1 == TrainLine.western) ? "DDR" : "DR";
      codeL2 = (l2 == TrainLine.western) ? "DDR" : "DR";
    } else if ((l1 == TrainLine.western && l2 == TrainLine.harbour) ||
               (l1 == TrainLine.harbour && l2 == TrainLine.western)) {
      junctionName = "Bandra";
      codeL1 = "BA";
      codeL2 = "BA";
    } else if ((l1 == TrainLine.central && l2 == TrainLine.harbour) ||
               (l1 == TrainLine.harbour && l2 == TrainLine.central)) {
      junctionName = "Kurla";
      codeL1 = "CLA";
      codeL2 = "CLA";
    }

    final list1 = MumbaiStationData.getStationsByLine(l1);
    final list2 = MumbaiStationData.getStationsByLine(l2);

    final junctionStn1 = list1.firstWhere(
      (s) => s.code == codeL1,
      orElse: () => MumbaiStation(code: codeL1, name: junctionName, lat: from.lat, lng: from.lng, line: l1),
    );
    final junctionStn2 = list2.firstWhere(
      (s) => s.code == codeL2,
      orElse: () => MumbaiStation(code: codeL2, name: junctionName, lat: to.lat, lng: to.lng, line: l2),
    );

    final idxStart1 = list1.indexWhere((s) => s.code == from.code);
    final idxJunction1 = list1.indexWhere((s) => s.code == codeL1);
    final stopsCount1 = idxStart1 != -1 && idxJunction1 != -1 ? (idxJunction1 - idxStart1).abs() : 5;

    final idxJunction2 = list2.indexWhere((s) => s.code == codeL2);
    final idxEnd2 = list2.indexWhere((s) => s.code == to.code);
    final stopsCount2 = idxJunction2 != -1 && idxEnd2 != -1 ? (idxEnd2 - idxJunction2).abs() : 5;

    return [
      PlannedRouteLeg(
        line: l1,
        start: from,
        end: junctionStn1,
        description: "Take ${l1.displayName} Line to ${junctionStn1.name}.",
        stopsCount: stopsCount1,
      ),
      PlannedRouteLeg(
        line: l2,
        start: junctionStn2,
        end: to,
        description: "Transfer to ${l2.displayName} Line towards ${to.name}.",
        stopsCount: stopsCount2,
      ),
    ];
  }

  Future<void> _calculateRouteItineraries() async {
    final from = _routeFromStation;
    final to = _routeToStation;
    if (from == null || to == null) return;

    setState(() {
      _isLoadingRoutes = true;
      _routesError = null;
      _plannedTrips = [];
    });

    try {
      final legs = _calculateRouteLegs(from, to);
      if (legs.isEmpty) {
        setState(() {
          _isLoadingRoutes = false;
        });
        return;
      }

      final Map<String, List<LiveTrainEntry>> timetables = {};
      for (final leg in legs) {
        if (!timetables.containsKey(leg.start.code)) {
          final list = await _apiService.getStationTimetable(leg.start.code);
          timetables[leg.start.code] = list;
        }
      }

      final leg1 = legs[0];
      final leg1Timetable = timetables[leg1.start.code] ?? [];
      
      final list1 = MumbaiStationData.getStationsByLine(leg1.line);
      final idxStart1 = list1.indexWhere((s) => s.code == leg1.start.code);
      final idxEnd1 = list1.indexWhere((s) => s.code == leg1.end.code);
      final isDown1 = idxEnd1 > idxStart1;

      final now = DateTime.now();
      final currentMinutes = now.hour * 60 + now.minute;

      final List<LiveTrainEntry> leg1MatchingTrains = [];
      for (final train in leg1Timetable) {
        final depTime = train.scheduledDeparture ?? '';
        if (depTime.isEmpty) continue;
        final parts = depTime.split(':');
        if (parts.length < 2) continue;
        final hr = int.tryParse(parts[0]) ?? 0;
        final min = int.tryParse(parts[1]) ?? 0;
        final trainMinutes = hr * 60 + min;

        if (trainMinutes < currentMinutes - 2) continue;

        final trainDest = train.destinationStation;
        final idxTrainDest = list1.indexWhere((s) => s.code == trainDest);
        if (idxTrainDest != -1) {
          final isTrainDown = idxTrainDest > idxStart1;
          if (isTrainDown != isDown1) continue;
        }
        
        leg1MatchingTrains.add(train);
      }

      leg1MatchingTrains.sort((a, b) {
        final depA = a.scheduledDeparture ?? '';
        final depB = b.scheduledDeparture ?? '';
        return depA.compareTo(depB);
      });

      final nextLeg1Trains = leg1MatchingTrains.take(4).toList();
      final List<PlannedTripItinerary> trips = [];

      for (final train1 in nextLeg1Trains) {
        final depTimeStr1 = train1.scheduledDeparture ?? '';
        final depParts = depTimeStr1.split(':');
        final depHr = int.tryParse(depParts[0]) ?? 0;
        final depMin = int.tryParse(depParts[1]) ?? 0;
        final depMinutes = depHr * 60 + depMin;

        final duration1 = leg1.stopsCount * 2 + 1;
        final arrMinutes1 = depMinutes + duration1;
        final arrHr = (arrMinutes1 ~/ 60) % 24;
        final arrMin = arrMinutes1 % 60;
        final arrTimeStr1 = '${arrHr.toString().padLeft(2, '0')}:${arrMin.toString().padLeft(2, '0')}';

        final leg1Itinerary = PlannedRouteLegItinerary(
          leg: leg1,
          train: train1,
          departureTime: depTimeStr1,
          arrivalTime: arrTimeStr1,
        );

        if (legs.length == 1) {
          trips.add(PlannedTripItinerary(
            legItineraries: [leg1Itinerary],
            totalDurationMinutes: duration1,
          ));
        } else {
          final leg2 = legs[1];
          final leg2Timetable = timetables[leg2.start.code] ?? [];

          final list2 = MumbaiStationData.getStationsByLine(leg2.line);
          final idxStart2 = list2.indexWhere((s) => s.code == leg2.start.code);
          final idxEnd2 = list2.indexWhere((s) => s.code == leg2.end.code);
          final isDown2 = idxEnd2 > idxStart2;

          final minDepartureMinutes2 = arrMinutes1 + 3;

          LiveTrainEntry? connectingTrain;
          for (final train2 in leg2Timetable) {
            final depTime2 = train2.scheduledDeparture ?? '';
            if (depTime2.isEmpty) continue;
            final parts2 = depTime2.split(':');
            if (parts2.length < 2) continue;
            final hr2 = int.tryParse(parts2[0]) ?? 0;
            final min2 = int.tryParse(parts2[1]) ?? 0;
            final trainMinutes2 = hr2 * 60 + min2;

            if (trainMinutes2 < minDepartureMinutes2) continue;

            final trainDest2 = train2.destinationStation;
            final idxTrainDest2 = list2.indexWhere((s) => s.code == trainDest2);
            if (idxTrainDest2 != -1) {
              final isTrainDown2 = idxTrainDest2 > idxStart2;
              if (isTrainDown2 != isDown2) continue;
            }

            if (connectingTrain == null) {
              connectingTrain = train2;
            } else {
              final currentBest = connectingTrain.scheduledDeparture ?? '';
              if (depTime2.compareTo(currentBest) < 0) {
                connectingTrain = train2;
              }
            }
          }

          if (connectingTrain != null) {
            final depTimeStr2 = connectingTrain.scheduledDeparture ?? '';
            final depParts2 = depTimeStr2.split(':');
            final depHr2 = int.tryParse(depParts2[0]) ?? 0;
            final depMin2 = int.tryParse(depParts2[1]) ?? 0;
            final depMinutes2 = depHr2 * 60 + depMin2;

            final duration2 = leg2.stopsCount * 2 + 1;
            final arrMinutes2 = depMinutes2 + duration2;
            final arrHr2 = (arrMinutes2 ~/ 60) % 24;
            final arrMin2 = arrMinutes2 % 60;
            final arrTimeStr2 = '${arrHr2.toString().padLeft(2, '0')}:${arrMin2.toString().padLeft(2, '0')}';

            final leg2Itinerary = PlannedRouteLegItinerary(
              leg: leg2,
              train: connectingTrain,
              departureTime: depTimeStr2,
              arrivalTime: arrTimeStr2,
            );

            final totalTripDuration = arrMinutes2 - depMinutes;

            trips.add(PlannedTripItinerary(
              legItineraries: [leg1Itinerary, leg2Itinerary],
              totalDurationMinutes: totalTripDuration,
            ));
          }
        }
      }

      setState(() {
        _plannedTrips = trips;
        _isLoadingRoutes = false;
      });
    } catch (e) {
      setState(() {
        _routesError = e.toString();
        _isLoadingRoutes = false;
      });
    }
  }
}

class PlannedRouteLeg {
  final TrainLine line;
  final MumbaiStation start;
  final MumbaiStation end;
  final String description;
  final int stopsCount;

  PlannedRouteLeg({
    required this.line,
    required this.start,
    required this.end,
    required this.description,
    required this.stopsCount,
  });
}

class PlannedTripItinerary {
  final List<PlannedRouteLegItinerary> legItineraries;
  final int totalDurationMinutes;
  
  PlannedTripItinerary({
    required this.legItineraries,
    required this.totalDurationMinutes,
  });
}

class PlannedRouteLegItinerary {
  final PlannedRouteLeg leg;
  final LiveTrainEntry train;
  final String departureTime;
  final String arrivalTime;
  
  PlannedRouteLegItinerary({
    required this.leg,
    required this.train,
    required this.departureTime,
    required this.arrivalTime,
  });
}

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

