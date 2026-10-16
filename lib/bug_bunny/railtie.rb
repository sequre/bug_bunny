# frozen_string_literal: true

require 'rails'

module BugBunny
  # Integración automática de BugBunny con el ciclo de vida de Ruby on Rails.
  #
  # Esta clase es responsable de:
  # 1. Registrar la carpeta `app/rabbit` en el autoloader de Rails (Zeitwerk).
  # 2. Gestionar la seguridad de las conexiones durante el "forking" de procesos (Puma/Spring).
  # 3. Envolver cada mensaje del Consumer con el executor de Rails (ver {ConsumerMiddleware::RailsExecutor}).
  #
  # @see https://guides.rubyonrails.org/engines.html#railtie
  class Railtie < ::Rails::Railtie
    # 1. Configuración de Autoload
    initializer 'bug_bunny.add_autoload_paths' do |app|
      rabbit_path = File.join(app.root, 'app', 'rabbit')
      app.config.paths.add 'app/rabbit', eager_load: true if Dir.exist?(rabbit_path)
    end

    # 2. Gestión de Forks (Puma / Spring / otros)
    #
    # Es vital cerrar la conexión heredada del proceso padre (Master) antes de que
    # el hijo empiece a trabajar, para evitar compartir el mismo socket TCP.
    config.after_initialize do
      # Estrategia 1: Rails 7.1+ ForkTracker (La forma estándar moderna)
      ActiveSupport::ForkTracker.after_fork { BugBunny.disconnect } if defined?(ActiveSupport::ForkTracker)

      # Estrategia 2: Hook específico de Puma (Legacy)
      # Solo intentamos usarlo si la API 'events' está disponible (Puma < 5).
      if defined?(Puma) && Puma.respond_to?(:events)
        Puma.events.on_worker_boot do
          BugBunny.disconnect
        end
      end
    end

    # 3. Executor de Rails alrededor de cada mensaje del Consumer
    #
    # El Consumer procesa en el hilo de Bunny, que Rails no conoce: sin esto, el estado por hilo
    # pasa de un mensaje al siguiente. Va al principio de la cadena (`prepend`, no `use`) para que
    # envuelva también a los middlewares que cargan ese estado, como el de tracing de ExisRay, que
    # se registra en su propio `after_initialize` y en un orden que no controlamos.
    config.after_initialize do
      if BugBunny.configuration.consumer_rails_executor
        require_relative 'consumer_middleware/rails_executor'
        BugBunny.consumer_middlewares.prepend(BugBunny::ConsumerMiddleware::RailsExecutor)
      end
    end

    # 4. Rake tasks (bug_bunny:sync)
    rake_tasks do
      load File.expand_path('../tasks/bug_bunny.rake', __dir__)
    end

    # 5. Hook de Spring (Preloader)
    if defined?(Spring)
      Spring.after_fork do
        BugBunny.disconnect
      end
    end
  end
end
