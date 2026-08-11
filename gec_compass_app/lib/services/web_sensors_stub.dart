// Stub for non-web platforms

Future<bool> requestWebSensorPermissions() async => true;

void listenToWebCompass(void Function(double) onHeading) {}

void stopWebCompass() {}
