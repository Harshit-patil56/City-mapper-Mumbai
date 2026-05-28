import 'dart:math';
import 'dart:ui' show Color;

/// Represents one of Mumbai's three suburban railway lines.
enum TrainLine {
  western('Western', 'W', Color(0xFF2196F3)), // Blue
  central('Central', 'C', Color(0xFFF44336)), // Red
  harbour('Harbour', 'H', Color(0xFF4CAF50)); // Green

  final String displayName;
  final String shortCode;
  final Color color;

  const TrainLine(this.displayName, this.shortCode, this.color);
}

// Custom Color class to avoid importing flutter material in a data file.
// This will be replaced by Flutter's Color at the usage site.
// Actually, we need to import material for Color. Let's use int values instead
// and convert at the widget level to keep this file pure Dart + latlong2.

/// A single Mumbai suburban railway station.
class MumbaiStation {
  /// Indian Railways station code (e.g. "BCT", "CSTM").
  final String code;

  /// Human-readable station name.
  final String name;

  /// Latitude in decimal degrees.
  final double lat;

  /// Longitude in decimal degrees.
  final double lng;

  /// Which suburban line this station belongs to.
  final TrainLine line;

  /// Whether this is a major junction (serves multiple lines or high traffic).
  final bool isJunction;

  const MumbaiStation({
    required this.code,
    required this.name,
    required this.lat,
    required this.lng,
    required this.line,
    this.isJunction = false,
  });

  /// Calculates the Haversine distance in meters from this station to [lat2], [lng2].
  double distanceTo(double lat2, double lng2) {
    const double earthRadiusM = 6371000;
    final double dLat = _toRadians(lat2 - lat);
    final double dLng = _toRadians(lng2 - lng);
    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat)) *
            cos(_toRadians(lat2)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusM * c;
  }

  static double _toRadians(double degrees) => degrees * pi / 180;

  @override
  String toString() => 'MumbaiStation($code, $name, $line)';
}

/// Central registry of all Mumbai suburban stations.
///
/// To add a new station, simply append a [MumbaiStation] entry to the
/// appropriate line list below. No other code changes are needed.
class MumbaiStationData {
  MumbaiStationData._();

  // ---------------------------------------------------------------------------
  // Western Line — Churchgate to Virar (South → North)
  // ---------------------------------------------------------------------------
  static const List<MumbaiStation> _westernStations = [
    MumbaiStation(
      code: 'CCG',
      name: 'Churchgate',
      lat: 18.93449,
      lng: 72.82729,
      line: TrainLine.western,
      isJunction: true,
    ),
    MumbaiStation(
      code: 'MEL',
      name: 'Marine Lines',
      lat: 18.94566,
      lng: 72.82378,
      line: TrainLine.western,
    ),
    MumbaiStation(
      code: 'CYR',
      name: 'Charni Road',
      lat: 18.95139,
      lng: 72.81891,
      line: TrainLine.western,
    ),
    MumbaiStation(
      code: 'BCL',
      name: 'Mumbai Central',
      lat: 18.97084,
      lng: 72.81886,
      line: TrainLine.western,
      isJunction: true,
    ),
    MumbaiStation(
      code: 'DDR',
      name: 'Dadar',
      lat: 19.01888,
      lng: 72.84299,
      line: TrainLine.western,
      isJunction: true,
    ),
    MumbaiStation(
      code: 'BA',
      name: 'Bandra',
      lat: 19.05417,
      lng: 72.84126,
      line: TrainLine.western,
      isJunction: true,
    ),
    MumbaiStation(
      code: 'ADH',
      name: 'Andheri',
      lat: 19.11874,
      lng: 72.84692,
      line: TrainLine.western,
      isJunction: true,
    ),
    MumbaiStation(
      code: 'JOS',
      name: 'Jogeshwari',
      lat: 19.13647,
      lng: 72.84896,
      line: TrainLine.western,
    ),
    MumbaiStation(
      code: 'GMN',
      name: 'Goregaon',
      lat: 19.16461,
      lng: 72.84961,
      line: TrainLine.western,
    ),
    MumbaiStation(
      code: 'MDD',
      name: 'Malad',
      lat: 19.18723,
      lng: 72.84898,
      line: TrainLine.western,
    ),
    MumbaiStation(
      code: 'KILE',
      name: 'Kandivali',
      lat: 19.20451,
      lng: 72.85199,
      line: TrainLine.western,
    ),
    MumbaiStation(
      code: 'BVI',
      name: 'Borivali',
      lat: 19.22891,
      lng: 72.85673,
      line: TrainLine.western,
      isJunction: true,
    ),
    MumbaiStation(
      code: 'MIRA',
      name: 'Mira Road',
      lat: 19.27972,
      lng: 72.85612,
      line: TrainLine.western,
    ),
    MumbaiStation(
      code: 'VR',
      name: 'Virar',
      lat: 19.45495,
      lng: 72.81202,
      line: TrainLine.western,
      isJunction: true,
    ),
  ];

