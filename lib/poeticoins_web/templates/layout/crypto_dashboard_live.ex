defmodule PoeticoinsWeb.CryptoDashboardLive do
    use PoeticoinsWeb, :live_view
    alias Poeticoins.{Product, Trade, Exchanges}

    @impl true
    def mount(_params, _session, socket) do
        products = Poeticoins.available_products()
        trades = 
            products
            |> Poeticoins.get_last_trades()
            |> Enum.reject(&is_nil/1)
            |> Enum.map(&{&1.product, &1})
            |> Enum.into(%{})

        if connected?(socket) do
            Enum.each(products, &Poeticoins.subscribe_to_trades/1)
        end

        socket = assign(socket, trades: trades, products: products, filter_products: & &1)
        {:ok, socket}
    end

    @impl true
    def handle_info({:new_trade, trade}, socket) do
        # socket = assign(socket, :trade, trade)
        socket = 
            socket
            |> update(:trades, &Map.put(&1, trade.product, trade))
            |> assign(:page_title, "#{trade.price}")
        {:noreply, socket}
    end

    @impl true
    def handle_event("clear", _params, socket) do
        {:noreply, assign(socket, :trades, %{})}
    end

    @impl true
    def handle_event("add-product", %{"product_id" => product_id}, socket) do
        IO.puts("\n\n\n\n pppppp: #{product_id}")
        [exchange_name, currency_pair] = String.split(product_id, ":")
        product = Product.new(exchange_name, currency_pair)
        socket = maybe_add_product(socket, product)
        {:noreply, socket}
    end
    def handle_event("add-product", _info, socket) do
        {:noreply, put_flash(socket, :error, "error occured")}
    end

    def handle_event("filter-products", %{"search" => search}, socket) do
        IO.puts "\n\n\n\n\n sssssssss:" <> search
        socket =
            assign(socket, :filter_products, fn product ->
                String.downcase(product.exchange_name) =~ String.downcase(search) or
                String.downcase(product.currency_pair) =~ String.downcase(search)
            end)
        
        {:noreply, socket}
    end

     
    defp maybe_add_product(socket, product) do
        if product not in socket.assigns.products do
            socket
            |> add_product(product)
            |> put_flash(
                :info,
                "#{product.exchange_name} - #{product.currency_pair}"
            )
        else
            socket
            |> put_flash(:error, "The product has already been added.")
        end
    end

    defp add_product(socket, product) do
        Poeticoins.subscribe_to_trades(product)

        socket
        |> update(:products, fn products -> products ++ [product] end)
        |> update(:trades, fn trades ->
            trade = Poeticoins.get_last_trade(product)
            Map.put(trades, product, trade)
        end)
    end
end