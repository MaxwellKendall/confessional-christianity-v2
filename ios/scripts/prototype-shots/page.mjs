// Turns the approved TKL-885 prototype (prototype.html, committed as approved)
// into a page showing only the phone, in one named state, with the app's own
// font files so it renders offline. Used by render.sh; tested in
// scripts/ios/chapel-design.test.mjs.
//   node page.mjs <state> > page.html
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const NAME = /^(today|catechism|lordsday|settings|addchild)-(empty|loading|error|full)(?:-(thu|sat|sun))?(-signed)?-(light|dark)$/;

export function parseState(name) {
  const match = NAME.exec(name);
  if (!match) {
    throw new Error(`bad state "${name}": expected <today|catechism|lordsday|settings|addchild>-<empty|loading|error|full>[-thu|sat|sun][-signed]-<light|dark>`);
  }
  const [, screen, state, day = 'thu', signed, theme] = match;
  return { screen, state, day, signed: signed ? '1' : '0', theme };
}

export function prototypePage(html, name, fontsUrl) {
  const { screen, ...state } = parseState(name);
  const face = (family, weight, file) =>
    `@font-face{font-family:${family};font-weight:${weight};src:url("${fontsUrl}${file}")}`;
  const style = [
    face('Cinzel', 400, 'Cinzel-Regular.ttf'),
    face('Cinzel', 600, 'Cinzel-SemiBold.ttf'),
    face('Marcellus', 400, 'Marcellus-Regular.ttf'),
    '.bar,.note{display:none!important}',
    '.phone{position:fixed!important;left:0;top:0;width:390px!important;max-width:none!important;border-radius:0;box-shadow:none}',
    // iOS draws text with greyscale smoothing; Chrome on a Mac is heavier by default.
    'body{-webkit-font-smoothing:antialiased}',
    '*{transition:none!important;animation:none!important}',
  ].join('\n');

  const tab = { catechism: 'cat', lordsday: 'ld' }[screen] ?? 'today';
  const sheet = screen === 'settings' || screen === 'addchild' ? `openSheet('${screen}');` : '';
  const setup = `Object.assign(S,${JSON.stringify({ ...state, tab })});render();${sheet}`;

  const page = html.replace(/<link [^>]*fonts\.g[^>]*>\n?/g, '');
  const scriptEnd = page.lastIndexOf('</script>');
  return (page.slice(0, scriptEnd) + setup + page.slice(scriptEnd))
    .replace('</head>', () => `<style>${style}</style>\n</head>`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const html = readFileSync(new URL('./prototype.html', import.meta.url), 'utf8');
  const fonts = new URL('../../App/Sources/Fonts/', import.meta.url).href;
  process.stdout.write(prototypePage(html, process.argv[2] ?? '', fonts));
}
