# frozen_string_literal: true

# App Rails mínima para probar el Railtie de BugBunny con Rails de verdad (ActiveRecord sobre SQLite
# en memoria).
#
# Rails se inicializa una vez por proceso, así que estos specs corren en su propio proceso
# (`rake spec:rails`): la suite de `spec/` sigue probando la gema fuera de Rails. Para bootear con
# otra configuración, el spec corre este archivo solo, en un subproceso (`ruby spec/rails/app.rb`),
# y lee la cadena de middlewares que imprime.
#
# `BUG_BUNNY_SPEC_EXECUTOR=off` bootea con `config.consumer_rails_executor = false`.

ENV['RAILS_ENV'] = 'test'
ENV['DATABASE_URL'] = 'sqlite3::memory:'

require 'bundler/setup'
require 'logger'
require 'rails'
require 'active_record/railtie'
require 'bug_bunny'

module BugBunnyRailsSpec
  # La app: sin archivos de configuración propios, todo acá.
  class Application < Rails::Application
    config.root = __dir__
    config.eager_load = false
    config.logger = Logger.new(nil)
    config.secret_key_base = 'bug_bunny-rails-spec'
  end

  # Lo que un mensaje deja por hilo: lo que los specs miran pasar (o no) al siguiente.
  class LeftoverState < ActiveSupport::CurrentAttributes
    attribute :value
  end

  # Contexto de traza, como el `ExisRay::Tracer` de ExisRay: un `CurrentAttributes`.
  class TraceContext < ActiveSupport::CurrentAttributes
    attribute :trace_id
  end

  # Un middleware que carga estado por hilo antes de procesar el mensaje y lo limpia al salir, como
  # el de tracing de ExisRay. Se registra ANTES de que el Railtie de BugBunny registre el suyo: es el
  # orden que hace falta para ver si el executor lo borra.
  class TracingMiddleware < BugBunny::ConsumerMiddleware::Base
    def call(delivery_info, properties, body)
      TraceContext.trace_id = 'from-tracing'
      @app.call(delivery_info, properties, body)
    ensure
      TraceContext.reset
    end
  end
end

BugBunny.configure do |config|
  config.logger = Logger.new(nil)
  # El `respond_to?` deja correr estos specs contra una versión de la gema sin la opción, para ver
  # que fallan sin el cambio.
  if config.respond_to?(:consumer_rails_executor=)
    config.consumer_rails_executor = ENV['BUG_BUNNY_SPEC_EXECUTOR'] != 'off'
  end
end
BugBunny.consumer_middlewares.use(BugBunnyRailsSpec::TracingMiddleware)

BugBunnyRailsSpec::Application.initialize!

puts BugBunny.consumer_middlewares.instance_variable_get(:@middlewares).map(&:name) if $PROGRAM_NAME == __FILE__
