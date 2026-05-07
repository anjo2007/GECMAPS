import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:environment_sensors/environment_sensors.dart';

class SensorDataPoint {
  final int timestamp;
  final double? lat;
  final double? lng;
  final double? accelX;
  final double? accelY;
  final double? accelZ;
  final double? gyroX;
  final double? gyroY;
  final double? gyroZ;
  final double? magX;
  final double? magY;
  final double? magZ;
  final double? pressure;

  SensorDataPoint({
    required this.timestamp,
    this.lat,
    this.lng,
    this.accelX,
    this.accelY,
    this.accelZ,
    this.gyroX,
    this.gyroY,
    this.gyroZ,
    this.magX,
    this.magY,
    this.magZ,
    this.pressure,
  });

  List<dynamic> toCsvRow() {
    return [
      timestamp,
      lat, lng,
      accelX, accelY, accelZ,
      gyroX, gyroY, gyroZ,
      magX, magY, magZ,
      pressure
    ];
  }
}

class SensorService {
  StreamSubscription? _accelSub;
  StreamSubscription? _gyroSub;
  StreamSubscription? _magSub;
  StreamSubscription? _pressureSub;
  StreamSubscription? _gpsSub;

  double? _lastLat;
  double? _lastLng;
  double? _lastAccelX;
  double? _lastAccelY;
  double? _lastAccelZ;
  double? _lastGyroX;
  double? _lastGyroY;
  double? _lastGyroZ;
  double? _lastMagX;
  double? _lastMagY;
  double? _lastMagZ;
  double? _lastPressure;

  Timer? _timer;
  final environmentSensors = EnvironmentSensors();

  void Function(SensorDataPoint)? onDataPointCollected;

  void startListening() async {
    // Start listening to GPS if permission granted
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    LocationPermission permission = await Geolocator.checkPermission();
    if (serviceEnabled && (permission == LocationPermission.always || permission == LocationPermission.whileInUse)) {
      _gpsSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best)
      ).listen((Position position) {
        _lastLat = position.latitude;
        _lastLng = position.longitude;
      });
    }

    // Start listening to IMU
    try {
      _accelSub = accelerometerEventStream().listen((AccelerometerEvent event) {
        _lastAccelX = event.x;
        _lastAccelY = event.y;
        _lastAccelZ = event.z;
      });
    } catch (e) {
      // Fallback for older versions of sensors_plus (if applicable)
    }

    try {
      _gyroSub = gyroscopeEventStream().listen((GyroscopeEvent event) {
        _lastGyroX = event.x;
        _lastGyroY = event.y;
        _lastGyroZ = event.z;
      });
    } catch (e) {}

    try {
      _magSub = magnetometerEventStream().listen((MagnetometerEvent event) {
        _lastMagX = event.x;
        _lastMagY = event.y;
        _lastMagZ = event.z;
      });
    } catch (e) {}

    // Barometer
    environmentSensors.getSensorAvailable(SensorType.Pressure).then((available) {
      if (available) {
        _pressureSub = environmentSensors.pressure.listen((event) {
          _lastPressure = event;
        });
      }
    });

    // Sample data at 50Hz (every 20ms)
    _timer = Timer.periodic(const Duration(milliseconds: 20), (timer) {
      final point = SensorDataPoint(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        lat: _lastLat,
        lng: _lastLng,
        accelX: _lastAccelX,
        accelY: _lastAccelY,
        accelZ: _lastAccelZ,
        gyroX: _lastGyroX,
        gyroY: _lastGyroY,
        gyroZ: _lastGyroZ,
        magX: _lastMagX,
        magY: _lastMagY,
        magZ: _lastMagZ,
        pressure: _lastPressure,
      );
      if (onDataPointCollected != null) {
        onDataPointCollected!(point);
      }
    });
  }

  void stopListening() {
    _gpsSub?.cancel();
    _accelSub?.cancel();
    _gyroSub?.cancel();
    _magSub?.cancel();
    _pressureSub?.cancel();
    _timer?.cancel();
  }
}
