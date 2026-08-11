import 'dart:async';
import 'dart:js_interop';

@JS('requestIosSensorPermissions')
external JSPromise<JSBoolean>? _requestIosSensorPermissions();

Future<bool> requestWebSensorPermissions() async {
  try {
    final promise = _requestIosSensorPermissions();
    if (promise == null) return true;
    final result = await promise.toDart;
    return result.toDart;
  } catch (e) {
    return true; // Not iOS or method missing
  }
}

// Extension type for DeviceOrientationEvent
extension type _DeviceOrientationEvent(JSObject _) implements JSObject {
  external JSNumber? get alpha;
  external JSNumber? get beta;
  external JSNumber? get gamma;
  external JSNumber? get webkitCompassHeading;
}

@JS('window.addEventListener')
external void _addEventListener(JSString type, JSFunction callback);

@JS('window.removeEventListener')
external void _removeEventListener(JSString type, JSFunction callback);

JSFunction? _compassCallback;
bool _isListening = false;

void listenToWebCompass(void Function(double) onHeading) {
  // Remove previous listener to prevent memory leaks and duplicate callbacks
  if (_isListening && _compassCallback != null) {
    _removeEventListener('deviceorientation'.toJS, _compassCallback!);
    _removeEventListener('deviceorientationabsolute'.toJS, _compassCallback!);
  }

  _compassCallback = ((JSObject event) {
    final orientEvent = _DeviceOrientationEvent(event);
    final compassHeading = orientEvent.webkitCompassHeading;
    if (compassHeading != null) {
      // iOS Safari provides webkitCompassHeading (magnetic north)
      onHeading(compassHeading.toDartDouble % 360.0);
    } else {
      final alpha = orientEvent.alpha;
      if (alpha != null) {
        // Normalize heading to [0, 360) range
        onHeading(((360.0 - alpha.toDartDouble) % 360.0 + 360.0) % 360.0);
      }
    }
  }).toJS;

  // Try absolute orientation first (Android Chrome - gives magnetic north)
  // Fall back to relative orientation if absolute is unavailable
  _addEventListener('deviceorientationabsolute'.toJS, _compassCallback!);
  _addEventListener('deviceorientation'.toJS, _compassCallback!);
  _isListening = true;
}

void stopWebCompass() {
  if (_compassCallback != null) {
    _removeEventListener('deviceorientation'.toJS, _compassCallback!);
    _removeEventListener('deviceorientationabsolute'.toJS, _compassCallback!);
    _compassCallback = null;
    _isListening = false;
  }
}
