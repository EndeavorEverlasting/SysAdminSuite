using SysAdminSuite.Core.Text;
using Xunit;

namespace SysAdminSuite.Core.Tests.Text;

public class CommentLineTests
{
    [Theory]
    [InlineData("host1", "host1")]
    [InlineData("  host1  ", "  host1")]
    [InlineData("host1 # trailing", "host1")]
    [InlineData("# all comment", "")]
    [InlineData("", "")]
    public void StripTrailingComment_RemovesHashAndRest(string input, string expected)
    {
        Assert.Equal(expected, CommentLine.StripTrailingComment(input));
    }

    [Fact]
    public void StripTrailingComment_HashOnlyLine_IsEmpty()
    {
        Assert.Equal(string.Empty, CommentLine.StripTrailingComment("#"));
    }
}
