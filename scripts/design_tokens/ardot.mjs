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
  '邻接 Prism 材质': themed({
    '表面/页面': paired('canvas'),
    '表面/卡片': paired('surface'),
    '表面/模块': paired('surface-module'),
    '表面/内嵌': paired('surface-inset'),
    '表面/浮层': paired('surface-floating'),
    '前景/正文': paired('text'),
    '前景/次要': paired('secondary'),
    '前景/边界': paired('outline'),
    '动作/主按钮': paired('primary-action'),
    '动作/主按钮文字': paired('on-primary'),
    '动作/危险': paired('danger-text'),
    '动作/危险底': paired('danger-action'),
    '动作/选中镜片': paired('glass-selected'),
    '动作/禁用文字': paired('control-disabled'),
    '动作/禁用底': paired('control-disabled-track'),
    '动作/焦点': paired('focus'),
    '动作/按压': paired('control-pressed'),
    '动作/开关轨道': paired('switch-off'),
    '动作/开关滑块': theme('white'),
    '玻璃/regular': paired('glass'),
    '玻璃/pill': paired('glass-pill'),
    '玻璃/menu': paired('glass-menu'),
    '玻璃/alert': paired('glass-alert'),
    '玻璃/clear': theme('glass-clear'),
    '玻璃/细边': paired('glass-edge'),
    '遮罩/模态': paired('scrim'),
    '遮罩/媒体': theme('media-shade'),
    '媒体/前景': theme('white'),
  }),
  '邻接 Prism 尺寸': {
    variables: Object.fromEntries(Object.entries({
      '按钮/工具尺寸': 'icon-button.size',
      '按钮/工具图形': 'tool-glyph.size',
      '按钮/工具圆角': 'icon-button.rounded',
      '按钮/工具间距': 'icon-button.gap',
      '按钮/主操作高度': 'button-primary.height',
      '按钮/主操作圆角': 'button-primary.rounded',
      '按钮/焦点宽度': 'control-focus.size',
      '菜单/外圆角': 'menu.rounded',
      '菜单/项目圆角': 'menu-item.rounded',
      '菜单/外内边距': 'menu.padding',
      '菜单/项目内边距': 'menu-item.padding',
      '菜单/图形': 'menu-item.size',
      '菜单/最小行高': 'menu-item.height',
      '确认框/圆角': 'alert.rounded',
      '确认框/首选宽度': 'alert.width',
      '确认框/按钮高度': 'alert-button.height',
      '确认框/按钮圆角': 'alert-button.rounded',
      '确认框/动作间距': 'alert-actions.gap',
      '确认框/动作内边距': 'alert-actions.padding',
      '确认框/正文内边距': 'alert.padding',
      '抽屉/把手宽': 'sheet-handle.width',
      '抽屉/把手高': 'sheet-handle.height',
      '抽屉/顶部圆角': 'sheet.rounded',
      '分段/高度': 'segmented-track.height',
      '分段/轨道圆角': 'segmented-track.rounded',
      '分段/镜片圆角': 'segmented-item.rounded',
      '分段/内边距': 'segmented-track.padding',
      '开关/宽度': 'switch-track.width',
      '开关/高度': 'switch-track.height',
      '开关/轨道圆角': 'switch-track.rounded',
      '开关/滑块': 'switch-thumb.size',
      '开关/滑块圆角': 'switch-thumb.rounded',
      '开关/内边距': 'switch-track.padding',
      '选择/复选可见面': 'checkbox-mark.size',
      '选择/命中区': 'checkbox-target.size',
      '选择/复选圆角': 'checkbox-mark.rounded',
      '输入/圆角': 'connection-field.rounded',
      '输入/水平内边距': 'connection-field.padding',
      '导航/轨道高': 'navigation.height',
      '导航/轨道圆角': 'navigation.rounded',
      '导航/轨道边距': 'navigation.padding',
      '列表/最小行高': 'row.height',
      '列表/水平内边距': 'list-card.padding',
      '列表/圆角': 'list-card.rounded',
    }).map(([name, property]) => [name, dimensions[`components.${property}`]])),
  },
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
