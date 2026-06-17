using FlaUI.Core.AutomationElements;

namespace PontenWPF.E2E.Tests;

[Trait("Category", "E2E")]
public class MenuBarE2ETests
{
    [Fact]
    public void EmptyState_IsVisibleOnLaunch()
    {
        using var fixture = new E2ETestFixture();
        var window = fixture.WaitForMainWindow();

        var emptyState = fixture.RequireElement(window, "EmptyState");
        Assert.True(emptyState.IsAvailable);
        Assert.Contains("No signatures", emptyState.Name, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void PreSeededSignature_AppearsInList()
    {
        var dataDirectory = Path.Combine(Path.GetTempPath(), "PontenE2E_" + Guid.NewGuid().ToString());
        E2ETestFixture.SeedSignature(dataDirectory, "E2E Signature");

        using var fixture = new E2ETestFixture(dataDirectory);
        var window = fixture.WaitForMainWindow();

        var signaturesList = fixture.RequireElement(window, "SignaturesList");
        var listItem = signaturesList.FindFirstDescendant(cf => cf.ByName("E2E Signature"));
        Assert.NotNull(listItem);
    }

    [Fact]
    public void SignButton_ShowsCopiedStatus()
    {
        var dataDirectory = Path.Combine(Path.GetTempPath(), "PontenE2E_" + Guid.NewGuid().ToString());
        E2ETestFixture.SeedSignature(dataDirectory);

        using var fixture = new E2ETestFixture(dataDirectory);
        var window = fixture.WaitForMainWindow();

        var signButton = fixture.RequireElement(window, "SignButton").AsButton();
        signButton.Invoke();

        var statusText = fixture.RequireElement(window, "StatusText", TimeSpan.FromSeconds(5));
        Assert.Contains("copied", statusText.Name, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void AutoPasteToggle_PersistsAcrossRestart()
    {
        var dataDirectory = Path.Combine(Path.GetTempPath(), "PontenE2E_" + Guid.NewGuid().ToString());
        E2ETestFixture.SeedSignature(dataDirectory);

        using (var fixture = new E2ETestFixture(dataDirectory))
        {
            var window = fixture.WaitForMainWindow();
            var autoPaste = fixture.RequireElement(window, "AutoPasteCheck").AsCheckBox();
            if (!autoPaste.IsChecked.GetValueOrDefault())
            {
                autoPaste.Click();
                Thread.Sleep(300);
            }

            var quitButton = fixture.RequireElement(window, "QuitButton").AsButton();
            quitButton.Invoke();
            fixture.Application.WaitWhileBusy(TimeSpan.FromSeconds(10));
        }

        using var restarted = new E2ETestFixture(dataDirectory);
        var restartedWindow = restarted.WaitForMainWindow();
        var restartedAutoPaste = restarted.RequireElement(restartedWindow, "AutoPasteCheck").AsCheckBox();
        Assert.True(restartedAutoPaste.IsChecked);
    }

    [Fact]
    public void QuitButton_ClosesApplication()
    {
        using var fixture = new E2ETestFixture();
        var window = fixture.WaitForMainWindow();

        var quitButton = fixture.RequireElement(window, "QuitButton").AsButton();
        quitButton.Invoke();

        var exited = fixture.Application.WaitWhileBusy(TimeSpan.FromSeconds(10));
        Assert.True(exited || fixture.Application.HasExited);
    }
}