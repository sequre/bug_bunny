# frozen_string_literal: true

require_relative 'rails_helper'
require 'rails/generators'
require 'stringio'
require 'tmpdir'
require 'generators/bug_bunny/install/install_generator'

# El generador de instalación no escribe nada fuera de lo que la gema necesita: ni crea ni modifica
# el `CLAUDE.md` del repo que la usa (sequre/bug_bunny#72).
RSpec.describe BugBunny::Generators::InstallGenerator do
  let(:template) { File.expand_path('../../lib/generators/bug_bunny/install/templates/initializer.rb', __dir__) }

  # Corre el generador sobre `dir` y devuelve lo que imprimió.
  def run_generator(dir)
    output = StringIO.new
    original_stdout = $stdout
    $stdout = output
    described_class.start([], destination_root: dir)
    output.string
  ensure
    $stdout = original_stdout
  end

  around do |example|
    Dir.mktmpdir('bug_bunny-generator') do |dir|
      @dir = dir
      example.run
    end
  end

  let(:claude_md) { File.join(@dir, 'CLAUDE.md') }

  it 'does not create CLAUDE.md' do
    run_generator(@dir)

    expect(File.exist?(claude_md)).to be(false)
  end

  it 'leaves an existing CLAUDE.md untouched' do
    original = "# App\n\n## Gemas internas\n"
    File.write(claude_md, original)

    run_generator(@dir)

    expect(File.read(claude_md)).to eq(original)
  end

  it 'still creates the initializer and the controllers directory' do
    run_generator(@dir)

    expect(File.read(File.join(@dir, 'config/initializers/bug_bunny.rb'))).to eq(File.read(template))
    expect(File.exist?(File.join(@dir, 'app/bug_bunny/controllers/.keep'))).to be(true)
  end

  it 'does not mention CLAUDE.md nor bug_bunny:sync in its output' do
    output = run_generator(@dir)

    expect(output).not_to include('CLAUDE.md')
    expect(output).not_to include('bug_bunny:sync')
  end

  it 'only runs the initializer and directories steps' do
    expect(described_class.all_tasks.keys).to eq(%w[create_initializer create_directories])
  end
end
