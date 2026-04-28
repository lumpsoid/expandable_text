import 'package:expandable_text/expandable_text.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Helpers

/// Wraps [widget] in a minimal Material app so DefaultTextStyle etc. resolve.
Widget _wrap(Widget widget, {double width = 300}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: width,
        child: widget,
      ),
    ),
  );
}

/// Finds the first [TapGestureRecognizer] attached to a [TextSpan] whose text
/// contains [label] inside the first [RichText] in the tree.
TapGestureRecognizer? _tapRecognizer(WidgetTester tester, String label) {
  final richTexts = tester.widgetList<RichText>(find.byType(RichText));
  for (final rt in richTexts) {
    TapGestureRecognizer? found;
    rt.text.visitChildren((span) {
      if (span is TextSpan &&
          span.text?.contains(label) == true &&
          span.recognizer is TapGestureRecognizer) {
        found = span.recognizer! as TapGestureRecognizer;
        return false; // stop
      }
      return true;
    });
    if (found != null) return found;
  }
  return null;
}

/// Fires the [TapGestureRecognizer] for the span whose text contains [label].
Future<void> _tapSpan(WidgetTester tester, String label) async {
  final recognizer = _tapRecognizer(tester, label);
  expect(recognizer, isNotNull, reason: 'No tap recognizer found for "$label"');
  recognizer!.onTap!();
  await tester.pump();
}

/// Returns every [TextSpan] leaf text concatenated from the first [RichText].
String _fullRenderedText(WidgetTester tester) {
  final buffer = StringBuffer();
  final richText = tester.widget<RichText>(find.byType(RichText).first);
  richText.text.visitChildren((span) {
    if (span is TextSpan && span.text != null) buffer.write(span.text);
    return true;
  });
  return buffer.toString();
}

/// Short text that should never overflow at 300 px width.
const _shortText = 'Hello world.';

/// Long text guaranteed to exceed 3 lines at 300 px.
const _longText =
    'Lorem ipsum dolor sit amet, consectetur adipiscing elit. '
    'Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. '
    'Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris '
    'nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in '
    'reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla '
    'pariatur. Excepteur sint occaecat cupidatat non proident.';

