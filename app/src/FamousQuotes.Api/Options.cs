

public record DatabaseOptions
{
    public string Server { get; init; } = string.Empty;
    public string Name   { get; init; } = string.Empty;
}

public record SeedOptions
{
    public string BlobUrl     { get; init; } = string.Empty;
    public string? SasToken   { get; init; }
}