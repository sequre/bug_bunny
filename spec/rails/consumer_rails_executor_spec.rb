# frozen_string_literal: true

require_relative 'rails_helper'
require 'open3'

# Cada mensaje del Consumer corre dentro del executor de Rails (sequre/bug_bunny#70).
#
# Las entregas se procesan en un hilo propio, como el hilo de trabajo de Bunny: Rails no lo conoce.
RSpec.describe 'BugBunny::ConsumerMiddleware::RailsExecutor' do
  let(:channel) do
    double('channel').tap do |ch|
      allow(ch).to receive(:ack)
      allow(ch).to receive(:reject)
      allow(ch).to receive(:open?).and_return(true)
    end
  end

  let(:consumer) do
    session = instance_double(BugBunny::Session, channel: channel, close: nil)
    described_consumer = BugBunny::Consumer.new(double('connection'))
    described_consumer.instance_variable_set(:@session, session)
    described_consumer
  end

  let(:properties) do
    double('properties', type: 'probe/show', headers: { 'x-http-method' => 'GET' },
                         correlation_id: 'corr-1', reply_to: nil, content_type: 'application/json')
  end

  # Lo que hace la acción del controller en cada entrega.
  let(:on_message) { -> {} }

  before do
    allow(BugBunny.routes).to receive(:recognize)
      .and_return({ controller: 'probe', action: 'show', params: {}, namespace: nil })

    handler = on_message
    stub_const('BugBunny::Controllers::ProbeController', Class.new(BugBunny::Controller) do
      define_method(:show) do
        handler.call
        render status: 200, json: {}
      end
    end)
  end

  # Procesa las entregas en orden, en un hilo propio (como el de Bunny).
  def deliver_on_a_bunny_like_thread(*tags)
    Thread.new do
      tags.each do |tag|
        delivery_info = double('delivery_info', exchange: 'x', routing_key: 'probe', delivery_tag: tag,
                                                redelivered?: false)
        yield(:before, tag) if block_given?
        consumer.send(:handle_delivery, delivery_info, properties, '{}')
        yield(:after, tag) if block_given?
      end
    end.join
  end

  it 'queda primero en la cadena, antes del middleware de tracing registrado antes que él' do
    middlewares = BugBunny.consumer_middlewares.instance_variable_get(:@middlewares).map(&:name)

    expect(middlewares).to eq(%w[BugBunny::ConsumerMiddleware::RailsExecutor BugBunnyRailsSpec::TracingMiddleware])
  end

  describe 'el estado por hilo no pasa de un mensaje al siguiente' do
    let(:seen) { [] }
    let(:on_message) do
      lambda do
        seen << BugBunnyRailsSpec::LeftoverState.value
        BugBunnyRailsSpec::LeftoverState.value = 'left by the previous message'
      end
    end

    it 'el segundo mensaje arranca sin lo que el primero dejó en un CurrentAttributes' do
      deliver_on_a_bunny_like_thread(1, 2)

      expect(seen).to eq([nil, nil])
    end
  end

  describe 'la conexión de ActiveRecord' do
    # Si el hilo tiene una conexión tomada del pool (en Rails 8.1, `active_connection?` devuelve la
    # conexión, o nil).
    def connection_leased?
      ActiveRecord::Base.connection_pool.active_connection?.present?
    end

    let(:inside) { [] }
    let(:on_message) do
      lambda do
        ActiveRecord::Base.connection.execute('SELECT 1')
        inside << connection_leased?
      end
    end

    it 'vuelve al pool al terminar el mensaje que la usó' do
      after = []
      deliver_on_a_bunny_like_thread(1) do |moment, _tag|
        after << connection_leased? if moment == :after
      end

      expect(inside).to eq([true]) # el mensaje la usó
      expect(after).to eq([false]) # y al terminar ya no la tiene el hilo
    end
  end

  describe 'un middleware que carga estado antes que el executor' do
    let(:seen) { [] }
    let(:on_message) { -> { seen << BugBunnyRailsSpec::TraceContext.trace_id } }

    it 'conserva ese estado dentro del mensaje: el executor lo envuelve y no lo borra' do
      deliver_on_a_bunny_like_thread(1)

      expect(seen).to eq(['from-tracing'])
    end
  end

  describe 'un error que escapa del procesamiento del mensaje' do
    let(:reports) { [] }
    let(:subscriber) do
      collected = reports
      Class.new do
        define_method(:report) { |error, handled:, **| collected << [error.message, handled] }
      end.new
    end

    before { Rails.error.subscribe(subscriber) }
    after { Rails.error.unsubscribe(subscriber) if Rails.error.respond_to?(:unsubscribe) } # no existe en Rails 7.0

    it 'termina en un reject sin requeue, como hoy, y además se reporta a Rails.error' do
      allow(consumer).to receive(:process_message).and_raise(RuntimeError, 'boom')

      deliver_on_a_bunny_like_thread(7)

      expect(channel).to have_received(:reject).with(7, false)
      expect(reports).to eq([['boom', false]])
    end
  end

  describe 'config.consumer_rails_executor' do
    # Rails se inicializa una vez por proceso: la app se bootea de nuevo en un subproceso.
    # Las líneas de stdout que nombran un middleware: un warning del entorno no las rompe.
    def middlewares_after_boot(env)
      app = File.expand_path('app.rb', __dir__)
      stdout, stderr, status = Open3.capture3(env, RbConfig.ruby, app)
      raise "la app no booteó:\n#{stderr}" unless status.success?

      stdout.lines.map(&:strip).grep(/\ABugBunny/)
    end

    it 'con false, no registra el middleware' do
      expect(middlewares_after_boot('BUG_BUNNY_SPEC_EXECUTOR' => 'off')).to eq(['BugBunnyRailsSpec::TracingMiddleware'])
    end

    it 'con true, lo registra primero' do
      expect(middlewares_after_boot('BUG_BUNNY_SPEC_EXECUTOR' => 'on'))
        .to eq(%w[BugBunny::ConsumerMiddleware::RailsExecutor BugBunnyRailsSpec::TracingMiddleware])
    end

    it 'sin BugBunny.configure previo, bootea y lo registra: la opción ausente vale su default' do
      expect(middlewares_after_boot('BUG_BUNNY_SPEC_CONFIGURE' => 'none'))
        .to eq(['BugBunny::ConsumerMiddleware::RailsExecutor'])
    end
  end
end
