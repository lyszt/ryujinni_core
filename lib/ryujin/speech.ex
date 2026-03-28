defmodule Ryujin.Speech do
  # Mudar isso para o servidor da Providentia
  @base_url "http://0.0.0.0:8000/speech/"
  @finch Ryujin.Finch
  require Logger

  def answer_quickly(message, channel_id) do
    {:ok, responseStruct} = get_simple_response(message, channel_id)

    case create_message_embed(responseStruct["response"]) do
      {:ok, embed} ->
        {:ok, embed}

    end
  end

  def think(prompt) do
    {:ok, responseStruct} = get_simple_prompt(prompt)
    responseStruct
  end

  defp create_message_embed(message_string) do
    embed_payload = %Nostrum.Struct.Embed{
      title: "Clairemont responde...",
      description: message_string,
      color: 14_423_100,
      footer: %Nostrum.Struct.Embed.Footer{
        text: "Movida pela PROVIDENCE Network."
      }
    }

    {:ok, embed_payload}
  end

  defp get_context(channel_id) do
    case Nostrum.Api.Channel.messages(channel_id, 6) do
      {:ok, messages} ->
        {:ok, messages}

      {:error, reason} ->
        Logger.info("Error finding message context: #{inspect(reason)}")
    end
  end

  defp get_simple_response(message, channel_id) do
    url = @base_url <> "deepthink/"
    headers = [{"content-type", "application/json"}]

    {context_text, triggering_user} =
      case get_context(channel_id) do
        {:ok, messages} ->
          latest_author = List.last(messages).author.username

      text =
        messages
        |> Enum.reverse()
        |> Enum.map(&(&1.author.username <> ":" <> &1.content))
        |> Enum.join("\n")

      {text, latest_author}
  end

    message_with_context = "#{message} -- CHAT CONTEXT: #{context_text}"

    request_body = Jason.encode!(%{
      prompt: message_with_context,
      light: true,
      username: "discord:#{triggering_user}"
    })
    request = Finch.build(:post, url, headers, request_body)

    # Needs a huge timeout in case Providentia overthinks
    case Finch.request(request, @finch, receive_timeout: 200_000) do
      {:ok, %Finch.Response{status: 200, body: body}} ->
        case Jason.decode(body, keys: :strings) do
          {:ok, data} -> {:ok, data}
          {:error, reason} -> {:error, "JSON decoding failed: #{inspect(reason)}"}
        end

      {:ok, %Finch.Response{status: status, body: body}} ->
        {:error, "API returned status #{status} with body: #{body}"}

      {:error, reason} ->
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end

  defp get_simple_prompt(prompt) do
    url = @base_url <> "answer/"
    headers = [{"content-type", "application/json"}]

    request_body = Jason.encode!(%{prompt: prompt, light: true, username: "discord:ryujinni"})
    request = Finch.build(:post, url, headers, request_body)

    case Finch.request(request, @finch, receive_timeout: 200_000) do
      {:ok, %Finch.Response{status: 200, body: body}} ->
        case Jason.decode(body, keys: :strings) do
          {:ok, data} -> {:ok, data}
          {:error, reason} -> {:error, "JSON decoding failed: #{inspect(reason)}"}
        end

      {:ok, %Finch.Response{status: status, body: body}} ->
        {:error, "API returned status #{status} with body: #{body}"}

      {:error, reason} ->
        {:error, "HTTP request failed: #{inspect(reason)}"}
    end
  end
end
