using Microsoft.Extensions.Diagnostics.HealthChecks;

public sealed class PostStorageHealthCheck(IServiceScopeFactory scopeFactory) : IHealthCheck
{
    public async Task<HealthCheckResult> CheckHealthAsync(
        HealthCheckContext context,
        CancellationToken cancellationToken = default)
    {
        try
        {
            await using var scope = scopeFactory.CreateAsyncScope();
            var repository = scope.ServiceProvider.GetRequiredService<IPostRepository>();
            await repository.CheckHealthAsync(cancellationToken);
            return HealthCheckResult.Healthy("Post storage is reachable.");
        }
        catch (Exception exception)
        {
            return HealthCheckResult.Unhealthy("Post storage is unavailable.", exception);
        }
    }
}
