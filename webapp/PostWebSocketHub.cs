using System.Collections.Concurrent;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;

public sealed class PostWebSocketHub
{
    private readonly ConcurrentDictionary<Guid, ConnectedClient> clients = new();

    public int ConnectedClientCount => clients.Count;

    public Guid Add(WebSocket socket)
    {
        var clientId = Guid.NewGuid();
        clients[clientId] = new ConnectedClient(socket);
        return clientId;
    }

    public async Task WaitForDisconnectAsync(
        WebSocket socket,
        CancellationToken cancellationToken)
    {
        var buffer = new byte[1024];

        while (socket.State == WebSocketState.Open)
        {
            var result = await socket.ReceiveAsync(
                new ArraySegment<byte>(buffer),
                cancellationToken);

            if (result.MessageType == WebSocketMessageType.Close)
                break;
        }
    }

    public async Task RemoveAsync(Guid clientId)
    {
        if (!clients.TryRemove(clientId, out var client))
            return;

        await client.CloseAsync();
    }

    public async Task BroadcastAsync<T>(T message)
    {
        var payload = JsonSerializer.SerializeToUtf8Bytes(
            message,
            new JsonSerializerOptions(JsonSerializerDefaults.Web));

        await BroadcastPayloadAsync(payload);
    }

    public async Task BroadcastPayloadAsync(string payload)
    {
        await BroadcastPayloadAsync(Encoding.UTF8.GetBytes(payload));
    }

    private async Task BroadcastPayloadAsync(byte[] payload)
    {
        var sends = clients.ToArray().Select(async pair =>
        {
            var (clientId, client) = pair;
            try
            {
                await client.SendAsync(payload);
            }
            catch (WebSocketException)
            {
                await RemoveAsync(clientId);
            }
            catch (ObjectDisposedException)
            {
                await RemoveAsync(clientId);
            }
            catch (InvalidOperationException)
            {
                await RemoveAsync(clientId);
            }
        });

        await Task.WhenAll(sends);
    }

    private sealed class ConnectedClient(WebSocket socket)
    {
        private readonly SemaphoreSlim sendLock = new(1, 1);

        public async Task SendAsync(byte[] payload)
        {
            await sendLock.WaitAsync();
            try
            {
                if (socket.State != WebSocketState.Open)
                    return;

                await socket.SendAsync(
                    new ArraySegment<byte>(payload),
                    WebSocketMessageType.Text,
                    endOfMessage: true,
                    CancellationToken.None);
            }
            finally
            {
                sendLock.Release();
            }
        }

        public async Task CloseAsync()
        {
            await sendLock.WaitAsync();
            try
            {
                if (socket.State is WebSocketState.Open or WebSocketState.CloseReceived)
                {
                    await socket.CloseAsync(
                        WebSocketCloseStatus.NormalClosure,
                        "Connection closed",
                        CancellationToken.None);
                }
            }
            catch (WebSocketException)
            {
                // The client may already have disconnected.
            }
            catch (ObjectDisposedException)
            {
                // The client may already have disconnected.
            }
            finally
            {
                sendLock.Release();
                socket.Dispose();
                sendLock.Dispose();
            }
        }
    }
}
