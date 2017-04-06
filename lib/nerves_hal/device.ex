defmodule Nerves.HAL.Device do

  defstruct [subsystem: nil, devpath: nil,  attributes: []]

  def load(devpath, subsystem) when is_binary(subsystem) do
    load(devpath, String.to_atom(subsystem))
  end

  def load(devpath, subsystem) do
    %__MODULE__{
      devpath: devpath,
      subsystem: subsystem,
      attributes: load_attributes(devpath)}
  end

  def load_attributes(devpath) do
    case File.ls(devpath) do
      {:ok, files} ->
        files
        |> Enum.map(fn (attribute) ->
            file = Path.join(devpath, attribute)
            lstat = File.lstat!(file)
            %{attribute: attribute, lstat: lstat}
        end)
        |> Enum.filter(& &1.lstat.type == :regular)
      _ -> []
    end
  end

  def device_file(device) do
    dev = Enum.find(device.attributes, & &1.attribute == "dev")
    case dev do
      [] -> {:error, :no_device_file}
      _ ->
        [dev_major, dev_minor] =
          Path.join(device.devpath, "dev")
          |> File.read!()
          |> String.split(":")
          |> Enum.map(&String.strip/1)
          |> Enum.map(fn (int) ->
            {int, _} = Integer.parse(int)
            int
          end)

        case File.ls("/dev") do
          {:ok, files} ->
            files
            |> Enum.map(& Path.join("/dev", &1))
            |> Enum.reject(& File.lstat!(&1).type != :device)
            |> Enum.filter(fn (dev_path) ->
              %{minor_device: rdev} = File.lstat!(dev_path)
              <<major, minor>> = <<rdev :: size(16)>>
              dev_major == major and
              dev_minor == minor
            end)
            |> List.first
          error -> error
        end

    end
  end


end