  // ---------------------------------------------------------------------------
  // Central Line — CSMT to Kasara (South → North/East)
  // ---------------------------------------------------------------------------
  static const List<MumbaiStation> _centralStations = [
    MumbaiStation(
      code: 'CSMT',
      name: 'Chhatrapati Shivaji Maharaj Terminus',
      lat: 18.94087,
      lng: 72.83606,
      line: TrainLine.central,
      isJunction: true,
    ),
    MumbaiStation(
      code: 'MSD',
      name: 'Masjid',
      lat: 18.95195,
      lng: 72.83834,
      line: TrainLine.central,
    ),
    MumbaiStation(
      code: 'BY',
      name: 'Byculla',
      lat: 18.97664,
      lng: 72.83287,
      line: TrainLine.central,
    ),
    MumbaiStation(
      code: 'DR',
      name: 'Dadar',
      lat: 19.01705,
      lng: 72.84303,
      line: TrainLine.central,
      isJunction: true,
    ),
    MumbaiStation(
      code: 'CLA',
      name: 'Kurla',
      lat: 19.06515,
      lng: 72.87940,
      line: TrainLine.central,
      isJunction: true,
    ),
    MumbaiStation(
      code: 'GC',
      name: 'Ghatkopar',
      lat: 19.08560,
      lng: 72.90812,
      line: TrainLine.central,
      isJunction: true,
    ),
    MumbaiStation(
      code: 'VK',
      name: 'Vikhroli',
      lat: 19.11194,
      lng: 72.92847,
      line: TrainLine.central,
    ),
    MumbaiStation(
      code: 'BND',
      name: 'Bhandup',
      lat: 19.14228,
      lng: 72.93779,
      line: TrainLine.central,
    ),
    MumbaiStation(
      code: 'MLND',
      name: 'Mulund',
      lat: 19.17173,
      lng: 72.95663,
      line: TrainLine.central,
    ),
    MumbaiStation(
      code: 'TNA',
      name: 'Thane',
      lat: 19.18616,
      lng: 72.97619,
      line: TrainLine.central,
      isJunction: true,
    ),
    MumbaiStation(
      code: 'DI',
      name: 'Dombivli',
      lat: 19.21812,
      lng: 73.08689,
      line: TrainLine.central,
    ),
    MumbaiStation(
      code: 'KYN',
      name: 'Kalyan',
      lat: 19.23544,
      lng: 73.13110,
      line: TrainLine.central,
      isJunction: true,
    ),
    MumbaiStation(
      code: 'BUD',
      name: 'Badlapur',
      lat: 19.16679,
      lng: 73.23874,
      line: TrainLine.central,
    ),
    MumbaiStation(
      code: 'KSRA',
      name: 'Kasara',
      lat: 19.64830,
      lng: 73.47306,
      line: TrainLine.central,
      isJunction: true,
    ),
  ];

  // ---------------------------------------------------------------------------
  // Harbour Line — CSMT to Panvel (South → East)
  // ---------------------------------------------------------------------------
  static const List<MumbaiStation> _harbourStations = [
    MumbaiStation(
      code: 'CSMT',
      name: 'Chhatrapati Shivaji Maharaj Terminus',
      lat: 18.94087,
      lng: 72.83606,
      line: TrainLine.harbour,
      isJunction: true,
    ),
    MumbaiStation(
      code: 'VDLR',
      name: 'Wadala Road',
      lat: 19.01599,
      lng: 72.85889,
      line: TrainLine.harbour,
    ),
    MumbaiStation(
      code: 'GTBN',
      name: 'GTB Nagar',
      lat: 19.03781,
      lng: 72.86407,
      line: TrainLine.harbour,
    ),
    MumbaiStation(
      code: 'CHF',
      name: 'Chunabhatti',
      lat: 19.05155,
      lng: 72.86899,
      line: TrainLine.harbour,
    ),
    MumbaiStation(
      code: 'CLA',
      name: 'Kurla',
      lat: 19.06515,
      lng: 72.87940,
      line: TrainLine.harbour,
      isJunction: true,
    ),
    MumbaiStation(
      code: 'CMBR',
      name: 'Chembur',
      lat: 19.06266,
      lng: 72.90125,
      line: TrainLine.harbour,
    ),
    MumbaiStation(
      code: 'MNKD',
      name: 'Mankhurd',
      lat: 19.04681,
      lng: 72.93217,
      line: TrainLine.harbour,
    ),
    MumbaiStation(
      code: 'VSH',
      name: 'Vashi',
      lat: 19.06319,
      lng: 72.99885,
      line: TrainLine.harbour,
      isJunction: true,
    ),
    MumbaiStation(
      code: 'NEU',
      name: 'Nerul',
      lat: 19.03314,
      lng: 73.01818,
      line: TrainLine.harbour,
    ),
    MumbaiStation(
      code: 'BEPR',
      name: 'Belapur CBD',
      lat: 19.01907,
      lng: 73.03917,
      line: TrainLine.harbour,
    ),
    MumbaiStation(
      code: 'KHAG',
      name: 'Kharghar',
      lat: 19.02614,
      lng: 73.05956,
      line: TrainLine.harbour,
    ),
    MumbaiStation(
      code: 'PNVL',
      name: 'Panvel',
      lat: 18.99063,
      lng: 73.12033,
      line: TrainLine.harbour,
      isJunction: true,
    ),
  ];

