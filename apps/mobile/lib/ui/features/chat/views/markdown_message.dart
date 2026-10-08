import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:markdown/markdown.dart' as md;

import '../../../core/atl_theme.dart';

/// Renders an assistant reply written in Markdown (headings, lists, emphasis,
/// inline code, and fenced code blocks) using the app's typefaces.
///
/// We convert Markdown → HTML with the pure-Dart `markdown` package and hand it
/// to [HtmlWidget] — the same renderer the email detail screen already uses — so
/// there's one styling path for rich content instead of a second bespoke parser.
/// Streaming replies keep their fast plain-text path in the caller; this is used
/// once the message is complete.
class MarkdownMessage extends StatelessWidget {
  const MarkdownMessage(this.source, {super.key});

  final String source;

  @override
  Widget build(BuildContext context) {
    final atl = context.atl;
    final html = md.markdownToHtml(
      source,
      extensionSet: md.ExtensionSet.gitHubFlavored,
    );
    return HtmlWidget(
      html,
      textStyle: atlSans(size: 15, color: atl.text, height: 1.5),
      customStylesBuilder: (element) {
        switch (element.localName) {
          case 'code':
          case 'pre':
            return {
              'background-color': _hex(atl.surface2),
              'border-radius': '6px',
              'font-family': 'monospace',
              'font-size': '13px',
            };
          case 'a':
            return {'color': _hex(atl.accent), 'text-decoration': 'none'};
          case 'h1':
          case 'h2':
          case 'h3':
            return {'font-weight': '600'};
          default:
            return null;
        }
      },
    );
  }

  /// `flutter_widget_from_html` expects CSS colour strings, so serialise the
  /// theme colour to `#rrggbb`.
  static String _hex(Color c) {
    final v = c.toARGB32() & 0xFFFFFF;
    return '#${v.toRadixString(16).padLeft(6, '0')}';
  }
}
