using System;
using System.Runtime.InteropServices;
using System.Windows.Interop;

namespace PontenWPF
{
    public class GlobalShortcutManager : IDisposable
    {
        [DllImport("user32.dll")]
        private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

        [DllImport("user32.dll")]
        private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

        private IntPtr _hWnd;
        private int _hotKeyId;

        public bool Success { get; private set; }
        public event Action? HotKeyPressed;

        public GlobalShortcutManager(IntPtr hWnd)
        {
            _hWnd = hWnd;
        }

        public void RegisterShortcut(int id, uint modifiers, uint key)
        {
            if (_hotKeyId != 0)
            {
                UnregisterHotKey(_hWnd, _hotKeyId);
                ComponentDispatcher.ThreadPreprocessMessage -= ThreadPreprocessMessageMethod;
            }

            _hotKeyId = id;
            Success = RegisterHotKey(_hWnd, id, modifiers, key);
            if (Success)
            {
                ComponentDispatcher.ThreadPreprocessMessage += ThreadPreprocessMessageMethod;
            }
        }

        private void ThreadPreprocessMessageMethod(ref MSG msg, ref bool handled)
        {
            const int WM_HOTKEY = 0x0312;

            if (msg.message == WM_HOTKEY && msg.wParam.ToInt32() == _hotKeyId)
            {
                HotKeyPressed?.Invoke();
                handled = true;
            }
        }

        public void Dispose()
        {
            UnregisterHotKey(_hWnd, _hotKeyId);
            ComponentDispatcher.ThreadPreprocessMessage -= ThreadPreprocessMessageMethod;
        }
    }
}
