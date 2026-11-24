// Sonda 2 do wstack, passo C: um hook Node do plugin importa um módulo da mesma pasta e um de outra pasta do plugin.
// Para `echo wstack-sonda-node`, nega com um motivo montado pelos dois módulos (o agente vê o motivo em qualquer modo de
// permissão). Para o número 5 do passo B, aprova: prova se a aprovação vinda de hook dispensa a regra allow.
import { mesmaPasta } from './sonda-modulo.mjs';
import { outraPasta } from '../lib/sonda-comum.mjs';

let input = '';
process.stdin.on('data', (c) => (input += c)).on('end', () => {
  let cmd = '';
  try {
    cmd = JSON.parse(input).tool_input?.command ?? '';
  } catch {
    return;
  }
  const out = (decision, reason) =>
    process.stdout.write(
      JSON.stringify({
        hookSpecificOutput: { hookEventName: 'PreToolUse', permissionDecision: decision, permissionDecisionReason: reason },
      }) + '\n',
    );
  if (cmd === 'echo wstack-sonda-node') {
    out('deny', `wstack-sonda-node: hook Node rodou; módulo da mesma pasta: ${mesmaPasta}; módulo de outra pasta: ${outraPasta}`);
  } else if (/^bash \S*\/scripts\/sonda-allow\.sh 5$/.test(cmd)) {
    out('allow', 'wstack-sonda-node: aprovação vinda de hook para o número 5');
  }
});
