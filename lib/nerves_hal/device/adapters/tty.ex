if Code.ensure_loaded?(Circuits.UART) do
  defmodule Nerves.HAL.Device.Adapters.Tty do
    use Nerves.HAL.Device.Adapter, subsystem: "tty"

    alias Circuits.UART
    require Logger

    def attributes(device) do
      <<"/dev/", device_file::binary>> = Nerves.HAL.Device.device_file(device)

      info =
        UART.enumerate()
        |> Enum.find(fn {dev_file, _} -> dev_file == device_file end)

      case info do
        {_, attributes} -> attributes
        nil -> %{}
      end
    end

    def handle_connect(device, s) do
      case Nerves.HAL.Device.device_file(device) do
        <<"/dev/", devfile::binary>> ->
          {:ok, pid} = UART.start_link()
          UART.configure(pid, s.opts)
          UART.open(pid, devfile, s.opts)
          {:ok, Map.put(s, :driver, pid)}

        _ ->
          {:error, "no dev file found", s}
      end
    end

    def handle_info({:circuits_uart, _dev, message}, s) do
      {:data_in, message, s}
    end
  end
end
