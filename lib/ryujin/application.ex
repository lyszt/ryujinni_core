defmodule Ryujin.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  alias Nostrum.Api.Self

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
      name = "Planejando como destruir o #{Enum.random(active_servers).name}."
      Self.update_status(:online, {:streaming, name, "https://youtu.be/47AVNwXG3CA"})
    end)

    {:ok, pid}
  end

  @impl true
  def config_change(changed, _new, removed) do
    RyujinWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
