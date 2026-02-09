import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hlai_app/app.dart';

void main() {
  testWidgets('App builds without error', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: HLAIApp()),
    );
    expect(find.text('HLAI'), findsOneWidget);
  });
}
