class AddressLocation {
  final String formattedAddress;
  final double latitude;
  final double longitude;
  final String source;
  final String? placeId;
  final String? landmark;
  final bool insideServiceArea;
  final Map<String, dynamic> components;

  const AddressLocation({
    required this.formattedAddress,
    required this.latitude,
    required this.longitude,
    required this.source,
    this.placeId,
    this.landmark,
    required this.insideServiceArea,
    this.components = const {},
  });

  Map<String, dynamic> toMap() => {
    'formattedAddress': formattedAddress,
    'latitude': latitude,
    'longitude': longitude,
    'source': source,
    if (placeId != null) 'placeId': placeId,
    if (landmark != null && landmark!.trim().isNotEmpty)
      'landmark': landmark!.trim(),
    'insideServiceArea': insideServiceArea,
    if (components.isNotEmpty) 'components': components,
    'precision': source == 'manual_pin' ? 'pin' : 'geocoded',
    'verified': false,
  };
}

class AddressSuggestion {
  final String formattedAddress;
  final double latitude;
  final double longitude;
  final String? placeId;
  final Map<String, dynamic> components;

  const AddressSuggestion({
    required this.formattedAddress,
    required this.latitude,
    required this.longitude,
    this.placeId,
    this.components = const {},
  });
}
