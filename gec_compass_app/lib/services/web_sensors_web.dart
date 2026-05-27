import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:async';

Future<bool> requestWebSensorPermissions() async {
  try {
    final result = js.context.callMethod('requestIosSensorPermissions');
    return result == true;
  } catch (e) {
    return true; // Not iOS or method missing
  }
}

StreamSubscription<html.DeviceOrientationEvent>? _compassSub;

void listenToWebCompass(void Function(double) onHeading) {
  _compassSub = html.window.onDeviceOrientation.listen((event) {
    final jsEvent = js.JsObject.fromBrowserObject(event);
    final compassHeading = jsEvent['webkitCompassHeading'];
    if (compassHeading != null) {
      onHeading((compassHeading as num).toDouble());
    } else if (event.alpha != null) {
      onHeading(360 - event.alpha!.toDouble());
    }
  });
}

void stopWebCompass() {
  _compassSub?.cancel();
  _compassSub = null;
}
