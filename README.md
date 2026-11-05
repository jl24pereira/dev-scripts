# Dev Scripts

Scripts de automatización para entorno de desarrollo WSL2 (zsh + gum).

## ds: todos los scripts en un solo lugar

```zsh
~/dev-scripts/ds install   # una vez: accesos en ~/.local/bin (ds, dev, git-commit…)

ds                         # menú: escribe "commit", "rama", "gradle"… y Enter lo ejecuta
ds ls                      # lista todos, agrupados, con su descripción
ds git-commit              # ejecuta uno directo (igual que llamarlo por su nombre)
```

Un script nuevo en esta carpeta aparece solo en `ds`; su descripción es la 2ª línea (`# …`).

| Script | Qué hace |
|---|---|
| `ds` | Índice: busca y ejecuta cualquiera de estos scripts |
| `dev.zsh` | Ambiente local tipo EKS + AWS: k3d + Floci, despliegue, API Gateway |
| `git-status` | Rama, sincronía con el remoto, stashes, archivos por estado |
| `git-branch` | Rama con prefijo (`feature/`…) desde `origin/develop` actualizada |
| `git-switch` | Cambia de rama (búsqueda, recientes primero), stash si hay cambios |
| `git-commit` | Conventional commit con scope y ticket detectado de la rama |
| `git-push` | Publica ramas nuevas, protege `develop`/`main`, rebase si lo rechazan |
| `git-mergeback` | Integra la rama actual en otra de forma segura |
| `git-history` | Historial, blame, búsquedas y qué trae tu rama vs la base |
| `gradle-run` | Menú de tasks de Gradle (bootRun con perfil, un test, Sonar) |
| `spring-new` | Proyecto Spring Boot, opcionalmente con `k8s/` de otro proyecto |
| `docker-start` | Inicia Docker en WSL2 (systemd o service) |

Todos usan `lib/ui.zsh` (estilos, spinner que muestra el error si algo falla).

### Variables opcionales

| Variable | Uso | Por defecto |
|---|---|---|
| `GIT_BASE` | Rama base del equipo | develop → main → master |
| `BRANCH_PREFIXES` | Prefijos de `git-branch` | `feature bugfix hotfix release chore` |
| `GIT_FETCH_TIMEOUT` | Segundos máximos de `git fetch` | 15 |
| `SONAR_HOST` / `SONAR_HOST_URL`, `SONAR_TOKEN` | Sonar (el token nunca se imprime) | — |
| `SONAR_BRANCH` | Rama en Sonar | develop |
| `SPRING_GROUP`, `SPRING_DEFAULT_DEPS` | Valores por defecto de `spring-new` | — |
| `DEV_PROJECTS` | Carpeta de proyectos (`dev`, `spring-new`) | `~/projects` |

## dev.zsh

```zsh
alias dev=~/dev-scripts/dev.zsh

dev                      # menú
dev on / dev off         # enciende / apaga Docker, Floci y k3d (ver abajo)
dev deploy               # proyecto de la carpeta actual
dev -p hola-mundo apply  # otro proyecto desde cualquier carpeta
dev overview             # estado de todos los proyectos de ~/projects
dev aws                  # recursos AWS (colas, tablas, buckets…)
dev apigw                # API Gateway: elegir, ver y quitar rutas
dev render k8s qa        # rellena $(variables) del bloque qa (antes render.sh)
dev help
```

**Proyecto activo:** `-p` → carpeta actual (si tiene `k8s/vars.yaml`) → último usado.
Desde el menú, "Cambiar proyecto" lista los de `$DEV_PROJECTS` (por defecto `~/projects`).

### Claves de `k8s/vars.yaml` (bloque `local`)

```yaml
local:
  appName: hola-mundo          # obligatoria
  namespace: local             # local
  containerPort: 8080          # 8080
  repository: hola-mundo       # appName
  imageTag: local              # local
  dockerfile: Dockerfile       # Dockerfile
  gradleTask: build -x test    # false para no compilar fuera de Docker
  dockerBuildArgs:             # → --build-arg (mapa o lista "K=v")
    BASE_IMAGE: eclipse-temurin:21-jre
```

### Encender y apagar

