import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moviebox_glassy/api/models.dart';
import 'package:moviebox_glassy/theme.dart';
import 'package:moviebox_glassy/widgets/app_widgets.dart';

/// Smoke test: the Material 3 theme + poster card render without errors.
/// (Full screens hit the live API, so they are covered by the parsing +
/// signing tests instead of a networked widget test.)
void main() {
  testWidgets('poster card renders title, year and rating', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: Scaffold(
          body: PosterCard(
            subject: const Subject(
              id: '1',
              title: 'Avengers: Doomsday',
              type: MediaType.movie,
              year: '2026',
              rating: '6.5',
            ),
            onTap: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Avengers: Doomsday'), findsOneWidget);
    expect(find.text('2026'), findsOneWidget);
    expect(find.text('6.5'), findsOneWidget);
  });

  testWidgets('app card renders its child', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AppCard(child: Text('material'))),
      ),
    );
    expect(find.text('material'), findsOneWidget);
  });
}
