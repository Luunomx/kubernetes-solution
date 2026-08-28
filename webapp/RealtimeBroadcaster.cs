using StackExchange.Redis;
using System.Text.Json;

public sealed class RealtimeBroadcaster(
    PostWebSocketHub hub,
    ILogger<RealtimeBroadcaster> logger) : BackgroundService
{
    private const string ChannelName = "bulletinboard:realtime";
    private readonly string? connectionString =
        Environment.GetEnvironmentVariable("REDIS_CONNECTION_STRING");
    private IConnectionMultiplexer? redis;

    public async Task PublishAsync<T>(T message)
    {
        var payload = JsonSerializer.Serialize(
            message,
            new JsonSerializerOptions(JsonSerializerDefaults.Web));

        var connection = redis;
        if (connection?.IsConnected == true)
        {
            try
            {
                await connection.GetSubscriber().PublishAsync(
                    RedisChannel.Literal(ChannelName),
                    payload);
                return;
            }
            catch (RedisException exception)
            {
                logger.LogWarning(exception, "Redis publish failed; broadcasting locally.");
            }
        }

        await hub.BroadcastPayloadAsync(payload);
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (string.IsNullOrWhiteSpace(connectionString))
        {
            logger.LogInformation("Redis backplane disabled; using process-local WebSockets.");
            await WaitForShutdownAsync(stoppingToken);
            return;
        }

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                redis = await ConnectionMultiplexer.ConnectAsync(connectionString);
                var subscriber = redis.GetSubscriber();

                await subscriber.SubscribeAsync(
                    RedisChannel.Literal(ChannelName),
                    (channel, value) =>
                    {
                        _ = channel;
                        _ = hub.BroadcastPayloadAsync(value.ToString());
                    });

                logger.LogInformation("Redis realtime backplane connected.");
                await WaitForShutdownAsync(stoppingToken);
                return;
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                return;
            }
            catch (Exception exception)
            {
                logger.LogWarning(
                    exception,
                    "Redis backplane unavailable; retrying in 10 seconds.");
                redis?.Dispose();
                redis = null;

                try
                {
                    await Task.Delay(TimeSpan.FromSeconds(10), stoppingToken);
                }
                catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
                {
                    return;
                }
            }
        }
    }

    private static async Task WaitForShutdownAsync(CancellationToken cancellationToken)
    {
        try
        {
            await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            // Normal application shutdown.
        }
    }

    public override void Dispose()
    {
        redis?.Dispose();
        base.Dispose();
    }
}
