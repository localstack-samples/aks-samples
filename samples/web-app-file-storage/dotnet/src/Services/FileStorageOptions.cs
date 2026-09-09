namespace VacationPlanner.Services;

/// <summary>Settings read from the same environment variables the Python sample uses.</summary>
public sealed record FileStorageOptions(string ActivitiesDir, string PodName)
{
    public static FileStorageOptions FromEnvironment()
    {
        // Directory where the Azure file share is mounted in the container.
        var activitiesDir = Environment.GetEnvironmentVariable("ACTIVITIES_DIR") ?? "/data";
        if (string.IsNullOrWhiteSpace(activitiesDir))
        {
            throw new InvalidOperationException("The ACTIVITIES_DIR environment variable is set to an empty value.");
        }

        // Name of the pod serving the request, shown in the UI. All replicas mount the same file share, so an
        // activity added through one pod is served by every other pod as well.
        var podName = Environment.GetEnvironmentVariable("HOSTNAME") is { Length: > 0 } hostname ? hostname : Environment.MachineName;
        return new FileStorageOptions(activitiesDir, podName);
    }
}
