import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'sharing_ui.dart';

class LocationMap extends StatefulWidget {
  const LocationMap({super.key, required this.latitude, required this.longitude, this.height = 182, this.onPick});
  final double latitude, longitude, height;
  final void Function(double, double)? onPick;
  @override
  State<LocationMap> createState() => _LocationMapState();
}
class _LocationMapState extends State<LocationMap> with AutomaticKeepAliveClientMixin {
  Widget? _map;
  Brightness? _brightness;
  @override
  bool get wantKeepAlive => true;
  @override
  void didUpdateWidget(covariant LocationMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.latitude != widget.latitude || oldWidget.longitude != widget.longitude || (oldWidget.onPick == null) != (widget.onPick == null)) _map = null;
  }
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final c = SharingColors(context);
    final brightness = Theme.of(context).brightness;
    if (_brightness != brightness) { _map = null; _brightness = brightness; }
    _map ??= FlutterMap(key: ValueKey('${widget.latitude},${widget.longitude}'), options: MapOptions(
      initialCenter: LatLng(widget.latitude, widget.longitude), initialZoom: 15, minZoom: 3, maxZoom: 19,
      interactionOptions: InteractionOptions(flags: widget.onPick == null ? InteractiveFlag.none : InteractiveFlag.all),
      onTap: widget.onPick == null ? null : (_, point) => widget.onPick?.call(point.latitude, point.longitude)), children: [
      TileLayer(urlTemplate: const String.fromEnvironment('OPAQUE_MAP_TILE_URL', defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
        userAgentPackageName: 'com.zarq.messenger', maxNativeZoom: 19, panBuffer: 0, tileDisplay: const TileDisplay.instantaneous()),
      MarkerLayer(markers: [Marker(point: LatLng(widget.latitude, widget.longitude), width: 36, height: 42, child: Icon(Icons.location_on, color: c.blue, size: 36))]),
    ]);
    return SizedBox(height: widget.height, child: ClipRRect(borderRadius: BorderRadius.circular(14), child: Stack(children: [
      RepaintBoundary(child: IgnorePointer(ignoring: widget.onPick == null, child: _map!)),
      Positioned(bottom: 0, right: 0, child: Material(color: c.surface, child: InkWell(onTap: () => launchUrl(Uri.parse('https://www.openstreetmap.org/copyright'), mode: LaunchMode.externalApplication), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3), child: Text('© OpenStreetMap contributors', style: c.text(9)))))),
    ])));
  }
}
