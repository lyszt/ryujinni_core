defmodule Ryujin.Consumer do
  @behaviour Nostrum.Consumer
  require Logger
  alias Nostrum.Api.Message
  alias Nostrum.Cache.GuildCache
  alias Nostrum.Struct.Interaction
  alias Ryujin.VoiceSession
  alias Ryujin.Speech

  defp answer_individual(msg) do
    answer =
      case Speech.answer_quickly(msg.content, msg.channel_id) do
        {:ok, embed} ->
          embed
      end

    case Message.create(
           msg.channel_id,
           embed: answer
         ) do
      {:ok, message} ->
        message

      {:error, reason} ->
        Logger.info("Error creating the response: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp get_last_messages(channel_id) do
    {:ok, message} = Nostrum.Api.Channel.messages(channel_id, 2)
    message
  end

  defp get_bot_id() do
    app_info =
      case Nostrum.Api.Self.application_information() do
        {:ok, info} ->
          info

        {:error, reason} ->
          Logger.info("Error getting bot id: #{inspect(reason)}")
          reason
      end

    # Logger.info(app_info)
    bot_details = app_info.bot.id
    {:ok, bot_details}
  end

  @impl true
  def handle_event({:MESSAGE_CREATE, msg, _ws_state}) do
    lowered_msg = String.downcase(msg.content)
    {:ok, bot_id} = get_bot_id()

    # Logger.info(bot_id)
    last_messages = get_last_messages(msg.channel_id)
    id_message = "<@#{bot_id}>"

    Enum.each(
      last_messages,
      fn message ->
        if message.author.id == bot_id do
          answer_individual(msg)
        end
      end
    )

    # First, verify if the author is not oneself
    if msg.author.id != bot_id do
      # Check if it it's referencing the bot
      if String.contains?(lowered_msg, id_message) or String.contains?(lowered_msg, "claire") or
           String.contains?(lowered_msg, "clairemont") do
        answer_individual(msg)
      end
    end
  end

  @impl true
  def handle_event({:VOICE_SPEAKING_UPDATE, %{guild_id: guild_id, speaking: false, timed_out: false}, _}) do
    VoiceSession.on_track_end(guild_id)
  end

  # VOICE COMMANDS
  # ========================================
  @impl true
  def handle_event(
        {:INTERACTION_CREATE, %Interaction{data: %{name: "join"}} = interaction, _ws_state}
      ) do
    case check_if_incall(interaction) do
      {:ok, voice_channel} ->
        Nostrum.Api.Interaction.create_response(interaction, %{
          type: 4,
          data: %{
            content: "> Se juntando à chamada...",
            flags: 64
          }
        })

        case VoiceSession.join(interaction.guild_id, voice_channel) do
          :ok ->
            :ok

          {:error, reason} ->
            Logger.warning(
              "Failed to ensure voice session for guild #{interaction.guild_id}: #{inspect(reason)}"
            )
        end

      {:not_found, nil} ->
        Nostrum.Api.Interaction.create_response(interaction, %{
          type: 4,
          data: %{
            content: "> Desculpe, mas me parece que você não está em uma chamada de voz.",
            #
            flags: 64
          }
        })

      {:error, reason} ->
        Logger.info("Guild not found in cache: #{inspect(reason)}")
    end
  end

  @impl true
  def handle_event(
        {:INTERACTION_CREATE, %Interaction{data: %{name: "skip"}} = interaction, _ws_state}
      ) do
    case VoiceSession.skip(interaction.guild_id) do
      :ok ->
        Nostrum.Api.Interaction.create_response(interaction, %{
          type: 4,
          data: %{content: "> Pulando...", flags: 64}
        })

      {:error, :session_not_found} ->
        Nostrum.Api.Interaction.create_response(interaction, %{
          type: 4,
          data: %{content: "> Não estou em nenhum canal de voz.", flags: 64}
        })
    end
  end

  @impl true
  def handle_event(
        {:INTERACTION_CREATE, %Interaction{data: %{name: "play"}} = interaction, _ws_state}
      ) do
    case check_if_incall(interaction) do
      {:ok, voice_channel} ->
        case get_option(interaction, "query") do
          {:ok, raw} when is_binary(raw) and byte_size(raw) > 0 ->
            # If the user provided a plain search term (not a URL), convert it to a yt-dlp search
            url =
              if Regex.match?(~r/^https?:\/\//i, raw) do
                raw
              else
                "ytsearch:" <> String.trim(raw)
              end

            case VoiceSession.join(interaction.guild_id, voice_channel) do
              :ok ->
                Nostrum.Api.Interaction.create_response(interaction, %{
                  type: 5,
                  data: %{
                    content: "> Buscando...",
                    # flags: 64 - Deactivated cause I want people to know what I listen to
                  }
                })

                # Single yt-dlp call: first printed line = title, second = direct stream URL.
                # Using :url type so Nostrum never calls yt-dlp internally (no cookie support there).
                yt_args =
                  ["--print", "title", "--print", "urls",
                   "-f", "bestaudio/best",
                   "--no-playlist", "--no-warnings", "--ignore-errors",
                   "--max-downloads", "1"] ++ ytdlp_auth_args() ++ [url]

                {title, stream_url} =
                  case System.cmd("yt-dlp", yt_args) do
                    {output, _} when byte_size(output) > 0 ->
                      lines = output |> String.trim() |> String.split("\n")
                      {List.first(lines) || raw, List.last(lines) || url}

                    _ ->
                      {raw, url}
                  end

                message =
                  case VoiceSession.play(interaction.guild_id, stream_url, :url) do
                    :playing -> "> Tocando #{title}."
                    :queued -> "> Adicionado à fila: #{title}."
                    _ -> "> #{title}."
                  end

                Nostrum.Api.Interaction.edit_response(interaction, %{content: message})

              {:error, reason} ->
                Logger.warning(
                  "Failed to join voice before playing on guild #{interaction.guild_id}: #{inspect(reason)}"
                )

                Nostrum.Api.Interaction.create_response(interaction, %{
                  type: 4,
                  data: %{
                    content:
                      "> Não consegui entrar na chamada para tocar a música. Tente novamente.",
                    flags: 64
                  }
                })
            end

          {:error, :missing} ->
            Nostrum.Api.Interaction.create_response(interaction, %{
              type: 4,
              data: %{
                content: "> Por favor, forneça um URL ou termo de busca para reproduzir.",
                flags: 64
              }
            })
        end

      {:not_found, nil} ->
        Nostrum.Api.Interaction.create_response(interaction, %{
          type: 4,
          data: %{
            content: "> Desculpe, mas me parece que você não está em uma chamada de voz.",
            flags: 64
          }
        })

      {:error, reason} ->
        Logger.info("Guild not found in cache: #{inspect(reason)}")

      _ ->
        Logger.info("Unexpected response from check_if_incall/1")
    end
  end

  @impl true
  def handle_event(
        {:INTERACTION_CREATE, %Interaction{data: %{name: "loop"}} = interaction, _ws_state}
      ) do
    case VoiceSession.toggle_loop(interaction.guild_id) do
      {:ok, true} ->
        Nostrum.Api.Interaction.create_response(interaction, %{
          type: 4,
          data: %{content: "> Loop ativado.", flags: 64}
        })

      {:ok, false} ->
        Nostrum.Api.Interaction.create_response(interaction, %{
          type: 4,
          data: %{content: "> Loop desativado.", flags: 64}
        })

      {:error, :session_not_found} ->
        Nostrum.Api.Interaction.create_response(interaction, %{
          type: 4,
          data: %{content: "> Não estou em nenhum canal de voz.", flags: 64}
        })
    end
  end

  @impl true
  def handle_event(
        {:INTERACTION_CREATE, %Interaction{data: %{name: "leave"}} = interaction, _ws_state}
      ) do
    VoiceSession.leave(interaction.guild_id)

    Nostrum.Api.Interaction.create_response(interaction, %{
      type: 4,
      data: %{
        content: "> Até mais, companheiro.",
        flags: 64
      }
    })
  end

  # ================================================================================

  # Politics

  @impl true
  def handle_event(
        {:INTERACTION_CREATE, %Interaction{data: %{name: "camara_eventos"}} = interaction,
         _ws_state}
      ) do
    Nostrum.Api.Interaction.create_response(interaction, %{
      type: 4,
      data: %{
        content: "> Processando...",
        #
        flags: 64
      }
    })

    %Interaction{application_id: _app_id, token: _token} = interaction

    case CamaraApi.Eventos.fetch_and_format_events() do
      {:ok, formatted_events} ->
        if Enum.empty?(formatted_events) do
          Message.create(interaction.channel_id, %{
            content: "Nenhum evento encontrado para o período especificado."
          })
        else
          embeds =
            Enum.map(formatted_events, fn event ->
              safe_description = String.slice(event.description, 0, 3800)

              %Nostrum.Struct.Embed{
                title: event.title,
                url: event.uri,
                color: "RANDOM",
                description:
                  "**Início:** #{event.start_time} UTC\n" <>
                    "**Local:** #{event.location}\n" <>
                    "**Órgãos:** #{event.organs}\n" <>
                    "**Situação:** #{event.situation}\n\n" <>
                    "--- \n" <>
                    "#{safe_description}" <>
                    if(String.length(event.description) > 3800, do: "...", else: ""),
                footer: %Nostrum.Struct.Embed.Footer{
                  text: "Dados da API de Dados Abertos da Câmara dos Deputados"
                }
              }
            end)

          for embed <- embeds do
            Message.create(interaction.channel_id, %{
              embed: embed
            })
          end
        end

      {:error, reason} ->
        Logger.info("Failed to fetch Camara events: #{inspect(reason)}")

        Message.create(interaction.channel_id, %{
          content: "Desculpe, não consegui carregar os eventos da Câmara no momento."
        })
    end
  end

  def handle_event(_), do: :ok

  # ===================================
  # PRIVATE

  defp check_if_incall(interaction) do
    case GuildCache.get(interaction.guild_id) do
      {:ok, guild = %Nostrum.Struct.Guild{}} ->
        voice_states = guild.voice_states

        if voice_states != nil do
          user_voice_state =
            Enum.find(voice_states, fn state ->
              state.user_id == interaction.user.id
            end)

          if user_voice_state[:channel_id] != nil do
            {:ok, user_voice_state[:channel_id]}
          end
        else
          {:not_found, nil}
        end

      {:error, reason} ->
        Logger.info("Guild not found: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Helper to fetch an option value by name from an Interaction's data
  defp get_option(%Interaction{data: %{options: options}} = _interaction, name)
       when is_list(options) do
    case Enum.find(options, fn opt -> Map.get(opt, :name) == name end) do
      %{value: value} -> {:ok, value}
      _ -> {:error, :missing}
    end
  end

  # Fallback: when options isn't a list or option isn't found
  defp get_option(_interaction, _name), do: {:error, :missing}

  # Returns extra yt-dlp flags for cookie auth, based on :ryujin, :ytdlp_cookies config.
  defp ytdlp_auth_args do
    case Application.get_env(:ryujin, :ytdlp_cookies) do
      {:file, path} -> ["--cookies", path]
      {:browser, browser} -> ["--cookies-from-browser", browser]
      _ -> []
    end
  end

  @impl true
end
