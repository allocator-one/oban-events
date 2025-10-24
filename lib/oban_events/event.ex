defmodule ObanEvents.Event do
  @moduledoc """
  Container for event data with metadata.

  Handlers receive event data wrapped in this struct, which includes
  the user's event data plus metadata for deduplication, causation tracking,
  and correlation.

  ## Fields

  - `:data` - The user's event data (map)
  - `:event_id` - Unique per emit. Identifies this specific emit event (shared by all handlers).
  - `:idempotency_key` - Unique per job. Use for deduplication/outbox patterns.
  - `:causation_id` - Optional. The event_id of the parent emit that caused this one.
  - `:correlation_id` - Optional. Groups related events from the same business operation.

  ## Metadata explained

  ### event_id (Auto-generated per emit)
  Identifies the emit itself. All handlers processing this emit receive the same event_id.
  Use as causation_id in child emits to build event chains.

      def handle_event(:user_created, %Event{event_id: id, data: data}) do
        # Pass parent's event_id as causation_id for child events
        Events.emit(:send_welcome_email, data, causation_id: id)
      end

  ### idempotency_key (Auto-generated per job)
  Unique for each handler job. Prevents duplicate processing when jobs retry.

      def handle_event(:send_email, %Event{idempotency_key: key, data: data}) do
        OutboxEmail.insert(%{
          idempotency_key: key,
          user_id: data["user_id"]
        }, on_conflict: :nothing, conflict_target: :idempotency_key)
      end

  ### causation_id (User-provided, optional)
  The event_id that caused this emit. Build audit trails and event chains.

      # Event chain:
      # user_registered (event_id: "evt-001", causation_id: nil)
      #   └─> send_welcome_email (event_id: "evt-002", causation_id: "evt-001")
      #       └─> email_delivered (event_id: "evt-003", causation_id: "evt-002")

  ### correlation_id (User-provided, optional)
  Groups related events from a single business operation across multiple emits.
  Useful for debugging complex workflows.

      correlation_id = UUIDv7.generate()
      Events.emit(:subscription_created, data, correlation_id: correlation_id)
      Events.emit(:payment_processed, data, correlation_id: correlation_id)
      Events.emit(:invoice_generated, data, correlation_id: correlation_id)
      # All logs filterable by this correlation_id
  """

  @type t :: %__MODULE__{
          data: map(),
          event_id: String.t(),
          idempotency_key: String.t(),
          causation_id: String.t() | nil,
          correlation_id: String.t() | nil
        }

  defstruct [
    :data,
    :event_id,
    :idempotency_key,
    :causation_id,
    :correlation_id
  ]
end
