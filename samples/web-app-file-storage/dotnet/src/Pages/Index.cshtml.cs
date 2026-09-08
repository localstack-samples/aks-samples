using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using VacationPlanner.Models;
using VacationPlanner.Services;

namespace VacationPlanner.Pages;

public class IndexModel(IActivityStore store, FileStorageOptions options) : PageModel
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
                TempData["Flash"] = await store.UpdateAsync(id, text, cancellationToken)
                    ? "Activity updated successfully."
                    : "Failed to update the activity on the file share.";
            }
            else
            {
                TempData["Flash"] = await store.AddAsync(text, cancellationToken)
                    ? "Activity added successfully."
                    : "Failed to add the activity to the file share.";
            }
        }

        return RedirectToPage();
    }
}
