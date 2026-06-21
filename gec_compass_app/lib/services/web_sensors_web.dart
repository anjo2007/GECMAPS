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

void listenToWebCompass(void Function(double) onHeading) {
  _compassCallback = ((JSObject event) {
    final orientEvent = _DeviceOrientationEvent(event);
    final compassHeading = orientEvent.webkitCompassHeading;
    if (compassHeading != null) {
      onHeading(compassHeading.toDartDouble);
    } else {
      final alpha = orientEvent.alpha;
      if (alpha != null) {
        onHeading(360 - alpha.toDartDouble);
      }
    }
  }).toJS;
  _addEventListener('deviceorientation'.toJS, _compassCallback!);
}

void stopWebCompass() {
  if (_compassCallback != null) {
    _removeEventListener('deviceorientation'.toJS, _compassCallback!);
    _compassCallback = null;
  }
}
