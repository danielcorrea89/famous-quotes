using System.Text.Json;
using Azure.Storage.Blobs;
using FamousQuotes.Api.Models;
using FamousQuotes.Api.Data;
using Microsoft.Data.SqlClient;
using Azure.Identity;


namespace FamousQuotes.Api.Services;

public class SeedService : IHostedService
{
    private readonly IConfiguration _cfg;
    private readonly ILogger<SeedService> _log;

    public SeedService(IConfiguration cfg, ILogger<SeedService> log) { _cfg = cfg; _log = log; }

    public async Task StartAsync(CancellationToken ct)
    {
        var server = _cfg["Sql:Server"] ?? _cfg["Sql__Server"];
        var db     = _cfg["Sql:Database"] ?? _cfg["Sql__Database"];
        var blobUrl = _cfg["Seed:BlobUrl"] ?? _cfg["Seed__BlobUrl"]; // e.g. https://stfamousquotesdev.blob.core.windows.net/seed/quotes.json
        var sas     = _cfg["Seed:BlobSasToken"] ?? _cfg["Seed__BlobSasToken"]; // optional


        if (string.IsNullOrWhiteSpace(server) || string.IsNullOrWhiteSpace(db))
        {
            _log.LogWarning("SQL settings missing; skipping seed.");
            return;
        }

       


        await using var conn = await SqlAccess.CreateOpenConnectionAsync(server, db, ct);

        await DbInitializer.EnsureTableExistsAsync(conn, ct);

       // Is there anything already?
        var countCmd = new SqlCommand("SELECT COUNT(*) FROM dbo.Quotes", conn);
        var existing = (int)await countCmd.ExecuteScalarAsync(ct);
        if (existing > 0)
        {
            _log.LogInformation("Quotes already present. Skipping seed.");
            return;
        }

        if (string.IsNullOrWhiteSpace(blobUrl)) { _log.LogWarning("Seed blob URL missing; skipping."); return; }

        _log.LogInformation("Seeding quotes from {Url}", blobUrl);

        // download JSON (private with SAS or AAD; will also work for public)
        string json;
        
        if (!string.IsNullOrWhiteSpace(sas))
        {
            if (!sas.StartsWith("?")) sas = "?" + sas;
            using var http = new HttpClient();
            var resp = await http.GetAsync(blobUrl + sas, ct);
            resp.EnsureSuccessStatusCode();
            json = await resp.Content.ReadAsStringAsync(ct);
        }
        else
        {
            // AAD path: MI in Azure; your az login locally
            var cred = new DefaultAzureCredential(includeInteractiveCredentials: true);
            var blob = new BlobClient(new Uri(blobUrl), cred);
            var dl   = await blob.DownloadContentAsync(ct);
            json     = dl.Value.Content.ToString();
        }

        // expected format: [{ "text": "...", "author": "..." , "source": "..."}, ...]
        using var doc = JsonDocument.Parse(json);
        var rows = new List<(string Text, string? Author, string? Source)>();
        foreach (var q in doc.RootElement.EnumerateArray())
        {
            var text = q.TryGetProperty("text", out var tEl) && tEl.ValueKind == JsonValueKind.String
                ? tEl.GetString() ?? ""                
                : "";
            if (string.IsNullOrWhiteSpace(text)) continue;
            string? author = null;
            string? source = null;
            if (q.TryGetProperty("author", out var aEl) && aEl.ValueKind == JsonValueKind.String)
                author = aEl.GetString();
            if (q.TryGetProperty("source", out var sEl) && sEl.ValueKind == JsonValueKind.String)
                source = sEl.GetString();
            rows.Add((text.Trim(), author, source));
        }

        if (rows.Count == 0) { _log.LogWarning("No quotes found in JSON; skipping."); return; }

        var cmd = new SqlCommand(@"INSERT INTO dbo.Quotes(Text, Author, Source, CreatedAt)
                                   VALUES (@t,@a,@s,SYSUTCDATETIME())", conn);

        cmd.Parameters.Add(new SqlParameter("@t", System.Data.SqlDbType.NVarChar, 1000));
        cmd.Parameters.Add(new SqlParameter("@a", System.Data.SqlDbType.NVarChar, 200));
        cmd.Parameters.Add(new SqlParameter("@s", System.Data.SqlDbType.NVarChar, 200));

        int inserted = 0;
        foreach (var r in rows)
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