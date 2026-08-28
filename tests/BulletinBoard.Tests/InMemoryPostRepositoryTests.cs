using Xunit;

public class InMemoryPostRepositoryTests
{
    [Fact]
    public async Task Starts_empty_for_a_clean_local_demo()
    {
        var repository = new InMemoryPostRepository();

        var posts = await repository.ListAsync();

        Assert.Empty(posts);
    }

    [Fact]
    public async Task Creates_and_deletes_a_post()
    {
        var repository = new InMemoryPostRepository();

        var created = await repository.CreateAsync("Tester", "A local post");

        Assert.Contains(created, await repository.ListAsync());
        Assert.True(await repository.DeleteAsync(created.Id));
        Assert.DoesNotContain(created, await repository.ListAsync());
    }

    [Fact]
    public async Task Clears_all_posts_and_restarts_ids()
    {
        var repository = new InMemoryPostRepository();

        await repository.CreateAsync("Tester", "First");
        await repository.CreateAsync("Tester", "Second");

        await repository.ClearAsync();

        Assert.Empty(await repository.ListAsync());
        var nextPost = await repository.CreateAsync("Tester", "After reset");
        Assert.Equal(1, nextPost.Id);
    }
}