  /// All stations across all three lines.
  static List<MumbaiStation> get allStations => [
        ..._westernStations,
        ..._centralStations,
        ..._harbourStations,
      ];

  /// Returns stations for a specific line, in route order.
  static List<MumbaiStation> getStationsByLine(TrainLine line) {
    switch (line) {
      case TrainLine.western:
        return _westernStations;
      case TrainLine.central:
        return _centralStations;
      case TrainLine.harbour:
        return _harbourStations;
    }
  }

  static const Map<String, String> _stationCodeNames = {
    // Western Line
    'CCG': 'Churchgate',
    'MEL': 'Marine Lines',
    'CYR': 'Charni Road',
    'GTR': 'Grant Road',
    'BCL': 'Mumbai Central',
    'MX': 'Mahalakshmi',
    'PL': 'Lower Parel',
    'EPR': 'Prabhadevi',
    'DDR': 'Dadar',
    'MRU': 'Matunga Road',
    'MM': 'Mahim',
    'BA': 'Bandra',
    'KHAR': 'Khar Road',
    'STC': 'Santa Cruz',
    'VLP': 'Vile Parle',
    'ADH': 'Andheri',
    'JOS': 'Jogeshwari',
    'RMAR': 'Ram Mandir',
    'GMN': 'Goregaon',
    'MDD': 'Malad',
    'KILE': 'Kandivali',
    'BVI': 'Borivali',
    'DIC': 'Dahisar',
    'MIRA': 'Mira Road',
    'BYR': 'Bhayandar',
    'NIG': 'Naigaon',
    'BSR': 'Vasai Road',
    'NSP': 'Nallasopara',
    'VR': 'Virar',
    'VTN': 'Vaitarna',
    'SAH': 'Saphale',
    'KLV': 'Kelve Road',
    'PLG': 'Palghar',
    'UOI': 'Umroli',
    'BOR': 'Boisar',
    'VGN': 'Vangaon',
    'DRD': 'Dahanu Road',

    // Central Line
    'CSMT': 'Chhatrapati Shivaji Maharaj Terminus',
    'CSTM': 'Chhatrapati Shivaji Maharaj Terminus',
    'VT': 'Chhatrapati Shivaji Maharaj Terminus',
    'MSD': 'Masjid',
    'SNRD': 'Sandhurst Road',
    'BY': 'Byculla',
    'CHG': 'Chinchpokli',
    'CRD': 'Currey Road',
    'PR': 'Parel',
    'DR': 'Dadar',
    'MTN': 'Matunga',
    'SIN': 'Sion',
    'CLA': 'Kurla',
    'VVH': 'Vidyavihar',
    'GC': 'Ghatkopar',
    'VK': 'Vikhroli',
    'KJRD': 'Kanjurmarg',
    'BND': 'Bhandup',
    'NHU': 'Nahur',
    'MLND': 'Mulund',
    'TNA': 'Thane',
    'KLVA': 'Kalwa',
    'MBQ': 'Mumbra',
    'DIVA': 'Diva',
    'KOPR': 'Kopar',
    'DI': 'Dombivli',
    'THK': 'Thakurli',
    'KYN': 'Kalyan',
    'VLDI': 'Vithalwadi',
    'ULNR': 'Ulhasnagar',
    'ABH': 'Ambernath',
    'BUD': 'Badlapur',
    'VGI': 'Vangani',
    'SHLU': 'Shelu',
    'NRL': 'Neral',
    'BVS': 'Bhivpuri Road',
    'KJT': 'Karjat',
    'PDI': 'Palasdhari',
    'KHS': 'Khopoli',
    'LWJ': 'Lowjee',
    'DLV': 'Dolavali',
    'KAV': 'Kelavli',
    'KHPI': 'Khopoli',
    
    // Central Line North-East branch
    'SHAD': 'Shahad',
    'ABY': 'Ambivli',
    'TLA': 'Titwala',
    'KDV': 'Khadavli',
    'VSD': 'Vasind',
    'ASO': 'Asangaon',
    'ATG': 'Atgaon',
    'THS': 'Thansit',
    'KEB': 'Khardi',
    'OMB': 'Oombermali',
    'KSRA': 'Kasara',

    // Harbour Line
    'VDLR': 'Wadala Road',
    'GTBN': 'Guru Tegh Bahadur Nagar',
    'CHF': 'Chunabhatti',
    'CMBR': 'Chembur',
    'GV': 'Govandi',
    'MNKD': 'Mankhurd',
    'VSH': 'Vashi',
    'SNCR': 'Sanpada',
    'JNJ': 'Juinagar',
    'NEU': 'Nerul',
    'SWDV': 'Seawoods-Darave',
    'BEPR': 'Belapur CBD',
    'CBDS': 'Belapur CBD',
    'KHAG': 'Kharghar',
    'MANR': 'Mansarovar',
    'KNDS': 'Khandeshwar',
    'PNVL': 'Panvel',
    
    // Harbour Line (CSMT to Andheri branch)
    'DKRD': 'Dockyard Road',
    'RRD': 'Reay Road',
    'CTGN': 'Cotton Green',
    'SVE': 'Sewri',
    
    // Trans-Harbour Line
    'AIRL': 'Airoli',
    'RABE': 'Rabale',
    'GNSL': 'Ghansoli',
    'KKR': 'Koparkhairane',
    'TUH': 'Turbhe',
    
    // Uran Line
    'THMR': 'Targhar',
    'BMDR': 'BamanDongri',
    'KHAGR': 'KharKopar',
    'GAVN': 'Gavhan',
    'RJGN': 'Ranjanpada',
    'NHVP': 'Nhava Sheva',
    'DRWN': 'Dronagiri',
    'URAN': 'Uran',

    // Lonavala/Pune branch
    'LNL': 'Lonavala',
    'PUNE': 'Pune Junction',
    'SVJR': 'Shivajinagar',
    'KK': 'Khadki',
    'PMP': 'Pimpri',
    'CCH': 'Chinchwad',
    'AKRD': 'Akurdi',
    'DEHR': 'Dehu Road',
    'BGWI': 'Begdewadi',
    'GRWD': 'Ghorawadi',
    'TGN': 'Talegaon',
    'VDN': 'Vadgaon',
    'KMST': 'Kamshet',
    'MVL': 'Malavli',
  };

