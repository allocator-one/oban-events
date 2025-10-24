defmodule ObanEvents.DispatchWorkerTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: ObanEvents.Test.Repo

  import ExUnit.CaptureLog

  alias ObanEvents.DispatchWorker

  # Mock handler for testing
  defmodule TestHandler do
    @moduledoc false
    use ObanEvents.Handler

    def handle_event(:test_event, %Event{data: %{"action" => "success"}}) do
      send(self(), {:handler_called, :test_event, %{"action" => "success"}})
      :ok
    end

    def handle_event(:test_event, %Event{data: %{"action" => "error"}}) do
      send(self(), {:handler_called, :test_event, %{"action" => "error"}})
      {:error, :test_error}
    end

    def handle_event(:test_event, %Event{data: %{"action" => "raise"}}) do
      raise "Test exception"
    end

    def handle_event(:test_event, %Event{data: %{"action" => "success_with_result"}}) do
      send(self(), {:handler_called, :test_event, %{"action" => "success_with_result"}})
      {:ok, %{processed: true, count: 42}}
    end

    def handle_event(:test_event, %Event{data: %{"action" => "unexpected"}}) do
      send(self(), {:handler_called, :test_event, %{"action" => "unexpected"}})
      :unexpected_return_value
    end

    def handle_event(_event, %Event{}), do: :ok
  end

  describe "perform/1" do
    test "successfully processes event and calls handler" do
      job_args = %{
        "event" => "test_event",
        "handler" => "Elixir.ObanEvents.DispatchWorkerTest.TestHandler",
        "data" => %{"action" => "success"},
        "event_id" => UUIDv7.generate(),
        "idempotency_key" => UUIDv7.generate()
      }

      assert :ok = perform_job(DispatchWorker, job_args)

      assert_received {:handler_called, :test_event, %{"action" => "success"}}
    end

    test "returns error when handler returns error" do
      job_args = %{
        "event" => "test_event",
        "handler" => "Elixir.ObanEvents.DispatchWorkerTest.TestHandler",
        "data" => %{"action" => "error"},
        "event_id" => UUIDv7.generate(),
        "idempotency_key" => UUIDv7.generate()
      }

      log =
        capture_log(fn ->
          assert {:error, :test_error} = perform_job(DispatchWorker, job_args)
        end)

      assert log =~ "Event handler failed"
      assert_received {:handler_called, :test_event, %{"action" => "error"}}
    end

    test "handles handler exceptions gracefully" do
      job_args = %{
        "event" => "test_event",
        "handler" => "Elixir.ObanEvents.DispatchWorkerTest.TestHandler",
        "data" => %{"action" => "raise"},
        "event_id" => UUIDv7.generate(),
        "idempotency_key" => UUIDv7.generate()
      }

      assert_raise RuntimeError, "Test exception", fn ->
        perform_job(DispatchWorker, job_args)
      end
    end

    test "returns error for invalid job arguments" do
      # Missing required fields
      job_args = %{
        "handler" => "SomeHandler",
        "data" => %{}
      }

      log =
        capture_log(fn ->
          assert {:error, _} = perform_job(DispatchWorker, job_args)
        end)

      assert log =~ "DispatchWorker received invalid job arguments"
    end

    test "returns error for invalid handler module" do
      job_args = %{
        "event" => "test_event",
        "handler" => "NonExistent.Handler.Module",
        "data" => %{},
        "event_id" => UUIDv7.generate(),
        "idempotency_key" => UUIDv7.generate()
      }

      assert_raise ArgumentError, fn ->
        perform_job(DispatchWorker, job_args)
      end
    end

    test "handles {:ok, result} return value" do
      job_args = %{
        "event" => "test_event",
        "handler" => "Elixir.ObanEvents.DispatchWorkerTest.TestHandler",
        "data" => %{"action" => "success_with_result"},
        "event_id" => UUIDv7.generate(),
        "idempotency_key" => UUIDv7.generate()
      }

      assert :ok = perform_job(DispatchWorker, job_args)
      assert_received {:handler_called, :test_event, %{"action" => "success_with_result"}}
    end

    test "handles unexpected return value gracefully" do
      job_args = %{
        "event" => "test_event",
        "handler" => "Elixir.ObanEvents.DispatchWorkerTest.TestHandler",
        "data" => %{"action" => "unexpected"},
        "event_id" => UUIDv7.generate(),
        "idempotency_key" => UUIDv7.generate()
      }

      log =
        capture_log(fn ->
          assert :ok = perform_job(DispatchWorker, job_args)
        end)

      assert log =~ "Event handler returned unexpected value"
      assert_received {:handler_called, :test_event, %{"action" => "unexpected"}}
    end
  end

  describe "Oban configuration" do
    test "accepts queue option" do
      changeset =
        DispatchWorker.new(
          %{
            "event" => "test",
            "handler" => "Test",
            "data" => %{}
          },
          queue: :custom_queue
        )

      assert changeset.changes.queue == "custom_queue"
    end

    test "accepts priority option" do
      changeset =
        DispatchWorker.new(
          %{
            "event" => "test",
            "handler" => "Test",
            "data" => %{}
          },
          priority: 0
        )

      assert changeset.changes.priority == 0
    end

    test "accepts max_attempts option" do
      changeset =
        DispatchWorker.new(
          %{
            "event" => "test",
            "handler" => "Test",
            "data" => %{}
          },
          max_attempts: 10
        )

      assert changeset.changes.max_attempts == 10
    end

    test "accepts all options together" do
      changeset =
        DispatchWorker.new(
          %{
            "event" => "test",
            "handler" => "Test",
            "data" => %{}
          },
          queue: :high_priority,
          max_attempts: 5,
          priority: 0
        )

      assert changeset.changes.queue == "high_priority"
      assert changeset.changes.priority == 0
      assert changeset.changes.max_attempts == 5
    end
  end
end
