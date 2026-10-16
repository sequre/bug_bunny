# frozen_string_literal: true

require 'spec_helper'

# Fuera de Rails la gema se comporta como antes de sequre/bug_bunny#70: el middleware del executor
# lo registra el Railtie, y el Railtie no se carga.
RSpec.describe 'BugBunny fuera de Rails' do
  it 'no carga el Railtie' do
    expect(defined?(Rails)).to be_nil
    expect(defined?(BugBunny::Railtie)).to be_nil
  end

  it 'no carga el middleware del executor ni lo pone en la cadena del Consumer' do
    middlewares = BugBunny.consumer_middlewares.instance_variable_get(:@middlewares).map(&:name)

    expect(defined?(BugBunny::ConsumerMiddleware::RailsExecutor)).to be_nil
    expect(middlewares).not_to include('BugBunny::ConsumerMiddleware::RailsExecutor')
  end
end
