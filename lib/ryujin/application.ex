defmodule Ryujin.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger
  alias Nostrum.Api.Self
  alias Ryujin.Speech

  @impl true
  def start(_type, _args) do
    bot_options = %{
      name: Ryujin.Bot,
      module: Ryujin.Bot,
      consumer: Ryujin.Consumer,
      # Intent categories (keeps intents as categories rather than per-event atoms)
      intents: [
        :guilds,
        :guild_members,
        :guild_moderation,
        :guild_expressions,
        :guild_integrations,
        :guild_webhooks,
        :guild_invites,
        :guild_voice_states,
        :guild_presences,
        :guild_messages,
        :guild_message_reactions,
        :guild_message_typing,
        :direct_messages,
        :direct_message_reactions,
        :direct_message_typing,
        :message_content,
        :guild_scheduled_events,
        :auto_moderation_configuration,
        :auto_moderation_execution,
        :guild_message_polls,
        :direct_message_polls
      ],
      wrapped_token: fn -> System.fetch_env!("DISCORD_TOKEN") end
    }

    children = [
      RyujinWeb.Telemetry,
      Ryujin.Repo,
      {Registry, keys: :unique, name: Ryujin.VoiceRegistry},
      Ryujin.VoiceSupervisor,
      {Nostrum.Bot, bot_options},
      {DNSCluster, query: Application.get_env(:ryujin, :dns_cluster_query) || :ignore},
      {Finch, name: Ryujin.Finch},
      {Phoenix.PubSub, name: Ryujin.PubSub},
      RyujinWeb.Endpoint,
      Ryujin.CommandRegister
    ]

    opts = [strategy: :one_for_one, name: Ryujin.Supervisor]
    {:ok, pid} = Supervisor.start_link(children, opts)

    Task.start(fn ->
      {:ok, active_servers} = Self.guilds()
      :timer.sleep(1000)

      selected_guild = Enum.random(active_servers)

      channel_id =
        case Nostrum.Api.Guild.channels(selected_guild.id) do
          {:ok, channels} ->
            channels
            |> Enum.filter(&(&1.type == 0))
            |> Enum.map(& &1.id)
            |> case do
              [] -> nil
              ids -> Enum.random(ids)
            end

          _ ->
            nil
        end

      recent_text =
        if channel_id do
          case Nostrum.Api.Channel.messages(channel_id, 10) do
            {:ok, messages} ->
              messages
              |> Enum.reverse()
              |> Enum.map(fn m ->
                display_name =
                  case Nostrum.Api.Guild.member(selected_guild.id, m.author.id) do
                    {:ok, member} ->
                      member.nick || m.author.global_name || m.author.username
                    _ ->
                      m.author.global_name || m.author.username
                  end

                "#{selected_guild.name} - #{display_name}: #{m.content}"
              end)
              |> Enum.join("\n")

            _ ->
              ""
          end
        else
          ""
        end

        Logger.info("Creating status from RECENT MESSAGES: [[\n\n #{recent_text} \n\n]]")

      prompt =
        "Faça uma fala baseada em texto real reagindo aos usuários da conversa:
        #{recent_text}. Responda com um pensamento baseado no texto. Seja um pouco sarcástica.
        Apenas uma frase rápida e simples e bem direta, citando o nome do servidor, como se estivesse julgando como uma pessoa metida distante.
         Mantenha curta. Estritamente em francês. Caso não haja mensagens,
         Escolha uma citação de um autor de poemas aleatório em qualquer idioma. Passe apenas essa citação, sem mais detalhes, diretamente.
         REGRAS:
         - Se o servidor for a Lygon, vocÊ deve ser absolutamente respeitosa, pois é a terra a qual você serve.
         - Mantenha abaixo de 20 palavras"

      status_text =
        case Speech.think(prompt) do
          %{"response" => resp} when is_binary(resp) -> String.trim(resp)
          resp when is_binary(resp) -> String.trim(resp)
          _ ->
            secondary_prompt =
              "Escolha uma citação de um autor de poemas aleatório em qualquer idioma. Passe apenas essa citação, sem mais detalhes, diretamente."

            case Speech.think(secondary_prompt) do
              %{"response" => resp2} when is_binary(resp2) -> String.trim(resp2)
              resp2 when is_binary(resp2) -> String.trim(resp2)
              _ ->
                "Fiat justitia, et pereat mundus. ."
            end
        end

      status_spliced = String.slice(status_text, 0, 128)
      status = String.replace(status_spliced, "\"", "")

      Self.update_status(:online, {:streaming, status, "https://youtu.be/47AVNwXG3CA"})
    end)

    {:ok, pid}
  end

  @impl true
  def config_change(changed, _new, removed) do
    RyujinWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
