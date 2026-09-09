using VacationPlanner.Models;

namespace VacationPlanner.Services;

/// <summary>Persistence for the planner's activities. Every call goes to the backing store; nothing is cached in-process.</summary>
public interface IActivityStore
{
    /// <summary>Creates whatever the store needs (container, table, collection, directory) before the first request.</summary>
    Task InitializeAsync(CancellationToken cancellationToken);

    Task<IReadOnlyList<Activity>> ListAsync(CancellationToken cancellationToken);

    /// <summary>Adds an activity and returns whether the store confirmed the write; the page flashes only then.</summary>
    Task<bool> AddAsync(string text, CancellationToken cancellationToken);

    /// <summary>Updates an activity and returns whether the store reported a change, with the meaning the Python sample's driver gives it.</summary>
    Task<bool> UpdateAsync(string id, string text, CancellationToken cancellationToken);

    /// <summary>Deletes an activity by its store id and returns whether the store reported a deletion.</summary>
    Task<bool> DeleteAsync(string id, CancellationToken cancellationToken);

    /// <summary>Cheap connectivity probe used by <c>GET /health</c>.</summary>
    Task<bool> IsHealthyAsync(CancellationToken cancellationToken);
}
