import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { dirname, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { lint } from '@google/design.md/linter';

const root = fileURLToPath(new URL('../../', import.meta.url));
const defaultSource = resolve(root, 'designs/design.md');
const defaultOutput = resolve(root, 'packages/design_system/lib/src/generated/design_tokens.g.dart');
const consumer = resolve(root, 'packages/design_system/lib/design_system.dart');
// 显式声明 DESIGN.md 标准组件属性之外支持的扩展。
const componentProperties = new Set([
  'backgroundColor', 'textColor', 'typography', 'rounded', 'padding', 'size',
  'height', 'width', 'maxWidth', 'borderColor', 'blur', 'shadowBlur', 'shadowOffset', 'angle',
  'refractionIndex', 'refractionWidth', 'opticalDepth', 'dispersion', 'magnification', 'saturation',
  'gap', 'verticalPadding', 'opacity', 'scale', 'stretch',
  'specularThickness', 'specularSharpness', 'specularSpread', 'specularIntensity',
  'specularOppositeIntensity', 'glowThickness', 'glowAngle', 'glowSpread',
  'glowIntensity', 'glowOppositeIntensity',
]);

function identifier(path) {
  const words = path.split(/[.\-_]/);
  if (words.some(word => !/^[A-Za-z][A-Za-z0-9]*$/.test(word))) {
    throw new Error(`Unsupported Dart token identifier: ${path}`);
  }
  return words[0] + words.slice(1).map(word => word[0].toUpperCase() + word.slice(1)).join('');
}

function number(value, path) {
  if (!Number.isFinite(value)) throw new Error(`Expected finite number at ${path}`);
  return Number.isInteger(value) ? `${value}.0` : String(value);
}

function dimension(value, path) {
  // 项目把 DESIGN.md 的 px 定义为 Flutter 逻辑像素；其他 CSS 单位需要布局或字体上下文，不能静默去除单位。
  //
  if (value.unit !== 'px') throw new Error(`Unsupported unit '${value.unit}' at ${path}; expected px`);
  return number(value.value, path);
}

function color(value, path) {
  if (!/^#[a-f\d]{6}([a-f\d]{2})?$/i.test(value.hex)) throw new Error(`Unsupported color at ${path}`);
  const hex = value.hex.slice(1).toLowerCase();
  return `Color(0x${hex.length === 8 ? hex.slice(6) : 'ff'}${hex.slice(0, 6)})`;
}

function typography(value, path) {
  if (!value.fontSize || !value.lineHeight || value.fontWeight === undefined || !value.fontFamily) {
    throw new Error(`Missing typography fields at ${path}; fontFamily/fontSize/fontWeight/lineHeight are required (quote unitless lineHeight for official parser)`);
  }
  if (value.fontFeature || value.fontVariation) throw new Error(`Unsupported font features/variations at ${path}`);
  if (!Number.isInteger(value.fontWeight) || value.fontWeight < 100 || value.fontWeight > 900 || value.fontWeight % 100 !== 0) {
    throw new Error(`Unsupported fontWeight at ${path}`);
  }
  dimension(value.fontSize, `${path}.fontSize`);
  let height;
  if (value.lineHeight.unit === '') height = value.lineHeight.value;
  else if (value.lineHeight.unit === 'px') height = value.lineHeight.value / value.fontSize.value;
  else throw new Error(`Unsupported lineHeight unit at ${path}`);
  const fields = {
    fontFamily: JSON.stringify(value.fontFamily).replaceAll('$', '\\$'),
    fontSize: dimension(value.fontSize, `${path}.fontSize`),
    fontWeight: `FontWeight.w${value.fontWeight}`,
    lineHeight: number(height, `${path}.lineHeight`),
  };
  fields.letterSpacing = value.letterSpacing ? dimension(value.letterSpacing, `${path}.letterSpacing`) : 'null';
  return fields;
}

function literal(value, path) {
  if (typeof value === 'number') return number(value, path);
  if (typeof value === 'boolean') return String(value);
  if (value?.type === 'color') return color(value, path);
  if (value?.type === 'dimension') return dimension(value, path);
  if (value?.type === 'typography') {
    const fields = typography(value, path);
    // 字体族仅描述设计稿；运行时样式继承各平台 Flutter 默认字体。
    //
    delete fields.fontFamily;
    return `TextStyle(${Object.entries(fields).map(([key, field]) => `${key === 'lineHeight' ? 'height' : key}: ${field}`).join(', ')})`;
  }
  throw new Error(`Unsupported or unresolved token at ${path}`);
}

export function generate(markdown, requiredTokens = []) {
  const report = lint(markdown);
  if (report.summary.errors) throw new Error(`Official DESIGN.md lint errors:\n${report.findings.filter(item => item.severity === 'error').map(item => `${item.path ?? ''}: ${item.message}`).join('\n')}`);
  const ignoredTypography = report.findings.filter(item => item.message.includes('not a recognized typography property'));
  if (ignoredTypography.length) throw new Error(`Unsupported typography properties: ${ignoredTypography.map(item => item.path).join(', ')}`);
  const state = report.designSystem;
  if (state.unknownKeys?.length) throw new Error(`Unknown DESIGN.md keys: ${state.unknownKeys.join(', ')}`);
  for (const [path, value] of state.symbolTable) {
    if (/^(spacing|rounded)\./.test(path) && value?.type !== 'dimension') {
      throw new Error(`Unsupported or unresolved dimension at ${path}; use an explicit px value`);
    }
  }
  const constants = new Map();
  function add(path, value) {
    const name = identifier(path);
    if (constants.has(name)) throw new Error(`Dart identifier collision: ${path} → ${name}`);
    constants.set(name, value);
  }
  for (const [category, map] of [['color', state.colors], ['spacing', state.spacing], ['rounded', state.rounded]]) {
    for (const [name, value] of map) add(`${category}.${name}`, literal(value, `${category}.${name}`));
  }
  for (const [name, value] of state.typography) {
    for (const [property, field] of Object.entries(typography(value, `typography.${name}`))) add(`typography.${name}.${property}`, field);
  }
  for (const [name, component] of state.components) {
    for (const [property, value] of component.properties) {
      if (!componentProperties.has(property)) throw new Error(`Unsupported component property: components.${name}.${property}`);
      add(`component.${name}.${property}`, literal(value, `components.${name}.${property}`));
    }
  }
  for (const name of requiredTokens) {
    if (!constants.has(name)) throw new Error(`Missing required DESIGN.md token: ${name}`);
  }
  const source = [
    '// Generated by tool/design_tokens/generate.mjs using @google/design.md 0.4.0.',
    '// Edit designs/design.md, then run node tool/design_tokens/generate.mjs.',
    '// DESIGN.md px values map to Flutter logical pixels.',
    "import 'package:flutter/material.dart';", '',
    'abstract final class DesignTokens {',
    ...[...constants.keys()].sort().map(name => `  static const ${constants.get(name) === 'null' ? 'double? ' : ''}${name} = ${constants.get(name)};`),
    '}', '',
  ].join('\n');
  const formatter = spawnSync('dart', ['format', '--output=show', '--summary=none'], { input: source, encoding: 'utf8' });
  if (formatter.error || formatter.status !== 0) throw new Error(`Dart formatting failed: ${formatter.error?.message ?? formatter.stderr}`);
  return { source: formatter.stdout, summary: report.summary };
}

export function run(args = process.argv.slice(2)) {
  let source = defaultSource;
  let output = defaultOutput;
  let check = false;
  for (let index = 0; index < args.length; index++) {
    if (args[index] === '--check') check = true;
    else if (args[index] === '--source' && args[index + 1]) source = resolve(args[++index]);
    else if (args[index] === '--output' && args[index + 1]) output = resolve(args[++index]);
    else throw new Error(`Unknown or incomplete argument: ${args[index]}`);
  }
  const required = [...readFileSync(consumer, 'utf8').matchAll(/\bDesignTokens\.([A-Za-z][A-Za-z0-9]*)/g)].map(match => match[1]);
  const result = generate(readFileSync(source, 'utf8'), required);
  if (check) {
    let existing;
    try { existing = readFileSync(output, 'utf8'); } catch { /* Missing output is stale. */ }
    if (existing !== result.source) throw new Error('Design tokens are stale; run node tool/design_tokens/generate.mjs');
  } else {
    mkdirSync(dirname(output), { recursive: true });
    writeFileSync(output, result.source);
  }
  console.log(`DESIGN.md ${check ? 'checked' : 'generated'} with official 0.4.0 parser: ${result.summary.errors} errors, ${result.summary.warnings} warnings`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try { run(); } catch (error) { console.error(error.message); process.exitCode = 1; }
}
