defmodule ObanEvents.DispatchWorker do
  @moduledoc """
  Generic Oban worker that dispatches events to their handlers.

  This worker:
  1. Receives an event name, handler module, data, and idempotency key from job args
  2. Converts strings back to atoms safely
  3. Creates an Event struct with the data and idempotency key
  4. Calls the handler's `handle_event/2` callback
  5. Logs success/failure for observability

  ## Job arguments

  - `event_name`: String representation of the event name
  - `handler_module`: String representation of the handler module
  - `events_module`: String representation of the events module (for exhausted callback)
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
            "event_name" => event_name_string,
            "handler_module" => handler_module_string,
            "data" => data,
            "event_id" => event_id,
            "idempotency_key" => idempotency_key
          } = args,
        attempt: attempt,
        max_attempts: max_attempts
      } = job) do
    # Safely convert strings back to atoms
    # These atoms should already exist since they were created during emit
    event_name = String.to_existing_atom(event_name_string)
    handler_module = String.to_existing_atom(handler_module_string)

    # Create Event struct with all metadata
    event_struct = %Event{
      data: data,
      event_id: event_id,
      idempotency_key: idempotency_key,
      causation_id: Map.get(args, "causation_id"),
      correlation_id: Map.get(args, "correlation_id")
    }

    Logger.info("Processing event: #{event_name} with handler: #{inspect(handler_module)}")

    case handler_module.handle_event(event_name, event_struct) do
      :ok ->
        Logger.info("Event processed successfully: #{event_name} by #{inspect(handler_module)}")
        :ok

      {:ok, result} ->
        Logger.info(
          "Event processed successfully: #{event_name} by #{inspect(handler_module)}, result: #{inspect(result)}"
        )

        :ok

      {:error, reason} = error ->
        Logger.error(
          "Event handler failed: #{event_name} by #{inspect(handler_module)}, error: #{inspect(reason)}"
        )

        # Check if this is the final attempt
        if attempt >= max_attempts do
          handle_exhausted(args, event_name, handler_module, event_struct, reason, job)
        end

        # Return error to trigger Oban retry (or mark as discarded if final attempt)
        error

      other ->
        Logger.warning(
          "Event handler returned unexpected value: #{inspect(other)} for #{event_name} by #{inspect(handler_module)}"
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

    {:error, "Invalid job arguments: missing event_name, handler_module, or data"}
  end

  # Called when a handler exhausts all retry attempts
  defp handle_exhausted(args, event_name, handler_module, event_struct, error, job) do
    # Always log as a safety net
    Logger.warning("""
    Event handler exhausted all retry attempts.

    Event: #{inspect(event_name)}
    Handler: #{inspect(handler_module)}
    Event ID: #{event_struct.event_id}
    Job ID: #{job.id}
    Error: #{inspect(error)}
    """)

    # Call custom handler from events module
    module_string = args["events_module"]

    try do
      events_module = String.to_existing_atom(module_string)
      events_module.handle_exhausted(event_name, handler_module, event_struct, error)
    rescue
      e ->
        Logger.error(
          "Failed to call custom handle_exhausted/4: #{inspect(e)}. " <>
            "Ensure #{module_string}.handle_exhausted/4 is defined correctly."
        )

        :ok
    end
  end
end
