#!/usr/bin/env bash
# Reemplaza $(variable) en las plantillas de k8s/, igual que el pipeline de Azure DevOps.
# Uso: ./render.sh <dir_k8s> [ambiente] [dir_salida]
#   ej: ./render.sh ~/projects/hola-mundo/k8s local
set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true   # bash 5.2: evita que '&' se interprete en reemplazos
 
SRC=${1:?"Uso: render.sh <dir_k8s> [ambiente] [dir_salida]"}
ENV_NAME=${2:-local}
OUT=${3:-$SRC/../.rendered/$ENV_NAME}
VARS="$SRC/vars.yaml"
 
yq --version 2>/dev/null | grep -q mikefarah || {
  echo "Necesito el yq de mikefarah (el de apt es otro programa)."; exit 1
}
[[ -f $VARS ]] || { echo "No encontré $VARS"; exit 1; }
 
# Aplana el bloque del ambiente en pares clave=valor (anidados con punto: limits.memory)
mapfile -t PAIRS < <(
  yq ".${ENV_NAME} // {}" "$VARS" |
    yq '.. | select(tag != "!!map" and tag != "!!seq") | (path | join(".")) + "=" + (. | to_string)'
)
[[ ${#PAIRS[@]} -gt 0 ]] || { echo "No encontré el bloque '${ENV_NAME}' en $VARS"; exit 1; }
 
mkdir -p "$OUT"
rm -f "$OUT"/*.yaml
 
pendientes=0
for f in "$SRC"/*.yaml; do
  name=$(basename "$f")
  [[ $name == vars.yaml ]] && continue
  content=$(<"$f")
  for p in "${PAIRS[@]}"; do
    k=${p%%=*}; v=${p#*=}
    content=${content//"\$($k)"/$v}
  done
  printf '%s\n' "$content" > "$OUT/$name"
  if grep -qE '\$\([A-Za-z0-9_.]+\)' "$OUT/$name"; then
    echo "✘ Variables sin valor en $name:"
    grep -noE '\$\([A-Za-z0-9_.]+\)' "$OUT/$name" | sed 's/^/   /'
    pendientes=1
  fi
done
 
if [[ $pendientes -ne 0 ]]; then
  echo "Agrega las variables faltantes al bloque '$ENV_NAME' de $VARS"
  exit 1
fi
echo "✔ Plantillas renderizadas en $OUT"
