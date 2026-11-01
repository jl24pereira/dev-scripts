#!/usr/bin/env bash
# Publica en Floci un API Gateway REST local a partir de los archivos de rutas
# (uno por microservicio) en ~/projects/local-env/api/routes.d/*.yaml
#
# Cada ejecución reconstruye el API completo con el mismo ID, así la URL no cambia.
#
# Uso:  apigw.sh            → publica
#       DRY_RUN=1 apigw.sh  → solo muestra lo que haría
set -euo pipefail
 
ROUTES_DIR=${ROUTES_DIR:-$HOME/projects/local-env/api/routes.d}
API_ID=${API_ID:-local}                    # ID fijo del API en Floci
STAGE=${STAGE:-local}
NODE_HOST=${NODE_HOST:-k3d-local-server-0} # nodo k3d, alcanzable desde Floci por la red aws-local
FLOCI=${FLOCI:-http://localhost:4566}
DRY_RUN=${DRY_RUN:-0}
 
say()  { printf '%s\n' "$*"; }
fail() { printf '✘ %s\n' "$*" >&2; exit 1; }
 
# Llamada al AWS CLI contra Floci (en DRY_RUN solo imprime y devuelve un ID falso)
awsf() {
  if [[ $DRY_RUN == 1 ]]; then
    printf '  aws %s\n' "$*" >&2
    echo "id$RANDOM"
  else
    aws --profile floci --output text "$@"
  fi
}
 
shopt -s nullglob
FILES=("$ROUTES_DIR"/*.yaml)
(( ${#FILES[@]} > 0 )) || fail "No hay archivos de rutas en $ROUTES_DIR"
 
# ---------------------------------------------------------------- validación
declare -A SEEN_PORT SEEN_ROUTE
for f in "${FILES[@]}"; do
  app=$(yq '.app // ""' "$f"); port=$(yq '.localPort // ""' "$f")
  [[ -n $app && -n $port ]] || fail "$(basename "$f"): faltan 'app' o 'localPort'"
  [[ -z ${SEEN_PORT[$port]:-} ]] || fail "localPort $port repetido en $(basename "$f") y ${SEEN_PORT[$port]}"
  SEEN_PORT[$port]=$(basename "$f")
  while IFS=$'\t' read -r m p; do
    key="$m $p"
    [[ -z ${SEEN_ROUTE[$key]:-} ]] || fail "Ruta duplicada '$key' en $(basename "$f") y ${SEEN_ROUTE[$key]}"
    SEEN_ROUTE[$key]=$(basename "$f")
  done < <(yq -r '.routes[] | [(.method | upcase), .path] | @tsv' "$f")
done
 
# ---------------------------------------------------------------- 1) acceso de Floci al clúster
say "▸ Exponiendo microservicios para el API Gateway"
MANIFEST=$(mktemp)
for f in "${FILES[@]}"; do
  cat >>"$MANIFEST" <<EOF
---
apiVersion: v1
kind: Service
metadata:
  name: $(yq '.app' "$f")-apigw
  namespace: $(yq '.namespace // "local"' "$f")
  labels:
    local-env/apigw: "true"
spec:
  type: LoadBalancer
  selector:
    app: $(yq '.app' "$f")
  ports:
    - name: http
      port: $(yq '.localPort' "$f")
      targetPort: $(yq '.containerPort // 8080' "$f")
EOF
done
if [[ $DRY_RUN == 1 ]]; then cat "$MANIFEST"; else kubectl apply -f "$MANIFEST" >/dev/null; fi
rm -f "$MANIFEST"
 
# ---------------------------------------------------------------- 2) API Gateway
say "▸ Reconstruyendo API Gateway '$API_ID' en Floci"
[[ $DRY_RUN == 1 ]] || aws --profile floci apigateway delete-rest-api --rest-api-id "$API_ID" >/dev/null 2>&1 || true
awsf apigateway create-rest-api --name local-gateway \
  --endpoint-configuration types=REGIONAL \
  --tags "{\"floci:override-id\":\"$API_ID\"}" --query id >/dev/null
 
declare -A RES
if [[ $DRY_RUN == 1 ]]; then
  RES[/]=root
else
  RES[/]=$(aws --profile floci --output text apigateway get-resources --rest-api-id "$API_ID" --query "items[?path=='/'].id")
fi
 
# Crea (si falta) cada segmento de la ruta; deja el ID en RID
ensure_resource() {
  local path=$1
  if [[ -n ${RES[$path]:-} ]]; then RID=${RES[$path]}; return; fi
  local parent=${path%/*}; [[ -z $parent ]] && parent=/
  ensure_resource "$parent"
  RID=$(awsf apigateway create-resource --rest-api-id "$API_ID" --parent-id "$RID" \
        --path-part "${path##*/}" --query id)
  RES[$path]=$RID
}
 
ROUTES_OUT=()
for f in "${FILES[@]}"; do
  port=$(yq '.localPort' "$f")
  while IFS=$'\t' read -r method path target; do
    ensure_resource "$path"
 
    # Parámetros de ruta: {channelId} o {proxy+} → se pasan tal cual al backend
    mparams=(); iparams=()
    for p in $(grep -o '{[^}]*}' <<<"$path" || true); do
      name=${p//[\{\}+]/}
      mparams+=("\"method.request.path.$name\":true")
      iparams+=("\"integration.request.path.$name\":\"method.request.path.$name\"")
    done
    mextra=(); iextra=()
    if (( ${#mparams[@]} > 0 )); then
      mextra=(--request-parameters "{$(IFS=,; echo "${mparams[*]}")}")
      iextra=(--request-parameters "{$(IFS=,; echo "${iparams[*]}")}")
    fi
 
    awsf apigateway put-method --rest-api-id "$API_ID" --resource-id "$RID" \
      --http-method "$method" --authorization-type NONE "${mextra[@]}" >/dev/null
    awsf apigateway put-integration --rest-api-id "$API_ID" --resource-id "$RID" \
      --http-method "$method" --type HTTP_PROXY --integration-http-method "$method" \
      --uri "http://$NODE_HOST:$port${target}" "${iextra[@]}" >/dev/null
 
    ROUTES_OUT+=("$(printf '%-7s %s' "$method" "$FLOCI/restapis/$API_ID/$STAGE/_user_request_$path")")
  done < <(yq -r '.routes[] | [(.method | upcase), .path, (.target // .path)] | @tsv' "$f")
done
 
awsf apigateway create-deployment --rest-api-id "$API_ID" --stage-name "$STAGE" >/dev/null
 
say "✔ API Gateway publicado. Rutas:"
printf '  %s\n' "${ROUTES_OUT[@]}"
