using Azure.Core;
using Azure.Identity;
using Microsoft.Data.SqlClient;

namespace FamousQuotes.Api.Data;

public static class SqlAccess
{
    private static readonly string[] Scope = ["https://database.windows.net/.default"];

    public static async Task<SqlConnection> ConnectAsync(DatabaseOptions opt, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(opt.Server) || string.IsNullOrWhiteSpace(opt.Name))
            throw new InvalidOperationException("Database configuration is incomplete.");

        var csb = new SqlConnectionStringBuilder
        {
            DataSource = opt.Server,
            InitialCatalog = opt.Name,
            Encrypt = true,
            TrustServerCertificate = false,
            ConnectTimeout = 15
        };

        var conn = new SqlConnection(csb.ConnectionString);

        var credential = new DefaultAzureCredential(includeInteractiveCredentials: true);
        var token = await credential.GetTokenAsync(new TokenRequestContext(Scope), ct);

        conn.AccessToken = token.Token;
        await conn.OpenAsync(ct);

        return conn;
    }
}