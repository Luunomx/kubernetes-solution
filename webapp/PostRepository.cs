using MongoDB.Bson;
using MongoDB.Driver;

public interface IPostRepository
{
    Task<IReadOnlyList<Post>> ListAsync();
    Task<Post> CreateAsync(string name, string message);
    Task<bool> DeleteAsync(int id);
    Task ClearAsync();
    Task CheckHealthAsync(CancellationToken cancellationToken = default);
}

public sealed class InMemoryPostRepository : IPostRepository
{
    private readonly object syncRoot = new();
    private readonly List<Post> posts = [];

    private int nextId;

    public Task<IReadOnlyList<Post>> ListAsync()
    {
        lock (syncRoot)
        {
            return Task.FromResult<IReadOnlyList<Post>>(
                posts.OrderByDescending(post => post.CreationTime).ToList());
        }
    }

    public Task<Post> CreateAsync(string name, string message)
    {
        lock (syncRoot)
        {
            var post = new Post
            {
                Id = ++nextId,
                Name = name,
                Message = message,
                CreationTime = DateTime.UtcNow
            };

            posts.Add(post);
            return Task.FromResult(post);
        }
    }

    public Task<bool> DeleteAsync(int id)
    {
        lock (syncRoot)
        {
            var post = posts.FirstOrDefault(candidate => candidate.Id == id);
            return Task.FromResult(post is not null && posts.Remove(post));
        }
    }

    public Task ClearAsync()
    {
        lock (syncRoot)
        {
            posts.Clear();
            nextId = 0;
            return Task.CompletedTask;
        }
    }

    public Task CheckHealthAsync(CancellationToken cancellationToken = default)
    {
        return Task.CompletedTask;
    }
}

public sealed class MongoPostRepository(IMongoDatabase database) : IPostRepository
{
    private readonly IMongoCollection<Post> collection = database.GetCollection<Post>("Posts");
    private readonly IMongoCollection<BsonDocument> counters = database.GetCollection<BsonDocument>("Counters");

    public async Task<IReadOnlyList<Post>> ListAsync()
    {
        return await collection.Find(_ => true)
            .SortByDescending(post => post.CreationTime)
            .ToListAsync();
    }

    public async Task<Post> CreateAsync(string name, string message)
    {
        var last = await collection.Find(_ => true)
            .SortByDescending(post => post.Id)
            .FirstOrDefaultAsync();

        // The counter update is atomic in MongoDB. The $max seeds it from an
        // existing collection on first use, while $inc gives concurrent API
        // replicas distinct IDs without a read-then-increment race.
        var counter = await counters.FindOneAndUpdateAsync(
            Builders<BsonDocument>.Filter.Eq("_id", "posts"),
            Builders<BsonDocument>.Update.Combine(
                Builders<BsonDocument>.Update.Max("value", last?.Id ?? 0),
                Builders<BsonDocument>.Update.Inc("value", 1)),
            new FindOneAndUpdateOptions<BsonDocument>
            {
                IsUpsert = true,
                ReturnDocument = ReturnDocument.After
            });

        var post = new Post
        {
            Id = counter["value"].AsInt32,
            Name = name,
            Message = message,
            CreationTime = DateTime.UtcNow
        };

        await collection.InsertOneAsync(post);
        return post;
    }

    public async Task<bool> DeleteAsync(int id)
    {
        var result = await collection.DeleteOneAsync(post => post.Id == id);
        return result.DeletedCount > 0;
    }

    public async Task ClearAsync()
    {
        await collection.DeleteManyAsync(_ => true);
    }

    public async Task CheckHealthAsync(CancellationToken cancellationToken = default)
    {
        await database.RunCommandAsync<BsonDocument>(
            new BsonDocument("ping", 1),
            cancellationToken: cancellationToken);
    }
}
