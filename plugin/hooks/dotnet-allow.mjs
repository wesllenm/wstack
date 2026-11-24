// Veredito do dotnet-allow.sh (payload do PreToolUse em Bash na entrada padrão). Imprime ALLOW ou nada.
// dotnet build, test, restore, format e ef migrations saíram do allow por prefixo do settings.json: o prefixo aceitava
// opção que grava arquivo onde o agente quiser (-flp:logfile=, -bl:, -o, -p:OutputPath=, --logger, --results-directory,
// --diag, --report, ef migrations script -o). Gravado num hook, o log vira comando (provado: -flp:logfile= sobre o
// push-guard.sh com uma linha injetada por -p:). Este hook devolve allow só para o comando INTEIRO num formato fechado;
// qualquer outra forma cai no pedido de permissão normal. Um buraco no formato vira pedido, nunca gravação liberada.
// - dotnet <build|test|restore> [<projeto>] [opções], dotnet format [<projeto>] --verify-no-changes [opções] e
//   dotnet ef migrations <list|add <Nome>|script [<de> [<para>]]> [opções] e
//   dotnet list [<projeto>] package [--vulnerable] [--include-transitive] [--outdated] [--deprecated] (o restore dele
//   também lê o Directory.Build.rsp: saiu do allow por prefixo pelo mesmo motivo);
// - <projeto> é caminho relativo literal, sem .. e sem começar por - ou /;
// - opções só da lista OPTS, cada uma com o valor da forma fechada dela; --filter só entre aspas duplas, com alfabeto
//   em que o bash não expande nada dentro delas (sem $, crase, barra invertida);
// - separadas só por espaço; no fim, no máximo 2>&1 ou 2>/dev/null, ou > <arquivo literal na pasta temporária> 2>&1,
//   e um "| tail -N" ou "| head -N".
// O MSBuild também lê opções que não estão no texto: um Directory.Build.rsp na pasta do projeto ou acima dela acrescenta
// -flp:logfile= e -p: por dentro (provado: o log com uma linha injetada gravado num hook). Com um Directory.Build.rsp
// da pasta do comando até a raiz, nada é liberado; o rsp, o Directory.Build.targets, o nuget.config e o global.json
// estão no ask do settings.json. Alvo de MSBuild num .csproj gravado pelo agente é "código rodado pelo build" (risco
// aceito, como o código de teste).
import { existsSync, statSync } from 'node:fs';
import { basename, dirname, join, resolve } from 'node:path';
import { inTempDir } from './closed-forms.mjs';

const PATH = '(?!-)(?!/)[A-Za-z0-9._/-]+';
const NAME = '[A-Za-z][A-Za-z0-9_]*';
const FLAG = '--no-restore|--no-build|--nologo|--locked-mode|--force-evaluate|--idempotent|--no-incremental|--blame-crash';
const VALUED = `(?:-c|--configuration) (?:Debug|Release)|(?:-v|--verbosity) (?:q|quiet|m|minimal|n|normal)|--filter "[A-Za-z0-9.=!&|~_ ()+-]+"|--include ${PATH}|--project ${PATH}|--startup-project ${PATH}`;
const OPTS = `(?: +(?:${FLAG}|${VALUED}))*`;
const TAIL = '(?: +(?:2>&1|2>/dev/null|> (/[A-Za-z0-9._/+=:@-]+) 2>&1))?(?: +\\| +(?:tail|head) +(?:-n +)?-?[0-9]+)?';
const FORMS = [
  `dotnet (?:build|test|restore)(?: +${PATH})?${OPTS}`,
  `dotnet format(?: +${PATH})? --verify-no-changes${OPTS}`,
  `dotnet ef migrations (?:list|add ${NAME}|script(?: +${NAME}(?: +${NAME})?)?)${OPTS}`,
  `dotnet list(?: +${PATH})? package(?: +(?:--vulnerable|--include-transitive|--outdated|--deprecated))*`,
].map((f) => new RegExp(`^${f}${TAIL}$`));

// Directory.Build.rsp na pasta de start (ou na pasta dele, se start é arquivo ou não existe) ou em alguma acima dela
function rspAbove(start) {
  let dir = resolve(start);
  if (!existsSync(dir) || !statSync(dir).isDirectory()) dir = dirname(dir);
  for (; ; dir = dirname(dir)) {
    if (existsSync(join(dir, 'Directory.Build.rsp'))) return true;
    if (dirname(dir) === dir) return false;
  }
}

// Exportada para o path-guard (com allow_module = dotnet), que não pede nestas formas pela citação de caminho.
export function allowed(cmd, cwd) {
  if (typeof cmd !== 'string' || cmd.length > 2000) return false;
  for (const re of FORMS) {
    const m = re.exec(cmd);
    if (!m) continue;
    if (/(^|[ /])\.\.(\/| |$)/.test(cmd)) return false;
    if (m[1] !== undefined && !inTempDir(m[1])) return false;
    // o cwd e cada palavra que é caminho (projeto, --project, --startup-project, --include), da pasta dela até a raiz
    const paths = cmd.split(/ +/).filter((w) => /^[A-Za-z0-9._/][A-Za-z0-9._/-]*$/.test(w));
    return ![cwd, ...paths.map((w) => resolve(cwd, w))].some(rspAbove);
  }
  return false;
}

// Só lê a entrada quando roda como o hook, não quando o path-guard importa allowed
if (basename(process.argv[1] ?? '') === 'dotnet-allow.mjs') {
  let d = '';
  process.stdin.on('data', (c) => (d += c)).on('end', () => {
    let j;
    try { j = JSON.parse(d); } catch { return; }
    if (allowed(j?.tool_input?.command, String(j?.cwd ?? process.cwd()))) process.stdout.write('ALLOW');
  });
}