  /// Resolves a station code to its name, falling back to the code if not found.
  static String getStationNameByCode(String code) {
    final cleanCode = code.trim().toUpperCase();
    if (_stationCodeNames.containsKey(cleanCode)) {
      return _stationCodeNames[cleanCode]!;
    }
    
    for (final station in allStations) {
      if (station.code.toUpperCase() == cleanCode) {
        return station.name;
      }
    }
    return code;
  }

  /// Returns the nearest [limit] stations to the given coordinates,
  /// sorted by distance (closest first).
  ///
  /// Each entry is a record of (station, distanceInMeters).
  static List<({MumbaiStation station, double distanceMeters})>
      findNearbyStations(
    double lat,
    double lng, {
    int limit = 8,
  }) {
    // Deduplicate stations that appear on multiple lines (e.g. CSTM, Kurla).
    // Keep the first occurrence for distance calculation.
    final Map<String, MumbaiStation> uniqueByCode = {};
    for (final station in allStations) {
      uniqueByCode.putIfAbsent(station.code, () => station);
    }

    final List<({MumbaiStation station, double distanceMeters})> withDistance =
        uniqueByCode.values
            .map((s) => (station: s, distanceMeters: s.distanceTo(lat, lng)))
            .toList();

    withDistance.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));

    return withDistance.take(limit).toList();
  }

  /// Returns all [TrainLine] values that serve a given station code.
  /// Useful for showing multiple line badges on shared stations (e.g. Dadar).
  static List<TrainLine> getLinesForStation(String code) {
    final Set<TrainLine> lines = {};
    for (final station in allStations) {
      if (station.code == code) {
        lines.add(station.line);
      }
    }
    return lines.toList();
  }

  /// Formats a distance in meters to a human-readable string.
  /// e.g. 350.0 → "350m", 1500.0 → "1.5 km"
  static String formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.round()}m';
    } else {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }
  }
}
