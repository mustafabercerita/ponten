using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;

namespace PontenWPF.E2E.Tests;

[CollectionDefinition("E2E", DisableParallelization = true)]
public sealed class E2ECollection;

[Trait("Category", "E2E")]
[Collection("E2E")]
public class MenuBarE2ETests
{
    [Fact]
    public void EmptyState_IsVisibleOnLaunch()
    {
        using var fixture = new E2ETestFixture();
        var window = fixture.WaitForMainWindow();

        var emptyState = fixture.RequireElement(window, cf => cf.ByName("No signatures yet."));
        Assert.True(emptyState.IsAvailable);
    }

    [Fact]
    public void PreSeededSignature_AppearsInList()
    {
        var dataDirectory = Path.Combine(Path.GetTempPath(), "PontenE2E_" + Guid.NewGuid().ToString());
        E2ETestFixture.SeedSignature(dataDirectory, "E2E Signature");

        using var fixture = new E2ETestFixture(dataDirectory);
        var window = fixture.WaitForMainWindow();

        var listItem = fixture.RequireElement(window, cf => cf.ByName("E2E Signature"));
        Assert.NotNull(listItem);
    }

    [Fact]
    public void SignButton_ShowsCopiedStatus()
    {
        var dataDirectory = Path.Combine(Path.GetTempPath(), "PontenE2E_" + Guid.NewGuid().ToString());
        E2ETestFixture.SeedSignature(dataDirectory);

        using var fixture = new E2ETestFixture(dataDirectory);
        var window = fixture.WaitForMainWindow();
        fixture.RequireElement(window, cf => cf.ByName("Test Signature"));

        var signButton = fixture.RequireElement(
            window,
            cf => cf.ByControlType(ControlType.Button).And(cf.ByName("Sign"))).AsButton();
        signButton.Invoke();

        var statusText = fixture.RequireTextContaining(window, "copied", TimeSpan.FromSeconds(5));
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
            var autoPaste = fixture.RequireElement(
                window,
                cf => cf.ByControlType(ControlType.CheckBox).And(cf.ByName("Auto-paste after copying"))).AsCheckBox();

            if (!autoPaste.IsChecked.GetValueOrDefault())
            {
                autoPaste.Toggle();
            }

            fixture.WaitForAutoPasteEnabled(dataDirectory);

            var quitButton = fixture.RequireElement(window, cf => cf.ByName("Quit")).AsButton();
            quitButton.Invoke();
            fixture.Application.WaitWhileBusy(TimeSpan.FromSeconds(10));
            E2ETestFixture.AssertAutoPastePersisted(dataDirectory);
        }

        using var restarted = new E2ETestFixture(dataDirectory);
        var restartedWindow = restarted.WaitForMainWindow();
        var restartedAutoPaste = restarted.WaitForCheckBoxChecked(
            restartedWindow,
            "Auto-paste after copying");
        Assert.True(restartedAutoPaste.IsChecked);
    }

    [Fact]
    public void QuitButton_ClosesApplication()
    {
        using var fixture = new E2ETestFixture();
        var window = fixture.WaitForMainWindow();

        var quitButton = fixture.RequireElement(window, cf => cf.ByName("Quit")).AsButton();
        quitButton.Invoke();

        var exited = fixture.Application.WaitWhileBusy(TimeSpan.FromSeconds(10));
        Assert.True(exited || fixture.Application.HasExited);
    }
}