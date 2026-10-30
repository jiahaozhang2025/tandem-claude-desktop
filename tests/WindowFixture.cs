using System;
using System.Runtime.InteropServices;

// An off-screen test window owned by the test runner. No vendor app is controlled.
public static class TandemWindowFixture {
    delegate IntPtr WindowProc(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct WindowClass {
        public uint style;
        public WindowProc procedure;
        public int classExtra, windowExtra;
        public IntPtr instance, icon, cursor, background;
        public string menu, name;
    }
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern ushort RegisterClassW(ref WindowClass value);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr CreateWindowExW(uint exStyle, string className, string title, uint style, int x, int y, int width, int height, IntPtr parent, IntPtr menu, IntPtr instance, IntPtr parameter);
    [DllImport("user32.dll")] static extern IntPtr DefWindowProcW(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool DestroyWindow(IntPtr window);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr window, int command);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr GetModuleHandleW(string name);
    static readonly WindowProc procedure = DefWindowProcW;
    const string ClassName = "Chrome_WidgetWin_TandemRegression";
    static bool registered;

    public static IntPtr Create(bool toolWindow) {
        var instance = GetModuleHandleW(null);
        if (!registered) {
            var cls = new WindowClass { procedure = procedure, instance = instance, name = ClassName };
            if (RegisterClassW(ref cls) == 0) throw new InvalidOperationException("Cannot register test window class");
            registered = true;
        }
        var window = CreateWindowExW(toolWindow ? 0x80u : 0u, ClassName, "Tandem regression fixture", 0x00CF0000u, -30000, -30000, 32, 32, IntPtr.Zero, IntPtr.Zero, instance, IntPtr.Zero);
        if (window == IntPtr.Zero) throw new InvalidOperationException("Cannot create test window");
        return window;
    }
    public static void Show(IntPtr window) { ShowWindow(window, 4); } // no activation
    public static void Hide(IntPtr window) { ShowWindow(window, 0); }
}
