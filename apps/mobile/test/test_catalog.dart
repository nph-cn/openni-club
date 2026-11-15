import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:openni_club/repository.dart';

/// Remote protocol tests seed their client-side catalog explicitly from the
/// same generated asset the application uses, not a second hardcoded catalog.
Future<Json> catalogService(ClubRepository repo) async {
  final catalog = jsonDecode(
    await rootBundle.loadString('assets/catalog.json', cache: false),
  );
  repo.services = (catalog['services'] as List)
      .map((v) => Json.from(v))
      .toList();
  return repo.services.first;
}
