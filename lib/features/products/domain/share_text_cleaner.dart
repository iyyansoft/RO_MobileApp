/// Share-text cleanup: removes supplier/distributor references from shared
/// product content (WhatsApp/native share, copy, fallback dialogs, the share
/// card). Only the shared text is cleaned; the saved product data is never
/// changed. The public share page uses the same rules from
/// `share_text_rules.json` (server `share_text.js`);
/// `test/share_text_cleaner_test.dart` fails if the two copies differ.
library;

/// (pattern, replacement) pairs, applied in order, case-insensitive. `$1`
/// in a replacement is the first group. Keep identical to
/// `share_text_rules.json`.
const shareTextRules = <(String, String)>[
  (
    r"\s*\([^()]*\b(?:suppliers?|supplier's|distributors?|distributor's|price list)\b[^()]*\)",
    '',
  ),
  (
    r'\b(?:the )?(?:suppliers?|distributors?) describes? (?:the |this )?(.+?) as ',
    r'The $1 is ',
  ),
  (
    r'\bthe (?:suppliers?|distributors?) lists? (?:this model|this product|it) as ',
    'This model is ',
  ),
  (r'\bthe (?:suppliers?|distributors?) lists? (an? )', r'It comes with $1'),
  (
    r"\bthe (?:suppliers?|distributors?)(?:'s)? photo shows (the |an? )?",
    r'This is $1',
  ),
  (r'\s+offered by the (?:suppliers?|distributors?)\b', ''),
  (r'\s+by the (?:suppliers?|distributors?)\b', ''),
  (
    r"\s+(?:in|from|of) the (?:suppliers?|distributors?)(?:'s?)? (?:photo|range|price list|catalogue|catalog|list)\b",
    '',
  ),
  (
    r"\b(?:suppliers?|distributors?)(?:'s)? (catalogue|catalog|photo|range|price list)\b",
    r'$1',
  ),
];

/// A supplier/distributor word still present after the rules.
const shareTextLeftover =
    r"\b(?:suppliers?|supplier's|distributors?|distributor's)\b";

final _rules = [
  for (final (pattern, replacement) in shareTextRules)
    (RegExp(pattern, caseSensitive: false), replacement),
];
final _leftover = RegExp(shareTextLeftover, caseSensitive: false);
final _leftoverWord = RegExp(
  r'\s*(?:the |a |an )?' + shareTextLeftover,
  caseSensitive: false,
);

String _apply(String text, RegExp re, String replacement) =>
    text.replaceAllMapped(
      re,
      (m) => replacement.replaceAllMapped(
        RegExp(r'\$(\d)'),
        (g) => m.group(int.parse(g.group(1)!)) ?? '',
      ),
    );

/// Spaces and punctuation left behind by a removal.
String _tidy(String text) => text
    .replaceAll(RegExp(r'\(\s*\)'), '')
    .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
    .replaceAllMapped(RegExp(r'[ \t]+([.,;:!?])'), (m) => m.group(1)!)
    .replaceAll(RegExp(r'([,;:])(?=[.!?])'), '')
    .replaceAllMapped(RegExp(r'([.!?])\1+'), (m) => m.group(1)!)
    .replaceAll(RegExp(r'^[\s,;:.]+'), '')
    .replaceAll(RegExp(r'[ \t]+$', multiLine: true), '')
    .trim();

String _capitalise(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String _cleanPiece(String piece) {
  var out = piece;
  for (final (re, replacement) in _rules) {
    out = _apply(out, re, replacement);
  }
  out = _tidy(out);
  if (out != _tidy(piece)) out = _capitalise(out);
  return out;
}

/// One line or short item (specification value, feature, name): references
/// removed; a leftover word is dropped rather than the whole item.
String cleanShareItem(String text) {
  var out = _cleanPiece(text);
  if (_leftover.hasMatch(out)) {
    out = _capitalise(_tidy(out.replaceAll(_leftoverWord, '')));
  }
  return out;
}

/// Prose (description): cleaned sentence by sentence; a sentence that still
/// names a supplier/distributor after the rules is left out.
String cleanShareText(String text) => text
    .split('\n')
    .map(
      (line) => line
          .split(RegExp(r'''(?<=[.!?])\s+(?=[A-Z0-9'"])'''))
          .map(_cleanPiece)
          .where((s) => s.isNotEmpty && !_leftover.hasMatch(s))
          .join(' '),
    )
    .join('\n')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .trim();