| Comando | Qué hace |
|---|---|
| `dev on` | arranca Docker si está apagado (pide sudo), luego Floci y k3d |
| `dev on floci` / `dev on k3d` | solo uno |
| `dev off` | pregunta: todo, solo k3d, solo Floci, o todo + Docker |
| `dev off all` · `k3d` · `floci` · `docker` | directo; `docker` libera la memoria de WSL |

Apagar no borra nada (clúster, imágenes, datos de Floci). En el menú, **⏻ Encender / apagar**
ofrece solo lo que tiene sentido según lo que esté encendido. Si al encender Floci no tiene
recursos (por ejemplo, sin datos persistentes), ofrece crear los de `stack/aws/`.

### Recursos AWS en Floci (`stack/aws/<proyecto>.yaml`)

Solo para la simulación local: los recursos de las cuentas reales se despliegan con
CloudFormation desde su propio repo y pipeline. Un archivo por proyecto declara colas (con DLQ), tópicos y suscripciones, tablas (con GSI y
datos semilla), buckets, secretos y parámetros. Ver `stack/aws/ejemplo.yaml.example`.

| Comando | Qué hace |
|---|---|
| `dev aws ls` | lista por servicio: mensajes por cola y su DLQ, ítems por tabla, objetos por bucket, de qué archivo viene cada uno y qué falta crear |
| `dev aws apply [archivo…]` | crea lo que falta (`+`), deja lo que existe (`=`); sin argumentos eliges archivos |
| `dev aws new` | formulario para crear uno y, al final, guardarlo en un archivo para que sea reproducible |
| `dev aws rm` | eliminar: elegidos de una lista, todo lo de un archivo, o vaciar todo (los archivos no se tocan) |
| `dev aws test` | enviar, ver, consumir y purgar mensajes; publicar en SNS; ver ítems, secretos, parámetros y objetos |

Los valores `${VAR}` (ej. claves en secretos) se toman de tu entorno al crear, así no quedan
escritos en los archivos. Ver mensajes de una cola cuenta para su `maxReceiveCount`.

### API Gateway (`stack/apigw/<app>.yaml`)

| Comando | Qué hace |
|---|---|
| `dev apigw publish [archivo…]` | publica archivos completos; sin argumentos eliges archivos o rutas sueltas (se marcan las activas) |
| `dev apigw ls` | rutas publicadas → backend, y avisa si alguna activa no está publicada (ej. tras reiniciar Floci) |
| `dev apigw rm` | quitar rutas sueltas, las de un archivo o todo el API |
| `dev apigw clear` | borra el API y los Services `-apigw` |

La selección de rutas activas se recuerda y el API se reconstruye con ella cada vez, con el
mismo ID (`local`), así la URL no cambia: `http://localhost:4566/restapis/local/local/_user_request_/<ruta>`.
Solo quedan Services `-apigw` en k3d para las apps con rutas activas.
`DRY_RUN=1 dev apigw publish …` muestra qué haría sin tocar nada.

### Comportamiento

- **deploy / apply** renderizan `k8s/` y añaden la anotación
  `dev-scripts/restarted-at` al Deployment: cada apply hace **un** rollout que toma la
  imagen nueva y los cambios de ConfigMap/Secret.
- Antes de aplicar se crea el namespace si falta y se le conecta Floci
  (Service + EndpointSlice `floci` y ConfigMap `aws-local`), así que cualquier namespace sirve.
- Floci: usa `stack/floci/compose.yaml` si existe; si no, un compose embebido
  (`floci/floci`, IP fija `172.18.0.10`, datos persistentes en el volumen `floci-data`).
- La red `aws-local` se crea con `--ip-range 172.18.128.0/17` para que k3d nunca
  tome IPs fijas como la de Floci (solo aplica a redes nuevas).

- `kubectl` siempre usa `--context k3d-local` y `aws` siempre el endpoint de Floci con
  credenciales de prueba: `dev` no puede tocar EKS ni tu cuenta real por accidente.

### stack/

```
stack/
  aws/<proyecto>.yaml     # recursos AWS (ver ejemplo.yaml.example)
  apigw/<app>.yaml        # rutas del API Gateway (ver hola-mundo.yaml.example)
  floci/compose.yaml      # opcional: tu compose de Floci (si no, el embebido)
```

Si tenías `~/projects/local-env/`, mueve `api/routes.d/*.yaml` a `stack/apigw/` y
`compose.yaml` a `stack/floci/`.
