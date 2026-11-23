import { readFileSync } from 'node:fs';

const registry = new URL('../../designs/icons.json', import.meta.url);
const identifier = name => name.replace(/-([a-z0-9])/g, (_, char) => char.toUpperCase());

export function readIcons() {
  return Object.entries(JSON.parse(readFileSync(registry, 'utf8'))).map(([role, glyph]) => {
    const validName = /^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$/;
    if (!validName.test(role) || typeof glyph !== 'string' || !validName.test(glyph)) {
      throw new Error(`Invalid icon role or glyph: ${role}`);
    }
    const svg = readFileSync(new URL(`./node_modules/lucide-static/icons/${glyph}.svg`, import.meta.url), 'utf8');
    return { role, glyph, name: identifier(role), constant: identifier(glyph), svg };
  });
}
