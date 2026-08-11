import 'package:flutter_test/flutter_test.dart';
import 'package:sensor_logger_app/main.dart';

void main() {
  testWidgets('Sensor logger app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const SensorLoggerApp());
    expect(find.text('GEC Sensor Logger'), findsOneWidget);
  });
}
