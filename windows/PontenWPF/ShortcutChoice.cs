namespace PontenWPF
{
    public enum ShortcutChoice
    {
        CtrlAltS = 0,
        CtrlShiftS = 1,
        AltShiftS = 2
    }

    public static class ShortcutChoiceExtensions
    {
        public static string GetDescription(this ShortcutChoice choice)
        {
            return choice switch
            {
                ShortcutChoice.CtrlAltS => "Ctrl+Alt+S",
                ShortcutChoice.CtrlShiftS => "Ctrl+Shift+S",
                ShortcutChoice.AltShiftS => "Alt+Shift+S",
                _ => "Ctrl+Alt+S"
            };
        }

        public static (uint modifiers, uint key) GetHotKeyRegistration(this ShortcutChoice choice)
        {
            const uint MOD_ALT = 0x0001;
            const uint MOD_CONTROL = 0x0002;
            const uint MOD_SHIFT = 0x0004;
            const uint VK_S = 0x53;

            return choice switch
            {
                ShortcutChoice.CtrlAltS => (MOD_CONTROL | MOD_ALT, VK_S),
                ShortcutChoice.CtrlShiftS => (MOD_CONTROL | MOD_SHIFT, VK_S),
                ShortcutChoice.AltShiftS => (MOD_ALT | MOD_SHIFT, VK_S),
                _ => (MOD_CONTROL | MOD_ALT, VK_S)
            };
        }
    }
}