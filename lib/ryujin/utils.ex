defmodule Ryujin.Utils do
  def get_bot_id() do
    Nostrum.Cache.Me.get().id
  end
end
