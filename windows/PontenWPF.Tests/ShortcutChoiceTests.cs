using PontenWPF;

namespace PontenWPF.Tests;

public class ShortcutChoiceTests
{
    [Theory]
    [InlineData(ShortcutChoice.CtrlAltS, "Ctrl+Alt+S", 0x0003)]
    [InlineData(ShortcutChoice.CtrlShiftS, "Ctrl+Shift+S", 0x0006)]
    [InlineData(ShortcutChoice.AltShiftS, "Alt+Shift+S", 0x0005)]
    public void ShortcutChoice_MapsToExpectedDescriptionAndModifiers(ShortcutChoice choice, string description, uint modifiers)
    {
        Assert.Equal(description, choice.GetDescription());

        var (registeredModifiers, key) = choice.GetHotKeyRegistration();
        Assert.Equal(modifiers, registeredModifiers);
        Assert.Equal(0x53u, key);
    }
}