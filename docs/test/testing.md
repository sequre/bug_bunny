# Test — bug_bunny

> meta: artefacto test · RFC-013 · generado `arch-structure` (§a-§d) +
> `arch-enrich` (§e-§h) · anclado a `35b075a` (squash de #65 en `main`; el ancla anterior `7bf1da7` no era ancestro de `main`), `Rakefile`, `bug_bunny.gemspec`,
> `spec/spec_helper.rb`, `spec/support/integration_helper.rb`,
> `.github/workflows/main.yml`, `CHANGELOG.md` · fecha 2026-07-22 · cobertura:
> §a-§d (estructura) + §e-§h (enrich, anclado a specs/CHANGELOG) completas.
> Incremento 2026-09-28 (#64): conteos, `drain_*_spec` y el gap de aislamiento.
> Incremento 2026-10-16 (#70): `spec/rails/` (Railtie con Rails de verdad), tarea
> `spec:rails` y conteos; **re-anclar al SHA del squash al mergear**; escrito por el agente, sin
> verificación humana todavía.

## 1. Resumen

Suite principal **RSpec** (`spec/`, 27 specs: 18 unit + 8 integration + 1 rails). Tarea
`:test` legacy de **Minitest** (`test/`, 2 archivos) fuera del default y del CI.
CI corre `bundle exec rake` en Ruby 3.4.4: el default corre `:spec` y `spec:rails`, cada una en
su proceso. `bundle exec rspec` pelado corre `spec/` sin Rails: `.rspec` excluye `spec/rails/` salvo que se lo pida
explícitamente (`bundle exec rspec spec/rails` la corre, en su propio proceso). Sin coverage tool
configurado.

## 2. Cuerpo

### a. Suites, frameworks y niveles

| framework | dir | nivel | nº | propósito |
|---|---|---|---|---|
| **RSpec** `~> 3.0` | `spec/unit/` | unit | 18 | client/session pool, configuration, consumer, `drain_tracker`, producer, controller, raise_error, remote_error, request, route, observability, otel, resource, middleware, `extra_top_level_params` (hook de params hermanos en `Resource#save`), `consumer_rails_executor_outside_rails` (fuera de Rails no se carga el Railtie ni el middleware del executor) |
| **RSpec** + `railties`/`activerecord`/`sqlite3` | `spec/rails/` | integration con Rails (sin broker) | 1 | `consumer_rails_executor`: una app Rails mínima (`spec/rails/app.rb`, ActiveRecord sobre SQLite en memoria) prueba que cada mensaje corre dentro del executor — el `CurrentAttributes` no pasa al siguiente, la conexión vuelve al pool, el orden frente a un middleware de tracing, el error que escapa (reject + `Rails.error`) y `consumer_rails_executor = false` (en subproceso) |
| **RSpec** | `spec/integration/` | integration | 8 | client, consumer_middleware, controller, drain, error_handling, infrastructure, publisher_confirms, resource — **requieren RabbitMQ real** (usan `BugBunny.create_connection` + pool) |
| **Minitest** `~> 5.0` (+ `mocha`, `minitest-reporters`) | `test/integration/` | integration (legacy) | 2 | `manual_client_test.rb`, `infrastructure_test.rb` — tarea `:test`, **no** en default ni CI |

Sin tags declarados (`:slow`/`:js`) en la config de RSpec.

### b. Comando de corrida

| objetivo | comando | qué corre |
|---|---|---|
| default / CI | `bundle exec rake` | `:spec` (la suite RSpec menos `spec/rails/`) y después `spec:rails`, cada una en su proceso — `Rakefile:` `task default: [:spec, 'spec:rails']` |
| `spec/` sin Rails | `bundle exec rspec` | todo `spec/` menos `spec/rails/` (lo excluye `.rspec` cuando no se pide `spec/rails` explícitamente) |
| solo unit | `bundle exec rake spec:unit` | `spec/unit/**/*_spec.rb` |
| solo integration | `bundle exec rake spec:integration` | `spec/integration/**/*_spec.rb` (requiere broker) |
| Railtie (Rails) | `bundle exec rake spec:rails` | `spec/rails/**/*_spec.rb`, en su propio proceso (Rails se inicializa una vez por proceso); equivale a `bundle exec rspec spec/rails` |
| Minitest legacy | `bundle exec rake test` | `test/**/*_test.rb` |
| CI | `.github/workflows/main.yml` → `bundle exec rake` | matrix Ruby `3.4.4`, `ruby/setup-ruby@v1` + `bundler-cache`, on push `main` + PR |

> Las tareas RSpec corren con `--require spec_helper` (`Rakefile`), salvo `spec:rails`, que
> carga su propio `spec/rails/rails_helper.rb`.

### c. Fixtures / Factories

- **Sin FactoryBot ni fixtures YAML.** El setup vive en `spec/spec_helper.rb`:
  configura `BugBunny` (host/user/pass desde ENV con default `guest`), arma un
  `ConnectionPool` de test (`TEST_POOL`, size 5) y declara rutas globales para
  todos los specs (`resources :ping/:node/:user`, `get 'around'/'rescue'/'boom'/
  'echo'`, `post 'events'`).
- **Carga `.env`** si existe (parse manual, `spec_helper.rb`).
- **Soporte:** `spec/support/integration_helper.rb` (helpers + `TEST_WORKER_QUEUE_OPTS`
  para colas efímeras), `spec/support/bunny_mocks.rb` (mocks de Bunny para unit).
- `exchange_options = { durable: false, auto_delete: true }` → exchanges efímeros
  en test.

### d. Configuración de coverage

**n/a** — sin SimpleCov ni `.simplecov` ni `SimpleCov.start` en el repo. No hay
umbral de coverage declarado.

### e. Gaps de cobertura

- **Integration specs no corren en CI:** `main.yml` no declara servicio RabbitMQ;
  las 8 integration specs **se skipean** vía `rabbitmq_available?`
  (`spec/support/integration_helper.rb:14`, ver `publisher_confirms_spec.rb:10`).
  En CI solo se ejercitan las **17 unit specs** → el contrato AMQP real (publish/
  consume/confirms contra broker) **no se valida en pipeline**, solo localmente
  con broker. Gap relevante.
- **Sin medición de cobertura:** no hay SimpleCov ni umbral → la cobertura no está
  cuantificada (no se sabe el % de líneas ejercidas).

### f. Contract-assessment

¿Los tests cubren los contratos públicos? (RFC-020/018/012/003)

| contrato | specs que lo cubren | veredicto |
|---|---|---|
| **Errores RFC-020** (status→excepción, materia prima) | `raise_error_spec`, `remote_error_spec`, `communication_error_wrapping_spec`, `error_handling_spec` (integration) | **bien cubierto** (unit) |
| **Consumed RFC-018** (Bunny::Exception→`CommunicationError`) | `communication_error_wrapping_spec`, `client_session_pool_spec` | cubierto (unit) |
| **Config RFC-012** (validaciones de `Configuration`) | `configuration_spec` | cubierto |
| **Consumer#drain** (drenar y salir, #64) | `drain_tracker_spec` (unit, reloj inyectado), `drain_spec` (integration) | cubierto; la parte integration skipea sin broker. Validado por mutación: quitar la espera, el retorno temprano o el chequeo de `busy?` hace fallar el test correspondiente |
| **Confirms** (`PublishNacked`/`PublishUnroutable`) | `producer_spec`, `publisher_confirms_spec` (integration) | parcial en CI (la parte integration skipea sin broker) |
| **Operaciones/routing** (RFC-003, capa F2) | `route_spec`, `request_spec`, `controller_spec`, `controller_after_action_spec`, `resource_spec` | cubierto (unit) |

- **Aislamiento entre specs — corregido 2026-09-28 (#64):** el `after` de
  `configuration_spec` reemplazaba la configuración global por una con defaults
  (`guest`), así que los specs de integración que corrían después se conectaban
  como `guest` y se **skipeaban como "RabbitMQ no disponible" aun con broker**.
  Cuántos, dependía del seed (11 en `main` con `--seed 1`). Ahora un `around`
  restaura la configuración original (`spec/unit/configuration_spec.rb:14-22`);
  medido con broker local: 311 examples, 0 failures, 0 pending en los seeds 1, 2 y 3.

### g. Link a incidente → test de regresión

| incidente | test de regresión | ancla |
|---|---|---|
| **#52** (`status`/`raw_response` en toda la jerarquía + hardening de `format_error_message`) | `raise_error_spec` — comentarios explícitos "Alcance issue #52" | `spec/unit/raise_error_spec.rb:59,120,169` |
| **#49** (leak de `Bunny::TCPConnectionFailedForAllHosts` en `try_create`) | `communication_error_wrapping_spec` — "Client#publish — TCP fail en try_create (issue #49 caso original)" | `spec/unit/communication_error_wrapping_spec.rb:41` |

### h. PII en fixtures / factories

- **Sin PII.** No hay fixtures con datos personales: `spec_helper` usa
  placeholders (`guest`/`localhost`), las rutas de test son `ping`/`node`/`user`
  **sin payloads de datos reales**, y `bunny_mocks.rb` mockea el driver. Cruza
  RFC-026: nada que clasificar/anonimizar. `confidence: high`.

## 3. Inferencias

- **Doble framework:** RSpec es el primario (default + CI); Minitest (`test/`,
  `mocha`, `minitest-reporters` en gemspec) es **legacy** — el comentario del
  `Rakefile` lo declara explícito ("tests de integración legacy de Minitest").
  `confidence: high`.
- ~~CI on `master` pero la rama principal es `main` (drift de naming)~~ →
  **resuelto** (`main.yml` ahora dispara `push: branches: [main]`). El trigger
  `push` corre en la rama por default; `pull_request` cubre los PRs.

## 4. Cobertura y fronteras

- §a-§d (estructura) + §e-§h (enrich, anclado a specs/CHANGELOG) **completas**.
- **Integration specs requieren un RabbitMQ vivo** y se skipean sin broker (§e) —
  por eso no se ejercitan en CI.
- **Contenido de cada test case** queda en el código, no se inventaria acá.
