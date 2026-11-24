#!/usr/bin/env bash
# Hook Notification: avisa no sistema operacional quando uma sessão precisa de você (permissão ou espera
# de resposta), com a branch no título, para saber qual atividade está parada sem alternar entre terminais.
# Windows (Git Bash ou WSL) por notificação do PowerShell; macOS por osascript; Linux por notify-send; senão, o sino
# do terminal. Roda em segundo plano e sai com 0 sempre: aviso que falha não pode atrapalhar a sessão.
# Título e mensagem nunca são interpolados em código: o PowerShell os lê de variáveis de ambiente e o osascript, de argv
# (o nome de uma branch ou o texto da mensagem não pode virar comando).
set -uo pipefail
input=$(cat)

msg=$(printf '%s' "$input" | sed -n 's/.*"message"[[:space:]]*:[[:space:]]*"\(\([^"\\]\|\\.\)*\)".*/\1/p' | sed 's/\\"/"/g; s/\\\\/\\/g')
msg=${msg:-a sessão está esperando você}
cd "${CLAUDE_PROJECT_DIR:-.}" 2> /dev/null || true
where=$(git symbolic-ref --short -q HEAD 2> /dev/null || basename "$PWD")
title="Claude Code: $where"
msg=${msg:0:200}; title=${title:0:80}

send() {
  if command -v powershell.exe > /dev/null 2>&1 && command -v iconv > /dev/null 2>&1; then
    local ps enc
    read -r -d '' ps <<'PS'
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > $null
$x = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
$n = $x.GetElementsByTagName("text")
$n.Item(0).AppendChild($x.CreateTextNode($env:WSTACK_NOTIFY_T)) > $null
$n.Item(1).AppendChild($x.CreateTextNode($env:WSTACK_NOTIFY_M)) > $null
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe").Show([Windows.UI.Notifications.ToastNotification]::new($x))
PS
    enc=$(printf '%s' "$ps" | iconv -f UTF-8 -t UTF-16LE | base64 | tr -d '\n')
    WSTACK_NOTIFY_T=$title WSTACK_NOTIFY_M=$msg WSLENV="${WSLENV:+$WSLENV:}WSTACK_NOTIFY_T:WSTACK_NOTIFY_M" \
      powershell.exe -NoProfile -NonInteractive -EncodedCommand "$enc" > /dev/null 2>&1 && return 0
  fi
  if command -v osascript > /dev/null 2>&1; then
    osascript -e 'on run argv' -e 'display notification (item 2 of argv) with title (item 1 of argv)' -e 'end run' "$title" "$msg" > /dev/null 2>&1 && return 0
  fi
  if command -v notify-send > /dev/null 2>&1; then notify-send -- "$title" "$msg" > /dev/null 2>&1 && return 0; fi
  { printf '\a' > /dev/tty; } 2> /dev/null || true
}

( send & ) > /dev/null 2>&1
exit 0
