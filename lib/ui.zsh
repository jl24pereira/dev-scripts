# Utilidades compartidas (gum + git) para los scripts de dev-scripts.
# Uso:  source ${0:A:h}/lib/ui.zsh

UI_LOG=${XDG_CACHE_HOME:-$HOME/.cache}/dev-scripts/last.log
mkdir -p ${UI_LOG:h}

ok()     { gum style --foreground 2 "✓ $*" }
warn()   { gum style --foreground 3 "⚠ $*" }
err()    { gum style --foreground 1 "✗ $*" >&2 }
info()   { gum style --foreground 6 "$*" }
dim()    { gum style --foreground 8 "$*" }
banner() { gum style --foreground ${2:-2} --border rounded --padding "0 2" "$1" }

# run "mensaje" cmd args...  → spinner; si falla muestra la salida (gum spin la oculta)
run() {
  local msg=$1; shift
  if gum spin --spinner dot --title "$msg..." -- zsh -c '"$@" >"$0" 2>&1' $UI_LOG "$@"; then
    return 0
  fi
  err "$msg falló:"
  tail -n 20 $UI_LOG | sed 's/^/  /' >&2
  return 1
}

# Cancelar con Esc/Ctrl+C en cualquier gum → salir sin ruido
cancel() { warn "Operación cancelada"; exit 0 }

require_repo() {
  git rev-parse --git-dir >/dev/null 2>&1 || { err "No estás en un repositorio git"; exit 1 }
}

has_upstream() { git rev-parse -q --verify '@{u}' >/dev/null 2>&1 }
is_dirty()     { [[ -n $(git status --porcelain --untracked-files=no) ]] }

# Rama base del equipo: $GIT_BASE, o develop > main > master en origin
base_branch() {
  [[ -n $GIT_BASE ]] && { print -r -- $GIT_BASE; return }
  local b
  for b in develop main master; do
    git show-ref -q --verify refs/remotes/origin/$b && { print $b; return }
  done
  git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||'
}

# fetch con timeout para no colgarse sin VPN
quick_fetch() {
  gum spin --spinner dot --title "Consultando remoto..." -- timeout ${GIT_FETCH_TIMEOUT:-15} git fetch --quiet --prune "$@" \
    || warn "No pude consultar el remoto (¿VPN?). Uso datos locales."
}
