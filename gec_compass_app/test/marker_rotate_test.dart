import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/material.dart';

void main() {
  test('Marker and MarkerLayer rotate property check', () {
    final m1 = Marker(
      point: const LatLng(10.0, 76.0),
      child: const Text('Test'),
      rotate: true,
    );
    expect(m1.rotate, isTrue);

    final ml = MarkerLayer(
      rotate: true,
      markers: [m1],
    );
    expect(ml.rotate, isTrue);
  });
}
