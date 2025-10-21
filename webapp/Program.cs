using MongoDB.Bson;
using MongoDB.Bson.Serialization.Attributes;
using MongoDB.Driver;
using System.Text.Json;

var builder = WebApplication.CreateBuilder(args);

// -----------------------
// CORS CONFIGURATION
// -----------------------
builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowBulletinBoard", policy =>
    {
        policy
            .WithOrigins("http://bulletinboard.local")
            .AllowAnyHeader()
            .AllowAnyMethod()
            .AllowCredentials();
    });
});

// -----------------------
// JSON SERIALIZATION
// -----------------------
builder.Services.ConfigureHttpJsonOptions(options =>
{
    options.SerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
});

// -----------------------
// MONGODB CONFIGURATION
// -----------------------
string? connectionString = Environment.GetEnvironmentVariable("MONGO_CONNECTION_STRING");
string mongoDatabaseName = Environment.GetEnvironmentVariable("MONGO_DATABASE") ?? "BulletinBoardDb";

if (string.IsNullOrWhiteSpace(connectionString))
{
    var mongoHost = Environment.GetEnvironmentVariable("MONGO_HOST") ?? "localhost";
    var mongoPort = Environment.GetEnvironmentVariable("MONGO_PORT") ?? "27017";
    var mongoUser = Environment.GetEnvironmentVariable("MONGO_ROOT_USERNAME");
    var mongoPass = Environment.GetEnvironmentVariable("MONGO_ROOT_PASSWORD");

    if (!string.IsNullOrEmpty(mongoUser) && !string.IsNullOrEmpty(mongoPass))
        connectionString = $"mongodb://{mongoUser}:{mongoPass}@{mongoHost}:{mongoPort}/{mongoDatabaseName}?authSource=admin";
    else
        connectionString = $"mongodb://{mongoHost}:{mongoPort}";
}

Console.WriteLine($"[INFO] Using MongoDB connection string: {connectionString}");

builder.Services.AddSingleton<IMongoClient>(new MongoClient(connectionString));
builder.Services.AddScoped(sp =>
{
    var client = sp.GetRequiredService<IMongoClient>();
    return client.GetDatabase(mongoDatabaseName);
});

var app = builder.Build();

// -----------------------
// PIPELINE
// -----------------------
app.UseCors("AllowBulletinBoard");
app.UseDefaultFiles();
app.UseStaticFiles();

// -----------------------
// API ENDPOINTS
// -----------------------

// GET all posts
app.MapGet("/api/posts", async (IMongoDatabase db) =>
{
    var col = db.GetCollection<Post>("Posts");
    var posts = await col.Find(_ => true)
                         .SortByDescending(p => p.CreationTime)
                         .ToListAsync();

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
app.MapPost("/api/posts", async (HttpContext ctx, IMongoDatabase db) =>
{
    try
    {
        var json = await JsonSerializer.DeserializeAsync<JsonElement>(ctx.Request.Body);
        var name = json.GetProperty("name").GetString() ?? string.Empty;
        var message = json.GetProperty("message").GetString() ?? string.Empty;

        var col = db.GetCollection<Post>("Posts");
        var last = await col.Find(_ => true)
                            .SortByDescending(p => p.Id)
                            .FirstOrDefaultAsync();

        var newPost = new Post
        {
            Id = (last == null || last.Id == 0) ? 1 : last.Id + 1,
            Name = name,
            Message = message,
            CreationTime = DateTime.UtcNow
        };

        await col.InsertOneAsync(newPost);
        return Results.Created($"/api/posts/{newPost.Id}", newPost);
    }
    catch (Exception ex)
    {
        Console.WriteLine($"[ERROR] POST /api/posts failed: {ex.Message}");
        return Results.Problem("Internal server error.");
    }
});

// DELETE post
app.MapDelete("/api/posts/{id}", async (int id, IMongoDatabase db) =>
{
    var col = db.GetCollection<Post>("Posts");
    var res = await col.DeleteOneAsync(p => p.Id == id);
    return res.DeletedCount > 0 ? Results.Ok() : Results.NotFound();
});

app.Run();

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
