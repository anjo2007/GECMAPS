import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'sensor_service.dart';

class StorageService {
  final List<List<dynamic>> _dataRows = [];
  String? _lastSavedFile;

  StorageService() {
    _addHeader();
  }

  void _addHeader() {
    _dataRows.add([
      'timestamp',
      'lat', 'lng',
      'accelX', 'accelY', 'accelZ',
      'gyroX', 'gyroY', 'gyroZ',
      'magX', 'magY', 'magZ',
      'pressure'
    ]);
  }

  void addDataPoint(SensorDataPoint point) {
    _dataRows.add(point.toCsvRow());
  }

  void clearData() {
    _dataRows.clear();
    _addHeader();
  }

  Future<String> saveCsvFile() async {
    String csvData = const ListToCsvConverter().convert(_dataRows);
    final directory = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = '${directory.path}/sensor_log_$timestamp.csv';
    final file = File(path);
    await file.writeAsString(csvData);
    _lastSavedFile = path;
    return path;
  }

  Future<void> shareCsvFile() async {
    if (_lastSavedFile != null) {
      await Share.shareXFiles([XFile(_lastSavedFile!)], text: 'Sensor Data Log');
    }
  }
}
