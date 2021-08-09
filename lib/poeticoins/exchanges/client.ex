defmodule Poeticoins.Exchanges.Client do
    use GenServer

    @type t :: %__MODULE__{
        module: module(),
        conn: pid(),
        conn_ref: reference(),
        currency_pairs: [String.t()]
    }

    @callback exchange_name() :: String.t()
    @callback server_host() :: list()
    @callback server_port() :: integer()
    @callback subscription_frames([String.t()]) :: [{:text, String.t()}]
    @callback handle_ws_message(map(), any()) :: any()

    defstruct [:module, :conn, :conn_ref, :currency_pairs]

    defmacro defclient(opts) do
        exchange_name = Keyword.fetch!(opts, :exchange_name)
        host = Keyword.fetch!(opts, :host)
        port = Keyword.fetch!(opts, :port)
        currency_pairs = Keyword.fetch!(opts, :currency_pairs)

        client_module = __MODULE__

        quote do
            @behaviour unquote(client_module)
            import unquote(client_module), only: [validate_required: 2]
            require Logger

            def available_currency_pairs, do: unquote(currency_pairs)
            def exchange_name, do: unquote(exchange_name)
            def server_host, do: unquote(host)
            def server_port, do: unquote(port)

            def handle_ws_message(msg, state) do
                Logger.debug("handle_ws_message #{inspect(msg)}")
                {:noreply, state}
            end

            defoverridable [handle_ws_message: 2]
        end
    end

    def start_link(module, currency_pairs, opts \\ []) do
        GenServer.start_link(__MODULE__, {module, currency_pairs}, opts)
    end

    #-------------------------------------------------------------------------
    # init/1
    # Initializes process with the currency pairs provided.
    # Notes: the {:continue, :connect} tuple returned as the 3rd argument
    # will call handle_continue/2.
    # handle_continue/2 expects the first parameter to be :connect
    #-------------------------------------------------------------------------
    def init({module, currency_pairs}) do
        client = %__MODULE__{
            module: module,
            currency_pairs: currency_pairs
        }
        {:ok, client, {:continue, :connect}}
    end

    #-------------------------------------------------------------------------
    # handle_continue/2 
    # The GenServer calls handle_continue asynchronously, allowing init/1
    # return without blocking the parent process.
    # Doing so separates the connection flow from the initialization flow.
    #-------------------------------------------------------------------------
    def handle_continue(:connect, client) do
        {:noreply, connect(client)}
    end

    def connect(client) do
        host = server_host(client.module)
        port = server_port(client.module)
        {:ok, conn} = :gun.open(host, port, %{protocols: [:http]})
        conn_ref = Process.monitor(conn)
        %{client | conn: conn, conn_ref: conn_ref}
    end

    defp server_host(module), do: module.server_host()
    defp server_port(module), do: module.server_port()

    #-------------------------------------------------------------------------
    # handle_info/2                                                          #
    #-------------------------------------------------------------------------
    # handle message returned from initial connection to API.
    #-------------------------------------------------------------------------
    def handle_info({:gun_up, conn, :http}, %{conn: conn}=client) do
        :gun.ws_upgrade(conn, "/")
        {:noreply, client}
    end

    #-------------------------------------------------------------------------
    # Handle response :gun.ws_send in subscribe/1
    #-------------------------------------------------------------------------
    def handle_info({:gun_upgrade, conn, _ref, ["websocket"], _headers}, %{conn: conn}=client) do
        subscribe(client)
        {:noreply, client}
    end

    #-------------------------------------------------------------------------
    # handle_info/2
    # Handle response from websocket upgrade
    #-------------------------------------------------------------------------
    def handle_info({:gun_ws, conn, _ref, {:text, msg}=_frame}, %{conn: conn}=client) do
        handle_ws_message(Jason.decode!(msg), client)
    end

    defp subscribe(client) do
        subscription_frames(client.module, client.currency_pairs)
        |> Enum.each(&:gun.ws_send(client.conn, &1))
    end
    defp subscription_frames(module, currency_pairs) do
        module.subscription_frames(currency_pairs)
    end

    defp handle_ws_message(msg, client) do
        module = client.module
        module.handle_ws_message(msg, client)
    end

    #-----------------------------------------------------------------------------
    # Checks if the map is either missing a key or the value for that key is nil.
    #-----------------------------------------------------------------------------
    @spec validate_required(map, [String.t()]) :: :ok | {:error, {String.t(), :required}}
    def validate_required(msg, keys) do
        required_key = Enum.find(keys, fn k -> is_nil([msg[k]]) end)

        if is_nil(required_key) do
            :ok
        else
            {:error, {required_key, :required}}
        end
    end
end