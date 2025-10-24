defmodule ObanEvents do
  @moduledoc """
  Event handling with persistent, transactional async handlers via Oban.

  This module provides a complete event handling system that combines event registration,
  handler management, and async job dispatching in a single interface.

  ## Features

  - **Registry-based** - Compile-time event and handler registration
  - **Persistent** - Events survive restarts (stored in Oban's DB)
  - **Reliable** - Automatic retries on failure via Oban
  - **Async** - Non-blocking execution of handlers
  - **Transactional** - Works within database transactions for atomicity
  - **Observable** - Track event processing via Oban Web UI
  - **Type-safe** - Compile-time validation of events

  ## Usage

  Define your events in one module:

      defmodule MyApp.Events do
        use ObanEvents,
          oban: {MyApp.Oban, queue: :my_events, max_attempts: 5, priority: 1}

        @events %{
          user_created: [
            {MyApp.EmailHandler, oban: [priority: 0, max_attempts: 10]},
            MyApp.AnalyticsHandler
          ],
          user_updated: [MyApp.CacheHandler],
          order_placed: []
        }
      end

  Emit events (preferably within transactions):

      MyApp.Repo.transaction(fn ->
        with {:ok, user} <- MyApp.Repo.insert(changeset),
             {:ok, _jobs} <- MyApp.Events.emit(:user_created, %{
               user_id: user.id,
               email: user.email
             }) do
          {:ok, user}
        end
      end)

  ## Event flow

  1. `emit/2` is called with an event name and data
  2. Registry looks up all handlers for that event
  3. Oban jobs are created (one per handler)
  4. Jobs are persisted to the database within the transaction
  5. `DispatchWorker` processes each job asynchronously
  6. Each handler's `handle_event/2` callback is invoked

  ## Configuration options

  - `:oban` - Oban instance and configuration. Can be:
    - Just a module: `oban: MyApp.Oban` (uses all defaults)
    - Tuple with options: `oban: {MyApp.Oban, queue: :custom, max_attempts: 5, priority: 1, tags: ["myapp"]}`

  Default Oban options:
  - `queue`: `:oban_events`
  - `max_attempts`: `3`
  - `priority`: `2` (0-3, lower is higher priority)
  - `tags`: `[]`

  Per-handler options (override globals):
  - Handlers can be atoms (use defaults) or tuples with options: `{Handler, oban: [priority: 0, max_attempts: 10, queue: :critical, tags: ["urgent"]]}`

  ## API

  Using this module provides:
  - `emit/2` - Dispatch events to handlers via Oban jobs
  - `get_handlers!/1` - Get handlers for an event
  - `all_events/0` - List all registered events
  - `registered?/1` - Check if an event exists

  ## Handler implementation

  Create handlers by implementing the `ObanEvents.Handler` behaviour:

      defmodule MyApp.EmailHandler do
        use ObanEvents.Handler

        @impl true
        def handle_event(:user_created, data) do
          %{"user_id" => user_id, "email" => email} = data
          # Send welcome email
          :ok
        end

        def handle_event(_event, _data), do: :ok
      end
  """

  @doc """
  Emit an event.

  Creates Oban jobs for all registered handlers of the given event.
  Should be called within a transaction to ensure atomicity.

  Returns `{:ok, jobs}` on success. Raises `ArgumentError` if event is not registered.
  """
  @callback emit(atom(), map()) :: {:ok, [Oban.Job.t()]}

  @doc """
  Get all handler modules registered for a given event.
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

  defmacro __using__(opts) do
    # Parse oban option - can be:
    # - atom (just module): oban: MyApp.Oban
    # - tuple with config: oban: {MyApp.Oban, queue: :custom, ...}
    {oban_module, oban_opts} =
      case Keyword.get(opts, :oban, Oban) do
        {module, config} when is_list(config) -> {module, config}
        module -> {module, []}
      end

    # Extract Oban options with defaults
    queue = Keyword.get(oban_opts, :queue, :oban_events)
    max_attempts = Keyword.get(oban_opts, :max_attempts, 3)
    priority = Keyword.get(oban_opts, :priority, 2)
    tags = Keyword.get(oban_opts, :tags, [])

    quote do
      use ObanEvents.Registry

      # Oban instance (cannot be overridden per-handler)
      @oban_instance unquote(oban_module)

      # Global Oban job defaults (can be overridden per-handler)
      @oban_queue unquote(queue)
      @oban_max_attempts unquote(max_attempts)
      @oban_priority unquote(priority)
      @oban_tags unquote(tags)

      @before_compile ObanEvents
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      alias ObanEvents.{DispatchWorker, Event}

      @doc """
      Emit an event.

      Creates Oban jobs for all registered handlers of the given event.
      Should be called within a transaction to ensure atomicity.

      ## Return values

      - `{:ok, jobs}` - Successfully created Oban jobs (list of `Oban.Job` structs)

      ## Parameters

      - `event_name`: Atom representing the event (e.g., `:user_created`)
      - `data`: Map of event-specific data (atom or string keys both work, must be JSON-serializable)
      - `opts`: Keyword list of optional metadata (see below)

      ## Options

      - `:causation_id` - Event ID that caused this emit (for event chains)
      - `:correlation_id` - Group related events from the same business operation

      ## Examples

          # Basic emit
          #{inspect(__MODULE__)}.emit(:user_created, %{user_id: 123})

          # Within a transaction (recommended)
          MyApp.Repo.transact(fn ->
            with {:ok, user} <- MyApp.Repo.insert(changeset),
                 {:ok, _jobs} <- #{inspect(__MODULE__)}.emit(:user_created, %{id: user.id}) do
              {:ok, user}
            end
          end)

          # Emit child event with causation
          def handle_event(:user_created, %Event{event_id: parent_id, data: data}) do
            #{inspect(__MODULE__)}.emit(:send_welcome_email, data, causation_id: parent_id)
          end

          # Group related events with correlation_id
          correlation_id = UUIDv7.generate()
          #{inspect(__MODULE__)}.emit(:order_placed, %{order_id: 1}, correlation_id: correlation_id)
          #{inspect(__MODULE__)}.emit(:payment_processed, %{order_id: 1}, correlation_id: correlation_id)

      Note: Handlers always receive data with string keys, regardless of how you emit.

      ## Errors

      Raises `ArgumentError` if the event is not registered.
      """
      @spec emit(atom(), map(), keyword()) :: {:ok, [Oban.Job.t()]}
      def emit(event_name, data, opts \\ []) when is_atom(event_name) and is_map(data) do
        handlers = get_handlers!(event_name)

        # Generate event_id once - shared by all handler jobs for this emit
        event_id = UUIDv7.generate()
        causation_id = Keyword.get(opts, :causation_id)
        correlation_id = Keyword.get(opts, :correlation_id)

        # Build Event struct for :if conditions (idempotency_key is per-job, not available yet)
        event = %Event{
          data: data,
          event_id: event_id,
          causation_id: causation_id,
          correlation_id: correlation_id,
          idempotency_key: nil
        }

        jobs =
          Enum.flat_map(handlers, fn handler_spec ->
            # Parse handler - can be atom or {atom, opts}
            {handler_module, handler_opts} =
              case handler_spec do
                {module, opts} when is_atom(module) -> {module, opts}
                module when is_atom(module) -> {module, []}
              end

            # Check :if condition - defaults to always true
            if_condition = Keyword.get(handler_opts, :if)

            should_schedule =
              case if_condition do
                nil ->
                  true

                fun when is_function(fun, 1) ->
                  fun.(event)

                {module, function, args}
                when is_atom(module) and is_atom(function) and is_list(args) ->
                  apply(module, function, args ++ [event])

                invalid ->
                  raise ArgumentError, """
                  Invalid :if condition for handler #{inspect(handler_module)}.

                  Expected: function/1 or MFA tuple {Module, :function, [args]}
                  Got: #{inspect(invalid)}

                  Examples:
                    if: fn event -> event.data["enabled"] end
                    if: {FunWithFlags, :enabled?, [:my_flag]}
                  """
              end

            if should_schedule do
              # Extract oban-specific options (grouped under :oban key)
              oban_opts = Keyword.get(handler_opts, :oban, [])

              # Merge per-handler oban options with global defaults
              job_opts = [
                queue: Keyword.get(oban_opts, :queue, @oban_queue),
                max_attempts: Keyword.get(oban_opts, :max_attempts, @oban_max_attempts),
                priority: Keyword.get(oban_opts, :priority, @oban_priority),
                tags: Keyword.get(oban_opts, :tags, @oban_tags)
              ]

              [
                DispatchWorker.new(
                  %{
                    event: Atom.to_string(event_name),
                    handler: Atom.to_string(handler_module),
                    data: data,
                    event_id: event_id,
                    idempotency_key: UUIDv7.generate(),
                    causation_id: causation_id,
                    correlation_id: correlation_id
                  },
                  job_opts
                )
              ]
            else
              # Condition not met, skip this handler
              []
            end
          end)

        if jobs == [] do
          # No handlers registered, nothing to do
          {:ok, []}
        else
          # Insert all jobs in a single operation
          # If called within a transaction, these inserts are part of it
          # Oban.insert_all always returns a list of jobs
          {:ok, @oban_instance.insert_all(jobs)}
        end
      end
    end
  end
end