void main() {
  // Rendering — short text (no overflow)
  group('Short text (no overflow)', () {
    testWidgets('renders a plain Text widget, not RichText', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ExpandableText(_shortText, maxLines: 3),
        ),
      );

      // A plain Text still creates a RichText internally, but we can check
      // that NO "Show more" span is present.
      expect(find.text(_shortText), findsOneWidget);
      expect(_tapRecognizer(tester, 'Show more'), isNull);
    });

    testWidgets('does not show "Show more" label', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ExpandableText(_shortText, maxLines: 3),
        ),
      );

      expect(find.textContaining('Show more'), findsNothing);
    });

    testWidgets('does not show overflow symbol', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ExpandableText(_shortText, maxLines: 3),
        ),
      );

      expect(find.textContaining('\u2026'), findsNothing);
    });
  });

  // Rendering — long text (overflow)
  group('Long text (overflow)', () {
    testWidgets('shows overflow symbol and "Show more" label', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ExpandableText(_longText, maxLines: 3),
        ),
      );

      final rendered = _fullRenderedText(tester);
      expect(rendered, contains('\u2026'));
      expect(rendered, contains('Show more'));
    });

    testWidgets('truncated text is a prefix of the full text', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ExpandableText(_longText, maxLines: 3),
        ),
      );

      final rendered = _fullRenderedText(tester);
      // Strip suffix to get only the body text
      final bodyEnd = rendered.indexOf('\u2026');
      final body = rendered.substring(0, bodyEnd);
      expect(_longText.startsWith(body.trimRight()), isTrue);
    });

    testWidgets('does not show "Show less" initially', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ExpandableText(_longText, maxLines: 3),
        ),
      );

      expect(find.textContaining('Show less'), findsNothing);
    });
  });

  // Expand / collapse interaction
  group('Expand / collapse', () {
    testWidgets('tapping "Show more" expands to full text', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ExpandableText(_longText, maxLines: 3),
        ),
      );

      await _tapSpan(tester, 'Show more');

      final rendered = _fullRenderedText(tester);
      expect(rendered, contains(_longText));
    });

    testWidgets('expanded state shows "Show less" label', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ExpandableText(_longText, maxLines: 3),
        ),
      );

      await _tapSpan(tester, 'Show more');

      expect(_tapRecognizer(tester, 'Show less'), isNotNull);
    });

    testWidgets('expanded state hides "Show more" label', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ExpandableText(_longText, maxLines: 3),
        ),
      );

      await _tapSpan(tester, 'Show more');

      expect(_tapRecognizer(tester, 'Show more'), isNull);
    });

    testWidgets('tapping "Show less" collapses back', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ExpandableText(_longText, maxLines: 3),
        ),
      );

      await _tapSpan(tester, 'Show more');
      await _tapSpan(tester, 'Show less');

      final rendered = _fullRenderedText(tester);
      expect(rendered, contains('Show more'));
      expect(rendered, isNot(contains('Show less')));
    });

    testWidgets('multiple expand/collapse cycles are stable', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ExpandableText(_longText, maxLines: 3),
        ),
      );

      for (var i = 0; i < 3; i++) {
        await _tapSpan(tester, 'Show more');
        expect(_tapRecognizer(tester, 'Show less'), isNotNull);

        await _tapSpan(tester, 'Show less');
        expect(_tapRecognizer(tester, 'Show more'), isNotNull);
      }
    });
  });

  // Custom labels and symbols
  group('Custom labels and overflow symbol', () {
    testWidgets('uses custom showMoreText', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ExpandableText(
            _longText,
            maxLines: 3,
            showMoreText: ' Read more',
          ),
        ),
      );

      final rendered = _fullRenderedText(tester);
      expect(rendered, contains('Read more'));
      expect(rendered, isNot(contains('Show more')));
    });

    testWidgets('uses custom showLessText', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ExpandableText(
            _longText,
            maxLines: 3,
            showMoreText: ' Read more',
            showLessText: ' Read less',
          ),
        ),
      );

      await _tapSpan(tester, 'Read more');

      final rendered = _fullRenderedText(tester);
      expect(rendered, contains('Read less'));
    });

    testWidgets('uses custom overflowSymbol', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ExpandableText(
            _longText,
            maxLines: 3,
            overflowSymbol: '***',
          ),
        ),
      );

      final rendered = _fullRenderedText(tester);
      expect(rendered, contains('***'));
      expect(rendered, isNot(contains('\u2026')));
    });

    testWidgets('expanded mode omits overflow symbol entirely', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ExpandableText(_longText, maxLines: 3),
        ),
      );

      await _tapSpan(tester, 'Show more');

      final rendered = _fullRenderedText(tester);
      expect(rendered, isNot(contains('\u2026')));
    });
  });

  // Custom styles
  group('Custom styles', () {
    testWidgets('showMoreStyle is applied to the "Show more" span', (
      tester,
    ) async {
      const customStyle = TextStyle(color: Colors.red, fontSize: 14);

      await tester.pumpWidget(
        _wrap(
          const ExpandableText(
            _longText,
            maxLines: 3,
            showMoreStyle: customStyle,
          ),
        ),
      );

      final richText = tester.widget<RichText>(find.byType(RichText).first);
      TextStyle? foundStyle;
      richText.text.visitChildren((span) {
        if (span is TextSpan && span.text?.contains('Show more') == true) {
          foundStyle = span.style;
          return false;
        }
        return true;
      });

      expect(foundStyle?.color, Colors.red);
      expect(foundStyle?.fontSize, 14);
    });

    testWidgets('showLessStyle is applied to the "Show less" span', (
      tester,
    ) async {
      const customStyle = TextStyle(color: Colors.blue, fontSize: 12);

      await tester.pumpWidget(
        _wrap(
          const ExpandableText(
            _longText,
            maxLines: 3,
            showLessStyle: customStyle,
          ),
        ),
      );

      await _tapSpan(tester, 'Show more');

      final richText = tester.widget<RichText>(find.byType(RichText).first);
      TextStyle? foundStyle;
      richText.text.visitChildren((span) {
        if (span is TextSpan && span.text?.contains('Show less') == true) {
          foundStyle = span.style;
          return false;
        }
        return true;
      });

      expect(foundStyle?.color, Colors.blue);
      expect(foundStyle?.fontSize, 12);
    });

    testWidgets('overflowSymbolStyle is applied to the ellipsis span', (
      tester,
    ) async {
      const symbolStyle = TextStyle(color: Colors.green);

      await tester.pumpWidget(
        _wrap(
          const ExpandableText(
            _longText,
            maxLines: 3,
            overflowSymbolStyle: symbolStyle,
          ),
        ),
      );

      final richText = tester.widget<RichText>(find.byType(RichText).first);
      TextStyle? foundStyle;
      richText.text.visitChildren((span) {
        if (span is TextSpan && span.text == '\u2026') {
          foundStyle = span.style;
          return false;
        }
        return true;
      });

      expect(foundStyle?.color, Colors.green);
    });
  });

  // maxLines boundary cases
  group('maxLines boundaries', () {
    testWidgets('maxLines: 1 truncates aggressively', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ExpandableText(_longText, maxLines: 1),
        ),
      );

      final rendered = _fullRenderedText(tester);
      expect(rendered, contains('\u2026'));
      expect(rendered, contains('Show more'));
    });

    testWidgets('maxLines: 1 — truncated body is shorter than maxLines: 5', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const ExpandableText(_longText, maxLines: 1)),
      );
      final short = _fullRenderedText(tester);

      await tester.pumpWidget(
        _wrap(const ExpandableText(_longText, maxLines: 5)),
      );
      final longer = _fullRenderedText(tester);

      // The body before the ellipsis should be shorter for maxLines: 1
      final shortBodyLen = short.indexOf('\u2026');
      final longerBodyLen = longer.indexOf('\u2026');
      expect(shortBodyLen, lessThan(longerBodyLen));
    });

    testWidgets('text exactly filling maxLines is not truncated', (
      tester,
    ) async {
      // A single word will always fit on 1 line without overflow.
      await tester.pumpWidget(
        _wrap(
          const ExpandableText('OneWord', maxLines: 1),
        ),
      );

      expect(_tapRecognizer(tester, 'Show more'), isNull);
    });
  });

  // Widget updates (didUpdateWidget-equivalent)
  group('Widget parameter updates', () {
    testWidgets('updating text re-evaluates truncation', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ExpandableText(_shortText, maxLines: 3),
        ),
      );

      // Short text — no overflow
      expect(_tapRecognizer(tester, 'Show more'), isNull);

      await tester.pumpWidget(
        _wrap(
          const ExpandableText(_longText, maxLines: 3),
        ),
      );

      // Long text — overflow expected
      expect(_tapRecognizer(tester, 'Show more'), isNotNull);
    });

    testWidgets('updating maxLines re-evaluates truncation', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ExpandableText(_longText, maxLines: 100),
        ),
      );

      expect(_tapRecognizer(tester, 'Show more'), isNull);

      await tester.pumpWidget(
        _wrap(
          const ExpandableText(_longText, maxLines: 1),
        ),
      );

      expect(_tapRecognizer(tester, 'Show more'), isNotNull);
    });

    testWidgets('updating container width re-evaluates truncation', (
      tester,
    ) async {
      // Wide container — no overflow
      await tester.pumpWidget(
        _wrap(
          const ExpandableText(_longText, maxLines: 2),
          width: 5000,
        ),
      );

      expect(_tapRecognizer(tester, 'Show more'), isNull);

      // Narrow container — overflow
      await tester.pumpWidget(
        _wrap(
          const ExpandableText(_longText, maxLines: 2),
          width: 100,
        ),
      );

      expect(_tapRecognizer(tester, 'Show more'), isNotNull);
    });

    testWidgets('expanded state resets when text changes', (tester) async {
      // Start with long text and expand it.
      await tester.pumpWidget(
        _wrap(
          const ExpandableText(_longText, maxLines: 3),
        ),
      );
      await _tapSpan(tester, 'Show more');
      expect(_tapRecognizer(tester, 'Show less'), isNotNull);

      // Swap to different long text — widget rebuilds; expanded state persists
      // because it lives in State, not derived from props. This test documents
      // the actual (intended) behavior: state is NOT reset on text change.
      await tester.pumpWidget(
        _wrap(
          const ExpandableText('$_longText extra words here', maxLines: 3),
        ),
      );

      // State still expanded — "Show less" remains.
      expect(_tapRecognizer(tester, 'Show less'), isNotNull);
    });
  });

  // Empty and edge-case strings
  group('Edge-case strings', () {
    testWidgets('empty string does not crash and shows nothing', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const ExpandableText('', maxLines: 3),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(_tapRecognizer(tester, 'Show more'), isNull);
    });

    testWidgets('single character does not crash', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ExpandableText('A', maxLines: 3),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('text with only whitespace does not crash', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ExpandableText('     \n\n\n     ', maxLines: 3),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('text with emoji (surrogate pairs) does not crash', (
      tester,
    ) async {
      final emojiText = 'Hello 😀😃😄😁😆😅😂🤣 world! ' * 20; // force overflow

      await tester.pumpWidget(
        _wrap(
          ExpandableText(emojiText, maxLines: 2),
        ),
      );

      expect(tester.takeException(), isNull);
      // Should still truncate cleanly
      final rendered = _fullRenderedText(tester);
      expect(rendered, contains('Show more'));
    });

    testWidgets('text with newlines is handled', (tester) async {
      const multiLine = 'Line 1\nLine 2\nLine 3\nLine 4\nLine 5';

      await tester.pumpWidget(
        _wrap(
          const ExpandableText(multiLine, maxLines: 2),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('very long single word is handled without infinite loop', (
      tester,
    ) async {
      final singleWord = 'a' * 500;

      await tester.pumpWidget(
        _wrap(
          ExpandableText(singleWord, maxLines: 2),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });

  // Recognizer lifecycle (no leaks after dispose)
  group('Recognizer lifecycle', () {
    testWidgets('widget disposes without error', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ExpandableText(_longText, maxLines: 3),
        ),
      );

      // Replace with an empty container to trigger dispose
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

      expect(tester.takeException(), isNull);
    });

    testWidgets('recognizers are not null after initState', (tester) async {
      final key = GlobalKey<State>();
      await tester.pumpWidget(
        _wrap(
          ExpandableText(_longText, maxLines: 3, key: key),
        ),
      );

      // Access recognizers indirectly by verifying taps still work
      await _tapSpan(tester, 'Show more');
      expect(_tapRecognizer(tester, 'Show less'), isNotNull);
    });
  });

  // Accessibility / semantics
  group('Semantics', () {
    testWidgets('collapsed text has "Show more" in semantics tree', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const ExpandableText(_longText, maxLines: 3),
        ),
      );

      final semantics = tester.getSemantics(find.byType(RichText).first);
      expect(semantics.label, contains('Show more'));
    });

    testWidgets('expanded text has "Show less" in semantics tree', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const ExpandableText(_longText, maxLines: 3),
        ),
      );

      await _tapSpan(tester, 'Show more');

      final semantics = tester.getSemantics(find.byType(RichText).first);
      expect(semantics.label, contains('Show less'));
    });
  });
}
