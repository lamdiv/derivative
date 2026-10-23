import { execFileSync } from 'node:child_process';
import { mkdirSync, rmSync, readFileSync, writeFileSync } from 'node:fs';
import electron from 'electron';
if (process.platform !== 'darwin') throw new Error('Icon generation uses macOS ImageIO and iconutil.');
const brand = JSON.parse(readFileSync('assets/brand.json', 'utf8'));
writeFileSync('assets/icon.svg', `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs><linearGradient id="tile" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#c9b9e7"/><stop offset="1" stop-color="#a18ac8"/></linearGradient></defs>
  <rect x="64" y="64" width="896" height="896" rx="212" fill="url(#tile)"/>
  <g transform="translate(160 150) scale(11)" fill="none" stroke="#fff" stroke-linecap="round" stroke-linejoin="round">
    <path d="${brand.bowl}" stroke-width="8"/><path d="${brand.prime}" stroke-width="5"/>
  </g>
</svg>
`);
const set = 'assets/Derivative.iconset';
mkdirSync(set, { recursive: true });
execFileSync(electron, ['scripts/render-icon.cjs'], { stdio: 'inherit', env: { ...process.env, ELECTRON_RUN_AS_NODE: undefined } });
for (const size of [16, 32, 128, 256, 512]) {
  execFileSync('sips', ['-z', String(size), String(size), 'assets/icon.png', '--out', `${set}/icon_${size}x${size}.png`], { stdio: 'ignore' });
  execFileSync('sips', ['-z', String(size * 2), String(size * 2), 'assets/icon.png', '--out', `${set}/icon_${size}x${size}@2x.png`], { stdio: 'ignore' });
}
execFileSync('iconutil', ['-c', 'icns', set, '-o', 'assets/icon.icns']);
rmSync(set, { recursive: true });
