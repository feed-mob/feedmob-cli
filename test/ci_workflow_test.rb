# frozen_string_literal: true

require_relative 'test_helper'

class CiWorkflowTest < Minitest::Test
  def test_workflow_runs_ruby_quality_gates_for_main_and_pull_requests
    workflow_path = File.expand_path('../.github/workflows/ci.yml', __dir__)
    assert File.exist?(workflow_path), 'Expected a GitHub Actions CI workflow.'

    workflow = File.read(workflow_path)

    assert_match(/^on:\n  pull_request:\n  push:\n    branches: \[main\]/, workflow)
    assert_includes workflow, 'uses: ruby/setup-ruby@v1'
    assert_includes workflow, 'bundle exec rake test'
    assert_includes workflow, 'bundle exec rubocop --format simple'
    assert_includes workflow, 'gem build feedmob-cli.gemspec'
  end

  def test_release_workflow_assembles_from_the_bump_commit_and_resumes_pending_versions
    workflow_path = File.expand_path('../.github/workflows/release.yml', __dir__)
    workflow = File.read(workflow_path)

    assert_includes workflow, 'needs: [validate, bump, build]'
    assert_includes workflow, 'Reusing unreleased source version $next.'
    assert_includes workflow, 'Source version must not be older than the latest release.'
  end
end
