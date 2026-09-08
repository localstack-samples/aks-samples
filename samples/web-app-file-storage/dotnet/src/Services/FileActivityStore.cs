using VacationPlanner.Models;

namespace VacationPlanner.Services;

/// <summary>
/// One text file per activity in the directory where the Azure file share is mounted: the file name is the
/// activity id and its content the text. The app talks to the share through the file system only: no Azure SDK,
/// no connection string, no account key. Everything that makes the share reachable (SMB or NFS, pre-created or
/// provisioned on demand) is handled by the Azure Files CSI driver when it mounts the volume into the pod.
/// </summary>
public sealed class FileActivityStore(FileStorageOptions options, ILogger<FileActivityStore> logger) : IActivityStore
{
    /// <summary>Suffix of the files holding the activities, one file per activity.</summary>
    public const string ActivityFileSuffix = "-activity.txt";

    private readonly string _directory = options.ActivitiesDir;

    public Task InitializeAsync(CancellationToken cancellationToken)
    {
        // A missing directory means the Azure file share was not mounted into the container: the app must not
        // create the mount point itself and write to the container file system, where the data would be invisible
        // to the other replicas and lost on restart.
        if (!Directory.Exists(_directory))
        {
            throw new DirectoryNotFoundException($"Activities directory '{_directory}' does not exist. Is the Azure file share mounted?");
        }

        ProbeWritable();
        logger.LogInformation("Activities directory '{Directory}' is ready.", _directory);
        return Task.CompletedTask;
    }

    public Task<IReadOnlyList<Activity>> ListAsync(CancellationToken cancellationToken)
    {
        // Sorted by name, which sorts by creation timestamp: the file name is the timestamp.
        var names = Directory.EnumerateFiles(_directory)
            .Select(path => Path.GetFileName(path))
            .Where(IsActivityName)
            .Order(StringComparer.Ordinal);

        var activities = new List<Activity>();
        foreach (var name in names)
        {
            var path = Path.Combine(_directory, name);
            if (File.Exists(path))
            {
                logger.LogInformation("Found activity file '{Name}' with size {Size} bytes", name, new FileInfo(path).Length);
                activities.Add(new Activity(name, File.ReadAllText(path)));
            }
        }

        logger.LogInformation("Retrieved {Count} activity file(s) from directory '{Directory}'", activities.Count, _directory);
        return Task.FromResult<IReadOnlyList<Activity>>(activities);
    }

    public Task<bool> AddAsync(string text, CancellationToken cancellationToken) =>
        Task.FromResult(Write($"{DateTime.Now:yyyy-MM-dd-HH-mm-ss}{ActivityFileSuffix}", text));

    public Task<bool> UpdateAsync(string id, string text, CancellationToken cancellationToken) =>
        Task.FromResult(Write(id, text));

    /// <summary>
    /// Returns whether the activity is gone from the share. A file that is already gone counts as gone: every
    /// replica mounts the same share, so another replica may have deleted it a moment earlier. A missing
    /// directory is not a deleted activity, though: the share itself is gone and success would hide that.
    /// </summary>
    public Task<bool> DeleteAsync(string id, CancellationToken cancellationToken)
    {
        if (!IsActivityName(id))
        {
            logger.LogWarning("Invalid activity name '{Name}'.", id);
            return Task.FromResult(false);
        }

        try
        {
            var path = Path.Combine(_directory, id);
            if (!File.Exists(path))
            {
                if (!Directory.Exists(_directory))
                {
                    logger.LogError("Activities directory '{Directory}' does not exist. Is the Azure file share mounted?", _directory);
                    return Task.FromResult(false);
                }

                logger.LogInformation("Activity file '{Name}' does not exist in directory '{Directory}': already deleted.", id, _directory);
                return Task.FromResult(true);
            }

            logger.LogInformation("Deleting activity file '{Name}' from directory '{Directory}'.", id, _directory);
            File.Delete(path);
            logger.LogInformation("Activity file '{Name}' deleted successfully.", id);
            return Task.FromResult(true);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            logger.LogError(ex, "An error occurred while deleting the activity file '{Name}'.", id);
            return Task.FromResult(false);
        }
    }

    public Task<bool> IsHealthyAsync(CancellationToken cancellationToken)
    {
        try
        {
            if (!Directory.Exists(_directory))
            {
                logger.LogWarning("Activities directory '{Directory}' does not exist. Is the Azure file share mounted?", _directory);
                return Task.FromResult(false);
            }

            ProbeWritable();
            return Task.FromResult(true);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            logger.LogWarning(ex, "Activities directory '{Directory}' is not writable.", _directory);
            return Task.FromResult(false);
        }
    }

    /// <summary>Creates or overwrites an activity file; returns whether the activity is on the share, so the caller never reports a success that did not happen.</summary>
    private bool Write(string name, string text)
    {
        if (!IsActivityName(name))
        {
            logger.LogWarning("Invalid activity name '{Name}'.", name);
            return false;
        }

        try
        {
            logger.LogInformation("Writing activity file '{Name}' in directory '{Directory}'.", name, _directory);
            File.WriteAllText(Path.Combine(_directory, name), text);
            logger.LogInformation("Activity file '{Name}' written successfully.", name);
            return true;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            logger.LogError(ex, "An error occurred while writing the activity file '{Name}'.", name);
            return false;
        }
    }

    /// <summary>
    /// Whether the name is one of this app's activity files, and nothing else: a file called
    /// yyyy-MM-dd-HH-mm-ss-activity.txt directly inside the mounted share. Names arrive from a form field, so
    /// this rejects an empty name, '.' and '..', anything carrying a path separator, and any name the app did not create.
    /// </summary>
    private static bool IsActivityName(string? name) =>
        !string.IsNullOrEmpty(name)
        && name is not ("." or "..")
        && Path.GetFileName(name) == name
        && !name.Contains('/') && !name.Contains('\\')
        && name.EndsWith(ActivityFileSuffix, StringComparison.Ordinal);

    /// <summary>
    /// The equivalent of the Python sample's os.access(W_OK | X_OK): the only portable proof that the mounted
    /// share accepts writes from this uid is to write to it. The probe is a dot file the listing never shows.
    /// </summary>
    private void ProbeWritable()
    {
        var probe = Path.Combine(_directory, $".write-probe-{Environment.ProcessId}");
        File.WriteAllText(probe, string.Empty);
        File.Delete(probe);
    }
}
