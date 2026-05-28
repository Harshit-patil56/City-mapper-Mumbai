import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:geolocator/geolocator.dart';
import 'settings_screen.dart';
import 'screens/train_stations_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'City Mapper Mumbai',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        textTheme: GoogleFonts.outfitTextTheme(),
      ),
      home: const CityMapperHomeScreen(),
    );
  }
}

class CityMapperHomeScreen extends StatefulWidget {
  const CityMapperHomeScreen({super.key});

  @override
  State<CityMapperHomeScreen> createState() => _CityMapperHomeScreenState();
}

class _CityMapperHomeScreenState extends State<CityMapperHomeScreen> {
  LatLng? _currentPosition;
  bool _isLoadingLocation = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _determinePosition();
    });
  }

  Future<void> _determinePosition() async {
    setState(() {
      _isLoadingLocation = true;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _isLoadingLocation = false;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _isLoadingLocation = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _isLoadingLocation = false;
        });
        return;
      }

      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      final newLatLng = LatLng(position.latitude, position.longitude);

      setState(() {
        _currentPosition = newLatLng;
        _isLoadingLocation = false;
      });

      mapController.move(newLatLng, 15.0);
    } catch (e) {
      debugPrint("Error fetching location: $e");
      setState(() {
        _isLoadingLocation = false;
      });
    }
  }

  final MapController mapController = MapController();

  // Initial map position: Gateway of India, Mumbai
  final LatLng _initialPosition = const LatLng(18.9220, 72.8347);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // 1. OpenStreetMap Background
          Positioned.fill(
            child: FlutterMap(
              mapController: mapController,
              options: MapOptions(
                initialCenter: _initialPosition,
                initialZoom: 14.5,
                minZoom: 5.0,
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
                if (_currentPosition != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _currentPosition!,
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
          ),

                    // 3. Floating GPS Location Button (positioned above the bottom sheet)
          Positioned(
            bottom: MediaQuery.of(context).size.height * 0.22 + 24,
            right: 16,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _determinePosition,
                  borderRadius: BorderRadius.circular(24),
                  child: Center(
                    child: _isLoadingLocation
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2F80ED)),
                            ),
                          )
                        : const Icon(
                            LucideIcons.navigation,
                            color: Color(0xFF334155),
                            size: 20,
                          ),
                  ),
                ),
              ),
            ),
          ),

