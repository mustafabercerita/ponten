using System.Net;
using PontenWPF;

namespace PontenWPF.Tests;

public class UpdaterTests
{
    [Theory]
    [InlineData(HttpStatusCode.Forbidden, "Update check blocked (rate limit). Try again later.")]
    [InlineData((HttpStatusCode)429, "Too many update checks. Try again later.")]
    [InlineData(HttpStatusCode.InternalServerError, "Update check failed (HTTP 500).")]
    public void DescribeHttpError_MapsKnownStatusCodes(HttpStatusCode statusCode, string expectedMessage)
    {
        Assert.Equal(expectedMessage, Updater.DescribeHttpError(statusCode));
    }
}