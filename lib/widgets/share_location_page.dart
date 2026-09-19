import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/chat_payloads.dart';
import '../services/location_places_service.dart';
import 'sharing_ui.dart';
import 'location_map.dart';

class ShareLocationPage extends StatefulWidget {
  const ShareLocationPage({super.key, required this.latitude, required this.longitude});
  final double latitude, longitude;
  @override
  State<ShareLocationPage> createState() => _ShareLocationPageState();
}
class _ShareLocationPageState extends State<ShareLocationPage> {
  final _search = TextEditingController();
  late LocationPayload _selected;
  late double _latitude, _longitude;
  List<LocationPayload> _places = [];
  bool _loading = false, _locating = false, _searchResults = false;
  String? _error;
  int _request = 0;
  @override
  void initState() { super.initState(); _latitude = widget.latitude; _longitude = widget.longitude; _selected = _current; _find(); }
  LocationPayload get _current => LocationPayload(latitude: _latitude, longitude: _longitude, name: 'Current location');
  @override
  void dispose() { _search.dispose(); super.dispose(); }
  Future<void> _find() async {
    if (_loading) return;
    final request = ++_request; final query = _search.text.trim();
    setState(() { _loading = true; _error = null; _searchResults = query.isNotEmpty; });
    try {
      final places = query.isEmpty ? await LocationPlacesService.nearby(_latitude, _longitude) : await LocationPlacesService.search(query, _latitude, _longitude);
      places.sort((a,b) => Geolocator.distanceBetween(_latitude, _longitude, a.latitude, a.longitude).compareTo(Geolocator.distanceBetween(_latitude, _longitude, b.latitude, b.longitude)));
      if (mounted && request == _request) setState(() => _places = places);
    } catch (_) { if (mounted && request == _request) setState(() { _places = []; _error = 'Could not load places. Check your connection and try again.'; }); }
    finally { if (mounted && request == _request) setState(() => _loading = false); }
  }
  Future<void> _locate() async {
    if (_locating || _loading) return;
    setState(() => _locating = true);
    try {
      final p = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)));
      if (!mounted) return;
      setState(() { _latitude = p.latitude; _longitude = p.longitude; _selected = _current; });
      _search.clear(); await _find();
    } catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not refresh location. Check GPS and permissions.'))); }
    finally { if (mounted) setState(() => _locating = false); }
  }
  @override
  Widget build(BuildContext context) {
    final c = SharingColors(context);
    return SharingPage(title: 'Send location', subtitle: 'Share a place', action: 'Send this location', onAction: () => Navigator.pop(context, _selected),
      child: ListView(padding: const EdgeInsets.all(22), children: [
        TextField(controller: _search, style: c.text(12), textInputAction: TextInputAction.search, onSubmitted: (_) => _find(),
          decoration: c.field('Search a place or address').copyWith(prefixIcon: Icon(Icons.search, size: 18, color: c.muted), suffixIcon: IconButton(tooltip: 'Search places', icon: Icon(Icons.arrow_forward, size: 18, color: c.blue), onPressed: _loading ? null : _find))),
        const SizedBox(height: 18), LocationMap(latitude: _selected.latitude, longitude: _selected.longitude, onPick: (lat, lon) => setState(() => _selected = LocationPayload(latitude: lat, longitude: lon, name: 'Dropped pin'))),
        const SizedBox(height: 6), Text('Tap the map to select a place.', style: c.text(10, secondary: true)),
        TextButton.icon(onPressed: _locating || _loading ? null : _locate, style: TextButton.styleFrom(foregroundColor: c.blue, alignment: Alignment.centerLeft), icon: const Icon(Icons.my_location, size: 18), label: Text(_locating ? 'Finding current location…' : 'Use current location', style: c.text(12).copyWith(color: c.blue))),
        Divider(color: c.line), const SizedBox(height: 10), Text(_searchResults ? 'SEARCH RESULTS' : 'NEARBY PLACES', style: c.text(10, secondary: true)),
        if (_loading) Padding(padding: const EdgeInsets.all(24), child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: c.blue, strokeWidth: 2))))
        else if (_error != null) TextButton(onPressed: _find, child: Text(_error!, style: c.text(11)))
        else if (_places.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Text('No places found. Search another address or select a point on the map.', style: c.text(12, secondary: true)))
        else for (final place in _places) Builder(builder: (_) {
          final distance = Geolocator.distanceBetween(_latitude, _longitude, place.latitude, place.longitude);
          final selected = place.latitude == _selected.latitude && place.longitude == _selected.longitude;
          return InkWell(onTap: () => setState(() => _selected = place), child: Container(padding: const EdgeInsets.symmetric(vertical: 13), decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))), child: Row(children: [
            Container(width: 35, height: 35, decoration: BoxDecoration(color: c.soft, borderRadius: BorderRadius.circular(11)), child: const Icon(Icons.location_on_outlined, color: Color(0xFF359B68), size: 18)), const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(place.name ?? 'Location', style: c.text(12)), Text('${place.address?.isNotEmpty == true ? '${place.address} · ' : ''}${distance < 1000 ? '${distance.round()} m' : '${(distance / 1000).toStringAsFixed(1)} km'} away', maxLines: 2, overflow: TextOverflow.ellipsis, style: c.text(10, secondary: true))])), const SizedBox(width: 8), Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, size: 17, color: selected ? c.blue : c.muted),
          ])));
        }),
        const SizedBox(height: 16), Text('Selected: ${_selected.name ?? 'Location'}', style: c.text(11)),
        Text('${_selected.latitude.toStringAsFixed(5)}, ${_selected.longitude.toStringAsFixed(5)}', style: c.text(10, secondary: true)),
        const SizedBox(height: 10), Text('Map and place searches use OpenStreetMap services.', style: c.text(9, secondary: true)),
      ]));
  }
}
