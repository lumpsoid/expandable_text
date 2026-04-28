import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// {@template expandable_text}
/// A widget that displays expandable/collapsible text with truncation.
///
/// The text is initially truncated to fit within [maxLines] with an
/// [overflowSymbol] and a "Show more" label. When the label is tapped,
/// the text expands to show its full content and the label changes to
/// "Show less" for collapsing.
///
/// This widget uses an optimized binary search algorithm to find the
/// optimal truncation point, minimizing layout passes and object
/// allocations through text painter caching.
///
/// Example:
/// ```dart
/// ExpandableText(
///   'This is a very long text that will be truncated after 3 lines. '
///   'Tap to read more...',
///   maxLines: 3,
///   showMoreText: ' Read more',
///   showLessText: ' Read less',
/// )
/// ```
/// {@endtemplate}
class ExpandableText extends StatefulWidget {
  /// {@macro expandable_text}
  const ExpandableText(
    this.text, {
    required this.maxLines,
    super.key,
    this.style,
    this.showMoreStyle,
    this.showLessStyle,
    this.showMoreText = ' Show more',
    this.showLessText = ' Show less',
    this.overflowSymbol = '\u2026',
    this.overflowSymbolStyle,
  });

  /// The text content to display and potentially truncate.
  ///
  /// This text will be measured and truncated based on the available
  /// width and [maxLines] constraint when not expanded.
  final String text;

  /// The maximum number of lines to display before truncation occurs.
  ///
  /// Must be a positive integer (≥ 1). When the text exceeds this many
  /// lines, it will be truncated with [overflowSymbol] and the "Show more"
  /// label. In expanded mode, all lines are displayed regardless of this value.
  final int maxLines;

  /// The base text style applied to the main text content.
  ///
  /// If null, defaults to the nearest [DefaultTextStyle] in the widget tree.
  /// This style is used for measuring and rendering the text content.
  final TextStyle? style;

  /// Text style for the "Show more" tappable label.
  ///
  /// If null, defaults to the base [style]. This style does not affect the
  /// overflow symbol.
  final TextStyle? showMoreStyle;

  /// Text style for the Show less tappable label.
  ///
  /// If null, defaults to the base [style]. This style is only visible when the
  /// text is expanded.
  final TextStyle? showLessStyle;

  /// The text label shown after truncation to indicate expandability.
  ///
  /// Defaults to `' Show more'` (with leading space). This label becomes
  /// tappable when the text is truncated. The leading space ensures proper
  /// spacing between the truncated text and the label.
  final String showMoreText;

  /// The text label shown when the text is fully expanded.
  ///
  /// Defaults to `' Show less'` (with leading space). Tapping this label
  /// collapses the text back to the truncated state. The leading space
  /// ensures proper spacing between the full text and the label.
  final String showLessText;

  /// The symbol displayed at the truncation point (ellipsis).
  ///
  /// Defaults to `'\u2026'` (horizontal ellipsis). This symbol appears at the
  /// end of the truncated text before the "Show more" label. Can be customized
  /// to use different truncation indicators.
  final String overflowSymbol;

  /// Text style for the [overflowSymbol].
  ///
  /// If null, defaults to the base [style] (or [DefaultTextStyle]). This style
  /// only affects the truncation symbol, not the "Show more/less" labels.
  final TextStyle? overflowSymbolStyle;

