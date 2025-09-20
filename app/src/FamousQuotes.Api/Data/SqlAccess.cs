using Azure.Identity;
using Microsoft.Data.SqlClient;

namespace FamousQuotes.Api.Data;

public static class SqlAccess
{
    public static async Task<SqlConnection> CreateOpenConnectionAsync(string server, string database, CancellationToken ct = default)
    {
        var csb = new SqlConnectionStringBuilder
        {
            DataSource = $"{server}",
            InitialCatalog = database,
            Encrypt = true,
            TrustServerCertificate = false,
            ConnectTimeout = 15
        };

        var conn = new SqlConnection(csb.ConnectionString);
        var credential = new DefaultAzureCredential(); // local: az login; in App Service: MSI
        var token = await credential.GetTokenAsync(
            new Azure.Core.TokenRequestContext(new[] { "https://database.windows.net/.default" }),
            ct);

        conn.AccessToken = token.Token;
        await conn.OpenAsync(ct);
        return conn;
    }
}