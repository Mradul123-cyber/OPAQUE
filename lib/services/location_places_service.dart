import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/chat_payloads.dart';

class LocationPlacesService {
  static const searchBase = String.fromEnvironment('OPAQUE_PLACE_SEARCH_URL', defaultValue: 'https://nominatim.openstreetmap.org/search');
  static const nearbyBase = String.fromEnvironment('OPAQUE_NEARBY_URL', defaultValue: 'https://overpass-api.de/api/interpreter');
  static const headers = {'User-Agent': 'OpaqueMessenger/1.0 (https://github.com/Mradul123-cyber/opaque)'};
  static final _cachedAt = <String, DateTime>{};
  static List<LocationPayload>? _cached(String key) {
    final created = _cachedAt[key];
    if (created == null || DateTime.now().difference(created) > const Duration(minutes: 5)) { _cache.remove(key); _cachedAt.remove(key); return null; }
    final value = _cache[key];
    return value == null ? null : List<LocationPayload>.of(value);
  }
  static final _cache = <String, List<LocationPayload>>{};
  static Future<void> _queue = Future.value();
  static DateTime _lastRequest = DateTime(1970);
  // Searches are explicitly submitted; no autocomplete or background tracking.
  static Future<List<LocationPayload>> search(String query, double lat, double lon) async {
    final uri = Uri.parse(searchBase).replace(queryParameters: {'q': query, 'format': 'jsonv2', 'limit': '8', 'addressdetails': '1', 'viewbox': '${lon - .08},${lat + .08},${lon + .08},${lat - .08}'});
    final cached = _cached(uri.toString()); if (cached != null) return cached;
    final before = _queue;
    final work = () async {
      await before;
      final wait = 1100 - DateTime.now().difference(_lastRequest).inMilliseconds;
      if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
      _lastRequest = DateTime.now();
      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 18));
      if (response.statusCode != 200) throw Exception('Place search unavailable');
      final rows = jsonDecode(response.body) as List;
      final results = rows.map((r) => LocationPayload(latitude: double.parse(r['lat'].toString()), longitude: double.parse(r['lon'].toString()), name: (r['name'] as String?)?.isNotEmpty == true ? r['name'] as String : (r['display_name'] as String).split(',').first, address: r['display_name'] as String?)).toList();
      _remember(uri.toString(), results); return results;
    }();
    _queue = work.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return work;
  }
  static Future<List<LocationPayload>> nearby(double lat, double lon) async {
    final key = 'nearby:${lat.toStringAsFixed(3)},${lon.toStringAsFixed(3)}';
    final cached = _cached(key); if (cached != null) return cached;
    final query = '[out:json][timeout:15];(nwr(around:1500,$lat,$lon)[amenity~"cafe|restaurant|library"][name];nwr(around:1500,$lat,$lon)[leisure=park][name];);out center 25;';
    final response = await http.post(Uri.parse(nearbyBase), headers: headers, body: {'data': query}).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) throw Exception('Nearby places unavailable');
    final rows = (jsonDecode(response.body) as Map)['elements'] as List;
    final result = <LocationPayload>[];
    for (final r in rows) {
      final coords = r['center'] ?? r; final tags = r['tags'] as Map;
      if (coords['lat'] == null || coords['lon'] == null) continue;
      final address = ['addr:housenumber', 'addr:street', 'addr:city'].map((k) => tags[k]).whereType<String>().join(' ');
      result.add(LocationPayload(latitude: (coords['lat'] as num).toDouble(), longitude: (coords['lon'] as num).toDouble(), name: tags['name'] as String, address: address.isEmpty ? null : address));
    }
    _remember(key, result); return result;
  }
  static void _remember(String key, List<LocationPayload> value) { if (_cache.length >= 40) { final oldest = _cache.keys.first; _cache.remove(oldest); _cachedAt.remove(oldest); } _cache[key] = List<LocationPayload>.of(value); _cachedAt[key] = DateTime.now(); }
}
