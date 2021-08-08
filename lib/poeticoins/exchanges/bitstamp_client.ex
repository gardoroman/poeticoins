defmodule Poeticoins.Exchanges.BitstampClient do
    use GenServer
    
    alias Poeticoins.{Trade, Product}

    @exchange_name "bitstamp"

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

    #-------------------------------------------------------------------------
    # handle_info/2
    # Handle response from websocket upgrade
    #-------------------------------------------------------------------------
    def handle_info({:gun_ws, conn, _ref, {:text, msg} = _frame}, %{conn: conn} = state) do
        Jason.decode!(msg)
        |> handle_ws_message(state)
    end
    
    defp handle_ws_message(%{"event" => "trade"} = msg, state) do
        msg
        |> message_to_trade()
        |> IO.inspect(label: "trade")

        {:noreply, state}
    end

    defp handle_ws_message(msg, state) do
        IO.inspect(msg, label: "Unhandled message")
        {:noreply, state}
    end

    @spec message_to_trade(map()) :: {:ok, Trade.t()} | {:error, any()}
    def message_to_trade(%{"data" => data, "channel" => "live_trades_" <> currency_pair}=_msg)
        when is_map(data)
    do
        with :ok <- validate_required(data, ["amount_str", "price_str", "timestamp"]),
             {:ok, traded_at} <- timestamp_to_datetime(data["timestamp"])
        do   
            trade = Trade.new(
                product: Product.new(@exchange_name, currency_pair),
                price: data["price_str"],
                volume: data["amount_str"],
                traded_at: traded_at
            )
            {:ok, trade}
        else
            {:error, _reason} = error -> error
        end
    end

    def message_to_trade(_msg), do: {:error, :invalid_trade_message}

    @spec validate_required(map(), [String.t()]) :: :ok | {:error, {String.t(), :required}}
    #-----------------------------------------------------------------------------
    # Checks if the map is either missing a key or the value for that key is nil.
    #-----------------------------------------------------------------------------
    defp validate_required(msg, keys) do
        required_key = Enum.find(keys, fn k -> is_nil(msg[k]) end)

        if is_nil(required_key), do: :ok,
        else: {:error, {required_key, :required}}
    end

    @spec timestamp_to_datetime(String.t()) :: {:ok, DateTime.t() | :error, atom()}
    defp timestamp_to_datetime(ts) do
        case Integer.parse(ts) do
            {timestamp, _} -> 
                DateTime.from_unix(timestamp)
            :error -> {:error, :invalid_timestamp_string}
        end
    end



    defp server_host, do: 'ws.bitstamp.net'
    defp server_port, do: 443
    defp http_protocols, do: %{protocols: [:http]}

    defp connect(state) do
        {:ok, conn} = :gun.open(server_host(), server_port(), http_protocols())
        %{state | conn: conn}
    end

    defp subscribe(state) do
        # send subscription frames to bitstamp
        subscription_frames(state.currency_pairs)
        |> Enum.each(&:gun.ws_send(state.conn, &1))
    end

    defp subscription_frames(currency_pairs) do
        Enum.map(currency_pairs, &subscription_frame/1)
    end

    defp subscription_frame(currency_pair) do
        msg = %{
            "event" => "bts:subscribe",
            "data" => %{
                "channel" => "live_trades_#{currency_pair}"
            }
        } |> Jason.encode!()
        {:text, msg}
    end

end