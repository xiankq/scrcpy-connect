import {readFile, writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import sharp from 'sharp';

const check = process.argv.slice(2).includes('--check');
const root = new URL('../../', import.meta.url);
const read = path => readFile(new URL(path, root), 'utf8');
const source = await read('designs/assets/app-icon.svg');
const paths = [...source.matchAll(/<path fill="(#[0-9A-F]{6})" d="([^"]+)"\/>/g)]
  .map(([, color, data]) => ({color, data}));
if (paths.length !== 2) throw new Error('Expected two filled shapes in the logo');

const outputs = new Map();
const android = 'app/android/app/src/main/res';
const ios = 'app/ios/Runner/Assets.xcassets/AppIcon.appiconset';
const mac = 'app/macos/Runner/Assets.xcassets/AppIcon.appiconset';
const svg = content => `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">${content}</svg>\n`;
const roundTile = (inset, radius) => svg(`<defs><clipPath id="tile-mask"><rect x="${inset}" y="${inset}" width="${1024 - 2 * inset}" height="${1024 - 2 * inset}" rx="${radius}"/></clipPath></defs>
<g clip-path="url(#tile-mask)">
${source.replace(/^<svg[^>]*>\n|<\/svg>\n?$/g, '').trimEnd()}
</g>`);
const alternate = (tile, colors) => svg(
  `<rect width="1024" height="1024" fill="${tile}"/>` +
  paths.map(({data}, i) => `<path fill="${colors[i]}" d="${data}"/>`).join(''),
);
const desktop = roundTile(40, 213);

function vector({ scale, color, legacy = false }) {
  const offset = 54 - 512 * scale;
  const layer = legacy
    ? '    <path android:fillColor="@color/icon_background" android:pathData="M24,0H84Q108,0 108,24V84Q108,108 84,108H24Q0,108 0,84V24Q0,0 24,0Z" />\n'
    : '';
  return `<!-- Generated from designs/assets/app-icon.svg. -->
<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="108dp" android:height="108dp" android:viewportWidth="108" android:viewportHeight="108">
${layer}    <group android:translateX="${offset}" android:translateY="${offset}" android:scaleX="${scale}" android:scaleY="${scale}">
${paths.map(path => `        <path android:fillColor="${color ?? path.color}" android:pathData="${path.data}" />`).join('\n')}
    </group>
</vector>
`;
}

outputs.set(`${android}/drawable/ic_launcher_foreground.xml`, vector({scale: 0.080078125}));
outputs.set(`${android}/drawable/ic_launcher_monochrome.xml`, vector({scale: 0.080078125, color: '#FFFFFFFF'}));
outputs.set(`${android}/mipmap-anydpi/ic_launcher.xml`, vector({scale: 0.10546875, legacy: true}));
outputs.set('app/linux/runner/interconnect.svg', desktop);

async function png(mark, size, opaque = false) {
  const image = sharp(Buffer.from(mark), {density: 72}).resize(size, size);
  if (opaque) image.removeAlpha().toColourspace('srgb');
  return image.png().toBuffer();
}

const iosSheets = {
  'Icon-App-1024x1024@1x.png': source,
  'Icon-App-Dark.png': alternate('#18233F', ['#8BA9FF', '#FF946B']),
  'Icon-App-Tinted.png': alternate('#252525', ['#FFFFFF', '#C7C7C7']),
};
for (const [file, mark] of Object.entries(iosSheets)) {
  outputs.set(`${ios}/${file}`, await png(mark, 1024, true));
}
const macCatalog = JSON.parse(await read(`${mac}/Contents.json`));
const macFiles = new Map(macCatalog.images.map(slot => [
  slot.filename, parseFloat(slot.size) * parseInt(slot.scale, 10),
]));
for (const [file, size] of macFiles) outputs.set(`${mac}/${file}`, await png(roundTile(85, 196), size));

const sizes = [16, 20, 24, 32, 40, 48, 64, 128, 256];
const images = await Promise.all(sizes.map(size => png(desktop, size)));
const header = Buffer.alloc(6 + 16 * images.length);
header.writeUInt16LE(1, 2);
header.writeUInt16LE(images.length, 4);
let offset = header.length;
for (const [i, image] of images.entries()) {
  const entry = 6 + 16 * i;
  header[entry] = header[entry + 1] = sizes[i] % 256;
  header.writeUInt16LE(1, entry + 4);
  header.writeUInt16LE(32, entry + 6);
  header.writeUInt32LE(image.length, entry + 8);
  header.writeUInt32LE(offset, entry + 12);
  offset += image.length;
}
outputs.set('app/windows/runner/resources/app_icon.ico', Buffer.concat([header, ...images]));

const differences = [];
for (const [path, content] of outputs) {
  const file = fileURLToPath(new URL(path, root));
  if (!check) {
    await writeFile(file, content);
    continue;
  }
  const actual = await readFile(file).catch(error => {
    if (error.code === 'ENOENT') return null;
    throw error;
  });
  // PNG encoders can emit different compression streams across hosts.
  if (actual && path.endsWith('.png')) {
    const [current, expected] = await Promise.all([actual, content].map(
      bytes => sharp(bytes).raw().toBuffer({resolveWithObject: true}),
    ));
    if (current.info.width === expected.info.width &&
        current.info.height === expected.info.height &&
        current.info.channels === expected.info.channels &&
        current.data.equals(expected.data)) continue;
  } else if (actual?.equals(Buffer.from(content))) {
    continue;
  }
  differences.push(path);
}
if (differences.length) {
  console.error(`Run npm run generate --prefix scripts/app_icons:\n${differences.join('\n')}`);
  process.exitCode = 1;
} else {
  console.log(`${outputs.size} app icon assets ${check ? 'verified' : 'generated'}.`);
}
