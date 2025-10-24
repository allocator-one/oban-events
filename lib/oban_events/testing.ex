defmodule ObanEvents.Testing do
  @moduledoc """
  Test helpers for ObanEvents handlers.

  Provides utilities to create Event structs for testing handlers without
  needing to manually construct all metadata fields.

  ## Usage

      defmodule MyApp.EmailHandlerTest do
        use ExUnit.Case
        import ObanEvents.Testing

        test "sends welcome email" do
          event = build_event(%{"user_id" => 123, "email" => "test@example.com"})

          assert :ok = MyApp.EmailHandler.handle_event(:user_created, event)
        end
      end

  ## Options

  You can override any metadata field:

      event = build_event(
        %{"user_id" => 123},
        event_id: "custom-event-id",
        causation_id: "parent-event-id",
        correlation_id: "correlation-id"
      )
  """

  alias ObanEvents.Event

  @doc """
  Builds an Event struct for testing.

  Automatically generates `event_id` and `idempotency_key` if not provided.
  Sets `causation_id` and `correlation_id` to `nil` by default.

  ## Examples

      iex> event = build_event(%{"user_id" => 123})
      %Event{
        data: %{"user_id" => 123},
        event_id: "01933b7e-...",
        idempotency_key: "01933b7e-...",
        causation_id: nil,
        correlation_id: nil
      }

      iex> event = build_event(%{"user_id" => 123},
            causation_id: "parent-event",
            correlation_id: "corr-123"
          )
      %Event{
        data: %{"user_id" => 123},
        event_id: "01933b7e-...",
        idempotency_key: "01933b7e-...",
        causation_id: "parent-event",
        correlation_id: "corr-123"
      }
  """
  @spec build_event(map(), keyword()) :: Event.t()
  def build_event(data, opts \\ []) when is_map(data) do
    %Event{
      data: data,
      event_id: Keyword.get(opts, :event_id, UUIDv7.generate()),
      idempotency_key: Keyword.get(opts, :idempotency_key, UUIDv7.generate()),
      causation_id: Keyword.get(opts, :causation_id),
      correlation_id: Keyword.get(opts, :correlation_id)
    }
  end
end
