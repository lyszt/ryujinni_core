defmodule Ryujin.VoiceSession do
  @moduledoc """
  Coordinates Discord voice operations for a single guild/channel pair.
  """

  use GenServer
  require Logger
  alias Nostrum.Voice

  # Public API -----------------------------------------------------------------

  @spec ensure_session(Nostrum.Struct.Guild.id(), Nostrum.Struct.Channel.id()) ::
          {:ok, pid()} | {:error, any()}
  def ensure_session(guild_id, channel_id) do
    with {:error, :not_found} <- lookup(guild_id),
         {:ok, pid} <- start_session(guild_id, channel_id) do
      {:ok, pid}
    else
      {:ok, pid} ->
        GenServer.call(pid, {:ensure_channel, channel_id})
        {:ok, pid}

      {:error, _} = error ->
        error
    end
  end

  @spec join(Nostrum.Struct.Guild.id(), Nostrum.Struct.Channel.id()) :: :ok | {:error, any()}
  def join(guild_id, channel_id) do
    with {:ok, pid} <- ensure_session(guild_id, channel_id) do
      GenServer.call(pid, {:ensure_channel, channel_id})
    end
  end

  @spec play(Nostrum.Struct.Guild.id(), any(), any(), Keyword.t()) ::
          :ok | {:error, :session_not_found}
  def play(guild_id, url, type, opts \\ []) do
    case lookup(guild_id) do
      {:ok, pid} ->
        GenServer.cast(pid, {:play, url, type, opts})
        :ok

      {:error, :not_found} ->
        {:error, :session_not_found}
    end
  end

  @spec toggle_loop(Nostrum.Struct.Guild.id()) :: {:ok, boolean()} | {:error, :session_not_found}
  def toggle_loop(guild_id) do
    case lookup(guild_id) do
      {:ok, pid} -> GenServer.call(pid, :toggle_loop)
      {:error, :not_found} -> {:error, :session_not_found}
    end
  end

  @spec on_track_end(Nostrum.Struct.Guild.id()) :: :ok
  def on_track_end(guild_id) do
    case lookup(guild_id) do
      {:ok, pid} -> GenServer.cast(pid, :on_track_end)
      {:error, :not_found} -> :ok
    end
  end

  @spec leave(Nostrum.Struct.Guild.id()) :: :ok
  def leave(guild_id) do
    case lookup(guild_id) do
      {:ok, pid} ->
        GenServer.call(pid, :leave)

      {:error, :not_found} ->
        :ok
    end
  end

  # GenServer callbacks --------------------------------------------------------

  def start_link({guild_id, channel_id}) do
    GenServer.start_link(__MODULE__, {guild_id, channel_id}, name: via(guild_id))
  end

  @impl true
  def init({guild_id, channel_id}) do
    state = %{
      guild_id: guild_id,
      channel_id: channel_id,
      pending_join?: true,
      current_track: nil,
      loop: false
    }

    send(self(), :attempt_join)
    {:ok, state}
  end

  @impl true
  def child_spec({guild_id, _channel_id} = arg) do
    %{
      id: {:voice_session, guild_id},
      start: {__MODULE__, :start_link, [arg]},
      restart: :temporary,
      type: :worker
    }
  end

  @impl true
  def handle_call({:ensure_channel, channel_id}, _from, state) do
    state =
      if state.channel_id != channel_id do
        # Leave current channel before joining a new one.
        Voice.leave_channel(state.guild_id)
        %{state | channel_id: channel_id, pending_join?: true}
      else
        state
      end

    if state.pending_join? do
      send(self(), :attempt_join)
    end

    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:leave, _from, state) do
    Voice.leave_channel(state.guild_id)
    {:stop, :normal, :ok, %{state | pending_join?: true, current_track: nil, loop: false}}
  end

  @impl true
  def handle_call(:toggle_loop, _from, state) do
    new_loop = !state.loop
    {:reply, {:ok, new_loop}, %{state | loop: new_loop}}
  end

  @impl true
  def handle_cast({:play, url, type, opts}, state) do
    attempt_play(state.guild_id, {url, type, opts})
    {:noreply, %{state | current_track: {url, type, opts}}}
  end

  @impl true
  def handle_cast(:on_track_end, %{loop: true, current_track: {_, _, _} = track} = state) do
    attempt_play(state.guild_id, track)
    {:noreply, state}
  end

  def handle_cast(:on_track_end, state), do: {:noreply, state}

  @impl true
  def handle_info(:attempt_join, state) do
    case Voice.join_channel(state.guild_id, state.channel_id) do
      :ok ->
        {:noreply, %{state | pending_join?: false}}

      {:error, reason} ->
        Logger.warning(
          "Ryujin voice session failed to join guild #{state.guild_id}: #{inspect(reason)}"
        )

        Process.send_after(self(), :attempt_join, 1_000)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:retry_play, payload}, state) do
    attempt_play(state.guild_id, payload)
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    Voice.leave_channel(state.guild_id)
    :ok
  end

  # Internal helpers -----------------------------------------------------------

  defp lookup(guild_id) do
    case Registry.lookup(Ryujin.VoiceRegistry, guild_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  defp start_session(guild_id, channel_id) do
    case DynamicSupervisor.start_child(
           Ryujin.VoiceSupervisor,
           {__MODULE__, {guild_id, channel_id}}
         ) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        {:ok, pid}

      {:error, reason} = error ->
        Logger.error("Failed to start voice session for guild #{guild_id}: #{inspect(reason)}")
        error
    end
  end

  defp via(guild_id), do: {:via, Registry, {Ryujin.VoiceRegistry, guild_id}}

  defp attempt_play(guild_id, {url, type, opts} = payload) do
    if Voice.ready?(guild_id) do
      Voice.play(guild_id, url, type, opts)
    else
      Process.send_after(self(), {:retry_play, payload}, 25)
    end
  end
end