  @override
  State<ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<ExpandableText> {
  bool _expanded = false;

  late final TapGestureRecognizer _showMoreRecognizer;
  late final TapGestureRecognizer _showLessRecognizer;

  // Cached TextPainter instances for reuse
  TextPainter? _fullTextPainter;
  TextPainter? _searchTextPainter;

  // Cached truncation results for early exit
  String? _cachedTruncatedText;
  double? _cachedMaxWidth;
  int? _cachedMaxLines;
  String? _cachedFullText;
  TextStyle? _cachedStyle;

  @override
  void initState() {
    super.initState();
    _showMoreRecognizer = TapGestureRecognizer()
      ..onTap = () => setState(() => _expanded = true);
    _showLessRecognizer = TapGestureRecognizer()
      ..onTap = () => setState(() => _expanded = false);
  }

  @override
  void dispose() {
    _showMoreRecognizer.dispose();
    _showLessRecognizer.dispose();
    _fullTextPainter?.dispose();
    _searchTextPainter?.dispose();
    super.dispose();
  }

  /// Invalidates the cache when widget parameters change.
  void _invalidateCacheIfNeeded() {
    final styleChanged = _cachedStyle != widget.style;
    final textChanged = _cachedFullText != widget.text;
    final maxLinesChanged = _cachedMaxLines != widget.maxLines;

    if (styleChanged || textChanged || maxLinesChanged) {
      _cachedTruncatedText = null;
    }
  }

  /// Returns true if the cache is valid for the current parameters.
  bool _isCacheValid(double maxWidth) {
    return _cachedMaxWidth == maxWidth &&
        _cachedFullText == widget.text &&
        _cachedMaxLines == widget.maxLines &&
        _cachedStyle == widget.style;
  }

  int _nextCharBoundary(String text, int index) {
    if (index <= 0) return 0;
    if (index >= text.length) return text.length;

    final codeUnit = text.codeUnitAt(index - 1);
    // If the previous code unit is a high surrogate, step back one
    // so we don't leave it unpaired
    if (codeUnit >= 0xD800 && codeUnit <= 0xDBFF) {
      return index - 1;
    }
    return index;
  }

  @override
  Widget build(BuildContext context) {
    final defaultStyle = widget.style ?? DefaultTextStyle.of(context).style;

    final showMoreStyle = widget.showMoreStyle ?? defaultStyle;

    final showLessStyle = widget.showLessStyle ?? defaultStyle;

    final overflowSymbolStyle = widget.overflowSymbolStyle ?? defaultStyle;

    // Expanded mode — skip LayoutBuilder and truncation entirely
    if (_expanded) {
      return Text.rich(
        TextSpan(
          children: [
            TextSpan(text: widget.text, style: defaultStyle),
            TextSpan(
              text: widget.showLessText,
              style: showLessStyle,
              recognizer: _showLessRecognizer,
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;

        // Early exit: use cached result if parameters unchanged
        _invalidateCacheIfNeeded();
        if (_isCacheValid(maxWidth) && _cachedTruncatedText != null) {
          final suffixSpan = TextSpan(
            children: [
              TextSpan(text: widget.overflowSymbol, style: overflowSymbolStyle),
              TextSpan(
                text: widget.showMoreText,
                style: showMoreStyle,
                recognizer: _showMoreRecognizer,
              ),
            ],
          );

          return Text.rich(
            TextSpan(
              children: [
                TextSpan(text: _cachedTruncatedText, style: defaultStyle),
                suffixSpan,
              ],
            ),
          );
        }

        final suffixSpan = TextSpan(
          children: [
            TextSpan(text: widget.overflowSymbol, style: overflowSymbolStyle),
            TextSpan(
              text: widget.showMoreText,
              style: showMoreStyle,
              recognizer: _showMoreRecognizer,
            ),
          ],
        );

        // Measure how much of the plain text fits within maxLines,
        // leaving room for the "Show more" suffix.
        final truncated = _truncateToFitOptimized(
          fullText: widget.text,
          textStyle: defaultStyle,
          suffixSpan: suffixSpan,
          maxLines: widget.maxLines,
          maxWidth: maxWidth,
        );

        // Cache the result for future builds
        _cachedTruncatedText = truncated;
        _cachedMaxWidth = maxWidth;
        _cachedMaxLines = widget.maxLines;
        _cachedFullText = widget.text;
        _cachedStyle = widget.style;

        // If nothing was truncated, render plain text.
        if (truncated == null) {
          return Text(widget.text, style: defaultStyle);
        }

        return Text.rich(
          TextSpan(
            children: [
              TextSpan(text: truncated, style: defaultStyle),
              suffixSpan,
            ],
          ),
        );
      },
    );
  }

  /// Returns the truncated string (without the suffix) if the full text
  /// overflows, or null if it fits within [maxLines].
  ///
  /// Uses cached TextPainter instances to minimize object allocation.
  String? _truncateToFitOptimized({
    required String fullText,
    required TextStyle textStyle,
    required TextSpan suffixSpan,
    required int maxLines,
    required double maxWidth,
  }) {
    // Reuse _fullTextPainter for initial overflow check
    _fullTextPainter ??= TextPainter(textDirection: TextDirection.ltr);

    _fullTextPainter!
      ..text = TextSpan(text: fullText, style: textStyle)
      ..maxLines = maxLines
      ..layout(maxWidth: maxWidth);

    if (!_fullTextPainter!.didExceedMaxLines) {
      return null; // No truncation needed.
    }

    // Binary search using the shared _searchTextPainter
    _searchTextPainter ??= TextPainter(textDirection: TextDirection.ltr);

    var lo = 0;
    var hi = fullText.length;

    while (lo < hi) {
      final rawMid = (lo + hi + 1) ~/ 2;
      final mid = _nextCharBoundary(fullText, rawMid);

      // Prevent infinite loop if snapping collapses mid back to lo
      if (mid == lo) {
        hi = rawMid - 1;
        continue;
      }

      final candidate = fullText.substring(0, mid);
      _searchTextPainter!.text = TextSpan(
        children: [
          TextSpan(text: candidate, style: textStyle),
          suffixSpan,
        ],
      );
      _searchTextPainter!.layout(maxWidth: maxWidth);

      final fits = !_searchTextPainter!.didExceedMaxLines;

      if (fits) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }

    // Trim trailing whitespace/newlines so the suffix sits flush.
    return fullText.substring(0, lo).trimRight();
  }
}
