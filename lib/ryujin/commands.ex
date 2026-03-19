# RYUJIN commands

defmodule Ryujin.CommandRegister do
  use GenServer
  require Logger
  alias Nostrum.Api.ApplicationCommand
  alias Nostrum.Api.Self

  @commands [
    %{
      name: "join",
      description: "Faz o bot entrar no seu canal de voz."
    },
    %{
      name: "play",
      description: "Toque uma bela música para seus amigos.",
      options: [
        %{
          name: "query",
          description: "URL ou termo de busca para reproduzir",
          type: 3,
          required: true
        }
      ]
    },
    %{
      name: "loop",
      description: "Toca a música atual em loop infinito.",
    },
    %{
      name: "leave",
      description: "Faz o bot sair do canal de voz atual."
    },
    %{
      name: "camara_eventos",
      description:
        "Veja uma lista de eventos previstos nos diversos orgãos da câmara de deputados."
    }
  ]

  @doc "Return the commands list for registration"
  def commands, do: @commands

  def start_link(_args) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @impl true
  def init(_) do
    Process.send_after(self(), :register_commands, 3_000)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:register_commands, state) do
    Logger.info("Registering global commands...")
    clear_bot_commands()
    :timer.sleep(1000)
    {:noreply, state}
  end

  defp clear_bot_commands do
    commands = Ryujin.CommandRegister.commands()

    Nostrum.Api.ApplicationCommand.bulk_overwrite_global_commands(commands)
    {:ok, guilds} = Nostrum.Api.Self.guilds()

    Enum.each(guilds, fn %Nostrum.Struct.Guild{id: guild_id} ->
      Nostrum.Api.ApplicationCommand.bulk_overwrite_guild_commands(guild_id, commands)
    end)

    :ok
  end
end
