using MongoDB.Bson;
using MongoDB.Bson.Serialization.Attributes;
using MongoDB.Driver;

var builder = WebApplication.CreateBuilder(args);

// Enable CORS for frontend (port 8081)
builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowFrontend", policy =>
    {
        policy.WithOrigins("http://localhost:8081")
              .AllowAnyHeader()
              .AllowAnyMethod();
    });
});

// Configure JSON serialization
builder.Services.ConfigureHttpJsonOptions(options =>
{
    options.SerializerOptions.PropertyNamingPolicy = System.Text.Json.JsonNamingPolicy.CamelCase;
});

// Add MongoDB
var mongoHost = Environment.GetEnvironmentVariable("MONGODB_HOST") ?? "localhost";
var mongoPort = Environment.GetEnvironmentVariable("MONGODB_PORT") ?? "27017";
var mongoDatabase = Environment.GetEnvironmentVariable("MONGODB_DATABASE") ?? "BulletinBoardDb";
var connectionString = $"mongodb://{mongoHost}:{mongoPort}";

builder.Services.AddSingleton<IMongoClient>(new MongoClient(connectionString));
builder.Services.AddScoped(sp =>
{
    var client = sp.GetRequiredService<IMongoClient>();
    return client.GetDatabase(mongoDatabase);
});

var app = builder.Build();
app.UseCors("AllowFrontend");

app.UseDefaultFiles();
app.UseStaticFiles();

// ------------------- API ENDPOINTS -------------------

// GET all posts
app.MapGet("/api/posts", async (IMongoDatabase db) =>
{
    var col = db.GetCollection<Post>("Posts");
    var posts = await col.Find(_ => true).SortByDescending(p => p.CreationTime).ToListAsync();
    return Results.Ok(posts);
});

// POST new post
app.MapPost("/api/posts", async (HttpContext ctx, IMongoDatabase db) =>
{
    var post = await ctx.Request.ReadFromJsonAsync<Post>();
    if (post == null)
        return Results.BadRequest("Invalid payload");

    var col = db.GetCollection<Post>("Posts");
    var last = await col.Find(_ => true).SortByDescending(p => p.Id).FirstOrDefaultAsync();
    post.Id = last?.Id + 1 ?? 1;
    post.CreationTime = DateTime.UtcNow;

    await col.InsertOneAsync(post);
    return Results.Created($"/api/posts/{post.Id}", post);
});

// DELETE post
app.MapDelete("/api/posts/{id}", async (int id, IMongoDatabase db) =>
{
    var col = db.GetCollection<Post>("Posts");
    var res = await col.DeleteOneAsync(p => p.Id == id);
    return res.DeletedCount > 0 ? Results.Ok() : Results.NotFound();
});

app.Run();

// ------------------- MODEL -------------------

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
