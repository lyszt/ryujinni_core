defmodule Ryujin.Bot do
  @behaviour Nostrum.Bot


  @impl true
  def handle_event(event) do
    Ryujin.Consumer.handle_event(event)
  end
end
