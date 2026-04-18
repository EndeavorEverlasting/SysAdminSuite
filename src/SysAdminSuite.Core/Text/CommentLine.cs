namespace SysAdminSuite.Core.Text;

/// <summary>
/// Helpers for host list and args files that use <c>#</c> line comments (same convention as native mapping).
/// </summary>
public static class CommentLine
{
    /// <summary>
    /// Returns the portion of <paramref name="line"/> before the first <c>#</c>, with trailing whitespace removed.
    /// </summary>
    public static string StripTrailingComment(string line)
    {
        if (string.IsNullOrEmpty(line))
            return string.Empty;

        var idx = line.IndexOf('#');
        var slice = idx >= 0 ? line[..idx] : line;
        return slice.TrimEnd();
    }
}
