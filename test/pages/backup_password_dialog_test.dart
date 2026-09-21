import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/l10n/app_localizations.dart';
import 'package:kira/pages/backup/backup_password_dialog.dart';

void main() {
  Future<void> openDialog(WidgetTester tester, Widget dialog) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<BackupPasswordChoice>(
                context: context,
                builder: (_) => dialog,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  List<TextField> fields(WidgetTester tester) =>
      tester.widgetList<TextField>(find.byType(TextField)).toList();

  testWidgets('every password field can be revealed', (tester) async {
    await openDialog(tester, const BackupPasswordDialog());

    expect(fields(tester).length, 2);
    expect(fields(tester).every((field) => field.obscureText), isTrue);

    await tester.tap(find.byIcon(Icons.visibility_off).first);
    await tester.pumpAndSettle();
    expect(fields(tester).first.obscureText, isFalse);
    expect(fields(tester).last.obscureText, isTrue);
  });

  testWidgets('the decrypt dialog asks for the password only', (tester) async {
    await openDialog(tester, const BackupPasswordDialog(decrypting: true));

    expect(fields(tester).length, 1);
    expect(find.text('记住密码'), findsNothing);
    expect(find.byIcon(Icons.visibility_off), findsOneWidget);
  });
}
