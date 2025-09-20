using FamousQuotes.Api.Data;
using FamousQuotes.Api.Services;
using FamousQuotes.Api.Models;
using Microsoft.Data.SqlClient;

var builder = WebApplication.CreateBuilder(args);

// PII-safe logging: don’t log bodies/queries
builder.Logging.ClearProviders();
builder.Logging.AddConsole();

builder.Services.AddHostedService<SeedService>();

var app = builder.Build();

app.MapGet("/", async (IConfiguration cfg, CancellationToken ct) =>
{
    var server = cfg["Sql:Server"] ?? cfg["Sql__Server"];
    var db     = cfg["Sql:Database"] ?? cfg["Sql__Database"];

    await using var conn = await SqlAccess.CreateOpenConnectionAsync(server, db, ct);

    await DbInitializer.EnsureTableExistsAsync(conn, ct);
    await using var cmd = new SqlCommand(
        "SELECT TOP 1 Id, Text, Author, Source, CreatedAt FROM dbo.Quotes ORDER BY NEWID()", conn);

    await using var r = await cmd.ExecuteReaderAsync(ct);
    if (!await r.ReadAsync(ct)) return Results.Problem("No quotes found.");

    var quote = new Quote(
        r.GetInt32(0),
        r.GetString(1),
        r.IsDBNull(2) ? null : r.GetString(2),
        r.IsDBNull(3) ? null : r.GetString(3),
        r.GetDateTime(4));

    return Results.Ok(new {
        id = quote.Id,
        text = quote.Text,
        author = quote.Author,
        source = quote.Source
    });
});

app.MapGet("/healthz", () => Results.Ok("ok"));
app.Run();