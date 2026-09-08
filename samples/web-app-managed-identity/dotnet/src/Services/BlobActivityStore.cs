using System.Text;
using Azure.Identity;
using Azure.Storage;
using Azure.Storage.Blobs;
using VacationPlanner.Models;

namespace VacationPlanner.Services;

/// <summary>One blob per activity in a Blob Storage container; the blob name is the activity id and its content the text.</summary>
public sealed class BlobActivityStore : IActivityStore
{
    private readonly BlobContainerClient _container;
    private readonly ILogger<BlobActivityStore> _logger;

    public BlobActivityStore(BlobStorageOptions options, ILogger<BlobActivityStore> logger)
    {
        _logger = logger;

        // The same credential ladder as the Python sample: an explicit service principal, then a connection string,
        // then the identity of the pod.
        BlobServiceClient service;
        if (options is { ClientId: { Length: > 0 }, ClientSecret: { Length: > 0 }, TenantId: { Length: > 0 }, AccountUrl: { Length: > 0 } })
        {
            logger.LogInformation("Using ClientSecretCredential with BlobServiceClient.");
            var credential = new ClientSecretCredential(options.TenantId, options.ClientId, options.ClientSecret);
            service = new BlobServiceClient(new Uri(options.AccountUrl), credential);
        }
        else if (!string.IsNullOrEmpty(options.ConnectionString))
        {
            logger.LogInformation("Using storage account connection string with BlobServiceClient.");
            service = FromConnectionString(options.ConnectionString);
        }
        else if (!string.IsNullOrEmpty(options.AccountUrl))
        {
            // DefaultAzureCredential picks up the Microsoft Entra Workload ID the webhook projects into the pod
            // (AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_FEDERATED_TOKEN_FILE, AZURE_AUTHORITY_HOST).
            logger.LogInformation("Using DefaultAzureCredential with BlobServiceClient.");
            service = new BlobServiceClient(new Uri(options.AccountUrl), new DefaultAzureCredential());
        }
        else
        {
            throw new InvalidOperationException(
                "Insufficient configuration for BlobServiceClient. Set AZURE_STORAGE_ACCOUNT_URL (workload identity) or AZURE_STORAGE_ACCOUNT_CONNECTION_STRING.");
        }

        _container = service.GetBlobContainerClient(options.ContainerName);
    }

    public async Task InitializeAsync(CancellationToken cancellationToken)
    {
        await _container.CreateIfNotExistsAsync(cancellationToken: cancellationToken);
        _logger.LogInformation("Container '{Container}' is ready.", _container.Name);
    }

    public async Task<IReadOnlyList<Activity>> ListAsync(CancellationToken cancellationToken)
    {
        // Blobs come back sorted by name, which sorts by creation timestamp: the blob name is the timestamp.
        var activities = new List<Activity>();
        await foreach (var blob in _container.GetBlobsAsync(cancellationToken: cancellationToken))
        {
            var content = await _container.GetBlobClient(blob.Name).DownloadContentAsync(cancellationToken);
            _logger.LogInformation("Found blob '{Blob}' with size {Size} bytes", blob.Name, blob.Properties.ContentLength);
            activities.Add(new Activity(blob.Name, content.Value.Content.ToString()));
        }

        _logger.LogInformation("Retrieved {Count} blob(s) from container '{Container}'", activities.Count, _container.Name);
        return activities;
    }

    public Task<bool> AddAsync(string text, CancellationToken cancellationToken) =>
        UploadAsync($"{DateTime.Now:yyyy-MM-dd-HH-mm-ss}-activity.txt", text, cancellationToken);

    public Task<bool> UpdateAsync(string id, string text, CancellationToken cancellationToken) =>
        UploadAsync(id, text, cancellationToken);

    public async Task<bool> DeleteAsync(string id, CancellationToken cancellationToken)
    {
        // As in the Python sample, a blob that is already gone still counts as deleted.
        var deleted = await _container.GetBlobClient(id).DeleteIfExistsAsync(cancellationToken: cancellationToken);
        if (deleted.Value)
        {
            _logger.LogInformation("Deleted blob '{Blob}' from container '{Container}'", id, _container.Name);
        }
        else
        {
            _logger.LogInformation("Blob '{Blob}' did not exist: already deleted.", id);
        }

        return true;
    }

    public async Task<bool> IsHealthyAsync(CancellationToken cancellationToken)
    {
        try
        {
            return await _container.ExistsAsync(cancellationToken);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Blob Storage health check failed");
            return false;
        }
    }

    private async Task<bool> UploadAsync(string name, string text, CancellationToken cancellationToken)
    {
        await _container.GetBlobClient(name).UploadAsync(new BinaryData(Encoding.UTF8.GetBytes(text)), overwrite: true, cancellationToken);
        _logger.LogInformation("Uploaded blob '{Blob}' to container '{Container}'", name, _container.Name);
        return true;
    }

    /// <summary>
    /// Builds the client from the connection string's explicit <c>BlobEndpoint</c> and shared key when they are present,
    /// as the Python SDK does. The .NET parser insists on a port-less <c>EndpointSuffix</c> and rejects the connection
    /// string the LocalStack emulator returns, whose suffix carries the gateway port (<c>core.azure.localhost.localstack.cloud:4566</c>).
    /// </summary>
    private static BlobServiceClient FromConnectionString(string connectionString)
    {
        var parts = connectionString.Split(';', StringSplitOptions.RemoveEmptyEntries)
            .Select(part => part.Split('=', 2))
            .Where(kv => kv.Length == 2)
            .ToDictionary(kv => kv[0].Trim(), kv => kv[1].Trim(), StringComparer.OrdinalIgnoreCase);

        return parts.TryGetValue("BlobEndpoint", out var endpoint)
            && parts.TryGetValue("AccountName", out var accountName)
            && parts.TryGetValue("AccountKey", out var accountKey)
            ? new BlobServiceClient(new Uri(endpoint), new StorageSharedKeyCredential(accountName, accountKey))
            : new BlobServiceClient(connectionString);
    }
}
