/**
 * Prerender pelnej tresci strony.
 *
 * Aplikacja jest czystym SPA: bot bez JavaScriptu dostaje <div id="root"></div>
 * i ZERO znakow tresci (pomiar 2026-08-31). Google uruchamia JavaScript,
 * wiec strona sie indeksuje — ale GPTBot, PerplexityBot i podglad linku
 * na Facebooku juz nie. Bez prerenderu salon nie ma szans na cytowanie
 * w ChatGPT, a udostepniony link pokazuje pusty kafelek.
 *
 * Skrypt uruchamia zbudowana aplikacje w Chromium, przewija strone (zeby
 * framer-motion odslonil sekcje `whileInView`), normalizuje style animacji
 * i nadpisuje dist/index.html kompletnym HTML-em. React startuje z tego
 * samego pliku i renderuje ten sam widok, wiec uzytkownik nie widzi roznicy.
 *
 * Jedna trasa, bo aplikacja uzywa HashRoutera: /#/blog to dla Google
 * fragment tej samej strony, nie osobny adres. Gdyby blog mial kiedys
 * rankowac samodzielnie, trzeba najpierw zmienic router na BrowserRouter.
 *
 * Uruchamiane po `npm run build` przez `npm run prerender`.
 * Wzorzec przeniesiony z projektu superirek.pl, gdzie dziala od 2026-08.
 */
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import process from 'node:process';
import { chromium } from 'playwright';

const ROOT = process.cwd();
const DIST = path.join(ROOT, 'dist');
const PORT = 4182;

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript',
  '.css': 'text/css',
  '.json': 'application/json',
  '.webp': 'image/webp',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.woff2': 'font/woff2',
  '.woff': 'font/woff',
  '.xml': 'application/xml',
  '.txt': 'text/plain; charset=utf-8',
};

function startServer() {
  const server = http.createServer((req, res) => {
    const urlPath = decodeURIComponent(req.url.split('?')[0]);
    let file = path.join(DIST, urlPath);
    if (!fs.existsSync(file) || fs.statSync(file).isDirectory()) {
      file = path.join(DIST, 'index.html');
    }
    res.writeHead(200, {
      'Content-Type': MIME[path.extname(file).toLowerCase()] || 'application/octet-stream',
    });
    fs.createReadStream(file).pipe(res);
  });
  return new Promise((resolve) => server.listen(PORT, () => resolve(server)));
}

const server = await startServer();
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1366, height: 900 } });

let kod = 0;
try {
  await page.goto(`http://localhost:${PORT}/`, { waitUntil: 'networkidle', timeout: 30000 });

  // Przewin cala strone, zeby whileInView odpalil kazda sekcje
  await page.evaluate(async () => {
    const step = window.innerHeight / 2;
    for (let y = 0; y <= document.body.scrollHeight; y += step) {
      window.scrollTo(0, y);
      await new Promise((r) => setTimeout(r, 120));
    }
    window.scrollTo(0, 0);
  });
  await page.waitForTimeout(600);

  const html = await page.evaluate(() => {
    // Nic nie moze zostac zapisane jako niewidoczne — inaczej bot dostanie
    // tresc z opacity: 0 i potraktuje ja jako ukrywanie tekstu.
    document.querySelectorAll('#root *').forEach((el) => {
      const cs = getComputedStyle(el);
      if (parseFloat(cs.opacity) < 1) el.style.opacity = '1';
      if (cs.transform !== 'none') el.style.transform = 'none';
    });
    return '<!doctype html>\n' + document.documentElement.outerHTML;
  });

  // Straznik: pusty prerender jest gorszy niz zaden, bo wyglada na udany.
  if (!/<h1/i.test(html)) throw new Error('brak <h1> po renderze');
  const tekst = html
    .replace(/<(script|style)[^>]*>[\s\S]*?<\/\1>/g, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  if (tekst.length < 500) throw new Error(`tylko ${tekst.length} znakow tresci`);

  fs.writeFileSync(path.join(DIST, 'index.html'), html, 'utf8');
  console.log(`[prerender] / -> index.html (${Math.round(html.length / 1024)} KB, ` +
              `${tekst.length} znakow tresci)`);
} catch (error) {
  console.error(`[prerender] Nie udalo sie: ${error.message}`);
  kod = 1;
} finally {
  await browser.close();
  server.close();
}

process.exitCode = kod;
