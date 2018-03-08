# Nerves.HAL

Hardware Abstraction Layer for Nerves Devices


## Usage

`nerves_hal` is used to perform automatic device discovery and connection from kernel uevent messages. Devices are described by implementing the  `Nerves.HAL.Device.Spec` behaviour. A device spec needs to know how to communicate with a device and therefore needs to specify which `Nerves.HAL.Device.Adapter` to use. Nerves.HAL contains a few default adapters for interacting with devices like `tty` and `hidraw`. You can implement your own device adapters to handle any kind of low level device communication. Device adapters are responsible for declaring which linux device subsystem it is designed to work with. 

Lets look at how this works with the `hidraw` adapter. First, the adapter implements the `Nerves.HAL.Device.Adapter` behaviour through `use`. This is where you specify the linux device subsystem, in this case `"hidraw"`.

```elixir
defmodule Nerves.HAL.Device.Adapters.Hidraw do
  use Nerves.HAL.Device.Adapter, subsystem: "hidraw"

end
```

Device adapters are used to bridge the high level Device spec with the low level driver. They are expected to define a `handle_connect/2` callback. This callback is used to open communication with the device and expose it to the spec. After successfully connecting the device, we pass the driver back into the new state so we can track it later.

For example, the `hidraw` adapter implements the `Hidraw` driver to open the communication.

```elixir
defmodule Nerves.HAL.Device.Adapters.Hidraw do
  use Nerves.HAL.Device.Adapter, subsystem: "hidraw"

  def handle_connect(device, s) do
    case Nerves.HAL.Device.device_file(device) do
      nil ->
        {:error, "no dev file found", s}

      devfile ->
        {:ok, pid} = Hidraw.start_link(devfile)
        {:ok, Map.put(s, :driver, pid)}
    end
  end
end
```



The adapter should also define a callback that is used to fetch the attributes of the device. These attributes will be used later to help discover the device. Here we take the `Nerves.HAL.Device` and ask the driver to give us more information about it such as its name and description. See [Hidraw](https://github.com/LeToteTeam/hidraw) for more information about the `hidraw` driver.

```elixir
defmodule Nerves.HAL.Device.Adapters.Hidraw do
  use Nerves.HAL.Device.Adapter, subsystem: "hidraw"

  # ...
  def attributes(device) do
    device_file = Nerves.HAL.Device.device_file(device)

    info =
      Hidraw.enumerate()
      |> Enum.find(fn {dev_file, _} -> dev_file == device_file end)

    case info do
      {_, name} -> %{name: name}
      nil -> %{}
    end
  end
end
```

Now lets see how this works in conjunction with a Device spec. Lets start by creating a module to communicate with a barcode scanner using `Nerves.HAL.Device.Adapters.Hidraw`. 

```elixir 
defmodule Barcode do
  use Nerves.HAL.Device.Spec,
    adapter: Nerves.HAL.Device.Adapters.Hidraw

end
```

The `Barcode` module implements the `Device.Spec` behaviour and defines that it uses the `Nerves.HAL.Device.Adapters.Hidraw` adapter. This dictates which type of devices this module will attempt to match on. `handle_discover/2` is called whenever a new device appears in the `hidraw` device subsystem in Linux. This callback is where you will determine if this is the device you were looking for, and connect to it.

```elixir 
defmodule Barcode do
  use Nerves.HAL.Device.Spec,
    adapter: Nerves.HAL.Device.Adapters.Hidraw

  def handle_discover(device, s) do
    {adapter, _opts} = __adapter__()
    case adapter.attributes(device) do
      %{name: "Symbol Technologies, Inc, 2008 Symbol Bar Code Scanner"} ->
        Logger.debug "[Barcode] Discovered"
        {:connect, device, s}
      _ ->
        {:noreply, s}
    end
  end
end
```

There are two callbacks implemented in the device spec for tracking when a device connects and disconnects. Lets implement them to track the state of the barcode scanner. First we will want to control the contents of the state in the device spec server. We can do that by overriding `start_link`. Then we need to implement the callbacks for `handle_connect/2` and `handle_disconnect/2`.

```elixir
defmodule Barcode do
  use Nerves.HAL.Device.Spec,
    adapter: Nerves.HAL.Device.Adapters.Hidraw
  
  def start_link() do
    Nerves.HAL.Device.Spec.start_link(__MODULE__, %{status: :disconnected}, name: __MODULE__)
  end

  #...

  def handle_connect(_device, s) do
    Logger.debug "[Barcode] Connected"
    {:noreply, %{s | status: :connected}}
  end

  def handle_disconnect(_device, s) do
    Logger.debug "[Barcode] Disconnected"
    {:noreply, %{s | status: :disconnected}}
  end

end
```

Now that we are tracking the status of the device we can expose a method to allow other processes to request it.

```elixir
defmodule Barcode do
  use Nerves.HAL.Device.Spec,
    adapter: Nerves.HAL.Device.Adapters.Hidraw

  #...

  def status() do
    Nerves.HAL.Device.Spec.call(__MODULE__, :status)
  end

  def handle_call(:status, _from, s) do
    {:reply, {:ok, s.status}, s}
  end
end
```

Now lets see how to handle when a barcode is scanned and data comes through the driver, into the adapter, and how it ends up in the Device spec. First we need to handle the data in the device adapter. The `hidraw` driver will send a message to the process that called `start_link` so we first need to handle it there.

```elixir
defmodule Nerves.HAL.Device.Adapters.Hidraw do
  use Nerves.HAL.Device.Adapter, subsystem: "hidraw"

  #...

  def handle_info({:hidraw, _dev, message}, s) do
    {:data_in, message, s}
  end
end
```

In this case, we are returning the data and telling the adapter that there is `:data_in`. This is then handled by the device spec through the `handle_data_in/3` callback.

```elixir
defmodule Barcode do
  use Nerves.HAL.Device.Spec,
    adapter: Nerves.HAL.Device.Adapters.Hidraw

  #...

  def handle_data_in(_device, data, s) do
    Logger.debug "[Barcode] Handled data in: #{inspect data}"
    {:noreply, s}
  end
end
```

To start the device spec, simply add it to your application supervisor.

```elixir
children = [
  {Barcode, []},
]
```

Nerves.HAL will handle the connecting, disconnecting, and data in for your device for you. Just start your application and connect your device.
