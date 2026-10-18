import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { generate } from './generate.mjs';

const design = readFileSync(new URL('../../designs/design.md', import.meta.url), 'utf8');
const cli = fileURLToPath(new URL('./generate.mjs', import.meta.url));

test('official parser preserves light/dark RGBA, line height, references and glass optics in Dart', () => {
  const { source } = generate(design);
  assert.match(source, /colorGlass = Color\(0x80ffffff\)/);
  assert.match(source, /colorGlassDark = Color\(0x991c1c1e\)/);
  assert.match(source, /colorTextDark = Color\(0xffffffff\)/);
  assert.match(source, /typographyDisplayLineHeight = 1\.15/);
  assert.match(source, /typographyDisplayLetterSpacing = -0\.6/);
  assert.match(source, /componentGlassBlur = 12\.0/);
  assert.match(source, /componentGlassRefractionIndex = 1\.1/);
  assert.match(source, /componentGlassRefractionWidth = 16\.0/);
  assert.match(source, /componentGlassSpecularThickness = 2\.0/);
  assert.match(source, /componentGlassSpecularIntensity = 0\.75/);
  assert.match(source, /componentGlassGlowIntensity = 0\.25/);
  assert.match(source, /componentGlassClearBlur = 4\.0/);
  assert.match(source, /componentContentPanelRounded = 20\.0/);
});

test('source edits propagate through generated semantic and component values', () => {
  const revised = design.replace("primary-action: '#1B1B1F'", "primary-action: '#12345678'")
    .replace("lineHeight: '1.15'", "lineHeight: '1.2'")
    .replace('blur: 12px', 'blur: 26px')
    .replace('  md: 16px', '  md: 18px');
  const { source } = generate(revised);
  assert.match(source, /colorPrimaryAction = Color\(0x78123456\)/);
  assert.match(source, /componentButtonPrimaryBackgroundColor = Color\(0x78123456\)/);
  assert.match(source, /typographyDisplayLineHeight = 1\.2/);
  assert.match(source, /componentGlassBlur = 26\.0/);
  assert.match(source, /componentRowPadding = 18\.0/);
});

test('generation fails on lint errors, missing tokens, unsupported units and silently ignored dimensions', () => {
  assert.throws(() => generate(design.replace("'{colors.canvas}'", "'{colors.missing}'")), /Official DESIGN.md lint errors/);
  assert.throws(() => generate(design, ['colorAbsent']), /Missing required.*colorAbsent/);
  assert.throws(() => generate(design.replace('  md: 16px', '  md: 1rem')), /Unsupported unit 'rem'/);
  assert.throws(() => generate(design.replace('  md: 16px', '  md: 16')), /Unsupported or unresolved dimension at spacing.md/);
  assert.throws(() => generate(design.replace("lineHeight: '1.15'", 'lineHeight: 1.15')), /Missing typography fields/);
  assert.throws(() => generate(design.replace('    blur: 12px', '    unknownOptics: 20px')), /Unsupported component property/);
  assert.throws(() => generate(design.replace('    fontSize: 28px', '    fontSize: 28px\n    tracking: 1px')), /Unsupported typography properties/);
  assert.throws(() => generate(design.replace('colors:\n', 'extension: custom\ncolors:\n')), /Unknown DESIGN.md keys/);
  assert.throws(() => generate(design.replace('colors:\n', 'colors:\n  foo-bar: "#000000"\n  fooBar: "#000000"\n')), /Dart identifier collision/);
});

test('--check detects source and output drift without writing, generation restores freshness', () => {
  const directory = mkdtempSync(join(tmpdir(), 'design-token-test-'));
  const source = join(directory, 'DESIGN.md');
  const output = join(directory, 'tokens.g.dart');
  const command = (...args) => spawnSync(process.execPath, [cli, '--source', source, '--output', output, ...args], { encoding: 'utf8' });
  try {
    writeFileSync(source, design);
    assert.equal(command().status, 0);
    const generated = readFileSync(output, 'utf8');
    assert.equal(command('--check').status, 0);
    writeFileSync(source, design.replace('blur: 12px', 'blur: 26px'));
    const stale = command('--check');
    assert.equal(stale.status, 1);
    assert.match(stale.stderr, /tokens are stale/);
    assert.equal(readFileSync(output, 'utf8'), generated);
    assert.equal(command().status, 0);
    assert.equal(command('--check').status, 0);
    writeFileSync(output, '// edited by hand\n');
    assert.equal(command('--check').status, 1);
    assert.equal(readFileSync(output, 'utf8'), '// edited by hand\n');
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});
