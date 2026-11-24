'use strict';
// Product description / specifications / key features: one shared reading for
// the Admin Dashboard API, Excel upload and the product-information import.

/**
 * Product specifications as entered by an admin: an object, a JSON object
 * string, or one "Name: Value" per line (the Admin form). Each line becomes its
 * own entry, in order. Returns { value } or { error } (a line without a name
 * and value is reported, never merged or guessed). Blank input = {}.
 */
function parseSpecifications(input) {
  if (input === undefined || input === null) return { value: {} };
  if (typeof input === 'object') {
    if (Array.isArray(input)) return { error: 'Specifications must be "Name: Value" pairs.' };
    const value = {};
    for (const [k, v] of Object.entries(input)) {
      const key = String(k).trim();
      if (key) value[key] = String(v ?? '').trim();
    }
    return { value };
  }
  const text = String(input).trim();
  if (!text) return { value: {} };
  if (text.startsWith('{')) {
    try { return parseSpecifications(JSON.parse(text)); } catch (_) { return { error: 'Specifications are not valid JSON. Use one "Name: Value" per line.' }; }
  }
  const value = {};
  const lines = text.split(/\r?\n/).map(l => l.trim()).filter(Boolean);
  for (let i = 0; i < lines.length; i++) {
    const at = lines[i].search(/[:=\t]/);
    const key = at > 0 ? lines[i].slice(0, at).trim() : '';
    const val = at > 0 ? lines[i].slice(at + 1).trim() : '';
    if (!key || !val) return { error: `Specification line ${i + 1} ("${lines[i].slice(0, 40)}") needs a name and a value, e.g. "Voltage: 24V".` };
    value[key] = val;
  }
  return { value };
}

/** Saved specifications -> one "Name: Value" line each (what an admin edits). */
function specificationLines(specs) {
  let value = specs;
  if (typeof value === 'string') { try { value = JSON.parse(value); } catch (_) { return value; } }
  if (!value || typeof value !== 'object' || Array.isArray(value)) return '';
  return Object.entries(value).map(([k, v]) => `${k}: ${v}`).join('\n');
}

/** Key features: an array, or one feature per line (commas stay inside a feature). */
function parseFeatures(input) {
  if (Array.isArray(input)) return input.map(f => String(f).trim()).filter(Boolean);
  if (input === undefined || input === null) return [];
  return String(input).split(/\r?\n/).map(f => f.trim()).filter(Boolean);
}

module.exports = { parseSpecifications, specificationLines, parseFeatures };
