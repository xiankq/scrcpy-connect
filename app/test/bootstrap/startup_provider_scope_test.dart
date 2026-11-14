import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final _startupValueProvider = Provider<int>((ref) => 0);

void main() {
  testWidgets('mounts session overrides in a new scope', (tester) async {
    await tester.pumpWidget(const SizedBox());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [_startupValueProvider.overrideWithValue(1)],
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Consumer(
            builder: (context, ref, child) =>
                Text('${ref.watch(_startupValueProvider)}'),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('1'), findsOneWidget);
  });
}
