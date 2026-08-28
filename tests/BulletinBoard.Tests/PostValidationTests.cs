using Xunit;

public class PostValidationTests
{
    [Fact]
    public void Accepts_a_valid_post()
    {
        var errors = PostValidation.Validate(new PostRequest("Hugo", "Hello from the board"));

        Assert.Empty(errors);
    }

    [Fact]
    public void Requires_a_message()
    {
        var errors = PostValidation.Validate(new PostRequest("Hugo", "   "));

        Assert.Contains("message", errors.Keys);
    }

    [Fact]
    public void Rejects_values_that_are_too_long()
    {
        var errors = PostValidation.Validate(new PostRequest(
            new string('n', PostValidation.MaxNameLength + 1),
            new string('m', PostValidation.MaxMessageLength + 1)));

        Assert.Contains("name", errors.Keys);
        Assert.Contains("message", errors.Keys);
    }
}
