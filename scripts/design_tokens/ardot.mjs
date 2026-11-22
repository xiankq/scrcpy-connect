import { readFileSync } from 'node:fs';
import { lintDesign } from './lint.mjs';
import { readIcons } from './icons.mjs';

const document = new URL('../../designs/design.md', import.meta.url);
const report = lintDesign(readFileSync(document, 'utf8'));
if (report.summary.errors || report.summary.warnings) {
  throw new Error('Run the design specification lint before syncing Ardot');
}
const { colors, spacing, rounded, typography, components } = report.designSystem;
const rgba = ({ r, g, b, a = 1 }) => ({ r: r / 255, g: g / 255, b: b / 255, a });
const color = token => rgba(colors.get(token));
const single = (type, value) => ({ type, value });
const theme = (light, dark = light) => ({
  type: 'COLOR',
  valuesByMode: { 日间: color(light), 夜间: color(dark) },
});
const paired = token => theme(token, `${token}-dark`);
const themed = variables => ({ modes: ['日间', '夜间'], variables });

const dimensions = {};
for (const [category, tokens] of [['spacing', spacing], ['rounded', rounded]]) {
  for (const [name, value] of tokens) {
    dimensions[`${category}.${name}`] = single('FLOAT', value.value);
  }
}
for (const [name, value] of typography) {
  dimensions[`typography.${name}.font-size`] = single('FLOAT', value.fontSize.value);
}
for (const [name, component] of components) {
  for (const [property, value] of component.properties) {
    if (value?.type === 'dimension') {
      dimensions[`components.${name}.${property}`] = single('FLOAT', value.value);
    } else if (property === 'opacity') {
      dimensions[`components.${name}.${property}`] = single('FLOAT', value * 100);
    }
  }
}

// 已有集合保留变量 ID，历史实例继续跟随同一份规范。
const variables = {
  邻接颜色: {
    variables: Object.fromEntries([...colors].map(([name, value]) => [name, single('COLOR', rgba(value))])),
  },
  邻接尺寸: { variables: dimensions },
  邻接界面: themed({
    canvas: paired('canvas'),
    ink: paired('text'),
    primary: paired('primary'),
    'on-primary': paired('on-primary'),
    secondary: paired('secondary'),
    surface: paired('surface'),
    edge: paired('muted'),
    online: paired('success'),
    danger: paired('danger'),
    warning: paired('warning'),
    'danger-text': paired('danger-text'),
    'on-danger': paired('on-danger'),
    'on-warning': theme('on-warning'),
    'device-panel': paired('device-panel'),
    'skeleton-graphic-dark': theme('skeleton-graphic-dark'),
    'skeleton-line': theme('tint'),
    'skeleton-line-dark': theme('muted-dark'),
    'connection-icon-discovery': theme('connection-nearby'),
    'connection-icon-pairing': theme('connection-pairing'),
    'connection-icon-scan': theme('connection-qr'),
    'connection-icon-usb': theme('connection-usb'),
    'connection-icon-ip': theme('connection-ip'),
  }),
  邻接: themed({
    paper: paired('canvas'),
    ink: paired('text'),
    muted: paired('secondary'),
    ice: paired('surface'),
    lime: paired('surface'),
    melon: paired('tint'),
    rule: paired('muted'),
    danger: paired('danger'),
  }),
  列表与宫格: {
    variables: Object.fromEntries(Object.entries({
      device: 'blue', connect: 'mint', document: 'document', media: 'slate',
      transfer: 'transfer', notice: 'coral', display: 'amber', archive: 'purple',
      utility: 'utility',
    }).map(([role, token]) => [`role-${role}`, single('COLOR', color(`list-icon-${token}`))])),
  },
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
          ? resolved && Object.keys(value).every(channel => Math.abs(resolved[channel] - value[channel]) < 1e-6)
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
