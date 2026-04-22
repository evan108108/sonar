defmodule SonarWeb.MessagesChannelTest do
  use SonarWeb.ChannelCase

  test "join messages:events succeeds" do
    {:ok, _, _socket} =
      SonarWeb.SonarSocket
      |> socket()
      |> subscribe_and_join(SonarWeb.MessagesChannel, "messages:events")
  end

  test "broadcasts are received by subscribers" do
    {:ok, _, _socket} =
      SonarWeb.SonarSocket
      |> socket()
      |> subscribe_and_join(SonarWeb.MessagesChannel, "messages:events")

    SonarWeb.Endpoint.broadcast("messages:events", "new_message", %{
      message_id: "test123",
      from_peer: "peer456",
      question: "Hello?",
      direction: "inbound",
      status: "pending"
    })

    assert_push "new_message", %{
      message_id: "test123",
      from_peer: "peer456",
      question: "Hello?"
    }
  end

  test "reply_received broadcast is pushed to subscribers" do
    {:ok, _, _socket} =
      SonarWeb.SonarSocket
      |> socket()
      |> subscribe_and_join(SonarWeb.MessagesChannel, "messages:events")

    SonarWeb.Endpoint.broadcast("messages:events", "reply_received", %{
      message_id: "msg789",
      from_peer: "peer456",
      answer: "All good"
    })

    assert_push "reply_received", %{
      message_id: "msg789",
      answer: "All good"
    }
  end
end
