defmodule ObanEvents.TestingTest do
  use ExUnit.Case, async: true

  import ObanEvents.Testing

  alias ObanEvents.Event

  describe "build_event/2" do
    test "builds event with generated IDs by default" do
      data = %{"user_id" => 123, "email" => "test@example.com"}

      event = build_event(data)

      assert %Event{} = event
      assert event.data == data
      assert is_binary(event.event_id)
      assert is_binary(event.idempotency_key)
      assert event.causation_id == nil
      assert event.correlation_id == nil
    end

    test "accepts custom metadata options" do
      data = %{"test" => "data"}

      event =
        build_event(data,
          event_id: "custom-event-id",
          idempotency_key: "custom-idempotency-key",
          causation_id: "parent-event-id",
          correlation_id: "correlation-id"
        )

      assert event.data == data
      assert event.event_id == "custom-event-id"
      assert event.idempotency_key == "custom-idempotency-key"
      assert event.causation_id == "parent-event-id"
      assert event.correlation_id == "correlation-id"
    end

    test "generates unique IDs for each call" do
      event1 = build_event(%{})
      event2 = build_event(%{})

      assert event1.event_id != event2.event_id
      assert event1.idempotency_key != event2.idempotency_key
    end

    test "works with empty data map" do
      event = build_event(%{})

      assert event.data == %{}
      assert is_binary(event.event_id)
    end
  end
end
