defmodule ObanEvents.Handler do
  @moduledoc """
  Behaviour for event handlers.

  Event handlers process events asynchronously via Oban workers.
  Each handler implements a single callback: `handle_event/2`.

  See the [README](README.md) for architectural guidance and best practices.

  ## Implementing a Handler

      defmodule MyApp.UserHandler do
        use ObanEvents.Handler

        @impl true
        def handle_event(:user_created, %Event{data: data, idempotency_key: key}) do
          %{"user_id" => user_id} = data

          # Use idempotency_key for outbox pattern
          OutboxEmail.insert(%{
            idempotency_key: key,
            user_id: user_id
          }, on_conflict: :nothing, conflict_target: :idempotency_key)

          :ok
        end
      end

  ## Return Values

  Handlers should return:
  - `:ok` - Event processed successfully
  - `{:ok, result}` - Event processed successfully with a result
  - `{:error, reason}` - Event processing failed (will trigger Oban retry)

  ## Error Handling

  If a handler returns `{:error, reason}` or raises an exception, Oban will
  automatically retry the job according to the worker's retry configuration.

  ## Event Metadata

  Handlers receive an `ObanEvents.Event` struct with these fields:

  - **data** - Your event data (map with string keys)
  - **event_id** - Unique ID for this emit (shared by all handlers)
  - **idempotency_key** - Unique per job (for deduplication)
  - **causation_id** - Optional parent event_id (for event chains)
  - **correlation_id** - Optional business operation grouping

  See `ObanEvents.Event` documentation for detailed explanations of each field.

  ## Best Practices

  1. Keep handlers focused on a single concern
  2. Make handlers idempotent using `idempotency_key`
  3. Use `event_id` as `causation_id` when emitting child events
  4. Use `correlation_id` to group related business operations
  5. Log important actions for debugging
  6. Return errors for retriable failures, :ok for non-retriable ones
  """

  alias ObanEvents.Event

  @doc """
  Handle an event.

  Receives the event name (atom) and an Event struct containing the event data
  and metadata for tracing, deduplication, and correlation.

  ## Parameters

  - `event_name`: Atom representing the event (e.g., `:user_created`)
  - `event`: `ObanEvents.Event` struct with data and metadata fields

  ## Return Values

  - `:ok` | `{:ok, any()}` - Success
  - `{:error, any()}` - Failure (will trigger retry)
  """
  @callback handle_event(event_name :: atom(), event :: Event.t()) ::
              :ok | {:ok, any()} | {:error, any()}

  @doc false
  defmacro __using__(_opts) do
    quote do
      @behaviour ObanEvents.Handler
      alias ObanEvents.Event
    end
  end
end
