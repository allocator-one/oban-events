defmodule ObanEventsTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias ObanEvents.DispatchWorker

  # Test handler module
  defmodule TestHandler do
    @moduledoc false
    use ObanEvents.Handler

    @impl true
    def handle_event(_event, %Event{}), do: :ok
  end

  # Test events module with handlers registered (uses defaults)
  defmodule TestEvents do
    @moduledoc false
    use ObanEvents

    alias ObanEventsTest.TestHandler

    @events %{
      investment_status_changed: [TestHandler],
      investment_created: [TestHandler],
      investment_cancelled: [],
      portfolio_company_added: [],
      portfolio_company_removed: [],
      portfolio_fund_added: [],
      portfolio_fund_removed: []
    }
  end

  # Test events module with custom configuration including extra Oban opts
  defmodule CustomConfigEvents do
    @moduledoc false
    use ObanEvents,
      oban:
        {Oban,
         queue: :custom_queue,
         max_attempts: 10,
         priority: 0,
         tags: ["custom"],
         meta: %{"global" => "metadata"}}

    @events %{
      test_event: [ObanEventsTest.TestHandler]
    }
  end

  # Test events module with per-handler options
  defmodule PerHandlerOptionsEvents do
    @moduledoc false
    use ObanEvents

    @events %{
      multi_handler_event: [
        {TestHandler, oban: [priority: 0, max_attempts: 5, tags: ["critical"]]},
        {TestHandler, oban: [queue: :low_priority, priority: 3]},
        TestHandler
      ]
    }
  end

  describe "emit/2" do
    test "creates Oban jobs for registered event handlers" do
      event_data = %{
        "investment_id" => Ecto.UUID.generate(),
        "account_id" => Ecto.UUID.generate(),
        "old_status" => "pending",
        "new_status" => "active_closed"
      }

      # emit/2 now returns {:ok, jobs} consistently in test and production
      assert {:ok, jobs} = TestEvents.emit(:investment_status_changed, event_data)
      assert length(jobs) == 1

      # Verify job was executed with correct data
      [job] = jobs
      assert job.worker == "ObanEvents.DispatchWorker"
      assert job.state == "completed"
      assert job.args["event_name"] == "investment_status_changed"
      assert job.args["handler_module"] == "Elixir.ObanEventsTest.TestHandler"
      assert job.args["data"] == event_data
    end

    test "creates multiple jobs when multiple handlers are registered" do
      event_data = %{
        "investment_id" => Ecto.UUID.generate(),
        "account_id" => Ecto.UUID.generate()
      }

      # investment_created has one handler currently
      assert {:ok, jobs} = TestEvents.emit(:investment_created, event_data)
      assert length(jobs) == 1
    end

    test "raises ArgumentError for unregistered events" do
      assert_raise ArgumentError, ~r/Unknown event: :unknown_event/, fn ->
        TestEvents.emit(:unknown_event, %{"data" => "value"})
      end
    end

    test "applies global Oban options including extra options like meta" do
      assert {:ok, [job]} = CustomConfigEvents.emit(:test_event, %{"test" => "data"})

      # Verify core options
      assert job.queue == "custom_queue"
      assert job.max_attempts == 10
      assert job.priority == 0
      assert job.tags == ["custom"]

      # Verify extra options are passed through from global config
      assert job.meta == %{"global" => "metadata"}
    end

    # Note: Transaction behavior (emit within Ecto.Repo.transaction, rollback, etc.)
    # should be tested in the consuming application with its specific Repo setup.
    # ObanEvents.emit/2 uses Oban.insert_all which participates in the current
    # transaction if one exists, but we don't test that here since this library
    # doesn't provide its own Repo.

    test "requires event_name to be an atom" do
      assert_raise FunctionClauseError, fn ->
        TestEvents.emit("string_event", %{})
      end
    end

    test "requires data to be a map" do
      assert_raise FunctionClauseError, fn ->
        TestEvents.emit(:event_name, "not a map")
      end
    end
  end

  describe "configuration" do
    test "uses default configuration when not specified" do
      assert {:ok, jobs} = TestEvents.emit(:investment_created, %{"test" => "data"})

      [job] = jobs
      # Defaults: queue: :oban_events, max_attempts: 3, priority: 2
      assert job.queue == "oban_events"
      assert job.max_attempts == 3
      assert job.priority == 2
    end

    test "uses custom configuration when specified" do
      assert {:ok, jobs} = CustomConfigEvents.emit(:test_event, %{"test" => "data"})

      [job] = jobs
      # Custom: queue: :custom_queue, max_attempts: 10, priority: 0, tags: ["custom"]
      assert job.queue == "custom_queue"
      assert job.max_attempts == 10
      assert job.priority == 0
      assert job.tags == ["custom"]
    end

    test "per-handler options override global defaults" do
      assert {:ok, jobs} =
               PerHandlerOptionsEvents.emit(:multi_handler_event, %{"test" => "data"})

      assert length(jobs) == 3

      [job1, job2, job3] = jobs

      # First handler: custom priority, max_attempts, and tags
      assert job1.priority == 0
      assert job1.max_attempts == 5
      assert job1.tags == ["critical"]
      # Uses global default
      assert job1.queue == "oban_events"

      # Second handler: custom queue and priority
      assert job2.queue == "low_priority"
      assert job2.priority == 3
      # Uses global default
      assert job2.max_attempts == 3
      # Uses global default
      assert job2.tags == []

      # Third handler: all defaults
      assert job3.queue == "oban_events"
      assert job3.priority == 2
      assert job3.max_attempts == 3
      assert job3.tags == []
    end

    test "passes through any Oban option, not just the core ones" do
      defmodule EventsWithExtraOpts do
        use ObanEvents, oban: {Oban, queue: :default, meta: %{"global" => "value"}}

        @events %{
          delayed_event: [
            {ObanEventsTest.TestHandler, oban: [schedule_in: 60, meta: %{"source" => "test"}]}
          ]
        }
      end

      {:ok, [job]} = EventsWithExtraOpts.emit(:delayed_event, %{"test" => "data"})

      # Verify core options work
      assert job.queue == "default"

      # Verify per-handler options override global options
      # Per-handler meta should override global meta
      assert job.meta == %{"source" => "test"}

      # schedule_in was applied (job should be scheduled, not immediate)
      # In test mode with inline execution, this still creates a scheduled_at
      assert job.scheduled_at != nil
    end
  end

  describe "handle_exhausted/4" do
    # Failing handler for testing exhausted callback
    defmodule FailingHandler do
      @moduledoc false
      use ObanEvents.Handler

      @impl true
      def handle_event(_event, %Event{}) do
        {:error, :always_fails}
      end
    end

    # Events module with custom exhausted handler
    defmodule EventsWithExhaustedHandler do
      @moduledoc false
      use ObanEvents, oban: {Oban, max_attempts: 1}

      @events %{
        failing_event: [ObanEventsTest.FailingHandler]
      }

      # Track calls to handle_exhausted
      def handle_exhausted(event_name, handler_module, event, error) do
        send(self(), {:exhausted_called, event_name, handler_module, event, error})
        :ok
      end
    end

    # Events module without custom exhausted handler (uses default)
    defmodule EventsWithDefaultExhausted do
      @moduledoc false
      use ObanEvents, oban: {Oban, max_attempts: 1}

      @events %{
        failing_event: [ObanEventsTest.FailingHandler]
      }
    end

    test "calls custom handle_exhausted/4 when handler fails max_attempts times" do
      # Emit event that will fail
      assert {:ok, [job]} = EventsWithExhaustedHandler.emit(:failing_event, %{"test" => "data"})

      # Job should be discarded after max_attempts with error
      assert job.state == "discarded"

      # Should have received exhausted callback
      assert_received {:exhausted_called, :failing_event, ObanEventsTest.FailingHandler, event,
                       :always_fails}

      assert event.data == %{"test" => "data"}
      assert event.event_id != nil
    end

    test "uses default handler when handle_exhausted/4 is not overridden" do
      # Capture logs to verify warning is logged
      log =
        capture_log(fn ->
          assert {:ok, [job]} =
                   EventsWithDefaultExhausted.emit(:failing_event, %{"test" => "data"})

          assert job.state == "discarded"
        end)

      # Should log warning with event details
      assert log =~ "Event handler exhausted all retry attempts"
      assert log =~ "Event: :failing_event"
      assert log =~ "Handler: ObanEventsTest.FailingHandler"
      assert log =~ "Error: :always_fails"

      # Default handler doesn't send messages, just logs
      refute_received {:exhausted_called, _, _, _, _}
    end

    test "stores events_module in job args" do
      assert {:ok, [job]} = EventsWithExhaustedHandler.emit(:failing_event, %{"test" => "data"})

      assert job.args["events_module"] ==
               "Elixir.ObanEventsTest.EventsWithExhaustedHandler"
    end

    test "handles crashing custom handle_exhausted/4 gracefully" do
      # Events module with crashing exhausted handler
      defmodule EventsWithCrashingExhausted do
        @moduledoc false
        use ObanEvents, oban: {Oban, max_attempts: 1}

        @events %{
          failing_event: [ObanEventsTest.FailingHandler]
        }

        # This will crash
        def handle_exhausted(_event_name, _handler_module, _event, _error) do
          raise "Crash in handle_exhausted"
        end
      end

      # Should log error but not crash the worker
      log =
        capture_log(fn ->
          assert {:ok, [job]} =
                   EventsWithCrashingExhausted.emit(:failing_event, %{"test" => "data"})

          assert job.state == "discarded"
        end)

      # Should log warning from worker
      assert log =~ "Event handler exhausted all retry attempts"
      # Should log error about failed callback
      assert log =~ "Failed to call custom handle_exhausted/4"
    end
  end
end
