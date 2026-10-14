class LocationDisplay {
  static String smartLocation({
    String? address,
    String? neighborhood,
    String? city,
  }) {
    final safeNeighborhood = neighborhood?.trim() ?? '';
    final safeCity = city?.trim() ?? '';
    final safeAddress = address?.trim() ?? '';
    final addressIsCoordinates = isCoordinateText(safeAddress);

    final reference = _extractReference(
      address: safeAddress,
      neighborhood: safeNeighborhood,
      city: safeCity,
    );

    if (safeNeighborhood.isNotEmpty && reference.isNotEmpty) {
      return '$safeNeighborhood, proximo a $reference';
    }
    if (safeNeighborhood.isNotEmpty && safeCity.isNotEmpty) {
      return '$safeNeighborhood, $safeCity';
    }
    if (safeNeighborhood.isNotEmpty) return safeNeighborhood;
    if (reference.isNotEmpty) return reference;
    if (safeAddress.isNotEmpty && !addressIsCoordinates) return safeAddress;
    if (safeCity.isNotEmpty) return safeCity;
    if (addressIsCoordinates) return 'Localizacao confirmada no mapa';
    return 'Localizacao indisponivel';
  }

  static String smartDescription({
    String? description,
    int? deliveryTimeMinutes,
    String? neighborhood,
    String? city,
    String? address,
    String? userNeighborhood,
  }) {
    final trimmedDescription = description?.trim() ?? '';
    if (trimmedDescription.isNotEmpty) return trimmedDescription;

    final location = smartLocation(
      address: address,
      neighborhood: neighborhood,
      city: city,
    );
    final deliveryTime = deliveryTimeMinutes ?? 25;
    final userArea = userNeighborhood?.trim().toLowerCase() ?? '';
    final restaurantArea = neighborhood?.trim().toLowerCase() ?? '';
    final nearbyHint = userArea.isNotEmpty && userArea == restaurantArea
        ? 'no seu bairro'
        : location;

    return 'Entrega estimada em $deliveryTime min, com referencia em $nearbyHint.';
  }

  static String compactReference({
    String? address,
    String? neighborhood,
    String? city,
  }) {
    final reference = _extractReference(
      address: address?.trim() ?? '',
      neighborhood: neighborhood?.trim() ?? '',
      city: city?.trim() ?? '',
    );
    if (reference.isNotEmpty) return reference;
    return smartLocation(
      address: address,
      neighborhood: neighborhood,
      city: city,
    );
  }

  static String displayAddress({
    String? address,
    String? neighborhood,
    String? city,
    String fallback = 'Localizacao confirmada no mapa',
  }) {
    final safeAddress = address?.trim() ?? '';
    final label = smartLocation(
      address: address,
      neighborhood: neighborhood,
      city: city,
    );
    // A single latitude/longitude value is an internal fallback, not a
    // customer-facing address. Keep coordinates available to map logic but
    // never leak them into order cards or summaries.
    if (RegExp(r'^-?\d{1,3}(?:\.\d+)?$').hasMatch(safeAddress)) {
      return fallback;
    }
    if (label == 'Localizacao confirmada no mapa' && fallback.isNotEmpty) {
      return fallback;
    }
    return label;
  }

  static bool isCoordinateText(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return false;
    return RegExp(
      r'^-?\d{1,3}(?:\.\d+)?\s*,\s*-?\d{1,3}(?:\.\d+)?$',
    ).hasMatch(raw);
  }

  static String _extractReference({
    required String address,
    required String neighborhood,
    required String city,
  }) {
    if (address.isEmpty) return '';

    final parts = address
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .where((part) => !isCoordinateText(part))
        .toList();

    for (final part in parts) {
      final normalized = part.toLowerCase();
      if (normalized == neighborhood.toLowerCase()) continue;
      if (normalized == city.toLowerCase()) continue;
      if (normalized.length < 4) continue;
      return part;
    }

    return parts.isNotEmpty ? parts.first : '';
  }
}
