using MongoDB.Bson;
using MongoDB.Bson.Serialization.Attributes;
using MongoDB.Driver;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.AspNetCore.RateLimiting;
using System.Security.Cryptography;
using System.Text.Json;
using System.Net.WebSockets;
using System.Text;
using System.Threading.RateLimiting;

var builder = WebApplication.CreateBuilder(args);

// -----------------------
// CORS CONFIGURATION
// -----------------------
builder.Services.AddCors(options =>
{
    var allowedOrigins = (Environment.GetEnvironmentVariable("CORS_ALLOWED_ORIGINS")
        ?? "http://bulletinboard.local,http://localhost:5173,http://127.0.0.1:5173")
        .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

    options.AddPolicy("AllowBulletinBoard", policy =>
    {
        policy
            .WithOrigins(allowedOrigins)
            .AllowAnyHeader()
            .AllowAnyMethod()
            .AllowCredentials();
    });
});

// -----------------------
// RATE LIMITING
// -----------------------
builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    options.AddPolicy("write", context =>
        RateLimitPartition.GetFixedWindowLimiter(
            context.Connection.RemoteIpAddress?.ToString() ?? "unknown",
            _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 30,
                Window = TimeSpan.FromMinutes(1),
                QueueLimit = 0,
                AutoReplenishment = true
            }));
});

// -----------------------
// JSON SERIALIZATION
// -----------------------
builder.Services.ConfigureHttpJsonOptions(options =>
{
    options.SerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
});

// -----------------------
// STORAGE CONFIGURATION
// -----------------------
string storageMode = (Environment.GetEnvironmentVariable("POST_STORAGE")
    ?? (builder.Environment.IsDevelopment() ? "inmemory" : "mongodb"))
    .Trim()
    .ToLowerInvariant();

if (storageMode == "inmemory")
{
    builder.Services.AddSingleton<IPostRepository, InMemoryPostRepository>();
    Console.WriteLine("[INFO] Using in-memory post storage.");
}
else if (storageMode == "mongodb")
{
    string? connectionString = Environment.GetEnvironmentVariable("MONGO_CONNECTION_STRING");
    string mongoDatabaseName = Environment.GetEnvironmentVariable("MONGO_DATABASE") ?? "BulletinBoardDb";

    if (string.IsNullOrWhiteSpace(connectionString))
    {
        var mongoHost = Environment.GetEnvironmentVariable("MONGO_HOST") ?? "localhost";
        var mongoPort = Environment.GetEnvironmentVariable("MONGO_PORT") ?? "27017";
        var mongoUser = Environment.GetEnvironmentVariable("MONGO_ROOT_USERNAME");
        var mongoPass = Environment.GetEnvironmentVariable("MONGO_ROOT_PASSWORD");

        if (!string.IsNullOrEmpty(mongoUser) && !string.IsNullOrEmpty(mongoPass))
            connectionString = $"mongodb://{Uri.EscapeDataString(mongoUser)}:{Uri.EscapeDataString(mongoPass)}@{mongoHost}:{mongoPort}/{mongoDatabaseName}?authSource=admin";
        else
            connectionString = $"mongodb://{mongoHost}:{mongoPort}";
    }

    Console.WriteLine($"[INFO] Connecting to MongoDB database '{mongoDatabaseName}'.");

    builder.Services.AddSingleton<IMongoClient>(new MongoClient(connectionString));
    builder.Services.AddScoped(sp =>
    {
        var client = sp.GetRequiredService<IMongoClient>();
        return client.GetDatabase(mongoDatabaseName);
    });
    builder.Services.AddScoped<IPostRepository, MongoPostRepository>();
}
else
{
    throw new InvalidOperationException($"Unsupported POST_STORAGE value '{storageMode}'. Use 'inmemory' or 'mongodb'.");
}

builder.Services.AddHealthChecks()
    .AddCheck<PostStorageHealthCheck>("post-storage", tags: ["ready"]);
builder.Services.AddSingleton<AppMetrics>();
builder.Services.AddSingleton<PostWebSocketHub>();
builder.Services.AddSingleton<RealtimeBroadcaster>();
builder.Services.AddHostedService(sp => sp.GetRequiredService<RealtimeBroadcaster>());

var app = builder.Build();

var resetApiKey = Environment.GetEnvironmentVariable("RESET_API_KEY");

// -----------------------
// PIPELINE
// -----------------------
app.UseWebSockets(new WebSocketOptions
{
    KeepAliveInterval = TimeSpan.FromSeconds(30)
});
app.UseRateLimiter();
app.UseCors("AllowBulletinBoard");
app.UseDefaultFiles();
app.UseStaticFiles();

// -----------------------
// API ENDPOINTS
// -----------------------

