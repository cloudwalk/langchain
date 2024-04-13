defmodule LangChain.ChatModels.ChatOpenAITest do
  use LangChain.BaseCase
  import LangChain.Fixtures

  doctest LangChain.ChatModels.ChatOpenAI
  alias LangChain.ChatModels.ChatOpenAI
  alias LangChain.Function
  alias LangChain.FunctionParam
  alias LangChain.Message
  alias LangChain.Message.UserContentPart
  alias LangChain.Message.ToolCall

  @test_model "gpt-3.5-turbo"
  @gpt4 "gpt-4-1106-preview"

  defp hello_world(_args, _context) do
    "Hello world!"
  end

  # TODO: find and remove function_call references

  setup do
    {:ok, hello_world} =
      Function.new(%{
        name: "hello_world",
        description: "Give a hello world greeting",
        function: fn -> IO.puts("Hello world!") end
      })

    {:ok, weather} =
      Function.new(%{
        name: "get_weather",
        description: "Get the current weather in a given US location",
        parameters: [
          FunctionParam.new!(%{
            name: "city",
            type: "string",
            description: "The city name, e.g. San Francisco",
            required: true
          }),
          FunctionParam.new!(%{
            name: "state",
            type: "string",
            description: "The 2 letter US state abbreviation, e.g. CA, NY, UT",
            required: true
          })
        ],
        function: fn -> IO.puts("75 degrees") end
      })

    %{hello_world: hello_world, weather: weather}
  end

  describe "new/1" do
    test "works with minimal attr" do
      assert {:ok, %ChatOpenAI{} = openai} = ChatOpenAI.new(%{"model" => @test_model})
      assert openai.model == @test_model
    end

    test "returns error when invalid" do
      assert {:error, changeset} = ChatOpenAI.new(%{"model" => nil})
      refute changeset.valid?
      assert {"can't be blank", _} = changeset.errors[:model]
    end

    test "supports overriding the API endpoint" do
      override_url = "http://localhost:1234/v1/chat/completions"

      model =
        ChatOpenAI.new!(%{
          endpoint: override_url
        })

      assert model.endpoint == override_url
    end
  end

  describe "for_api/3" do
    test "generates a map for an API call" do
      {:ok, openai} =
        ChatOpenAI.new(%{
          "model" => @test_model,
          "temperature" => 1,
          "frequency_penalty" => 0.5,
          "api_key" => "api_key"
        })

      data = ChatOpenAI.for_api(openai, [], [])
      assert data.model == @test_model
      assert data.temperature == 1
      assert data.frequency_penalty == 0.5
      assert data.response_format == %{"type" => "text"}
    end

    test "generates a map for an API call with JSON response set to true" do
      {:ok, openai} =
        ChatOpenAI.new(%{
          "model" => @test_model,
          "temperature" => 1,
          "frequency_penalty" => 0.5,
          "json_response" => true
        })

      data = ChatOpenAI.for_api(openai, [], [])
      assert data.model == @test_model
      assert data.temperature == 1
      assert data.frequency_penalty == 0.5
      assert data.response_format == %{"type" => "json_object"}
    end

    test "generates a map for an API call with max_tokens set" do
      {:ok, openai} =
        ChatOpenAI.new(%{
          "model" => @test_model,
          "temperature" => 1,
          "frequency_penalty" => 0.5,
          "max_tokens" => 1234
        })

      data = ChatOpenAI.for_api(openai, [], [])
      assert data.model == @test_model
      assert data.temperature == 1
      assert data.frequency_penalty == 0.5
      assert data.max_tokens == 1234
    end
  end

  describe "for_api/1" do
    test "turns a basic user message into the expected JSON format" do
      expected = %{"role" => :user, "content" => "Hi."}
      result = ChatOpenAI.for_api(Message.new_user!("Hi."))
      assert result == expected
    end

    test "includes 'name' when set" do
      expected = %{"role" => :user, "content" => "Hi.", "name" => "Harold"}
      result = ChatOpenAI.for_api(Message.new!(%{role: :user, content: "Hi.", name: "Harold"}))
      assert result == expected
    end

    test "turns a multi-modal user message into the expected JSON format" do
      expected = %{
        "role" => :user,
        "content" => [
          %{"type" => "text", "text" => "Tell me about this image:"},
          %{"type" => "image_url", "image_url" => %{"url" => "url-to-image"}}
        ]
      }

      result =
        ChatOpenAI.for_api(
          Message.new_user!([
            UserContentPart.text!("Tell me about this image:"),
            UserContentPart.image_url!("url-to-image")
          ])
        )

      assert result == expected
    end

    test "turns a text UserContentPart into the expected JSON format" do
      expected = %{"type" => "text", "text" => "Tell me about this image:"}
      result = ChatOpenAI.for_api(UserContentPart.text!("Tell me about this image:"))
      assert result == expected
    end

    test "turns an image UserContentPart into the expected JSON format" do
      expected = %{"type" => "image_url", "image_url" => %{"url" => "image_base64_data"}}
      result = ChatOpenAI.for_api(UserContentPart.image!("image_base64_data"))
      assert result == expected
    end

    test "turns an image_url UserContentPart into the expected JSON format" do
      expected = %{"type" => "image_url", "image_url" => %{"url" => "url-to-image"}}
      result = ChatOpenAI.for_api(UserContentPart.image_url!("url-to-image"))
      assert result == expected
    end

    test "turns a tool_call into expected JSON format" do
      tool_call =
        ToolCall.new!(%{tool_id: "call_abc123", name: "hello_world", arguments: "{}"})

      json = ChatOpenAI.for_api(tool_call)

      assert json ==
               %{
                 "id" => "call_abc123",
                 "type" => "function",
                 "function" => %{
                   "name" => "hello_world",
                   "arguments" => "\"{}\""
                 }
               }
    end

    test "turns an assistant tool_call into expected JSON format with arguments" do
      # Needed when restoring a conversation from structs for history.
      # args = %{"expression" => "11 + 10"}
      msg =
        Message.new_assistant!(%{
          tool_calls: [
            ToolCall.new!(%{
              tool_id: "call_abc123",
              name: "hello_world",
              arguments: %{expression: "11 + 10"}
            })
          ]
        })

      json = ChatOpenAI.for_api(msg)

      assert json == %{
               "role" => :assistant,
               "content" => nil,
               "tool_calls" => [
                 %{
                   "function" => %{
                     "arguments" => "{\"expression\":\"11 + 10\"}",
                     "name" => "hello_world"
                   },
                   "id" => "call_abc123",
                   "type" => "function"
                 }
               ]
             }
    end

    test "turns a tool execution response into expected JSON format" do
      msg = Message.new_tool!("tool_abc123", "Hello World!")

      json = ChatOpenAI.for_api(msg)

      assert json == %{
               "content" => "Hello World!",
               "tool_call_id" => "tool_abc123",
               "role" => :tool
             }
    end

    test "tools work with minimal definition and no parameters" do
      {:ok, fun} = Function.new(%{"name" => "hello_world"})

      result = ChatOpenAI.for_api(fun)

      assert result == %{
               "name" => "hello_world",
               #  NOTE: Sends the required empty parameter definition when none set
               "parameters" => %{"properties" => %{}, "type" => "object"}
             }
    end

    test "supports parameters" do
      params_def = %{
        "type" => "object",
        "properties" => %{
          "p1" => %{"type" => "string"},
          "p2" => %{"description" => "Param 2", "type" => "number"},
          "p3" => %{
            "enum" => ["yellow", "red", "green"],
            "type" => "string"
          }
        },
        "required" => ["p1"]
      }

      {:ok, fun} =
        Function.new(%{
          name: "say_hi",
          description: "Provide a friendly greeting.",
          parameters: [
            FunctionParam.new!(%{name: "p1", type: :string, required: true}),
            FunctionParam.new!(%{name: "p2", type: :number, description: "Param 2"}),
            FunctionParam.new!(%{name: "p3", type: :string, enum: ["yellow", "red", "green"]})
          ]
        })

      # result = Function.for_api(fun)
      result = ChatOpenAI.for_api(fun)

      assert result == %{
               "name" => "say_hi",
               "description" => "Provide a friendly greeting.",
               "parameters" => params_def
             }
    end

    test "supports parameters_schema" do
      params_def = %{
        "type" => "object",
        "properties" => %{
          "p1" => %{"description" => nil, "type" => "string"},
          "p2" => %{"description" => "Param 2", "type" => "number"},
          "p3" => %{
            "description" => nil,
            "enum" => ["yellow", "red", "green"],
            "type" => "string"
          }
        },
        "required" => ["p1"]
      }

      {:ok, fun} =
        Function.new(%{
          "name" => "say_hi",
          "description" => "Provide a friendly greeting.",
          "parameters_schema" => params_def
        })

      # result = Function.for_api(fun)
      result = ChatOpenAI.for_api(fun)

      assert result == %{
               "name" => "say_hi",
               "description" => "Provide a friendly greeting.",
               "parameters" => params_def
             }
    end

    test "does not allow both parameters and parameters_schema" do
      {:error, changeset} =
        Function.new(%{
          name: "problem",
          parameters: [
            FunctionParam.new!(%{name: "p1", type: :string, required: true})
          ],
          parameters_schema: %{stuff: true}
        })

      assert {"Cannot use both parameters and parameters_schema", _} =
               changeset.errors[:parameters]
    end

    test "does not include the function to execute" do
      # don't try and send an Elixir function ref through to the API
      {:ok, fun} = Function.new(%{"name" => "hello_world", "function" => &hello_world/2})
      # result = Function.for_api(fun)
      result = ChatOpenAI.for_api(fun)
      refute Map.has_key?(result, "function")
    end
  end

  describe "call/2" do
    @tag live_call: true, live_open_ai: true
    test "basic content example" do
      # set_fake_llm_response({:ok, Message.new_assistant("\n\nRainbow Sox Co.")})

      # https://js.langchain.com/docs/modules/models/chat/
      {:ok, chat} = ChatOpenAI.new(%{temperature: 1, seed: 0})

      {:ok, [%Message{role: :assistant, content: response}]} =
        ChatOpenAI.call(chat, [
          Message.new_user!("Return the response 'Colorful Threads'.")
        ])

      assert response =~ "Colorful Threads"
    end

    @tag live_call: true, live_open_ai: true
    test "basic streamed content example's final result" do
      # set_fake_llm_response({:ok, Message.new_assistant("\n\nRainbow Sox Co.")})

      # https://js.langchain.com/docs/modules/models/chat/
      {:ok, chat} = ChatOpenAI.new(%{temperature: 1, seed: 0, stream: true})

      {:ok, result} =
        ChatOpenAI.call(chat, [
          Message.new_user!("Return the response 'Colorful Threads'.")
        ])

      # returns a list of MessageDeltas. A list of a list because it's "n" choices.
      assert result == [
               [
                 %LangChain.MessageDelta{
                   content: "",
                   status: :incomplete,
                   index: 0,
                   function_name: nil,
                   role: :assistant,
                   arguments: nil
                 }
               ],
               [
                 %LangChain.MessageDelta{
                   content: "Color",
                   status: :incomplete,
                   index: 0,
                   function_name: nil,
                   role: :unknown,
                   arguments: nil
                 }
               ],
               [
                 %LangChain.MessageDelta{
                   content: "ful",
                   status: :incomplete,
                   index: 0,
                   function_name: nil,
                   role: :unknown,
                   arguments: nil
                 }
               ],
               [
                 %LangChain.MessageDelta{
                   content: " Threads",
                   status: :incomplete,
                   index: 0,
                   function_name: nil,
                   role: :unknown,
                   arguments: nil
                 }
               ],
               [
                 %LangChain.MessageDelta{
                   content: nil,
                   status: :complete,
                   index: 0,
                   function_name: nil,
                   role: :unknown,
                   arguments: nil
                 }
               ]
             ]
    end

    @tag live_call: true, live_open_ai: true
    test "executing a function with arguments", %{weather: weather} do
      {:ok, chat} = ChatOpenAI.new(%{seed: 0, stream: false, model: @gpt4})

      {:ok, message} =
        Message.new_user("What is the weather like in Moab Utah?")

      {:ok, [message]} = ChatOpenAI.call(chat, [message], [weather])

      assert %Message{role: :assistant} = message
      assert message.status == :complete
      assert message.role == :assistant
      assert message.content == nil
      [call] = message.tool_calls
      assert call.status == :complete
      assert call.type == :function
      assert call.tool_id != nil
      assert call.arguments == %{"city" => "Moab", "state" => "UT"}
    end

    @tag live_call: true, live_open_ai: true
    test "LIVE: supports receiving multiple tool calls in a single response", %{weather: weather} do
      {:ok, chat} = ChatOpenAI.new(%{seed: 0, stream: false, model: @gpt4})

      {:ok, message} =
        Message.new_user(
          "What is the weather like in Moab Utah, Portland Oregon, and Baltimore MD? Explain your thought process."
        )

      {:ok, [message]} = ChatOpenAI.call(chat, [message], [weather])

      assert %Message{role: :assistant} = message
      assert message.status == :complete
      assert message.content == nil
      [call1, call2, call3] = message.tool_calls

      assert call1.status == :complete
      assert call1.type == :function
      assert call1.name == "get_weather"
      assert call1.arguments == %{"city" => "Moab", "state" => "UT"}

      assert call2.name == "get_weather"
      assert call2.arguments == %{"city" => "Portland", "state" => "OR"}

      assert call3.name == "get_weather"
      assert call3.arguments == %{"city" => "Baltimore", "state" => "MD"}
    end

    # TODO: Fake API response with multiples.
    # TODO: LLMChain needs to support it as well. Perform multiple function call executions.
    # TODO: Message structure needs to change for calling functions to support a single message executing multiples.
    #      - make it easy to support only receiving a single function call.

    @tag live_call: true, live_open_ai: true
    test "executes callback function when data is streamed" do
      callback = fn %MessageDelta{} = delta ->
        send(self(), {:message_delta, delta})
      end

      # https://js.langchain.com/docs/modules/models/chat/
      {:ok, chat} = ChatOpenAI.new(%{seed: 0, temperature: 1, stream: true})

      {:ok, _post_results} =
        ChatOpenAI.call(
          chat,
          [
            Message.new_user!("Return the exact response 'Hi'.")
          ],
          [],
          callback
        )

      # we expect to receive the response over 3 delta messages
      assert_receive {:message_delta, delta_1}, 500
      assert_receive {:message_delta, delta_2}, 500
      assert_receive {:message_delta, delta_3}, 500

      # IO.inspect(delta_1)
      # IO.inspect(delta_2)
      # IO.inspect(delta_3)

      merged =
        delta_1
        |> MessageDelta.merge_delta(delta_2)
        |> MessageDelta.merge_delta(delta_3)

      assert merged.role == :assistant
      assert merged.content =~ "Hi"
      assert merged.status == :complete
    end

    @tag live_call: true, live_open_ai: true
    test "executes callback function when data is NOT streamed" do
      callback = fn %Message{} = new_message ->
        send(self(), {:message_received, new_message})
      end

      # https://js.langchain.com/docs/modules/models/chat/
      # NOTE streamed. Should receive complete message.
      {:ok, chat} = ChatOpenAI.new(%{seed: 0, temperature: 1, stream: false})

      {:ok, [message]} =
        ChatOpenAI.call(
          chat,
          [
            Message.new_user!("Return the response 'Hi'.")
          ],
          [],
          callback
        )

      assert message.content =~ "Hi"
      assert message.index == 0
      assert_receive {:message_received, received_item}, 500
      assert %Message{} = received_item
      assert received_item.role == :assistant
      assert received_item.content =~ "Hi"
      assert received_item.index == 0
    end

    @tag live_call: true, live_open_ai: true
    test "handles when request is too large" do
      {:ok, chat} =
        ChatOpenAI.new(%{model: "gpt-3.5-turbo-0301", seed: 0, stream: false, temperature: 1})

      {:error, reason} = ChatOpenAI.call(chat, [too_large_user_request()])
      assert reason =~ "maximum context length"
    end
  end

  describe "do_process_response/1" do
    test "handles receiving a message" do
      response = %{
        "message" => %{"role" => "assistant", "content" => "Greetings!"},
        "finish_reason" => "stop",
        "index" => 1
      }

      assert %Message{} = struct = ChatOpenAI.do_process_response(response)
      assert struct.role == :assistant
      assert struct.content == "Greetings!"
      assert struct.index == 1
    end

    test "handles receiving a single tool_calls message" do
      response = %{
        "finish_reason" => "tool_calls",
        "index" => 0,
        "logprobs" => nil,
        "message" => %{
          "content" => nil,
          "role" => "assistant",
          "tool_calls" => [
            %{
              "function" => %{
                "arguments" => "{\"city\":\"Moab\",\"state\":\"UT\"}",
                "name" => "get_weather"
              },
              "id" => "call_mMSPuyLd915TQ9bcrk4NvLDX",
              "type" => "function"
            }
          ]
        }
      }

      assert %Message{} = struct = ChatOpenAI.do_process_response(response)

      assert struct.role == :assistant

      assert [%ToolCall{} = call] = struct.tool_calls
      assert call.tool_id == "call_mMSPuyLd915TQ9bcrk4NvLDX"
      assert call.type == :function
      assert call.name == "get_weather"
      assert call.arguments == %{"city" => "Moab", "state" => "UT"}
      assert struct.index == 0
    end

    test "handles receiving multiple tool_calls messages" do
      response = %{
        "finish_reason" => "tool_calls",
        "index" => 0,
        "logprobs" => nil,
        "message" => %{
          "content" => nil,
          "role" => "assistant",
          "tool_calls" => [
            %{
              "function" => %{
                "arguments" => "{\"city\": \"Moab\", \"state\": \"UT\"}",
                "name" => "get_weather"
              },
              "id" => "call_4L8NfePhSW8PdoHUWkvhzguu",
              "type" => "function"
            },
            %{
              "function" => %{
                "arguments" => "{\"city\": \"Portland\", \"state\": \"OR\"}",
                "name" => "get_weather"
              },
              "id" => "call_ylRu5SPegST9tppLEj6IJ0Rs",
              "type" => "function"
            },
            %{
              "function" => %{
                "arguments" => "{\"city\": \"Baltimore\", \"state\": \"MD\"}",
                "name" => "get_weather"
              },
              "id" => "call_G17PCZZBTyK0gwpzIzD4OBep",
              "type" => "function"
            }
          ]
        }
      }

      assert %Message{} = struct = ChatOpenAI.do_process_response(response)

      assert struct.role == :assistant

      assert struct.tool_calls == [
               ToolCall.new!(%{
                 type: :function,
                 tool_id: "call_4L8NfePhSW8PdoHUWkvhzguu",
                 name: "get_weather",
                 arguments: %{"city" => "Moab", "state" => "UT"},
                 status: :complete
               }),
               ToolCall.new!(%{
                 type: :function,
                 tool_id: "call_ylRu5SPegST9tppLEj6IJ0Rs",
                 name: "get_weather",
                 arguments: %{"city" => "Portland", "state" => "OR"},
                 status: :complete
               }),
               ToolCall.new!(%{
                 type: :function,
                 tool_id: "call_G17PCZZBTyK0gwpzIzD4OBep",
                 name: "get_weather",
                 arguments: %{"city" => "Baltimore", "state" => "MD"},
                 status: :complete
               })
             ]
    end

    test "handles receiving multiple tool_calls and one has invalid JSON" do
      response = %{
        "finish_reason" => "tool_calls",
        "index" => 0,
        "logprobs" => nil,
        "message" => %{
          "content" => nil,
          "role" => "assistant",
          "tool_calls" => [
            %{
              "function" => %{
                "arguments" => "{\"city\": \"Moab\", \"state\": \"UT\"}",
                "name" => "get_weather"
              },
              "id" => "call_4L8NfePhSW8PdoHUWkvhzguu",
              "type" => "function"
            },
            %{
              "function" => %{
                "arguments" => "{\"invalid\"}",
                "name" => "get_weather"
              },
              "id" => "call_ylRu5SPegST9tppLEj6IJ0Rs",
              "type" => "function"
            }
          ]
        }
      }

      assert {:error, reason} = ChatOpenAI.do_process_response(response)
      assert reason == "tool_calls: arguments: invalid json"
    end

    test "handles a single tool_call from list" do
      call = %{
        "function" => %{
          "arguments" => "{\"city\": \"Moab\", \"state\": \"UT\"}",
          "name" => "get_weather"
        },
        "id" => "call_4L8NfePhSW8PdoHUWkvhzguu",
        "type" => "function"
      }

      assert %ToolCall{} = call = ChatOpenAI.do_process_response(call)
      assert call.type == :function
      assert call.status == :complete
      assert call.tool_id == "call_4L8NfePhSW8PdoHUWkvhzguu"
      assert call.name == "get_weather"
      assert call.arguments == %{"city" => "Moab", "state" => "UT"}
    end

    test "handles receiving a tool_call with invalid JSON" do
      call = %{
        "function" => %{
          "arguments" => "{\"invalid\"}",
          "name" => "get_weather"
        },
        "id" => "call_4L8NfePhSW8PdoHUWkvhzguu",
        "type" => "function"
      }

      assert {:error, message} = ChatOpenAI.do_process_response(call)

      assert message == "arguments: invalid json"
    end

    test "handles streamed deltas for multiple tool calls" do
      deltas =
        Enum.map(get_streamed_deltas_multiple_tool_calls(), &ChatOpenAI.do_process_response(&1))

      combined =
        deltas
        |> List.flatten()
        |> Enum.reduce(nil, &MessageDelta.merge_delta(&2, &1))

      expected = %MessageDelta{
        content: nil,
        status: :complete,
        index: 0,
        role: :assistant,
        tool_calls: [
          %ToolCall{
            status: :incomplete,
            type: :function,
            tool_id: nil,
            name: "get_weather",
            arguments: "{\"city\": \"Moab\", \"state\": \"UT\"}",
            index: 0
          },
          %ToolCall{
            status: :incomplete,
            type: :function,
            tool_id: nil,
            name: "get_weather",
            arguments: "{\"city\": \"Portland\", \"state\": \"OR\"}",
            index: 1
          },
          %ToolCall{
            status: :incomplete,
            type: :function,
            tool_id: nil,
            name: "get_weather",
            arguments: "{\"city\": \"Baltimore\", \"state\": \"MD\"}",
            index: 2
          }
        ]
      }

      assert combined == expected
    end

    test "handles error from server that the max length has been reached" do
      response = %{
        "finish_reason" => "length",
        "index" => 0,
        "message" => %{
          "content" => "Some of the response that was abruptly",
          "role" => "assistant"
        }
      }

      assert %Message{} = struct = ChatOpenAI.do_process_response(response)

      assert struct.role == :assistant
      assert struct.content == "Some of the response that was abruptly"
      assert struct.index == 0
      assert struct.status == :length
    end

    test "handles receiving a delta message for a content message at different parts" do
      delta_content = LangChain.Fixtures.raw_deltas_for_content()

      msg_1 = Enum.at(delta_content, 0)
      msg_2 = Enum.at(delta_content, 1)
      msg_10 = Enum.at(delta_content, 10)

      expected_1 = %MessageDelta{
        content: "",
        index: 0,
        function_name: nil,
        role: :assistant,
        arguments: nil,
        status: :incomplete
      }

      [%MessageDelta{} = delta_1] = ChatOpenAI.do_process_response(msg_1)
      assert delta_1 == expected_1

      expected_2 = %MessageDelta{
        content: "Hello",
        index: 0,
        function_name: nil,
        role: :unknown,
        arguments: nil,
        status: :incomplete
      }

      [%MessageDelta{} = delta_2] = ChatOpenAI.do_process_response(msg_2)
      assert delta_2 == expected_2

      expected_10 = %MessageDelta{
        content: nil,
        index: 0,
        function_name: nil,
        role: :unknown,
        arguments: nil,
        status: :complete
      }

      [%MessageDelta{} = delta_10] = ChatOpenAI.do_process_response(msg_10)
      assert delta_10 == expected_10
    end

    test "handles json parse error from server" do
      {:error, "Received invalid JSON: " <> _} =
        Jason.decode("invalid json")
        |> ChatOpenAI.do_process_response()
    end

    test "handles unexpected response" do
      {:error, "Unexpected response"} =
        "unexpected"
        |> ChatOpenAI.do_process_response()
    end

    test "return multiple responses when given multiple choices" do
      # received multiple responses because multiples were requested.
      response = %{
        "choices" => [
          %{
            "message" => %{"role" => "assistant", "content" => "Greetings!"},
            "finish_reason" => "stop",
            "index" => 0
          },
          %{
            "message" => %{"role" => "assistant", "content" => "Howdy!"},
            "finish_reason" => "stop",
            "index" => 1
          }
        ]
      }

      [msg1, msg2] = ChatOpenAI.do_process_response(response)
      assert %Message{role: :assistant, index: 0} = msg1
      assert %Message{role: :assistant, index: 1} = msg2
      assert msg1.content == "Greetings!"
      assert msg2.content == "Howdy!"
    end
  end

  describe "streaming examples" do
    @tag live_call: true, live_open_ai: true
    test "supports streaming response calling function with args" do
      callback = fn data ->
        IO.inspect(data, label: "DATA")
        send(self(), {:streamed_fn, data})
      end

      {:ok, chat} = ChatOpenAI.new(%{seed: 0, stream: true})

      {:ok, message} =
        Message.new_user("Answer the following math question: What is 100 + 300 - 200?")

      response =
        ChatOpenAI.do_api_request(chat, [message], [LangChain.Tools.Calculator.new!()], callback)

      IO.inspect(response, label: "OPEN AI POST RESPONSE")

      assert_receive {:streamed_fn, received_data}, 300
      assert %MessageDelta{} = received_data
      assert received_data.role == :assistant
      assert received_data.index == 0
    end

    @tag live_call: true, live_open_ai: true
    test "STREAMING handles receiving an error when no messages sent" do
      chat = ChatOpenAI.new!(%{seed: 0, stream: true})

      {:error, reason} = ChatOpenAI.call(chat, [], [], nil)

      assert reason == "[] is too short - 'messages'"
    end

    @tag live_call: true, live_open_ai: true
    test "STREAMING handles receiving a timeout error" do
      callback = fn data ->
        send(self(), {:streamed_fn, data})
      end

      {:ok, chat} = ChatOpenAI.new(%{seed: 0, stream: true, receive_timeout: 50})

      {:error, reason} =
        ChatOpenAI.call(chat, [Message.new_user!("Why is the sky blue?")], [], callback)

      assert reason == "Request timed out"
    end
  end

  def setup_expected_json(_) do
    json_1 = %{
      "choices" => [
        %{
          "delta" => %{
            "content" => nil,
            "function_call" => %{"arguments" => "", "name" => "calculator"},
            "role" => "assistant"
          },
          "finish_reason" => nil,
          "index" => 0
        }
      ],
      "created" => 1_689_801_995,
      "id" => "chatcmpl-7e8yp1xBhriNXiqqZ0xJkgNrmMuGS",
      "model" => "gpt-4-0613",
      "object" => "chat.completion.chunk"
    }

    json_2 = %{
      "choices" => [
        %{
          "delta" => %{"function_call" => %{"arguments" => "{\n"}},
          "finish_reason" => nil,
          "index" => 0
        }
      ],
      "created" => 1_689_801_995,
      "id" => "chatcmpl-7e8yp1xBhriNXiqqZ0xJkgNrmMuGS",
      "model" => "gpt-4-0613",
      "object" => "chat.completion.chunk"
    }

    %{json_1: json_1, json_2: json_2}
  end

  describe "decode_stream/1" do
    setup :setup_expected_json

    test "correctly handles fully formed chat completion chunks", %{
      json_1: json_1,
      json_2: json_2
    } do
      data =
        "data: {\"id\":\"chatcmpl-7e8yp1xBhriNXiqqZ0xJkgNrmMuGS\",\"object\":\"chat.completion.chunk\",\"created\":1689801995,\"model\":\"gpt-4-0613\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":null,\"function_call\":{\"name\":\"calculator\",\"arguments\":\"\"}},\"finish_reason\":null}]}\n\n
         data: {\"id\":\"chatcmpl-7e8yp1xBhriNXiqqZ0xJkgNrmMuGS\",\"object\":\"chat.completion.chunk\",\"created\":1689801995,\"model\":\"gpt-4-0613\",\"choices\":[{\"index\":0,\"delta\":{\"function_call\":{\"arguments\":\"{\\n\"}},\"finish_reason\":null}]}\n\n"

      {parsed, incomplete} = ChatOpenAI.decode_stream({data, ""})

      # nothing incomplete. Parsed 2 objects.
      assert incomplete == ""
      assert parsed == [json_1, json_2]
    end

    test "correctly parses when data split over received messages", %{json_1: json_1} do
      # split the data over multiple messages
      data =
        "data: {\"id\":\"chatcmpl-7e8yp1xBhriNXiqqZ0xJkgNrmMuGS\",\"object\":\"chat.comple
         data: tion.chunk\",\"created\":1689801995,\"model\":\"gpt-4-0613\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":null,\"function_call\":{\"name\":\"calculator\",\"arguments\":\"\"}},\"finish_reason\":null}]}\n\n"

      {parsed, incomplete} = ChatOpenAI.decode_stream({data, ""})

      # nothing incomplete. Parsed 1 object.
      assert incomplete == ""
      assert parsed == [json_1]
    end

    test "correctly parses when data split over decode calls", %{json_1: json_1} do
      buffered = "{\"id\":\"chatcmpl-7e8yp1xBhriNXiqqZ0xJkgNrmMuGS\",\"object\":\"chat.comple"

      # incomplete message chunk processed in next call
      data =
        "data: tion.chunk\",\"created\":1689801995,\"model\":\"gpt-4-0613\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":null,\"function_call\":{\"name\":\"calculator\",\"arguments\":\"\"}},\"finish_reason\":null}]}\n\n"

      {parsed, incomplete} = ChatOpenAI.decode_stream({data, buffered})

      # nothing incomplete. Parsed 1 object.
      assert incomplete == ""
      assert parsed == [json_1]
    end

    test "correctly parses when data previously buffered and responses split and has leftovers",
         %{json_1: json_1, json_2: json_2} do
      buffered = "{\"id\":\"chatcmpl-7e8yp1xBhriNXiqqZ0xJkgNrmMuGS\",\"object\":\"chat.comple"

      # incomplete message chunk processed in next call
      data =
        "data: tion.chunk\",\"created\":1689801995,\"model\":\"gpt-4-0613\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":null,\"function_call\":{\"name\":\"calculator\",\"arguments\":\"\"}},\"finish_reason\":null}]}\n\n
         data: {\"id\":\"chatcmpl-7e8yp1xBhriNXiqqZ0xJkgNrmMuGS\",\"object\":\"chat.completion.chunk\",\"crea
         data: ted\":1689801995,\"model\":\"gpt-4-0613\",\"choices\":[{\"index\":0,\"delta\":{\"function_call\":{\"argu
         data: ments\":\"{\\n\"}},\"finish_reason\":null}]}\n\n
         data: {\"id\":\"chatcmpl-7e8yp1xBhriNXiqqZ0xJkgNrmMuGS\",\"object\":\"chat.comp"

      {parsed, incomplete} = ChatOpenAI.decode_stream({data, buffered})

      # nothing incomplete. Parsed 1 object.
      assert incomplete ==
               "{\"id\":\"chatcmpl-7e8yp1xBhriNXiqqZ0xJkgNrmMuGS\",\"object\":\"chat.comp"

      assert parsed == [json_1, json_2]
    end
  end

  describe "image vision using message parts" do
    @tag live_call: true, live_open_ai: true
    test "supports multi-modal user message with image prompt" do
      # https://platform.openai.com/docs/guides/vision
      {:ok, chat} = ChatOpenAI.new(%{model: "gpt-4-vision-preview", seed: 0})

      url =
        "https://upload.wikimedia.org/wikipedia/commons/thumb/d/dd/Gfp-wisconsin-madison-the-nature-boardwalk.jpg/2560px-Gfp-wisconsin-madison-the-nature-boardwalk.jpg"

      message =
        Message.new_user!([
          UserContentPart.text!("Identify what this is a picture of:"),
          UserContentPart.image_url!(url)
        ])

      {:ok, [response]} = ChatOpenAI.call(chat, [message], [])

      assert %Message{role: :assistant} = response
      assert String.contains?(response.content, "boardwalk")
      assert String.contains?(response.content, "grass")
    end
  end

  describe "do_process_response - MessageDeltas" do
    test "parses basic text delta" do
      [d1, d2, d3, d4] = get_streamed_deltas_basic_text()

      [delta1] = ChatOpenAI.do_process_response(d1)

      assert %MessageDelta{
               role: :assistant,
               content: "",
               status: :incomplete,
               index: 0
             } = delta1

      [delta2] = ChatOpenAI.do_process_response(d2)

      assert %MessageDelta{
               role: :unknown,
               content: "Colorful",
               status: :incomplete,
               index: 0
             } = delta2

      [delta3] = ChatOpenAI.do_process_response(d3)

      assert %MessageDelta{
               role: :unknown,
               content: " Threads",
               status: :incomplete,
               index: 0
             } = delta3

      [delta4] = ChatOpenAI.do_process_response(d4)

      assert %MessageDelta{
               role: :unknown,
               content: nil,
               status: :complete,
               index: 0
             } = delta4
    end

    test "parses individual tool_calls in a delta message" do
      # chunk 1
      tool_call_response = %{
        "function" => %{"arguments" => "", "name" => "get_weather"},
        "id" => "call_1234",
        "index" => 0,
        "type" => "function"
      }

      assert %ToolCall{} = call = ChatOpenAI.do_process_response(tool_call_response)
      assert call.status == :incomplete
      assert call.type == :function
      assert call.name == "get_weather"
      assert call.arguments == nil
      assert call.index == 0

      # chunk 2
      tool_call_response = %{
        "function" => %{"arguments" => "{\"city\": \"Moab\", "},
        "index" => 0
      }

      assert %ToolCall{} = call = ChatOpenAI.do_process_response(tool_call_response)
      assert call.status == :incomplete
      assert call.type == :function
      assert call.name == nil
      assert call.arguments == "{\"city\": \"Moab\", "
      assert call.index == 0
    end

    test "parses a MessageDelta with tool_calls" do
      response = get_streamed_deltas_multiple_tool_calls()
      [d1, d2, d3 | _rest] = response
      last = List.last(response)

      assert [%MessageDelta{} = delta1] = ChatOpenAI.do_process_response(d1)
      assert delta1.role == :assistant
      assert delta1.status == :incomplete
      assert delta1.content == nil
      assert delta1.index == 0
      assert delta1.tool_calls == nil

      assert [%MessageDelta{} = delta2] = ChatOpenAI.do_process_response(d2)
      assert delta2.role == :unknown
      assert delta2.status == :incomplete
      assert delta2.content == nil
      assert delta2.index == 0

      expected_call =
        ToolCall.new!(%{
          id: "call_fFRRtPwaroz9wbs2eWR7dpcW",
          index: 0,
          type: :function,
          status: :incomplete,
          name: "get_weather",
          arguments: nil
        })

      assert [expected_call] == delta2.tool_calls

      assert [%MessageDelta{} = delta3] = ChatOpenAI.do_process_response(d3)
      assert delta3.role == :unknown
      assert delta3.status == :incomplete
      assert delta3.content == nil
      assert delta3.index == 0

      expected_call =
        ToolCall.new!(%{
          id: nil,
          index: 0,
          type: :function,
          status: :incomplete,
          name: nil,
          arguments: "{\"ci"
        })

      assert [expected_call] == delta3.tool_calls

      assert [%MessageDelta{} = delta4] = ChatOpenAI.do_process_response(last)
      assert delta4.role == :unknown
      assert delta4.status == :complete
      assert delta4.content == nil
      assert delta4.index == 0
      assert delta4.tool_calls == nil
    end
  end

  def get_streamed_deltas_basic_text do
    [
      %{
        "choices" => [
          %{
            "delta" => %{"content" => "", "role" => "assistant"},
            "finish_reason" => nil,
            "index" => 0,
            "logprobs" => nil
          }
        ],
        "created" => 1_712_610_022,
        "id" => "chatcmpl-9BqOELc5ktxtKeK1BtTBG2t0aaDty",
        "model" => "gpt-3.5-turbo-0125",
        "object" => "chat.completion.chunk",
        "system_fingerprint" => "fp_b28b39ffa8"
      },
      %{
        "choices" => [
          %{
            "delta" => %{"content" => "Colorful"},
            "finish_reason" => nil,
            "index" => 0,
            "logprobs" => nil
          }
        ],
        "created" => 1_712_610_022,
        "id" => "chatcmpl-9BqOELc5ktxtKeK1BtTBG2t0aaDty",
        "model" => "gpt-3.5-turbo-0125",
        "object" => "chat.completion.chunk",
        "system_fingerprint" => "fp_b28b39ffa8"
      },
      %{
        "choices" => [
          %{
            "delta" => %{"content" => " Threads"},
            "finish_reason" => nil,
            "index" => 0,
            "logprobs" => nil
          }
        ],
        "created" => 1_712_610_022,
        "id" => "chatcmpl-9BqOELc5ktxtKeK1BtTBG2t0aaDty",
        "model" => "gpt-3.5-turbo-0125",
        "object" => "chat.completion.chunk",
        "system_fingerprint" => "fp_b28b39ffa8"
      },
      %{
        "choices" => [
          %{
            "delta" => %{},
            "finish_reason" => "stop",
            "index" => 0,
            "logprobs" => nil
          }
        ],
        "created" => 1_712_610_022,
        "id" => "chatcmpl-9BqOELc5ktxtKeK1BtTBG2t0aaDty",
        "model" => "gpt-3.5-turbo-0125",
        "object" => "chat.completion.chunk",
        "system_fingerprint" => "fp_b28b39ffa8"
      }
    ]
  end

  def get_streamed_deltas_multiple_tool_calls() do
    # NOTE: these are artificially condensed for brevity.

    [
      %{
        "choices" => [
          %{
            "delta" => %{"content" => nil, "role" => "assistant"},
            "finish_reason" => nil,
            "index" => 0,
            "logprobs" => nil
          }
        ],
        "created" => 1_712_606_513,
        "id" => "chatcmpl-9BpTdyN883PR9yKpIK2wYYypgWw1Q",
        "model" => "gpt-4-1106-preview",
        "object" => "chat.completion.chunk",
        "system_fingerprint" => "fp_d6526cacfe"
      },
      %{
        "choices" => [
          %{
            "delta" => %{
              "tool_calls" => [
                %{
                  "function" => %{"arguments" => "", "name" => "get_weather"},
                  "id" => "call_fFRRtPwaroz9wbs2eWR7dpcW",
                  "index" => 0,
                  "type" => "function"
                }
              ]
            },
            "finish_reason" => nil,
            "index" => 0,
            "logprobs" => nil
          }
        ],
        "created" => 1_712_606_513,
        "id" => "chatcmpl-9BpTdyN883PR9yKpIK2wYYypgWw1Q",
        "model" => "gpt-4-1106-preview",
        "object" => "chat.completion.chunk",
        "system_fingerprint" => "fp_d6526cacfe"
      },
      %{
        "choices" => [
          %{
            "delta" => %{
              "tool_calls" => [
                %{"function" => %{"arguments" => "{\"ci"}, "index" => 0}
              ]
            },
            "finish_reason" => nil,
            "index" => 0,
            "logprobs" => nil
          }
        ],
        "created" => 1_712_606_513,
        "id" => "chatcmpl-9BpTdyN883PR9yKpIK2wYYypgWw1Q",
        "model" => "gpt-4-1106-preview",
        "object" => "chat.completion.chunk",
        "system_fingerprint" => "fp_d6526cacfe"
      },
      %{
        "choices" => [
          %{
            "delta" => %{
              "tool_calls" => [
                %{
                  "function" => %{"arguments" => "ty\": \"Moab\", \"state\": \"UT\"}"},
                  "index" => 0
                }
              ]
            },
            "finish_reason" => nil,
            "index" => 0,
            "logprobs" => nil
          }
        ],
        "created" => 1_712_606_513,
        "id" => "chatcmpl-9BpTdyN883PR9yKpIK2wYYypgWw1Q",
        "model" => "gpt-4-1106-preview",
        "object" => "chat.completion.chunk",
        "system_fingerprint" => "fp_d6526cacfe"
      },
      %{
        "choices" => [
          %{
            "delta" => %{
              "tool_calls" => [
                %{
                  "function" => %{"arguments" => "", "name" => "get_weather"},
                  "id" => "call_sEmznyM1sGqYQ4dbNGdubmxa",
                  "index" => 1,
                  "type" => "function"
                }
              ]
            },
            "finish_reason" => nil,
            "index" => 0,
            "logprobs" => nil
          }
        ],
        "created" => 1_712_606_513,
        "id" => "chatcmpl-9BpTdyN883PR9yKpIK2wYYypgWw1Q",
        "model" => "gpt-4-1106-preview",
        "object" => "chat.completion.chunk",
        "system_fingerprint" => "fp_d6526cacfe"
      },
      %{
        "choices" => [
          %{
            "delta" => %{
              "tool_calls" => [
                %{"function" => %{"arguments" => "{\"ci"}, "index" => 1}
              ]
            },
            "finish_reason" => nil,
            "index" => 0,
            "logprobs" => nil
          }
        ],
        "created" => 1_712_606_513,
        "id" => "chatcmpl-9BpTdyN883PR9yKpIK2wYYypgWw1Q",
        "model" => "gpt-4-1106-preview",
        "object" => "chat.completion.chunk",
        "system_fingerprint" => "fp_d6526cacfe"
      },
      %{
        "choices" => [
          %{
            "delta" => %{
              "tool_calls" => [
                %{
                  "function" => %{"arguments" => "ty\": \"Portland\", \"state\": \"OR\"}"},
                  "index" => 1
                }
              ]
            },
            "finish_reason" => nil,
            "index" => 0,
            "logprobs" => nil
          }
        ],
        "created" => 1_712_606_513,
        "id" => "chatcmpl-9BpTdyN883PR9yKpIK2wYYypgWw1Q",
        "model" => "gpt-4-1106-preview",
        "object" => "chat.completion.chunk",
        "system_fingerprint" => "fp_d6526cacfe"
      },
      %{
        "choices" => [
          %{
            "delta" => %{
              "tool_calls" => [
                %{
                  "function" => %{"arguments" => "", "name" => "get_weather"},
                  "id" => "call_cPufqMGm4TOFtqiqFPfz7pcp",
                  "index" => 2,
                  "type" => "function"
                }
              ]
            },
            "finish_reason" => nil,
            "index" => 0,
            "logprobs" => nil
          }
        ],
        "created" => 1_712_606_513,
        "id" => "chatcmpl-9BpTdyN883PR9yKpIK2wYYypgWw1Q",
        "model" => "gpt-4-1106-preview",
        "object" => "chat.completion.chunk",
        "system_fingerprint" => "fp_d6526cacfe"
      },
      %{
        "choices" => [
          %{
            "delta" => %{
              "tool_calls" => [
                %{"function" => %{"arguments" => "{\"ci"}, "index" => 2}
              ]
            },
            "finish_reason" => nil,
            "index" => 0,
            "logprobs" => nil
          }
        ],
        "created" => 1_712_606_513,
        "id" => "chatcmpl-9BpTdyN883PR9yKpIK2wYYypgWw1Q",
        "model" => "gpt-4-1106-preview",
        "object" => "chat.completion.chunk",
        "system_fingerprint" => "fp_d6526cacfe"
      },
      %{
        "choices" => [
          %{
            "delta" => %{
              "tool_calls" => [
                %{
                  "function" => %{"arguments" => "ty\": \"Baltimore\", \"state\": \"MD\"}"},
                  "index" => 2
                }
              ]
            },
            "finish_reason" => nil,
            "index" => 0,
            "logprobs" => nil
          }
        ],
        "created" => 1_712_606_513,
        "id" => "chatcmpl-9BpTdyN883PR9yKpIK2wYYypgWw1Q",
        "model" => "gpt-4-1106-preview",
        "object" => "chat.completion.chunk",
        "system_fingerprint" => "fp_d6526cacfe"
      },
      %{
        "choices" => [
          %{
            "delta" => %{},
            "finish_reason" => "tool_calls",
            "index" => 0,
            "logprobs" => nil
          }
        ],
        "created" => 1_712_606_513,
        "id" => "chatcmpl-9BpTdyN883PR9yKpIK2wYYypgWw1Q",
        "model" => "gpt-4-1106-preview",
        "object" => "chat.completion.chunk",
        "system_fingerprint" => "fp_d6526cacfe"
      }
    ]
  end
end
