import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

class AppSettingsScreen extends StatelessWidget {
  const AppSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const Color bgGray = Color(0xFFEDF1F4);
    const Color primaryText = Color(0xFF2D3748);
    const Color linkGreen = Color(0xFF1FA86A);

    return Scaffold(
      backgroundColor: bgGray,
      appBar: AppBar(
        backgroundColor: bgGray,
        elevation: 0,
        scrolledUnderElevation: 0,
        leadingWidth: 64,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16.0, top: 8.0, bottom: 8.0),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: const Icon(LucideIcons.x, color: Color(0xFF4A5568), size: 18),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
        title: Text(
          'App Settings',
          style: GoogleFonts.outfit(
            color: primaryText,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        children: [
          const SizedBox(height: 12),

          // 1. Remove Ads Banner
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF07294D),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                // Illustration Stack
                SizedBox(
                  width: 60,
                  height: 50,
                  child: Stack(
                    children: [
                      // Background Dashboard 1
                      Positioned(
                        left: 0,
                        top: 10,
                        child: Container(
                          width: 32,
                          height: 24,
                          decoration: BoxDecoration(
                            color: const Color(0x334FD1C5),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      // Background Dashboard 2
                      Positioned(
                        right: 0,
                        top: 5,
                        child: Container(
                          width: 36,
                          height: 28,
                          decoration: BoxDecoration(
                            color: const Color(0x224FD1C5),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      // Meditating character
                      Align(
                        alignment: Alignment.center,
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: const BoxDecoration(
                            color: Color(0xFFECC94B),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            LucideIcons.accessibility,
                            color: Color(0xFF07294D),
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Remove ads with CLUB',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Go ad-free and make it zen',
                        style: GoogleFonts.outfit(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  LucideIcons.chevronRight,
                  color: Colors.white54,
                  size: 20,
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),

          // 2. Settings Items List
          _buildSettingsRow(
            icon: LucideIcons.globe,
            iconColor: linkGreen,
            title: 'Singapore',
            actionText: 'Switch City',
            actionColor: linkGreen,
            onTap: () {},
          ),
          _buildDivider(),
          _buildSettingsRow(
            icon: LucideIcons.user,
            iconColor: linkGreen,
            title: 'Account',
            actionText: 'Login',
            actionColor: linkGreen,
            onTap: () {},
          ),
          _buildDivider(),
          _buildSettingsRow(
            icon: LucideIcons.crown,
            iconColor: const Color(0xFF1E3A8A),
            title: 'Remove Ads',
            actionText: '₹135.00/month',
            actionColor: linkGreen,
            onTap: () {},
          ),
          _buildDivider(),
          _buildSettingsRow(
            icon: LucideIcons.smartphone,
            iconColor: linkGreen,
            title: 'Change App Icon',
            onTap: () {},
          ),
          _buildDivider(),
          _buildSettingsRow(
            icon: LucideIcons.circle,
            iconColor: const Color(0xFF3B82F6),
            title: 'Change Map Location Dot',
            onTap: () {},
          ),

          const SizedBox(height: 24),

          // 3. Stats Card
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildStatCircle(
                        value: '0',
                        label: 'Calories',
                        icon: LucideIcons.flame,
                        iconColor: const Color(0xFF2B6CB0),
                        circleBg: const Color(0xFFEBF8FF),
                      ),
                      _buildStatCircle(
                        value: '0g',
                        label: 'CO2 Saved',
                        icon: LucideIcons.leaf,
                        iconColor: linkGreen,
                        circleBg: const Color(0xFFF0FFF4),
                      ),
                      _buildStatCircle(
                        value: '₹0',
                        label: 'Saved',
                        icon: LucideIcons.coins,
                        iconColor: const Color(0xFFB7791F),
                        circleBg: const Color(0xFFFFFFF0),
                      ),
                    ],
                  ),
                ),
                Container(
                  height: 1,
                  color: const Color(0xFFE2E8F0),
                ),
                InkWell(
                  onTap: () {},
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(10),
                    bottomRight: Radius.circular(10),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: Color(0xFFE6FFFA),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            LucideIcons.messageSquare,
                            color: linkGreen,
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'GO Stats',
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: primaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 4. Wrap Card
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 70,
                        height: 50,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2F855A),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '2025',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "2025 – That's a wrap!",
                              style: GoogleFonts.outfit(
                                color: const Color(0xFF2F855A),
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Read our first official partnerships, award for quickest transport mode, wacky feedback and our employee of the year",
                              style: GoogleFonts.outfit(
                                color: const Color(0xFF718096),
                                fontSize: 12,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  height: 1,
                  color: const Color(0xFFE2E8F0),
                ),
                InkWell(
                  onTap: () {},
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(10),
                    bottomRight: Radius.circular(10),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
                    child: Row(
                      children: [
                        const Icon(
                          LucideIcons.fileText,
                          color: Color(0xFF718096),
                          size: 18,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'All Posts',
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: primaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // 5. Social & Support Links
          _buildSettingsRow(
            icon: LucideIcons.mail,
            iconColor: const Color(0xFF4A5568),
            title: 'Contact Us',
            onTap: () {},
          ),
          _buildDivider(),
          _buildSettingsRow(
            icon: LucideIcons.twitter,
            iconColor: const Color(0xFF1DA1F2),
            title: '@Citymapper on Twitter',
            onTap: () {},
          ),
          _buildDivider(),
          _buildSettingsRow(
            icon: LucideIcons.share2,
            iconColor: const Color(0xFF4A5568),
            title: 'Share the App',
            onTap: () {},
          ),
          _buildDivider(),
          _buildSettingsRow(
            icon: LucideIcons.play,
            iconColor: const Color(0xFF34A853),
            title: 'Rate the App',
            onTap: () {},
          ),
          _buildDivider(),
          _buildSettingsRow(
            icon: LucideIcons.briefcase,
            iconColor: const Color(0xFF4A5568),
            title: 'Work at Citymapper',
            onTap: () {},
          ),

          const SizedBox(height: 32),

          // 6. Plain Text Links
          _buildTextLink('Privacy Policy', () {}),
          _buildTextLink('Privacy Settings', () {}),
          _buildTextLink('Terms of Service', () {}),
          _buildTextLink('Data Sources', () {}),
          _buildTextLink('Acknowledgements', () {}),

          const SizedBox(height: 24),

          // 7. Version Text
          Center(
            child: Text(
              'Version 11.53.1',
              style: GoogleFonts.outfit(
                color: const Color(0xFF718096),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 8. Bottom Character Graphic (Citymapper Commuters painting)
          SizedBox(
            width: double.infinity,
            height: 60,
            child: CustomPaint(
              painter: CommutersPainter(),
            ),
          ),
        ],
      ),
    );
  }

  // Row helper method
  Widget _buildSettingsRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? actionText,
    Color? actionColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
        key: Key('row_$title'),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 22),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF2D3748),
                ),
              ),
            ),
            if (actionText != null)
              Text(
                actionText,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: actionColor ?? const Color(0xFF718096),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.only(left: 54.0),
      child: Container(
        height: 1,
        color: const Color(0xFFE2E8F0),
      ),
    );
  }

  // Stat circle helper
  Widget _buildStatCircle({
    required String value,
    required String label,
    required IconData icon,
    required Color iconColor,
    required Color circleBg,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: circleBg,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 24),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: GoogleFonts.outfit(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF2D3748),
          ),
        ),
        Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF718096),
          ),
        ),
      ],
    );
  }

  // Plain text link helper
  Widget _buildTextLink(String text, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Center(
          child: Text(
            text,
            style: GoogleFonts.outfit(
              color: const Color(0xFF718096),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

// Custom painter to draw the unique row of Citymapper commuters in the footer
class CommutersPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final grayPaint = Paint()
      ..color = const Color(0xFFCBD5E0)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final greenPaint = Paint()
      ..color = const Color(0xFF1FA86A)
      ..style = PaintingStyle.fill;

    final greenStrokePaint = Paint()
      ..color = const Color(0xFF1FA86A)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // We will draw a series of schematic character figures across the screen.
    // Center character is colored solid green, the others are light gray outlines.
    final double center = size.width / 2;
    const double spacing = 42.0;

    // Draw 4 figures on left and 4 on right
    for (int i = -4; i <= 4; i++) {
      final double cx = center + (i * spacing);
      final double cy = size.height - 20;

      if (i == 0) {
        // Draw the green custom character (blowing bubblegum or standing)
        // Body (rounded rect)
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(cx - 10, cy - 22, 20, 26),
            const Radius.circular(6),
          ),
          greenPaint,
        );
        // Head/hair outline
        canvas.drawCircle(Offset(cx, cy - 28), 7, greenPaint);
        // Legs
        canvas.drawLine(Offset(cx - 4, cy + 4), Offset(cx - 4, cy + 12), greenStrokePaint);
        canvas.drawLine(Offset(cx + 4, cy + 4), Offset(cx + 4, cy + 12), greenStrokePaint);
        // Feet
        canvas.drawLine(Offset(cx - 4, cy + 12), Offset(cx - 8, cy + 12), greenStrokePaint);
        canvas.drawLine(Offset(cx + 4, cy + 12), Offset(cx + 8, cy + 12), greenStrokePaint);
      } else {
        // Draw gray outline character
        // Body
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(cx - 9, cy - 20, 18, 24),
            const Radius.circular(5),
          ),
          grayPaint,
        );
        // Head
        canvas.drawCircle(Offset(cx, cy - 25), 6, grayPaint);
        // Legs
        canvas.drawLine(Offset(cx - 3, cy + 4), Offset(cx - 3, cy + 10), grayPaint);
        canvas.drawLine(Offset(cx + 3, cy + 4), Offset(cx + 3, cy + 10), grayPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
