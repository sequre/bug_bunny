require 'bundler/gem_tasks'
require 'rake/testtask'
require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec) do |t|
  t.rspec_opts = '--require spec_helper'
  t.exclude_pattern = 'spec/rails/**/*_spec.rb'
end

RSpec::Core::RakeTask.new('spec:unit') do |t|
  t.pattern  = 'spec/unit/**/*_spec.rb'
  t.rspec_opts = '--require spec_helper'
end

RSpec::Core::RakeTask.new('spec:integration') do |t|
  t.pattern  = 'spec/integration/**/*_spec.rb'
  t.rspec_opts = '--require spec_helper'
end

# Los specs que necesitan Rails (el Railtie) bootean una app propia, y Rails se inicializa una vez por
# proceso: corren aparte, para que el resto de la suite siga probando la gema fuera de Rails.
RSpec::Core::RakeTask.new('spec:rails') do |t|
  t.pattern = 'spec/rails/**/*_spec.rb'
end

# Mantiene la tarea :test apuntando a los tests de integración legacy de Minitest
Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.libs << 'lib'
  t.test_files = FileList['test/**/*_test.rb']
  t.verbose    = true
  t.warning    = false
end

# Las dos suites, cada una en su proceso: es lo que corren `quality-code` y `gem-release`.
task default: [:spec, 'spec:rails']
