using System.Text.Json;
using Azure.Core;
using Azure.Identity;
using Azure.Storage.Blobs;
using Microsoft.Data.SqlClient;

var builder = WebApplication.CreateBuilder(args);

// --- Logging: console only, keep it lean & PII-safe ---
builder.Logging.ClearProviders();
builder.Logging.AddConsole();

var app = builder.Build();

// --- Load and validate settings early ---
string? dbServer  = GetCfg("Database:Server");
string? dbName    = GetCfg("Database:Name");
string? blobUrl   = GetCfg("Seed:BlobUrl");

Ensure(!string.IsNullOrWhiteSpace(dbServer), "Database:Server is required.");
Ensure(!string.IsNullOrWhiteSpace(dbName),   "Database:Name is required.");
Ensure(!string.IsNullOrWhiteSpace(blobUrl),  "Seed:BlobUrl is required.");

app.MapGet("/", async (CancellationToken ct) =>
{
    await using var conn = await OpenSqlWithManagedIdentityAsync(dbServer!, dbName!, ct);

    await EnsureQuotesTableAsync(conn, ct);

    var count = await ScalarAsync<int>(conn, "SELECT COUNT(*) FROM dbo.Quotes", ct);
    if (count == 0)
    {
        // First run: seed from Blob (using MI/AAD). Blob file format:
        // [ { "text":"...", "author":"...", "source":"..." }, ... ]
        var seeded = await SeedFromBlobAsync(conn, blobUrl!, ct);
        if (seeded == 0)
            return Results.Problem("No quotes available after seeding.");
    }

    var sql = @"SELECT TOP 1 Id, [Text], Author, [Source], CreatedAt
                FROM dbo.Quotes
                ORDER BY NEWID()";
    await using var cmd = new SqlCommand(sql, conn);
    await using var r = await cmd.ExecuteReaderAsync(ct);
    if (!await r.ReadAsync(ct)) return Results.Problem("No quotes found.");

    var result = new
    {
        //id     = r.GetInt32(0), // usually not needed by client
        text   = r.GetString(1),
        author = r.IsDBNull(2) ? null : r.GetString(2),
        source = r.IsDBNull(3) ? null : r.GetString(3)
    };

    return Results.Ok(result);
});

app.MapGet("/healthz", () => Results.Ok("ok"));

app.Run();

// -------------- helpers --------------

string? GetCfg(string key)
{
    // allow both ":" and "__" (App Service uses __)
    return builder.Configuration[key] ?? builder.Configuration[key.Replace(":", "__")];
}

static void Ensure(bool condition, string message)
{
    if (!condition) throw new InvalidOperationException(message);
}

static async Task<SqlConnection> OpenSqlWithManagedIdentityAsync(string server, string database, CancellationToken ct)
{
    var sqlConnStringBuilder = new SqlConnectionStringBuilder
    {
        DataSource = server,            // e.g. sql-famousquotes-dev.database.windows.net
        InitialCatalog = database,      // e.g. db-famousquotes-dev
        Encrypt = true,
        TrustServerCertificate = false,
        ConnectTimeout = 15
    };

    var sqlConnection = new SqlConnection(sqlConnStringBuilder.ConnectionString);

    var credential = new DefaultAzureCredential(includeInteractiveCredentials: true);
    var token = await credential.GetTokenAsync(
        new TokenRequestContext(new[] { "https://database.windows.net/.default" }), ct);

    sqlConnection.AccessToken = token.Token;
    await sqlConnection.OpenAsync(ct);
    return sqlConnection;
}

static async Task EnsureQuotesTableAsync(SqlConnection sqlConnection, CancellationToken cancellationToken)
{
    const string sql = @"
        IF NOT EXISTS (
            SELECT 1
            FROM sys.tables
            WHERE name = 'Quotes' AND schema_id = SCHEMA_ID('dbo')
        )
        BEGIN
            CREATE TABLE dbo.Quotes (
                Id        INT IDENTITY(1,1) PRIMARY KEY,
                [Text]    NVARCHAR(1000) NOT NULL,
                Author    NVARCHAR(200)  NULL,
                [Source]  NVARCHAR(200)  NULL,
                CreatedAt DATETIME2 NOT NULL CONSTRAINT DF_Quotes_CreatedAt DEFAULT SYSUTCDATETIME()
            );
        END";
    await using var cmd = new SqlCommand(sql, sqlConnection);
    await cmd.ExecuteNonQueryAsync(cancellationToken);
}

static async Task<T> ScalarAsync<T>(SqlConnection sqlConnection, string sql, CancellationToken cancellationToken)
{
    await using var cmd = new SqlCommand(sql, sqlConnection);
    var val = await cmd.ExecuteScalarAsync(cancellationToken);
    return (val == null || val is DBNull) ? default! : (T)Convert.ChangeType(val, typeof(T))!;
}

static async Task<int> SeedFromBlobAsync(SqlConnection sqlConnection, string blobFileUrl, CancellationToken cancellationToken)
{
    // Use MI (or az login locally) to fetch the JSON from Blob
    var credentials = new DefaultAzureCredential(includeInteractiveCredentials: true);
    var blobClient = new BlobClient(new Uri(blobFileUrl), credentials);
    var downloadResult   = await blobClient.DownloadContentAsync(cancellationToken);
    var downloadResultJson = downloadResult.Value.Content.ToString();

    // Parse JSON and insert quotes
    using var jsonDoc = JsonDocument.Parse(downloadResultJson);
    if (jsonDoc.RootElement.ValueKind != JsonValueKind.Array) return 0;

    // Prepare insert command
    const string insertSql = @"INSERT INTO dbo.Quotes([Text], [Author], [Source], [CreatedAt])
                               VALUES (@t, @a, @s, SYSUTCDATETIME())";
    await using var cmd = new SqlCommand(insertSql, sqlConnection);
    var parameterText = cmd.Parameters.Add("@t", System.Data.SqlDbType.NVarChar, 1000);
    var parameterAuthor = cmd.Parameters.Add("@a", System.Data.SqlDbType.NVarChar, 200);
    var parameterSource = cmd.Parameters.Add("@s", System.Data.SqlDbType.NVarChar, 200);

    // Insert each quote
    int inserted = 0;
    foreach (var element in jsonDoc.RootElement.EnumerateArray())
    {
        if (!element.TryGetProperty("text", out var textElement) || textElement.ValueKind != JsonValueKind.String)
            continue;

        var text   = (textElement.GetString() ?? string.Empty).Trim();
        if (string.IsNullOrWhiteSpace(text)) continue;

        string? author = (element.TryGetProperty("author", out var authorElement) && authorElement.ValueKind == JsonValueKind.String)
                         ? authorElement.GetString()
                         : null;
        string? source = (element.TryGetProperty("source", out var sourceElement) && sourceElement.ValueKind == JsonValueKind.String)
                         ? sourceElement.GetString()
                         : null;

        parameterText.Value = text;
        parameterAuthor.Value = (object?)author ?? DBNull.Value;
        parameterSource.Value = (object?)source ?? DBNull.Value;

        inserted += await cmd.ExecuteNonQueryAsync(cancellationToken);
    }

    return inserted;
}