// Leitor do `git diff -U0 --src-prefix=a/ --dst-prefix=b/` para os scripts de revisão (check-findings.mjs,
// diff-smells.mjs). Segue as contagens do cabeçalho "@@ -a,b +c,d @@": dentro de um trecho, toda linha é conteúdo,
// mesmo que comece com "+++ " (linha adicionada "++ x") ou "--- " (linha removida "-- x", comentário de SQL). Fora de
// um trecho, "+++ "/"--- " são os caminhos do arquivo.
// parseDiff(texto) -> Map<caminho, { added: [{line, text}], removed: [{at, text}], ranges: [[início, fim]], deleted }>
//   added: linhas adicionadas, com o número na versão nova;
//   removed: linhas removidas, com `at` = a linha da versão nova onde elas estavam (a que vem logo depois);
//   ranges: linhas da versão nova que o diff toca; trecho que só remove conta a linha antes e a depois do corte;
//   deleted: o arquivo foi apagado (as linhas removidas ficam sob o caminho antigo).

const unquote = (p) => {
  if (!p.startsWith('"')) return p;
  try { return JSON.parse(p); } catch { return p.slice(1, -1); }
};
const pathOf = (raw, prefix) => {
  const p = unquote(raw.replace(/\t$/, ''));
  return p === '/dev/null' ? null : p.startsWith(prefix) ? p.slice(prefix.length) : p;
};

export function parseDiff(text) {
  const files = new Map();
  const entry = (p) => { if (!files.has(p)) files.set(p, { added: [], removed: [], ranges: [], deleted: false }); return files.get(p); };
  let cur = null, oldPath = null, oldLeft = 0, newLeft = 0, newLine = 0;
  for (const l of text.split('\n')) {
    if (oldLeft > 0 || newLeft > 0) {
      if (l.startsWith('+') && newLeft > 0) { cur?.added.push({ line: newLine, text: l.slice(1) }); newLine++; newLeft--; continue; }
      if (l.startsWith('-') && oldLeft > 0) { cur?.removed.push({ at: newLine, text: l.slice(1) }); oldLeft--; continue; }
      if (l.startsWith(' ')) { newLine++; oldLeft--; newLeft--; continue; }
      if (l.startsWith('\\')) continue; // "\ No newline at end of file"
      oldLeft = newLeft = 0; // contagem que não fecha: volta a ler cabeçalho
    }
    if (l.startsWith('\\')) continue;
    if (l.startsWith('diff --git ')) { cur = null; oldPath = null; continue; }
    if (l.startsWith('--- ')) { oldPath = pathOf(l.slice(4), 'a/'); continue; }
    if (l.startsWith('+++ ')) {
      const p = pathOf(l.slice(4), 'b/');
      if (p) cur = entry(p);
      else if (oldPath) { cur = entry(oldPath); cur.deleted = true; }
      else cur = null;
      continue;
    }
    const h = /^@@ -\d+(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/.exec(l);
    if (h) {
      oldLeft = h[1] === undefined ? 1 : Number(h[1]);
      newLeft = h[3] === undefined ? 1 : Number(h[3]);
      const s = Number(h[2]);
      if (newLeft > 0) { newLine = s; cur?.ranges.push([s, s + newLeft - 1]); }
      else { newLine = s + 1; cur?.ranges.push([Math.max(1, s), s + 1]); } // só remove: o corte fica entre s e s + 1
    }
  }
  return files;
}
