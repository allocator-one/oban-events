# Compile test support modules
Code.require_file("support/repo.ex", __DIR__)

# Start Oban for testing with inline mode
# This allows tests to run and execute jobs immediately
{:ok, _} = Application.ensure_all_started(:postgrex)
{:ok, _} = Application.ensure_all_started(:ecto)

# Start Oban in test mode with inline execution
# This doesn't require a real database connection
{:ok, _} =
  Oban.start_link(
    repo: ObanEvents.Test.Repo,
    notifier: Oban.Notifiers.PG,
    testing: :inline,
    queues: false,
    plugins: false
  )

ExUnit.start()
