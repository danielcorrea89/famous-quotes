using FamousQuotes.Api.Data;
using FamousQuotes.Api.Models;
using FamousQuotes.Api.Services;
using Microsoft.Data.SqlClient;

var builder = WebApplication.CreateBuilder(args);

// PII-safe logging
builder.Logging.ClearProviders();
builder.Logging.AddConsole();

// Bind options (Database + Seeding)
builder.Services.Configure<DatabaseOptions>(
    builder.Configuration.GetSection("Database"));
builder.Services.Configure<SeedOptions>(
    builder.Configuration.GetSection("Seed"));

// Infra
builder.Services.AddHttpClient();
builder.Services.AddSingleton<BlobQuoteProvider>();
builder.Services.AddHostedService<SeedService>();

var app = builder.Build();

app.MapGet("/", async (DatabaseOptions dbOpt, CancellationToken ct) =>
{
    await using var conn = await SqlAccess.ConnectAsync(dbOpt, ct);

    const string sql = """
        SELECT TOP 1 Id, Text, Author, Source, CreatedAt
        FROM dbo.Quotes
        ORDER BY NEWID()
        """;

    await using var cmd = new SqlCommand(sql, conn);
    await using var reader = await cmd.ExecuteReaderAsync(ct);

    if (!await reader.ReadAsync(ct))
        return Results.Problem("No quotes found.");

    var quote = new Quote(
        reader.GetInt32(0),
        reader.GetString(1),
        reader.IsDBNull(2) ? null : reader.GetString(2),
        reader.IsDBNull(3) ? null : reader.GetString(3),
        reader.GetDateTime(4));

    return Results.Ok(new {
        id     = quote.Id,
        text   = quote.Text,
        author = quote.Author,
        source = quote.Source
    });
});

app.MapGet("/healthz", () => Results.Ok("ok"));

app.Run();