// WebSocket endpoint for live post updates.
app.Map("/api/ws", async (HttpContext context, PostWebSocketHub hub) =>
{
    if (!context.WebSockets.IsWebSocketRequest)
    {
        context.Response.StatusCode = StatusCodes.Status400BadRequest;
        await context.Response.WriteAsync("A WebSocket connection is required.");
        return;
    }

    using var socket = await context.WebSockets.AcceptWebSocketAsync();
    var clientId = hub.Add(socket);

    try
    {
        await hub.WaitForDisconnectAsync(socket, context.RequestAborted);
    }
    catch (OperationCanceledException) when (context.RequestAborted.IsCancellationRequested)
    {
        // The request was cancelled because the client disconnected.
    }
    catch (WebSocketException)
    {
        // The client closed the connection without a WebSocket close handshake.
    }
    finally
    {
        await hub.RemoveAsync(clientId);
    }
});

app.MapHealthChecks("/health/live", new HealthCheckOptions
{
    Predicate = _ => false
});

app.MapHealthChecks("/health/ready", new HealthCheckOptions
{
    Predicate = check => check.Tags.Contains("ready")
});

app.MapGet("/metrics", (AppMetrics metrics, PostWebSocketHub hub) =>
    Results.Text(
        metrics.RenderPrometheus(hub.ConnectedClientCount),
        "text/plain; version=0.0.4; charset=utf-8"));

// GET all posts
// Reset all posts for the shared local chat.
app.MapDelete("/api/posts", async (
    HttpContext context,
    IPostRepository repository,
    RealtimeBroadcaster broadcaster,
    AppMetrics metrics) =>
{
    if (!HasResetAuthorization(context, resetApiKey))
        return Results.Unauthorized();

    await repository.ClearAsync();
    await broadcaster.PublishAsync(new { type = "chatReset" });
    metrics.RecordChatReset();
    return Results.NoContent();
}).RequireRateLimiting("write");

app.MapGet("/api/posts", async (IPostRepository repository) =>
{
    var posts = await repository.ListAsync();

    var swedishZone = TimeZoneInfo.FindSystemTimeZoneById("Europe/Stockholm");

    var formattedPosts = posts.Select(p => new
    {
        id = p.Id,
        name = p.Name,
        message = p.Message,
        creationTime = TimeZoneInfo.ConvertTimeFromUtc(p.CreationTime, swedishZone)
                                   .ToString("yyyy-MM-dd HH:mm")
    });

    return Results.Ok(formattedPosts);
});

// POST new post
app.MapPost("/api/posts", async (
    HttpContext ctx,
    IPostRepository repository,
    RealtimeBroadcaster broadcaster,
    AppMetrics metrics) =>
{
    try
    {
        var request = await ctx.Request.ReadFromJsonAsync<PostRequest>();
        if (request is null)
            return Results.BadRequest(new { error = "A JSON request body is required." });

        var validationErrors = PostValidation.Validate(request);
        if (validationErrors.Count > 0)
            return Results.ValidationProblem(validationErrors);

        var name = string.IsNullOrWhiteSpace(request.Name) ? "Anonymous" : request.Name.Trim();
        var message = request.Message!.Trim();

        var newPost = await repository.CreateAsync(name, message);

        await broadcaster.PublishAsync(new
        {
            type = "postCreated",
            clientId = request.ClientId,
            post = new
            {
                id = newPost.Id,
                name = newPost.Name,
                message = newPost.Message,
                creationTime = TimeZoneInfo.ConvertTimeFromUtc(
                    newPost.CreationTime,
                    TimeZoneInfo.FindSystemTimeZoneById("Europe/Stockholm"))
                    .ToString("yyyy-MM-dd HH:mm")
            }
        });

        metrics.RecordPostCreated();

        return Results.Created($"/api/posts/{newPost.Id}", newPost);
    }
    catch (Exception ex)
    {
        Console.WriteLine($"[ERROR] POST /api/posts failed: {ex.Message}");
        return Results.Problem("Internal server error.");
    }
}).RequireRateLimiting("write");

// DELETE post
app.MapDelete("/api/posts/{id}", async (
    int id,
    HttpContext context,
    IPostRepository repository,
    AppMetrics metrics) =>
{
    if (!HasResetAuthorization(context, resetApiKey))
        return Results.Unauthorized();

    var deleted = await repository.DeleteAsync(id);
    if (deleted)
        metrics.RecordPostDeleted();

    return deleted ? Results.Ok() : Results.NotFound();
}).RequireRateLimiting("write");

app.Run();

static bool HasResetAuthorization(HttpContext context, string? expectedApiKey)
{
    if (string.IsNullOrWhiteSpace(expectedApiKey))
        return true;

    if (!context.Request.Headers.TryGetValue("X-Reset-Key", out var suppliedApiKey))
        return false;

    var expectedBytes = Encoding.UTF8.GetBytes(expectedApiKey);
    var suppliedBytes = Encoding.UTF8.GetBytes(suppliedApiKey.ToString());

    return CryptographicOperations.FixedTimeEquals(expectedBytes, suppliedBytes);
}

// -----------------------
// MODEL
// -----------------------
public class Post
{
    [BsonId]
    [BsonRepresentation(BsonType.ObjectId)]
    public string? _id { get; set; }

    public int Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public string Message { get; set; } = string.Empty;
    public DateTime CreationTime { get; set; } = DateTime.UtcNow;
}
