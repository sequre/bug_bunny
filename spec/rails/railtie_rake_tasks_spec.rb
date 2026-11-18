# frozen_string_literal: true

require_relative 'rails_helper'
require 'rake'

# El Railtie no registra tareas de rake: la que había, `bug_bunny:sync`, escribía el `CLAUDE.md` del repo
# que usa la gema (sequre/bug_bunny#72).
RSpec.describe 'BugBunny::Railtie rake tasks' do
  before(:all) do
    Rake.application = Rake::Application.new
    Rails.application.load_tasks
  end

  it 'does not define bug_bunny:sync' do
    expect(Rake::Task.task_defined?('bug_bunny:sync')).to be(false)
  end

  it 'loads the application tasks' do
    expect(Rake::Task.task_defined?('environment')).to be(true)
  end
end
