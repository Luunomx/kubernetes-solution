public sealed record PostRequest(string? Name, string? Message, string? ClientId = null);

public static class PostValidation
{
    public const int MaxNameLength = 80;
    public const int MaxMessageLength = 500;

    public static Dictionary<string, string[]> Validate(PostRequest request)
    {
        var errors = new Dictionary<string, string[]>();
        var name = request.Name?.Trim() ?? string.Empty;
        var message = request.Message?.Trim() ?? string.Empty;

        if (name.Length > MaxNameLength)
            errors["name"] = [$"Name must be {MaxNameLength} characters or fewer."];

        if (message.Length == 0)
            errors["message"] = ["Message is required."];
        else if (message.Length > MaxMessageLength)
            errors["message"] = [$"Message must be {MaxMessageLength} characters or fewer."];

        return errors;
    }
}
