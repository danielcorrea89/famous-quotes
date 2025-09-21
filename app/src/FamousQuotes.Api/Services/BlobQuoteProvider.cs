using System.Text.Json;
using Azure.Identity;
using Azure.Storage.Blobs;
using FamousQuotes.Api.Models;

namespace FamousQuotes.Api.Services;

public class BlobQuoteProvider
{
    private readonly IConfiguration _cfg;
    private readonly ILogger<BlobQuoteProvider> _log;

    public BlobQuoteProvider(IConfiguration cfg, ILogger<BlobQuoteProvider> log)
    {
        _cfg = cfg;
        _log = log;
    }

    public async Task<IReadOnlyList<QuoteSeed>> LoadQuotesAsync(CancellationToken ct)
    {
        var blobUrl = _cfg["Seed:BlobUrl"] ?? _cfg["Seed__BlobUrl"];
        if (string.IsNullOrWhiteSpace(blobUrl))
        {
            _log.LogWarning("Seed blob URL missing.");
            return Array.Empty<QuoteSeed>();
        }

        _log.LogInformation("Downloading seed quotes from {Url}", blobUrl);

        var cred = new DefaultAzureCredential(includeInteractiveCredentials: true);
        var blob = new BlobClient(new Uri(blobUrl), cred);

        var dl   = await blob.DownloadContentAsync(ct);
        var json = dl.Value.Content.ToString();

        using var doc = JsonDocument.Parse(json);
        var list = new List<QuoteSeed>();

        foreach (var q in doc.RootElement.EnumerateArray())
        {
            var text = q.TryGetProperty("text", out var tEl) && tEl.ValueKind == JsonValueKind.String
                ? tEl.GetString() ?? ""
                : "";
            if (string.IsNullOrWhiteSpace(text)) continue;

            var author = q.TryGetProperty("author", out var aEl) && aEl.ValueKind == JsonValueKind.String
                ? aEl.GetString()
                : null;

            var source = q.TryGetProperty("source", out var sEl) && sEl.ValueKind == JsonValueKind.String
                ? sEl.GetString()
                : null;

            list.Add(new QuoteSeed(text.Trim(), author, source));
        }

        return list;
    }
}

public record QuoteSeed(string Text, string? Author, string? Source);