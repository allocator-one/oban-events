defmodule ObanEvents.Registry do
  @moduledoc """
  Behaviour and macro for defining event bus registries.

  This module provides a macro that generates a registry mapping event names to handler modules.
  Each event can have multiple handlers, which are executed independently.

  See the [README](README.md) for architectural guidance and best practices.

  ## Defining a Registry

  To create a registry, use the macro and define your event handlers:

      defmodule MyApp.EventBus do
        use ObanEvents

        @event_handlers %{
          user_created: [
            MyApp.EmailHandler,
            MyApp.AnalyticsHandler
          ],
          user_updated: [
            MyApp.CacheHandler
          ]
        }
      end

  ## Adding New Events

  1. Add the event to `@event_handlers` in your registry module
  2. Create the handler module(s) implementing `ObanEvents.Handler`
  3. The system will automatically route events to handlers
  """

  @doc """
  Get all handler modules registered for a given event.

  Raises an error if the event is not registered.
  """
  @callback get_handlers!(atom()) :: [module()]

  @doc """
  Get all registered event names.
  """
  @callback all_events() :: [atom()]

  @doc """
  Check if an event is registered.
  """
  @callback registered?(atom()) :: boolean()

  defmacro __using__(_opts) do
    quote do
      @behaviour ObanEvents.Registry

      Module.register_attribute(__MODULE__, :event_handlers, [])

      @before_compile ObanEvents.Registry
    end
  end

  defmacro __before_compile__(env) do
    # Compile-time validation of @event_handlers
    event_handlers = Module.get_attribute(env.module, :event_handlers)

    # Validate @event_handlers exists
    unless event_handlers do
      raise CompileError,
        file: env.file,
        line: env.line,
        description:
          "Missing @event_handlers attribute in #{inspect(env.module)}. " <>
            "Please define @event_handlers as a map with event names (atoms) as keys and handler lists as values."
    end

    # Validate @event_handlers is a map
    unless is_map(event_handlers) do
      raise CompileError,
        file: env.file,
        line: env.line,
        description: "@event_handlers must be a map, got: #{inspect(event_handlers)}"
    end

    # Validate all keys are atoms
    non_atom_keys = event_handlers |> Map.keys() |> Enum.reject(&is_atom/1)

    unless Enum.empty?(non_atom_keys) do
      raise CompileError,
        file: env.file,
        line: env.line,
        description:
          "@event_handlers keys must be atoms (event names), found non-atom keys: #{inspect(non_atom_keys)}"
    end

    # Validate all values are lists
    non_list_values =
      event_handlers
      |> Enum.reject(fn {_key, value} -> is_list(value) end)
      |> Enum.map(fn {key, value} -> {key, value} end)

    unless Enum.empty?(non_list_values) do
      raise CompileError,
        file: env.file,
        line: env.line,
        description:
          "@event_handlers values must be lists of handler modules, found non-list values: #{inspect(non_list_values)}"
    end

    # Validate all handler modules are atoms (module names)
    invalid_handlers =
      event_handlers
      |> Enum.flat_map(fn {event, handlers} ->
        handlers
        |> Enum.reject(&is_atom/1)
        |> Enum.map(fn invalid -> {event, invalid} end)
      end)

    unless Enum.empty?(invalid_handlers) do
      raise CompileError,
        file: env.file,
        line: env.line,
        description:
          "@event_handlers must contain module names (atoms), found invalid handlers: #{inspect(invalid_handlers)}"
    end

    quote do
      @doc """
      Get all handler modules registered for a given event.

      Raises an error if the event is not registered.

      ## Examples

          iex> MyEventBus.get_handlers!(:user_created)
          [MyApp.EmailHandler, MyApp.AnalyticsHandler]

          iex> MyEventBus.get_handlers!(:unknown_event)
          ** (ArgumentError) Unknown event: :unknown_event. Known events: [:user_created, ...]
      """
      @impl true
      def get_handlers!(event_name) when is_atom(event_name) do
        case Map.fetch(@event_handlers, event_name) do
          {:ok, handlers} ->
            handlers

          :error ->
            raise ArgumentError, """
            Unknown event: #{inspect(event_name)}

            Known events: #{inspect(all_events())}

            To register this event, add it to @event_handlers in #{inspect(__MODULE__)}
            """
        end
      end

      @doc """
      Get all registered event names.

      Useful for documentation and debugging.

      ## Examples

          iex> MyEventBus.all_events()
          [:user_created, :user_updated, ...]
      """
      @impl true
      def all_events do
        Map.keys(@event_handlers)
      end

      @doc """
      Check if an event is registered.

      Note: This only checks if the event exists, not if it has handlers.
      An event can be registered with an empty handler list.

      ## Examples

          iex> MyEventBus.registered?(:user_created)
          true

          iex> MyEventBus.registered?(:unknown_event)
          false
      """
      @impl true
      def registered?(event_name) when is_atom(event_name) do
        Map.has_key?(@event_handlers, event_name)
      end
    end
  end
end
