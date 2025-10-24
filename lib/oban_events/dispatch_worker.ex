defmodule ObanEvents.DispatchWorker do
  @moduledoc """
  Generic Oban worker that dispatches events to their handlers.

  This worker:
  1. Receives an event name, handler module, data, and idempotency key from job args
  2. Converts strings back to atoms safely
  3. Creates an EventData struct with the data and idempotency key
  4. Calls the handler's `handle_event/2` callback
  5. Logs success/failure for observability

  ## Job arguments

  - `event`: String representation of the event name
  - `handler`: String representation of the handler module
  - `data`: Map of event-specific data
  - `event_id`: UUIDv7 string identifying this emit (shared by all handlers)
  - `idempotency_key`: UUIDv7 string for deduplication (unique per job)
  - `causation_id`: Optional event ID that caused this emit
  - `correlation_id`: Optional ID grouping related events

  ## Configuration

  Queue, max_attempts, and priority are configured per events module
  when using `ObanEvents`. Jobs are created with these settings via
  `new/2` options.

  ## Observability

  All event processing is logged at INFO level for successful processing
  and ERROR level for failures. Check Oban Web UI for job history.
  """

  use Oban.Worker

  require Logger

  alias ObanEvents.Event

  @impl Oban.Worker
  def perform(%Oban.Job{
        args:
          %{
            "event" => event_name_string,
            "handler" => handler_module_string,
            "data" => data,
            "event_id" => event_id,
            "idempotency_key" => idempotency_key
          } = args
      }) do
    # Safely convert strings back to atoms
    # These atoms should already exist since they were created during emit
    event = String.to_existing_atom(event_name_string)
    handler = String.to_existing_atom(handler_module_string)

    # Create Event struct with all metadata
    event_struct = %Event{
      data: data,
      event_id: event_id,
      idempotency_key: idempotency_key,
      causation_id: Map.get(args, "causation_id"),
      correlation_id: Map.get(args, "correlation_id")
    }

    Logger.info("Processing event: #{event} with handler: #{inspect(handler)}")

    case handler.handle_event(event, event_struct) do
      :ok ->
        Logger.info("Event processed successfully: #{event} by #{inspect(handler)}")
        :ok

      {:ok, result} ->
        Logger.info(
          "Event processed successfully: #{event} by #{inspect(handler)}, result: #{inspect(result)}"
        )

        :ok

      {:error, reason} = error ->
        Logger.error(
          "Event handler failed: #{event} by #{inspect(handler)}, error: #{inspect(reason)}"
        )

        # Return error to trigger Oban retry
        error

      other ->
        Logger.warning(
          "Event handler returned unexpected value: #{inspect(other)} for #{event} by #{inspect(handler)}"
        )

        # Treat unexpected returns as success to avoid retry loops
        :ok
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    Logger.error(
      "DispatchWorker received invalid job arguments: job_id=#{job.id}, args=#{inspect(args)}"
    )

    {:error, "Invalid job arguments: missing event, handler, or data"}
  end
end
