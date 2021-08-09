defmodule Poeticoins.Exchanges.CoinbaseClient do
    # use GenServer
    
    alias Poeticoins.{Trade, Product}
    alias Poeticoins.Exchanges.Client
    # import Client, only: [validate_required: 2]
    require Client

    Client.defclient exchange_name: "coinbase",
                     host: 'ws-feed.pro.coinbase.com',
                     port: 443,
                     currency_pairs: ["BTC-USD", "ETH-USD", "LTC-USD", "BTC-EUR", "ETH-EUR", "LTC-EUR"]

    @impl true
    def handle_ws_message(%{"type" => "ticker"} = msg, state) do
        msg
        |> message_to_trade()
        |> IO.inspect(label: "coinbase")

        {:noreply, state}
    end

    def handle_ws_message(msg, state) do
        IO.inspect(msg, label: "Unhandled message")
        {:noreply, state}
    end

    @impl true
    def subscription_frames(currency_pairs) do
        msg = %{
            "type" => "subscribe",
            "product_ids" => currency_pairs,
            "channels" => ["ticker"]
        } |> Jason.encode!()
        [{:text, msg}]
    end

    @spec message_to_trade(map()) :: {:ok, Trade.t()} | {:error, any()}
    def message_to_trade(msg) do
        with :ok <- validate_required(msg, ["product_id", "time", "last_size", "price"]),
             {:ok, traded_at, _} <- DateTime.from_iso8601(msg["time"])
        do
            currency_pair = msg["product_id"]
    
            Trade.new(
                product: Product.new(exchange_name(), currency_pair),
                price: msg["price"],
                volume: msg["last_size"],
                traded_at: traded_at
            )
            # {:ok, trade}
        else
            {:error, _reason} = error -> error
        end
    end

end