using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using VacationPlanner.Models;
using VacationPlanner.Services;

namespace VacationPlanner.Pages;

public class IndexModel(IActivityStore store, FileStorageOptions options, ILogger<IndexModel> logger) : PageModel
{
    public IReadOnlyList<Activity> Activities { get; private set; } = [];

    /// <summary>Name of the pod serving the request, shown next to the activity count.</summary>
    public string PodName => options.PodName;

    /// <summary>Flash messages set by the previous request (the equivalent of Flask's <c>flash()</c>).</summary>
    public IReadOnlyList<string> Flashes => TempData["Flash"] is string message ? [message] : [];

    [BindProperty(Name = "activity")]
    public string? Activity { get; set; }

    [BindProperty(Name = "row_id")]
    public string? RowId { get; set; }

    public async Task OnGetAsync(CancellationToken cancellationToken)
    {
        Activities = await store.ListAsync(cancellationToken);
    }

    public async Task<IActionResult> OnPostAsync(CancellationToken cancellationToken)
    {
        var text = Activity?.Trim();
        var id = RowId?.Trim();
        if (!string.IsNullOrEmpty(text))
        {
            if (!string.IsNullOrEmpty(id))
            {
                if (await store.UpdateAsync(id, text, cancellationToken))
                {
                    logger.LogInformation("Activity updated: {Id}", id);
                    TempData["Flash"] = "Activity updated successfully.";
                }
                else
                {
                    TempData["Flash"] = "Failed to update the activity on the file share.";
                }
            }
            else
            {
                if (await store.AddAsync(text, cancellationToken))
                {
                    logger.LogInformation("Activity added: {Activity}", text);
                    TempData["Flash"] = "Activity added successfully.";
                }
                else
                {
                    TempData["Flash"] = "Failed to add the activity to the file share.";
                }
            }
        }

        return RedirectToPage();
    }
}
