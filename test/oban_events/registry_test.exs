defmodule ObanEvents.RegistryTest do
  use ExUnit.Case, async: true

  alias ObanEvents.Handler

  # Test event bus with various handler configurations
  defmodule TestRegistry do
    @moduledoc false
    use ObanEvents

    defmodule HandlerOne do
      @moduledoc false
      use Handler

      def handle_event(_event, _data), do: :ok
    end

    defmodule HandlerTwo do
      @moduledoc false
      use Handler

      def handle_event(_event, _data), do: :ok
    end

    @events %{
      # Event with multiple handlers
      multi_handler_event: [HandlerOne, HandlerTwo],

      # Event with single handler
      single_handler_event: [HandlerOne],

      # Event with no handlers
      no_handler_event: [],

      # Additional events for testing
      test_event_one: [HandlerOne],
      test_event_two: [HandlerTwo]
    }
  end

  describe "get_handlers!/1" do
    test "returns multiple handlers for event with multiple handlers" do
      handlers = TestRegistry.get_handlers!(:multi_handler_event)

      assert length(handlers) == 2
      assert TestRegistry.HandlerOne in handlers
      assert TestRegistry.HandlerTwo in handlers
    end

    test "returns single handler for event with one handler" do
      handlers = TestRegistry.get_handlers!(:single_handler_event)

      assert handlers == [TestRegistry.HandlerOne]
    end

    test "returns empty list for event with no handlers" do
      handlers = TestRegistry.get_handlers!(:no_handler_event)

      assert handlers == []
    end

    test "raises ArgumentError for unregistered events" do
      assert_raise ArgumentError, ~r/Unknown event: :unknown_event/, fn ->
        TestRegistry.get_handlers!(:unknown_event)
      end
    end

    test "error message includes list of known events" do
      error =
        assert_raise ArgumentError, fn ->
          TestRegistry.get_handlers!(:some_random_event)
        end

      assert error.message =~ "Known events:"
      assert error.message =~ ":multi_handler_event"
      assert error.message =~ ":single_handler_event"
    end

    test "error message suggests how to fix" do
      assert_raise ArgumentError, ~r/To register this event, add it to @events/, fn ->
        TestRegistry.get_handlers!(:another_unknown_event)
      end
    end

    test "error message includes the module name" do
      error =
        assert_raise ArgumentError, fn ->
          TestRegistry.get_handlers!(:not_registered)
        end

      assert error.message =~ inspect(TestRegistry)
    end
  end

  describe "all_events/0" do
    test "returns all registered event names" do
      events = TestRegistry.all_events()

      assert :multi_handler_event in events
      assert :single_handler_event in events
      assert :no_handler_event in events
      assert :test_event_one in events
      assert :test_event_two in events

      # Should return exactly 5 events
      assert length(events) == 5
    end

    test "returns a list of atoms" do
      events = TestRegistry.all_events()

      assert is_list(events)
      assert Enum.all?(events, &is_atom/1)
    end
  end

  describe "registered?/1" do
    test "returns true for registered events" do
      assert TestRegistry.registered?(:multi_handler_event) == true
      assert TestRegistry.registered?(:single_handler_event) == true
      assert TestRegistry.registered?(:no_handler_event) == true
    end

    test "returns false for unregistered events" do
      assert TestRegistry.registered?(:unknown_event) == false
      assert TestRegistry.registered?(:some_random_event) == false
      assert TestRegistry.registered?(:not_a_real_event) == false
    end

    test "works with any atom" do
      assert TestRegistry.registered?(:literally_anything) == false
      assert TestRegistry.registered?(:test_event_one) == true
    end
  end

  describe "__events__/0" do
    test "returns the raw @events map" do
      events = TestRegistry.__events__()

      assert is_map(events)
      assert Map.has_key?(events, :multi_handler_event)
      assert Map.has_key?(events, :single_handler_event)
      assert Map.has_key?(events, :no_handler_event)
    end

    test "returned map contains handler configurations" do
      events = TestRegistry.__events__()

      assert events[:multi_handler_event] == [
               TestRegistry.HandlerOne,
               TestRegistry.HandlerTwo
             ]

      assert events[:single_handler_event] == [TestRegistry.HandlerOne]
      assert events[:no_handler_event] == []
    end
  end

  describe "compile-time validation" do
    test "raises when @events is missing" do
      assert_raise CompileError, ~r/Missing @events/, fn ->
        Code.compile_string("""
        defmodule TestMissingHandlers do
          use ObanEvents
        end
        """)
      end
    end

    test "raises when @events is not a map" do
      assert_raise CompileError, ~r/must be a map/, fn ->
        Code.compile_string("""
        defmodule TestNotMap do
          use ObanEvents
          @events [:user_created]
        end
        """)
      end
    end

    test "raises when @events has non-atom keys" do
      assert_raise CompileError, ~r/keys must be atoms/, fn ->
        Code.compile_string("""
        defmodule TestNonAtomKeys do
          use ObanEvents
          @events %{"user_created" => [SomeHandler]}
        end
        """)
      end
    end

    test "raises when @events has non-list values" do
      assert_raise CompileError, ~r/must be lists/, fn ->
        Code.compile_string("""
        defmodule TestNonListValues do
          use ObanEvents
          @events %{user_created: SomeHandler}
        end
        """)
      end
    end

    test "raises when handler modules are not atoms" do
      assert_raise CompileError, ~r/must contain module names/, fn ->
        Code.compile_string("""
        defmodule TestInvalidHandlers do
          use ObanEvents
          @events %{user_created: ["SomeHandler"]}
        end
        """)
      end
    end

    test "compiles successfully with valid @events" do
      assert Code.compile_string("""
             defmodule TestValidHandlers do
               use ObanEvents

               @events %{
                 user_created: [SomeHandler, AnotherHandler],
                 user_updated: []
               }
             end
             """)
    end
  end
end
