defmodule Poeticoins.Exchanges.CoinbaseClient do
    use GenServer
    
    alias Poeticoins.{Trade, Product}

    def start_link(currency_pairs, opts \\ []) do
        GenServer.start_link(__MODULE__, currency_pairs, opts)
    end

    #-------------------------------------------------------------------------
    # init/1
    # Initializes process with the currency pairs provided.
    # Notes: the {:continue, :connect} tuple returned as the 3rd argument
    # will call handle_continue/2.
    # handle_continue/2 expects the first parameter to be :connect
    #-------------------------------------------------------------------------
    def init(currency_pairs) do
        state = %{
            currency_pairs: currency_pairs,
            conn: nil
        }
        {:ok, state, {:continue, :connect}}
    end

    #-------------------------------------------------------------------------
    # handle_continue/2 
    # The GenServer calls handle_continue asynchronously, allowing init/1
    # return without blocking the parent process.
    # Doing so separates the connection flow from the initialization flow.
    #-------------------------------------------------------------------------
    def handle_continue(:connect, state) do
        # connect with :gun.open/3 to Exchange Websocket API
        updated_state = connect(state)
        {:noreply, updated_state}
    end

    #-------------------------------------------------------------------------
    # handle_info/2
    # handle message returned from initial connection to API.
    #-------------------------------------------------------------------------
    def handle_info({:gun_up, conn, :http}, %{conn: conn} = state) do
        :gun.ws_upgrade(state.conn, "/")
        {:noreply, state}
    end

    #-------------------------------------------------------------------------
    # handle_info/2
    # Handle response from websocket upgrade
    #-------------------------------------------------------------------------
    def handle_info({:gun_upgrade, conn, _ref, ["websocket"], _headers}, %{conn: conn} = state) do
        subscribe(state)
        {:noreply, state}
    end

    def handle_info({:gun_ws, conn, _ref, {:text, msg} = _frame}, %{conn: conn} = state) do
        Jason.decode!(msg)
        |> handle_ws_message(state)
    end
    
    defp handle_ws_message(%{"type" => "ticker"} = msg, state) do
        trade = 
        msg
        |> message_to_trade()
        |> IO.inspect(label: "trade")

        {:noreply, state}
    end

    defp message_to_trade(msg) do
        currency_pair = msg["product_id"]

        Trade.new(
            product: Product.new(@exchange_name, currency_pair),
            price: msg["price"],
            volume: msg["last_size"],
            traded_at: datetime_from_string(msg["time"])
        )
    end

    defp datetime_from_string(time_string) do
        {:ok, dt, _} = DateTime.from_iso8601(time_string)
        dt
    end

    defp handle_ws_message(msg, state) do
        IO.inspect(msg, label: "Unhandled message")
        {:noreply, state}
    end

    defp server_host, do: 'ws-feed.pro.coinbase.com'
    defp server_port, do: 443
    defp http_protocols, do: %{protocols: [:http]}

    defp connect(state) do
        {:ok, conn} = :gun.open(server_host(), server_port(), http_protocols())
        %{state | conn: conn}
    end

    defp subscribe(state) do
        # send subscription frames to coinbase
        subscription_frames(state.currency_pairs)
        |> Enum.each(&:gun.ws_send(state.conn, &1))
    end

    defp subscription_frames(currency_pairs) do
        msg = %{
            "type" => "subscribe",
            "product_ids" => currency_pairs,
            "channels" => ["ticker"]
        } |> Jason.encode!()
        [{:text, msg}]
    end

end