import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:latlong2/latlong.dart';
import '../data/mumbai_stations.dart';

class StationSearchScreen extends StatefulWidget {
  final String title;
  final LatLng? userPosition;

  const StationSearchScreen({
    super.key,
    required this.title,
    this.userPosition,
  });

  @override
  State<StationSearchScreen> createState() => _StationSearchScreenState();
}

class _StationSearchScreenState extends State<StationSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<MumbaiStation> _filteredStations = [];
  List<({MumbaiStation station, double distanceMeters})> _nearbyStations = [];

  @override
  void initState() {
    super.initState();
    _filteredStations = _getDeduplicatedStations();
    _computeNearbyStations();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<MumbaiStation> _getDeduplicatedStations() {
    // Deduplicate stations that appear on multiple lines (e.g. Dadar, CSMT)
    final Map<String, MumbaiStation> uniqueByCode = {};
    for (final station in MumbaiStationData.allStations) {
      uniqueByCode.putIfAbsent(station.code, () => station);
    }
    final list = uniqueByCode.values.toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  void _computeNearbyStations() {
    if (widget.userPosition != null) {
      _nearbyStations = MumbaiStationData.findNearbyStations(
        widget.userPosition!.latitude,
        widget.userPosition!.longitude,
        limit: 4,
      );
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    final all = _getDeduplicatedStations();
    if (query.isEmpty) {
      setState(() {
        _filteredStations = all;
      });
      return;
    }

    setState(() {
      _filteredStations = all.where((stn) {
        return stn.name.toLowerCase().contains(query) ||
            stn.code.toLowerCase().contains(query);
      }).toList();
    });
  }

  Color _getLineColor(TrainLine line) {
    switch (line) {
      case TrainLine.western:
        return const Color(0xFF2F80ED); // Western Blue
      case TrainLine.central:
        return const Color(0xFFEF4444); // Central Red
      case TrainLine.harbour:
        return const Color(0xFF10B981); // Harbour Green
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft, color: Color(0xFF334155)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.title,
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF334155),
          ),
        ),
      ),
      body: Column(
        children: [
          // Search Input Bar
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              style: GoogleFonts.outfit(
                fontSize: 15,
                color: const Color(0xFF1E293B),
              ),
              decoration: InputDecoration(
                hintText: 'Enter station name or code...',
                hintStyle: GoogleFonts.outfit(
                  fontSize: 15,
                  color: const Color(0xFF94A3B8),
                ),
                prefixIcon: const Icon(LucideIcons.search, color: Color(0xFF64748B), size: 18),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(LucideIcons.x, color: Color(0xFF64748B), size: 18),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),

          // Nearby / Current Location section (only if user position is available)
          if (widget.userPosition != null && _searchController.text.isEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(LucideIcons.navigation, size: 14, color: Color(0xFF64748B)),
                      const SizedBox(width: 6),
                      Text(
                        'Nearby Stations',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF64748B),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      // Current location shortcut (resolves to nearest station)
                      if (_nearbyStations.isNotEmpty)
                        ActionChip(
                          avatar: const Icon(LucideIcons.mapPin, size: 13, color: Colors.white),
                          label: Text(
                            'Nearest: ${_nearbyStations.first.station.name}',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          backgroundColor: const Color(0xFF19A66E), // Green active
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide.none,
                          ),
                          onPressed: () {
                            Navigator.pop(context, _nearbyStations.first.station);
                          },
                        ),
                      
                      // Other nearby stations
                      ..._nearbyStations.skip(1).map((item) {
                        final stn = item.station;
                        final distStr = MumbaiStationData.formatDistance(item.distanceMeters);
                        return ActionChip(
                          label: Text(
                            '${stn.name} ($distStr)',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF334155),
                            ),
                          ),
                          backgroundColor: const Color(0xFFF1F5F9),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide.none,
                          ),
                          onPressed: () {
                            Navigator.pop(context, stn);
                          },
                        );
                      }),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFFF1F5F9), height: 24),
          ],

          // Scrollable List of Stations
          Expanded(
            child: _filteredStations.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(LucideIcons.mapPinOff, size: 48, color: Color(0xFFCBD5E1)),
                        const SizedBox(height: 12),
                        Text(
                          'No stations found',
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            color: const Color(0xFF64748B),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _filteredStations.length,
                    itemBuilder: (context, index) {
                      final stn = _filteredStations[index];
                      final lines = MumbaiStationData.getLinesForStation(stn.code);
                      
                      // Calculate distance if position is available
                      String? distStr;
                      if (widget.userPosition != null) {
                        final dist = stn.distanceTo(
                          widget.userPosition!.latitude,
                          widget.userPosition!.longitude,
                        );
                        distStr = MumbaiStationData.formatDistance(dist);
                      }

                      return ListTile(
                        onTap: () {
                          Navigator.pop(context, stn);
                        },
                        leading: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            LucideIcons.train,
                            color: Color(0xFF475569),
                            size: 18,
                          ),
                        ),
                        title: Text(
                          stn.name,
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1E293B),
                          ),
                        ),
                        subtitle: Text(
                          stn.code,
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (distStr != null) ...[
                              Text(
                                distStr,
                                style: GoogleFonts.outfit(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: const Color(0xFF64748B),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            // Render line color pills for served lines
                            Wrap(
                              spacing: 4,
                              children: lines.map((line) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _getLineColor(line),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    line.shortCode,
                                    style: GoogleFonts.outfit(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
