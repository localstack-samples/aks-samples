using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using VacationPlanner.Services;

namespace VacationPlanner.Pages;

/// <summary>
/// Handles <c>POST /delete</c>. The activity is identified by its file name, posted in the <c>activity_id</c> form
/// field, never by its position in the rendered page: every replica mounts the same share and reloads it on each
/// GET, so the list can change between rendering a page and submitting a delete from it.
/// </summary>
public class DeleteModel(IActivityStore store) : PageModel
{
    [BindProperty(Name = "activity_id")]
    public string? ActivityId { get; set; }

    public IActionResult OnGet() => RedirectToPage("/Index");

    public async Task<IActionResult> OnPostAsync(CancellationToken cancellationToken)
    {
        TempData["Flash"] = await store.DeleteAsync(ActivityId?.Trim() ?? "", cancellationToken)
            ? "Activity deleted successfully."
            : "Failed to delete the activity from the file share.";

        return RedirectToPage("/Index");
    }
}
