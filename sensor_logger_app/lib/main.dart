import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensor_logger_app/services/sensor_service.dart';
import 'package:sensor_logger_app/services/storage_service.dart';

void main() {
  runApp(const SensorLoggerApp());
}

class SensorLoggerApp extends StatelessWidget {
  const SensorLoggerApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GEC Sensor Logger',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const LoggerHomepage(),
    );
  }
}

class LoggerHomepage extends StatefulWidget {
  const LoggerHomepage({Key? key}) : super(key: key);

  @override
  State<LoggerHomepage> createState() => _LoggerHomepageState();
}

class _LoggerHomepageState extends State<LoggerHomepage> {
  final SensorService _sensorService = SensorService();
  final StorageService _storageService = StorageService();
  
  bool _isRecording = false;
  int _recordedDataPoints = 0;
  String _statusMessage = 'Ready to record';

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _sensorService.onDataPointCollected = (data) {
      if (_isRecording) {
        _storageService.addDataPoint(data);
        if (mounted) {
          setState(() {
            _recordedDataPoints++;
          });
        }
      }
    };
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.locationWhenInUse,
      Permission.storage, // For saving CSV on older Android devices
    ].request();
  }

  void _toggleRecording() async {
    if (_isRecording) {
      // Stop recording
      _sensorService.stopListening();
      final filePath = await _storageService.saveCsvFile();
      if (mounted) {
        setState(() {
          _isRecording = false;
          _statusMessage = 'Saved to: $filePath';
        });
      }
      _storageService.shareCsvFile();
    } else {
      // Start recording
      _storageService.clearData();
      setState(() {
        _recordedDataPoints = 0;
        _isRecording = true;
        _statusMessage = 'Recording...';
      });
      _sensorService.startListening();
    }
  }

  @override
  void dispose() {
    _sensorService.stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GEC Sensor Logger'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              _statusMessage,
              style: const TextStyle(fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Text(
              '$_recordedDataPoints',
              style: const TextStyle(fontSize: 64, fontWeight: FontWeight.bold),
            ),
            const Text('Data Points Collected'),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: _toggleRecording,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isRecording ? Colors.red : Colors.green,
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
              ),
              child: Text(
                _isRecording ? 'Stop Recording' : 'Start Recording',
                style: const TextStyle(fontSize: 20, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
