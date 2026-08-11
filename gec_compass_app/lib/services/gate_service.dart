import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/gate.dart';

class GateService {
  static const _storageKey = 'user_gates';
  List<Gate> _gates = [];

  List<Gate> get currentGates => List.unmodifiable(_gates);

  Future<List<Gate>> loadGates() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_storageKey);
    if (data != null) {
      final list = json.decode(data) as List;
      _gates = list.map((e) => Gate.fromJson(e)).toList();
    }
    return _gates;
  }

  Future<void> addGate(Gate gate) async {
    _gates.add(gate);
    await _saveGates();
  }

  Future<void> _saveGates() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonData = json.encode(_gates.map((g) => g.toJson()).toList());
    await prefs.setString(_storageKey, jsonData);
  }
}
