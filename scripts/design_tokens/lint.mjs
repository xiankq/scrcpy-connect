import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { DEFAULT_RULES, lint } from '@google/design.md/linter';

const standardProperties = new Set([
  'backgroundColor', 'textColor', 'typography', 'rounded', 'padding', 'size', 'height', 'width',
]);
const extensions = new Map([
  ...['maxWidth', 'blur', 'shadowBlur', 'refractionWidth', 'opticalDepth', 'gap',
    'verticalPadding', 'specularThickness', 'glowThickness'].map(name => [name, { type: 'dimension', min: 0 }]),
  ['shadowOffset', { type: 'dimension' }],
  ['borderColor', { type: 'color' }],
  ...['opacity', 'stretch', 'specularSharpness', 'specularSpread', 'specularIntensity',
    'specularOppositeIntensity', 'glowSpread', 'glowIntensity', 'glowOppositeIntensity']
    .map(name => [name, { type: 'number', min: 0, max: 1 }]),
  ...['angle', 'glowAngle'].map(name => [name, { type: 'number' }]),
  ...['dispersion', 'saturation'].map(name => [name, { type: 'number', min: 0 }]),
  ...['scale', 'magnification'].map(name => [name, { type: 'number', min: Number.MIN_VALUE }]),
  ['refractionIndex', { type: 'number', min: 1 }],
]);

function validateExtension(value, spec) {
  if (spec.type === 'color') return value?.type === 'color';
  const number = spec.type === 'dimension' ? value?.value : value;
  return (spec.type !== 'dimension' || (value?.type === 'dimension' && value.unit === 'px'))
    && Number.isFinite(number) && number >= (spec.min ?? -Infinity) && number <= (spec.max ?? Infinity);
}

function componentRules(state) {
  const findings = [];
  for (const [name, component] of state.components) {
    for (const [property, value] of component.properties) {
      if (standardProperties.has(property)) continue;
      const path = `components.${name}.${property}`;
      const spec = extensions.get(property);
      if (!spec) {
        findings.push({ severity: 'error', rule: 'project-component', path, message: `Unsupported component property: ${path}` });
      } else if (!validateExtension(value, spec)) {
        const unit = spec.type === 'dimension' ? ' in px' : '';
        findings.push({ severity: 'error', rule: 'project-component', path,
          message: `Invalid project extension ${path}: expected ${spec.type}${unit}, range ${spec.min ?? '-Infinity'}..${spec.max ?? 'Infinity'}` });
      }
    }
  }
  return findings;
}

export function lintDesign(markdown) {
  // Only extend the official unknown-property check; every other official rule
  // still sees the complete model, including colors referenced by extensions.
  const rules = DEFAULT_RULES.map(rule => state => rule(state).filter(finding => {
    if (finding.rule !== 'broken-ref' || finding.severity !== 'warning') return true;
    const match = /^components\.([^.]+)\.([^.]+)$/.exec(finding.path ?? '');
    if (!match) return true;
    const spec = extensions.get(match[2]);
    const value = state.components.get(match[1])?.properties.get(match[2]);
    return !spec || !validateExtension(value, spec);
  }));
  return lint(markdown, { rules: [...rules, componentRules] });
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const source = fileURLToPath(new URL('../../designs/design.md', import.meta.url));
  try {
    const report = lintDesign(readFileSync(source, 'utf8'));
    for (const finding of report.findings.filter(item => item.severity !== 'info')) {
      console.log(`${finding.severity} ${finding.path ?? ''}: ${finding.message}`);
    }
    console.log(`DESIGN.md lint with official 0.4.0 parser and project schema: ${report.summary.errors} errors, ${report.summary.warnings} warnings`);
    if (report.summary.errors || report.summary.warnings) process.exitCode = 1;
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