// 2. Settings button overlay at top-left
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(left: 16.0, top: 8.0),
                key: const Key('settings_btn_padding'),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: const Icon(
                      LucideIcons.settings,
                      color: Color(0xFF334155),
                      size: 20,
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AppSettingsScreen(),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),

          // 3. Bottom Panel Overlay (Green Panel behind Search + Grid + Blue Footer)
          Positioned.fill(
            child: DraggableScrollableSheet(
              initialChildSize: 0.58,
              minChildSize: 0.22,
              maxChildSize: 0.85,
              snap: true,
              snapSizes: const [0.22, 0.58, 0.85],
              builder: (context, scrollController) {
                return ListView(
                  controller: scrollController,
                  padding: EdgeInsets.zero,
                  physics: const ClampingScrollPhysics(),
                  children: [
                    // A. White Card (Search & Quick Destinations)
                    const SizedBox(height: 12),
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // 1. Column holding Spacer + Green Container
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(height: 25),
                            Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1FA86A),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 12,
                            offset: const Offset(0, -2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 130),
                      
                      // Row 1 of Grid
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Row(
                          children: [
                            Expanded(child: Center(child: _buildTransitButton('All', _buildAllIcon(), () {}))),
                            Expanded(child: Center(child: _buildTransitButton('Walk', const Icon(LucideIcons.footprints, color: Colors.white, size: 24), () {}))),
                            Expanded(child: Center(child: _buildTransitButton('Cycle', const Icon(LucideIcons.bike, color: Color(0xFF8CEE3F), size: 24), () {}))),
                            Expanded(child: Center(child: _buildTransitButton('Maps', const Icon(LucideIcons.map, color: Color(0xFF3F95EE), size: 24), () {}))),
                            Expanded(child: Center(child: _buildTransitButton('Issues', _buildIssuesIcon(), () {}))),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 12),

                      // Row 2 of Grid
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Row(
                          children: [
                            Expanded(child: Center(child: _buildTransitButton('Bus', const Icon(LucideIcons.bus, color: Color(0xFF2ECC71), size: 24), () {}))),
                            Expanded(child: Center(child: _buildTransitButton('MRT', const Icon(LucideIcons.train, color: Color(0xFFE91E63), size: 24), () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => TrainStationsScreen(
                                    userPosition: _currentPosition,
                                  ),
                                ),
                              );
                            }))),
                            Expanded(child: Center(child: _buildTransitButton('LRT', const Icon(LucideIcons.train, color: Color(0xFF03A9F4), size: 24), () {}))),
                            Expanded(child: Center(child: _buildTransitButton('Shuttle', const Icon(LucideIcons.car, color: Color(0xFF009688), size: 24), () {}))),
                            Expanded(child: Center(child: _buildTransitButton('Ferry', const Icon(LucideIcons.ship, color: Color(0xFF00BCD4), size: 24), () {}))),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 20),

                      // Trip Stats Section
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Text(
                          'Trip Stats',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xB3FFFFFF),
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Carbon/CO2 Card
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF148E59),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: Color(0xFF1FA86A),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                LucideIcons.leaf,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: RichText(
                                text: TextSpan(
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  children: const [
                                    TextSpan(text: 'Track CO2 savings with '),
                                    TextSpan(
                                      text: 'go',
                                      style: TextStyle(
                                        fontStyle: FontStyle.italic,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const Icon(
                              LucideIcons.chevronRight,
                              color: Colors.white70,
                              size: 16,
                            ),
                          ],
                        ),
                      ),

                      // 4. Skyline Vector custom drawing
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: CustomPaint(
                          painter: SkylinePainter(),
                        ),
                      ),

                      // C. Blue Footer Banner (Outside Coverage)
                      Container(
                        width: double.infinity,
                        color: const Color(0xFF1D70B8),
                        padding: const EdgeInsets.only(
                          left: 16,
                          right: 16,
                          top: 14,
                          bottom: 24, // Added extra padding for navigation bar spacing
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF2ECC71),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const Icon(
                                  LucideIcons.clock,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ],
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    "You're outside our coverage",
                                    style: GoogleFonts.outfit(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    "See all cities >",
                                    style: GoogleFonts.outfit(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.white.withValues(alpha: 0.85),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                        ],
                      ),
                    )
                          ],
                        ),
                        // 2. White Search Card overlaying the Stack
                        Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // "Get Me Somewhere" Bar
                      InkWell(
                        onTap: () {},
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(12),
                          topRight: Radius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF28547A),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  LucideIcons.search,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Text(
                                'Get Me Somewhere',
                                style: GoogleFonts.outfit(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF334155),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      // Divider
                      Container(
                        height: 1,
                        color: const Color(0xFFE2E8F0),
                      ),

                      // Lower Destinations Row
                      SizedBox(
                                height: 56,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    // "Get Me Home"
                                    Expanded(
                                      child: InkWell(
                                        onTap: () {},
                                        borderRadius: const BorderRadius.only(
                                          bottomLeft: Radius.circular(12),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.only(left: 16.0),
                                          child: Row(
                                            children: [
                                              Container(
                                                width: 32,
                                                height: 32,
                                                decoration: const BoxDecoration(
                                                  color: Color(0xFF28547A),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(
                                                  LucideIcons.home,
                                                  color: Colors.white,
                                                  size: 16,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Text(
                                                'Get Me Home',
                                                style: GoogleFonts.outfit(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                  color: const Color(0xFF334155),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),

                                    // Left Divider (touches top and bottom)
                                    Container(
                                      width: 1,
                                      color: const Color(0xFFE2E8F0),
                                    ),

                                    // Work Shortcut
                                    InkWell(
                                      onTap: () {},
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              width: 32,
                                              height: 32,
                                              decoration: const BoxDecoration(
                                                color: Color(0xFF28547A),
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                LucideIcons.briefcase,
                                                color: Colors.white,
                                                size: 15,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Work',
                                              style: GoogleFonts.outfit(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w500,
                                                color: const Color(0xFF64748B),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),

                                    // Right Divider (touches top and bottom)
                                    Container(
                                      width: 1,
                                      color: const Color(0xFFE2E8F0),
                                    ),

                                    // Places Shortcut
                                    InkWell(
                                      onTap: () {},
                                      borderRadius: const BorderRadius.only(
                                        bottomRight: Radius.circular(12),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              width: 32,
                                              height: 32,
                                              decoration: const BoxDecoration(
                                                color: Color(0xFF28547A),
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                LucideIcons.star,
                                                color: Colors.white,
                                                size: 15,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Places',
                                              style: GoogleFonts.outfit(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w500,
                                                color: const Color(0xFF64748B),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                    ],
                  ),
                )
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // Helper widget to construct the transit buttons in the green panel
  Widget _buildTransitButton(String label, Widget icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: const Color(0xFF148E59),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Custom multi-icon representation for the "All" button
  Widget _buildAllIcon() {
    return const SizedBox(
      width: 24,
      height: 24,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            child: Icon(
              LucideIcons.train,
              color: Colors.white,
              size: 14,
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Icon(
              LucideIcons.bus,
              color: Colors.white,
              size: 14,
            ),
          ),
        ],
      ),
    );
  }

  // Custom icon representation for the "Issues" button (alert with red badge)
  Widget _buildIssuesIcon() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Icon(
          LucideIcons.alertTriangle,
          color: Color(0xFFF39C12),
          size: 24,
        ),
        Positioned(
          top: -2,
          right: -2,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(
              color: Color(0xFFE67E22),
              shape: BoxShape.circle,
            ),
            constraints: const BoxConstraints(
              minWidth: 12,
              minHeight: 12,
            ),
            child: const Text(
              '1',
              style: TextStyle(
                color: Colors.white,
                fontSize: 7,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }
}

// Custom painter to draw the subtle city skyline silhouette at the bottom of the green section
class SkylinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF148E59).withValues(alpha: 0.4)
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(0, size.height);

    // Draw a vector-like city skyline with different sized buildings
    path.lineTo(0, size.height - 15);
    path.lineTo(15, size.height - 15);
    path.lineTo(15, size.height - 30);
    path.lineTo(28, size.height - 30);
    path.lineTo(28, size.height - 12);
    path.lineTo(38, size.height - 12);
    path.lineTo(38, size.height - 25);
    path.lineTo(50, size.height - 25);
    path.lineTo(50, size.height - 18);
    path.lineTo(62, size.height - 18);
    path.lineTo(62, size.height - 35);
    path.lineTo(75, size.height - 35);
    // Draw building spire
    path.lineTo(75, size.height - 40);
    path.lineTo(76, size.height - 40);
    path.lineTo(76, size.height - 35);
    path.lineTo(82, size.height - 35);
    path.lineTo(82, size.height - 10);
    path.lineTo(95, size.height - 10);
    path.lineTo(95, size.height - 28);
    path.lineTo(110, size.height - 28);
    path.lineTo(110, size.height - 15);
    path.lineTo(125, size.height - 15);
    path.lineTo(125, size.height - 32);
    path.lineTo(138, size.height - 32);
    path.lineTo(138, size.height - 12);
    path.lineTo(150, size.height - 12);
    path.lineTo(150, size.height - 22);
    path.lineTo(165, size.height - 22);
    path.lineTo(165, size.height - 38);
    path.lineTo(178, size.height - 38);
    path.lineTo(178, size.height - 15);
    path.lineTo(190, size.height - 15);
    path.lineTo(190, size.height - 26);
    path.lineTo(205, size.height - 26);
    path.lineTo(205, size.height - 10);
    path.lineTo(220, size.height - 10);
    path.lineTo(220, size.height - 30);
    path.lineTo(235, size.height - 30);
    path.lineTo(235, size.height - 18);
    path.lineTo(250, size.height - 18);
    path.lineTo(250, size.height - 34);
    path.lineTo(262, size.height - 34);
    path.lineTo(262, size.height - 12);
    path.lineTo(275, size.height - 12);
    path.lineTo(275, size.height - 25);
    path.lineTo(288, size.height - 25);
    path.lineTo(288, size.height - 38);
    // Draw tower spire
    path.lineTo(293, size.height - 44);
    path.lineTo(294, size.height - 44);
    path.lineTo(299, size.height - 38);
    path.lineTo(305, size.height - 38);
    path.lineTo(305, size.height - 15);
    path.lineTo(320, size.height - 15);
    path.lineTo(320, size.height - 28);
    path.lineTo(335, size.height - 28);
    path.lineTo(335, size.height - 12);
    
    // Smooth transition to end of screen width
    path.lineTo(size.width, size.height - 12);
    path.lineTo(size.width, size.height);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}


