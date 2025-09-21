using FamousQuotes.Api.Data;
using Microsoft.Data.SqlClient;

namespace FamousQuotes.Api.Services;

public class SeedService : IHostedService
{
    private readonly IConfiguration _cfg;
    private readonly ILogger<SeedService> _log;
    private readonly BlobQuoteProvider _provider;

    public SeedService(IConfiguration cfg, ILogger<SeedService> log, BlobQuoteProvider provider)
    {
        _cfg = cfg;
        _log = log;
        _provider = provider;
    }

    public async Task StartAsync(CancellationToken ct)
    {
        var server   = _cfg["Database:Server"] ?? _cfg["Database__Server"];
        var database = _cfg["Database:Name"]   ?? _cfg["Database__Name"];

        if (string.IsNullOrWhiteSpace(server) || string.IsNullOrWhiteSpace(database))
        {
            _log.LogWarning("Database settings missing; skipping seed.");
            return;
        }

        var dbOptions = new DatabaseOptions
        {
            Server = server,
            Name   = database
        };

        await using var conn = await SqlAccess.ConnectAsync(dbOptions, ct);
        
        await DbInitializer.EnsureQuotesTableAsync(conn, ct);

        var countCmd = new SqlCommand("SELECT COUNT(*) FROM dbo.Quotes", conn);
        var existing = (int)await countCmd.ExecuteScalarAsync(ct);
        if (existing > 0)
        {
            _log.LogInformation("Quotes already present. Skipping seed.");
            return;
        }

        var quotes = await _provider.LoadQuotesAsync(ct);
        if (quotes.Count == 0)
        {
            _log.LogWarning("No quotes found in blob; skipping seed.");
            return;
        }

        var cmd = new SqlCommand(
            @"INSERT INTO dbo.Quotes(Text, Author, Source, CreatedAt)
              VALUES (@t,@a,@s,SYSUTCDATETIME())", conn);

        cmd.Parameters.Add(new SqlParameter("@t", System.Data.SqlDbType.NVarChar, 1000));
        cmd.Parameters.Add(new SqlParameter("@a", System.Data.SqlDbType.NVarChar, 200));
        cmd.Parameters.Add(new SqlParameter("@s", System.Data.SqlDbType.NVarChar, 200));

        int inserted = 0;
        foreach (var r in quotes)
        {
            cmd.Parameters["@t"].Value = r.Text;
            cmd.Parameters["@a"].Value = (object?)r.Author ?? DBNull.Value;
            cmd.Parameters["@s"].Value = (object?)r.Source ?? DBNull.Value;
            inserted += await cmd.ExecuteNonQueryAsync(ct);
        }

        _log.LogInformation("Seeded {Count} quotes.", inserted);
    }

    public Task StopAsync(CancellationToken ct) => Task.CompletedTask;
}