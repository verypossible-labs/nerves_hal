defmodule Nerves.HAL.Device.Adapter.Connection do

  @callback handle_data_in(device :: Device.t, data :: term, state :: term) ::
    {:noreply, state :: term} |
    {:disconnect, state :: term}
end
