# frozen_string_literal: true

module BugBunny
  module ConsumerMiddleware
    # Envuelve cada mensaje con el executor de Rails, como hace Sidekiq con cada job.
    #
    # El Consumer procesa los mensajes en el hilo de trabajo de Bunny, que Rails no conoce. Sin
    # el executor, lo que Rails guarda por hilo pasa de un mensaje al siguiente:
    # - los `ActiveSupport::CurrentAttributes` (y lo que vive en ellos: tags, trazas, métricas);
    # - la conexión de ActiveRecord, que el hilo retiene hasta morir en vez de devolverla al pool;
    # - la caché de queries.
    #
    # Lo registra el Railtie al principio de la cadena (ver {Stack#prepend}) salvo que
    # `config.consumer_rails_executor` sea `false`. Fuera de Rails no se carga.
    #
    # **Errores:** `executor.wrap` relanza lo que escapa del mensaje, así que sigue el camino de
    # siempre (el Consumer lo rechaza sin requeue). En Rails >= 7.1, antes de relanzar, además lo
    # reporta a `Rails.error` con `handled: false`.
    #
    # Si el hilo ya está dentro del executor, `wrap` no abre otro: sólo ejecuta el bloque.
    class RailsExecutor < Base
      # @param delivery_info [Bunny::DeliveryInfo]
      # @param properties [Bunny::MessageProperties]
      # @param body [String]
      # @return [void]
      def call(delivery_info, properties, body)
        ::Rails.application.executor.wrap { @app.call(delivery_info, properties, body) }
      end
    end
  end
end
