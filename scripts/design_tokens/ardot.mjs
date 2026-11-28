import { readFileSync } from 'node:fs';
import { lintDesign } from './lint.mjs';
import { readIcons } from './icons.mjs';

const document = new URL('../../designs/design.md', import.meta.url);
const report = lintDesign(readFileSync(document, 'utf8'));
if (report.summary.errors || report.summary.warnings) {
  throw new Error('Run the design specification lint before syncing Ardot');
}
const { colors, spacing, rounded, typography } = report.designSystem;
const rgba = ({ r, g, b, a = 1 }) => ({ r: r / 255, g: g / 255, b: b / 255, a });
const color = token => rgba(colors.get(token));
const single = (type, value) => ({ type, value });

const dimensions = {};
for (const [category, tokens] of [['spacing', spacing], ['rounded', rounded]]) {
  for (const [name, value] of tokens) {
    dimensions[`${category}/${name}`] = single('FLOAT', value.value);
  }
}
for (const [name, value] of typography) {
  dimensions[`typography/${name}/font-size`] = single('FLOAT', value.fontSize.value);
  dimensions[`typography/${name}/line-height`] = single('FLOAT', value.lineHeight.unit === 'px'
    ? value.lineHeight.value : value.lineHeight.value * value.fontSize.value);
}
// 组件几何由 Ardot 母组件承载；变量只保留页面会直接绑定的基础尺寸。

// 有 `-dark` 夜间值的角色进入主题集合，其余颜色在明暗下相同，进入固定色集合。
const themed = {};
const fixed = {};
for (const [name] of colors) {
  if (name.endsWith('-dark')) continue;
  if (colors.has(`${name}-dark`)) {
    themed[name] = { type: 'COLOR', valuesByMode: { 日间: color(name), 夜间: color(`${name}-dark`) } };
  } else {
    fixed[name] = single('COLOR', color(name));
  }
}

const variables = {
  '邻接 · 主题': { modes: ['日间', '夜间'], variables: themed },
  '邻接 · 固定色': { variables: fixed },
  '邻接 · 尺寸': { variables: dimensions },
};

const icons = readIcons().map(({ role, glyph, svg }) => ({ role, glyph, svg }));
const [flag, snapshot] = process.argv.slice(2);
if (flag === '--check' && snapshot) {
  const rows = readFileSync(snapshot, 'utf8').trim().split('\n').map(line => JSON.parse(line));
  const sets = new Map(rows.filter(row => row._variableSet).map(({ _variableSet: set }) => [set.name, set]));
  const actual = new Map(rows.filter(row => row.id).map(row => [`${row.collection}/${row.name}`, row]));
  const changes = [];
  let count = 0;
  for (const [setName, definition] of Object.entries(variables)) {
    const set = sets.get(setName);
    for (const [name, expected] of Object.entries(definition.variables)) {
      const key = `${setName}/${name}`;
      const item = actual.get(key);
      count++;
      if (item?.type !== expected.type) {
        changes.push(`${key}: missing or wrong type`);
        continue;
      }
      const modes = expected.valuesByMode ?? { [set.modes.find(mode => mode.id === set.defaultModeId).name]: expected.value };
      for (const [name, value] of Object.entries(modes)) {
        const mode = set.modes.find(mode => mode.name === name);
        const resolved = item.valuesByMode[mode?.id];
        const match = typeof value === 'object'
          ? resolved && Object.keys(value).every(channel => Math.abs(resolved[channel] - value[channel]) < 0.5 / 255)
          : resolved === value;
        if (!match) changes.push(`${key} [${name}]: value differs from the specification`);
      }
    }
  }
  if (changes.length) throw new Error(changes.join('\n'));
  console.log(`Ardot variables match the specification (${count} variables)`);
} else if (flag) {
  throw new Error('Usage: node ardot.mjs [--check <fetch_variables.jsonl>]');
} else {
  process.stdout.write(`${JSON.stringify({ variables, icons }, null, 2)}\n`);
}
