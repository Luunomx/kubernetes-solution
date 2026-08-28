using System.Globalization;

public sealed class AppMetrics
{
    private long postsCreated;
    private long postsDeleted;
    private long chatResets;

    public void RecordPostCreated() => Interlocked.Increment(ref postsCreated);

    public void RecordPostDeleted() => Interlocked.Increment(ref postsDeleted);

    public void RecordChatReset() => Interlocked.Increment(ref chatResets);

    public string RenderPrometheus(int websocketClients)
    {
        return string.Join('\n',
            "# HELP bulletinboard_posts_created_total Total posts created since process start.",
            "# TYPE bulletinboard_posts_created_total counter",
            $"bulletinboard_posts_created_total {Interlocked.Read(ref postsCreated).ToString(CultureInfo.InvariantCulture)}",
            "# HELP bulletinboard_posts_deleted_total Total posts deleted since process start.",
            "# TYPE bulletinboard_posts_deleted_total counter",
            $"bulletinboard_posts_deleted_total {Interlocked.Read(ref postsDeleted).ToString(CultureInfo.InvariantCulture)}",
            "# HELP bulletinboard_chat_resets_total Total chat resets since process start.",
            "# TYPE bulletinboard_chat_resets_total counter",
            $"bulletinboard_chat_resets_total {Interlocked.Read(ref chatResets).ToString(CultureInfo.InvariantCulture)}",
            "# HELP bulletinboard_websocket_clients Current connected WebSocket clients.",
            "# TYPE bulletinboard_websocket_clients gauge",
            $"bulletinboard_websocket_clients {websocketClients.ToString(CultureInfo.InvariantCulture)}",
            string.Empty);
    }
}
