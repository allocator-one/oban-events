defmodule ObanEvents.Test.Repo do
  @moduledoc """
  Minimal test Repo for ObanEvents testing.

  This repo is used for Oban.Testing which requires a repo parameter.
  It doesn't need to be started or configured for the inline testing mode.
  """
  use Ecto.Repo,
    otp_app: :oban_events,
    adapter: Ecto.Adapters.Postgres
end
