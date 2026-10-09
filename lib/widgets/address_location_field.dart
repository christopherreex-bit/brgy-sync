import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:universal_html/html.dart' as html;

import '../models/address_location.dart';
import '../services/location_service.dart';

class AddressLocationField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final bool required;
  final String? errorText;
  final ValueChanged<String> onTextChanged;
  final ValueChanged<AddressLocation?> onLocationChanged;

  const AddressLocationField({
    super.key,
    required this.controller,
    required this.label,
    required this.required,
    required this.errorText,
    required this.onTextChanged,
    required this.onLocationChanged,
  });

  @override
  State<AddressLocationField> createState() => _AddressLocationFieldState();
}

class _AddressLocationFieldState extends State<AddressLocationField> {
  static const _tileUrl = String.fromEnvironment(
    'MAP_TILE_URL',
    defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  );
  final _locationService = LocationService();
  final _landmark = TextEditingController();
  final _houseNumber = TextEditingController();
  final _street = TextEditingController();
  final _area = TextEditingController();
  final _city = TextEditingController();
  final _postcode = TextEditingController();
  final _mapController = MapController();
  Timer? _debounce;
  List<AddressSuggestion> _suggestions = const [];
  AddressLocation? _selected;
  bool _searching = false;
  bool _locating = false;
  String? _lookupMessage;
  int _pinLookupId = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _landmark.dispose();
    _houseNumber.dispose();
    _street.dispose();
    _area.dispose();
    _city.dispose();
    _postcode.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _onAddressChanged(String value) {
    widget.onTextChanged(value);
    final selected = _selected;
    if (selected != null && value.trim() != selected.formattedAddress) {
      if (selected.source == 'manual_pin') {
        final updated = AddressLocation(
          formattedAddress: value.trim(),
          latitude: selected.latitude,
          longitude: selected.longitude,
          source: selected.source,
          placeId: selected.placeId,
          landmark: selected.landmark,
          insideServiceArea: selected.insideServiceArea,
          components: selected.components,
        );
        setState(() => _selected = updated);
        widget.onLocationChanged(updated);
      } else {
        setState(() => _selected = null);
        widget.onLocationChanged(null);
      }
    }
    _debounce?.cancel();
    if (value.trim().length < 3) {
      setState(() => _suggestions = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () => _search(value));
  }

  Future<void> _search(String value) async {
    setState(() {
      _searching = true;
      _lookupMessage = null;
    });
    try {
      final suggestions = await _locationService.autocomplete(value);
      if (!mounted || widget.controller.text.trim() != value.trim()) return;
      setState(() {
        _suggestions = suggestions;
        _searching = false;
        if (suggestions.isEmpty) {
          _lookupMessage =
              'No suggestions available. You may enter the address and place the pin manually.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _suggestions = const [];
        _searching = false;
        _lookupMessage =
            'Address suggestions are unavailable. Manual entry and pin placement still work.';
      });
    }
  }

  void _selectSuggestion(AddressSuggestion suggestion) {
    widget.controller.text = suggestion.formattedAddress;
    final inside = _locationService.isInsideServiceArea(
      suggestion.latitude,
      suggestion.longitude,
    );
    final selected = AddressLocation(
      formattedAddress: suggestion.formattedAddress,
      latitude: suggestion.latitude,
      longitude: suggestion.longitude,
      source: 'autocomplete',
      placeId: suggestion.placeId,
      landmark: _landmark.text,
      insideServiceArea: inside,
      components: suggestion.components,
    );
    setState(() {
      _selected = selected;
      _suggestions = const [];
      _lookupMessage = null;
    });
    widget.onTextChanged(suggestion.formattedAddress);
    widget.onLocationChanged(selected);
    _populateAddressDetails(suggestion.components);
    _mapController.move(LatLng(suggestion.latitude, suggestion.longitude), 17);
  }

  Future<void> _placePin(LatLng point) async {
    final lookupId = ++_pinLookupId;
    final typedAddress = widget.controller.text.trim();
    final initialSelection = AddressLocation(
      formattedAddress: typedAddress,
      latitude: point.latitude,
      longitude: point.longitude,
      source: 'manual_pin',
      landmark: _landmark.text,
      insideServiceArea: _locationService.isInsideServiceArea(
        point.latitude,
        point.longitude,
      ),
    );
    setState(() {
      _selected = initialSelection;
      _suggestions = const [];
      _lookupMessage = 'Pin saved. Looking up address details…';
    });
    widget.onLocationChanged(initialSelection);

    try {
      final reverseResult = await _locationService.reverseGeocode(
        point.latitude,
        point.longitude,
      );
      if (!mounted || lookupId != _pinLookupId) return;
      final address = reverseResult?.formattedAddress.trim().isNotEmpty == true
          ? reverseResult!.formattedAddress.trim()
          : widget.controller.text.trim();
      if (address.isNotEmpty && address != widget.controller.text) {
        widget.controller.text = address;
        widget.onTextChanged(address);
      }
      final selected = AddressLocation(
        formattedAddress: address,
        latitude: point.latitude,
        longitude: point.longitude,
        source: 'manual_pin',
        placeId: reverseResult?.placeId,
        landmark: _landmark.text,
        insideServiceArea: initialSelection.insideServiceArea,
        components: reverseResult?.components ?? const {},
      );
      setState(() {
        _selected = selected;
        _lookupMessage = address.isEmpty
            ? 'Pin saved. Enter the house number, street, and nearby area in the Address field.'
            : null;
      });
      widget.onLocationChanged(selected);
      _populateAddressDetails(reverseResult?.components ?? const {});
    } catch (_) {
      if (!mounted || lookupId != _pinLookupId) return;
      setState(() {
        _lookupMessage = typedAddress.isEmpty
            ? 'Pin saved. Address lookup is unavailable, so enter the house number, street, and nearby area.'
            : 'Pin saved. Automatic address lookup is temporarily unavailable.';
      });
    }
  }

  void _populateAddressDetails(Map<String, dynamic> components) {
    _houseNumber.text = (components['houseNumber'] ?? '').toString();
    _street.text = (components['street'] ?? '').toString();
    _area.text = (components['suburb'] ?? components['district'] ?? '')
        .toString();
    _city.text = (components['city'] ?? '').toString();
    _postcode.text = (components['postcode'] ?? '').toString();
  }

  void _updateAddressComponent(String key, String value) {
    final selected = _selected;
    if (selected == null) return;
    final components = Map<String, dynamic>.from(selected.components);
    if (value.trim().isEmpty) {
      components.remove(key);
    } else {
      components[key] = value.trim();
    }
    final updated = AddressLocation(
      formattedAddress: selected.formattedAddress,
      latitude: selected.latitude,
      longitude: selected.longitude,
      source: selected.source,
      placeId: selected.placeId,
      landmark: selected.landmark,
      insideServiceArea: selected.insideServiceArea,
      components: components,
    );
    _selected = updated;
    widget.onLocationChanged(updated);
  }

  void _updateLandmark(String value) {
    final selected = _selected;
    if (selected == null) return;
    final updated = AddressLocation(
      formattedAddress: selected.formattedAddress,
      latitude: selected.latitude,
      longitude: selected.longitude,
      source: selected.source,
      placeId: selected.placeId,
      landmark: value,
      insideServiceArea: selected.insideServiceArea,
      components: selected.components,
    );
    _selected = updated;
    widget.onLocationChanged(updated);
  }

  void _zoomBy(double difference) {
    final camera = _mapController.camera;
    _mapController.move(
      camera.center,
      (camera.zoom + difference).clamp(3.0, 19.0),
    );
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _locating = true;
      _lookupMessage = 'Waiting for location permission…';
    });
    try {
      final position = await html.window.navigator.geolocation
          .getCurrentPosition(
            enableHighAccuracy: true,
            timeout: const Duration(seconds: 15),
            maximumAge: const Duration(minutes: 1),
          );
      if (!mounted) return;
      final point = LatLng(
        (position.coords?.latitude)?.toDouble() ??
            LocationService.barangayLatitude,
        (position.coords?.longitude)?.toDouble() ??
            LocationService.barangayLongitude,
      );
      _mapController.move(point, 18);
      await _placePin(point);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _lookupMessage =
            'Location permission was denied or unavailable. Search for an address or tap the map instead.';
      });
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Widget _zoomButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Colors.white,
      elevation: 2,
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
        iconSize: 20,
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.controller,
          onChanged: _onAddressChanged,
          decoration: InputDecoration(
            labelText: '${widget.label}${widget.required ? ' *' : ''}',
            hintText: 'Start typing an address in Calzada-Tipas, Taguig',
            border: const OutlineInputBorder(),
            errorText: widget.errorText,
            suffixIcon: _searching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.location_searching),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Type at least 3 characters, then select a search result to place the pin automatically.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        if (_suggestions.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 210),
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _suggestions.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final suggestion = _suggestions[index];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.place_outlined),
                  title: Text(suggestion.formattedAddress),
                  onTap: () => _selectSuggestion(suggestion),
                );
              },
            ),
          ),
        if (_lookupMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _lookupMessage!,
              style: TextStyle(color: Colors.orange.shade800, fontSize: 12),
            ),
          ),
        if (selected != null) ...[
          const SizedBox(height: 10),
          Text(
            'Address details',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _houseNumber,
                  onChanged: (value) =>
                      _updateAddressComponent('houseNumber', value),
                  decoration: const InputDecoration(
                    labelText: 'House/Lot No.',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _street,
                  onChanged: (value) =>
                      _updateAddressComponent('street', value),
                  decoration: const InputDecoration(
                    labelText: 'Street',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _area,
                  onChanged: (value) =>
                      _updateAddressComponent('suburb', value),
                  decoration: const InputDecoration(
                    labelText: 'Barangay / Area',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _city,
                  onChanged: (value) => _updateAddressComponent('city', value),
                  decoration: const InputDecoration(
                    labelText: 'City',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 130,
                child: TextField(
                  controller: _postcode,
                  onChanged: (value) =>
                      _updateAddressComponent('postcode', value),
                  decoration: const InputDecoration(
                    labelText: 'Postal Code',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _locating ? null : _useCurrentLocation,
            icon: _locating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location, size: 18),
            label: Text(_locating ? 'Locating…' : 'Use my current location'),
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            height: 260,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: const LatLng(
                      LocationService.barangayLatitude,
                      LocationService.barangayLongitude,
                    ),
                    initialZoom: 15.5,
                    onTap: (_, point) => _placePin(point),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: _tileUrl,
                      userAgentPackageName: 'ph.gov.taguig.calzada.brgysync',
                    ),
                    CircleLayer(
                      circles: const [
                        CircleMarker(
                          point: LatLng(
                            LocationService.barangayLatitude,
                            LocationService.barangayLongitude,
                          ),
                          radius: LocationService.serviceRadiusMeters,
                          useRadiusInMeter: true,
                          color: Color(0x15112A55),
                          borderColor: Color(0x80112A55),
                          borderStrokeWidth: 2,
                        ),
                      ],
                    ),
                    if (selected != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: LatLng(
                              selected.latitude,
                              selected.longitude,
                            ),
                            width: 48,
                            height: 48,
                            child: const Icon(
                              Icons.location_pin,
                              color: Colors.red,
                              size: 44,
                            ),
                          ),
                        ],
                      ),
                    const RichAttributionWidget(
                      attributions: [
                        TextSourceAttribution('© OpenStreetMap contributors'),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: Column(
                    children: [
                      _zoomButton(
                        icon: Icons.add,
                        tooltip: 'Zoom in',
                        onPressed: () => _zoomBy(1),
                      ),
                      const SizedBox(height: 6),
                      _zoomButton(
                        icon: Icons.remove,
                        tooltip: 'Zoom out',
                        onPressed: () => _zoomBy(-1),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _landmark,
          onChanged: _updateLandmark,
          decoration: const InputDecoration(
            labelText: 'Nearby landmark (optional)',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.flag_outlined),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(
              selected == null
                  ? Icons.touch_app_outlined
                  : selected.insideServiceArea
                  ? Icons.check_circle
                  : Icons.warning_amber,
              size: 18,
              color: selected == null
                  ? Colors.grey
                  : selected.insideServiceArea
                  ? Colors.green
                  : Colors.orange,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                selected == null
                    ? 'Select a suggestion or tap the map to confirm the location.'
                    : selected.insideServiceArea
                    ? 'Location is within the configured Calzada-Tipas service area.'
                    : 'Location appears outside the configured service area. Staff should verify it.',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
