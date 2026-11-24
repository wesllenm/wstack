// Veredito do redirect-guard.sh (payload do PreToolUse em Bash na entrada padrão). Imprime ASK <motivo> ou nada.
// Um comando liberado por prefixo no allow (git status, dotnet build...) grava por redirecionamento em qualquer arquivo,
// e no modo automático e no acceptEdits o Claude Code não aplica ao redirecionamento as regras ask de Edit (só as deny):
// provado com a 2.1.328 (prove-redirect-guard.sh), "git status --short > .gitignore" sobrescreveu o .gitignore.
// Daí a regra, por lista do que é permitido: todo comando com o caractere > pede aprovação, salvo as formas fechadas
// abaixo. Redirecionamento de saída sem o caractere > não existe no bash. O texto é lido sem interpretar aspas: um >
// entre aspas também pede aprovação (sobra para o lado seguro).
// - formas livres, seguidas de fronteira ASCII (espaço, tab, quebra de linha, ; & | ou parêntese) ou do fim: N>&M
//   (só duplica descritor) e > >> >| &> &>> (com ou sem descritor antes) para /dev/null, /dev/stdout, /dev/stderr ou
//   um caminho absoluto literal na pasta temporária, fora do projeto (closed-forms.mjs: sem aspas, expansão nem glob).
//   A segurança está só no alvo: o que vem antes do > não muda para onde ele grava;
// - o commit da skill commit (git commit -F - <<'EOF'): com o delimitador entre aspas, o corpo não redireciona nada.
// Na VM descartável da nuvem (CLAUDE_CODE_REMOTE=true) o hook não pede nada: trava por texto do comando é contornável
// (cp /dev/null .cl""aude/x, tee, sed -i passam) e custava pedido por > que não redirecionava (grep "X =>"). O que
// importa na VM é o que SAI dela: push-guard e checkpoint.sh conferem os caminhos protegidos do que será publicado
// (docs/decisions.md, trava por texto na nuvem). O desenvolvedor, na máquina dele, segue com a regra acima.
import { inTempDir, isCommitHeredoc } from './closed-forms.mjs';

const TARGET = '[A-Za-z0-9._/+=:@-]+';
// O [0-9]* é tentado em cada posição de uma sequência de dígitos (custo quadrático): um comando com 75 mil dígitos
// estourava o prazo de 10 s do hook, que é erro não bloqueante, e o comando passava. Comando maior que MAX pede
// aprovação sem passar pela regex (até MAX, o pior caso medido fica abaixo de 1 s).
const FORMS = new RegExp(`(?:[0-9]*>&[0-9]+|(?:[0-9]*>>?\\|?|&>>?)[ \\t]*(${TARGET}))(?=$|[ \\t\\n;&|)])`, 'g');
const MAX = 20000;
const DEV = /^\/dev\/(null|stdout|stderr)$/;

let d = '';
process.stdin.on('data', (c) => (d += c)).on('end', () => {
  let cmd;
  try { cmd = JSON.parse(d)?.tool_input?.command; } catch { process.stdout.write('ASK payload ilegível'); return; }
  if (process.env.CLAUDE_CODE_REMOTE === 'true') return;
  if (typeof cmd !== 'string' || !cmd.includes('>')) return;
  if (cmd.length > MAX) { process.stdout.write(`ASK comando com > maior que ${MAX} caracteres`); return; }
  if (isCommitHeredoc(cmd)) return;
  const rest = cmd.replace(FORMS, (all, to) => (to === undefined || DEV.test(to) || inTempDir(to) ? ' ' : all));
  if (rest.includes('>')) process.stdout.write('ASK comando com redirecionamento (>) para arquivo: o Claude Code não aplica as regras ask de Edit ao redirecionamento no modo automático; só /dev/null, 2>&1 e a pasta temporária saem livres');
});
