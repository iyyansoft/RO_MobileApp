'use strict';
// Share-text cleanup for the public share page: the same rules as the app
// (share_text_rules.json), so every share method removes supplier/distributor
// references the same way. Only the shared text is cleaned; saved product
// data is never changed.
const { rules, leftover } = require('./share_text_rules.json');

const compiled = rules.map(([pattern, replacement]) => [new RegExp(pattern, 'gi'), replacement]);
const leftoverRe = new RegExp(leftover, 'i');
const leftoverWordRe = new RegExp(`\\s*(?:the |a |an )?${leftover}`, 'gi');

// Spaces and punctuation left behind by a removal.
function tidy(text) {
  return text
    .replace(/\(\s*\)/g, '')
    .replace(/[ \t]{2,}/g, ' ')
    .replace(/[ \t]+([.,;:!?])/g, '$1')
    .replace(/([,;:])(?=[.!?])/g, '')
    .replace(/([.!?])\1+/g, '$1')
    .replace(/^[\s,;:.]+/, '')
    .replace(/[ \t]+$/gm, '')
    .trim();
}

const capitalise = s => (s ? s[0].toUpperCase() + s.slice(1) : s);

function cleanPiece(piece) {
  let out = piece;
  for (const [re, replacement] of compiled) out = out.replace(re, replacement);
  out = tidy(out);
  if (out !== tidy(piece)) out = capitalise(out);
  return out;
}

/// One line or short item (specification value, feature, name): references
/// removed; a leftover word is dropped rather than the whole item.
function cleanShareItem(text) {
  let out = cleanPiece(String(text || ''));
  if (leftoverRe.test(out)) out = capitalise(tidy(out.replace(leftoverWordRe, '')));
  return out;
}

/// Prose (description): cleaned sentence by sentence; a sentence that still
/// names a supplier/distributor after the rules is left out.
function cleanShareText(text) {
  const source = String(text || '');
  return source
    .split(/\n/)
    .map(line => line
      .split(/(?<=[.!?])\s+(?=[A-Z0-9'"])/)
      .map(cleanPiece)
      .filter(sentence => sentence && !leftoverRe.test(sentence))
      .join(' '))
    .join('\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

module.exports = { cleanShareText, cleanShareItem };
