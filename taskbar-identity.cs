using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
using System.Text;

namespace Tandem.Claude {
    // Uses shell window/shortcut properties; no code is loaded into Claude.
    public static class TaskbarIdentity {
        [StructLayout(LayoutKind.Sequential)] struct PropertyKey {
            public Guid Format; public uint Id;
            public PropertyKey(uint id) { Format = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"); Id = id; }
        }
        [StructLayout(LayoutKind.Explicit, Size = 24)] struct Variant {
            [FieldOffset(0)] public ushort Type;
            [FieldOffset(8)] public IntPtr Text;
        }
        [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface PropertyStore {
            void GetCount(out uint count);
            void GetAt(uint index, out PropertyKey key);
            void GetValue(ref PropertyKey key, out Variant value);
            void SetValue(ref PropertyKey key, ref Variant value);
            void Commit();
        }
        [DllImport("shell32.dll")] static extern int SHGetPropertyStoreForWindow(IntPtr window, ref Guid iid, out PropertyStore store);
        [DllImport("ole32.dll")] static extern int PropVariantClear(ref Variant value);
        [DllImport("shell32.dll")] static extern void SHChangeNotify(uint change, uint flags, IntPtr item1, IntPtr item2);
        delegate bool EnumCallback(IntPtr window, IntPtr data);
        [DllImport("user32.dll")] static extern bool EnumWindows(EnumCallback callback, IntPtr data);
        [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
        [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
        [DllImport("user32.dll", EntryPoint = "GetWindowLongW")] static extern int GetWindowStyle(IntPtr window, int index);
        [DllImport("user32.dll")] static extern bool IsWindow(IntPtr window);
        [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr window, uint relation);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr window, StringBuilder name, int length);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr LoadImage(IntPtr instance, string path, uint type, int width, int height, uint flags);
        [DllImport("user32.dll")] static extern bool DestroyIcon(IntPtr icon);
        [DllImport("user32.dll")] static extern IntPtr CopyIcon(IntPtr icon);
        [DllImport("user32.dll", SetLastError = true)] static extern IntPtr SendMessageTimeout(IntPtr window, uint message, UIntPtr argument, IntPtr value, uint flags, uint timeout, out UIntPtr result);
        static readonly uint[] Fields = { 2, 3, 4, 5 };
        sealed class Original { public string[] Values; public string Assigned; public IntPtr Small; public IntPtr Large; }
        static readonly Dictionary<IntPtr, Original> originals = new Dictionary<IntPtr, Original>();
        static readonly Dictionary<string, IntPtr[]> icons = new Dictionary<string, IntPtr[]>();

        static PropertyStore WindowStore(IntPtr window) {
            var iid = typeof(PropertyStore).GUID;
            PropertyStore store;
            Marshal.ThrowExceptionForHR(SHGetPropertyStoreForWindow(window, ref iid, out store));
            return store;
        }
        static string Read(PropertyStore store, uint id) {
            var key = new PropertyKey(id); Variant value;
            store.GetValue(ref key, out value);
            try { return value.Type == 31 ? Marshal.PtrToStringUni(value.Text) : null; }
            finally { PropVariantClear(ref value); }
        }
        static void Write(PropertyStore store, uint id, string text) {
            var key = new PropertyKey(id);
            var value = new Variant();
            if (text != null) { value.Type = 31; value.Text = Marshal.StringToCoTaskMemUni(text); }
            try { store.SetValue(ref key, ref value); }
            catch (COMException error) { throw new COMException("Cannot set taskbar property " + id + ": " + error.Message, error.ErrorCode); }
            finally { PropVariantClear(ref value); }
        }
        public static string ReadWindow(IntPtr window, uint property) {
            var store = WindowStore(window);
            try { return Read(store, property); }
            finally { Marshal.ReleaseComObject(store); }
        }
        static IntPtr Message(IntPtr window, uint message, uint kind, IntPtr value) {
            UIntPtr result;
            SendMessageTimeout(window, message, new UIntPtr(kind), value, 2, 500, out result);
            return new IntPtr(unchecked((long)result.ToUInt64()));
        }
        public static IntPtr[] WindowsForProcess(uint process) {
            var result = new List<IntPtr>();
            EnumWindows(delegate(IntPtr window, IntPtr ignored) {
                uint owner; GetWindowThreadProcessId(window, out owner);
                var name = new StringBuilder(128); GetClassName(window, name, name.Capacity);
                if (owner == process && IsWindowVisible(window) && (GetWindowStyle(window, -20) & 0x80) == 0 && GetWindow(window, 4) == IntPtr.Zero && name.ToString().StartsWith("Chrome_WidgetWin_")) result.Add(window);
                return true;
            }, IntPtr.Zero);
            return result.ToArray();
        }
        public static bool IsIconValid(IntPtr icon) {
            if (icon == IntPtr.Zero) return false;
            IntPtr copy = CopyIcon(icon);
            if (copy == IntPtr.Zero) return false;
            DestroyIcon(copy);
            return true;
        }
        static IntPtr[] LoadIcons(string path) {
            IntPtr[] pair;
            if (icons.TryGetValue(path, out pair) && IsIconValid(pair[0]) && IsIconValid(pair[1])) return pair;
            if (pair != null) foreach (IntPtr icon in pair) if (IsIconValid(icon)) DestroyIcon(icon);
            pair = new IntPtr[] { LoadImage(IntPtr.Zero, path, 1, 16, 16, 0x10), LoadImage(IntPtr.Zero, path, 1, 32, 32, 0x10) };
            if (!IsIconValid(pair[0]) || !IsIconValid(pair[1])) {
                foreach (IntPtr icon in pair) if (icon != IntPtr.Zero) DestroyIcon(icon);
                icons.Remove(path);
                throw new InvalidOperationException("Could not load taskbar icons: " + path);
            }
            icons[path] = pair;
            return pair;
        }
        public static bool WindowIconsValid(IntPtr window) {
            return IsIconValid(Message(window, 0x7F, 0, IntPtr.Zero)) && IsIconValid(Message(window, 0x7F, 1, IntPtr.Zero));
        }
        public static bool NeedsApply(IntPtr window, string id, string iconPath) {
            // Shell properties survive the helper that wrote them; its owned
            // HICON resources do not. Every helper must claim each window anew.
            if (!originals.ContainsKey(window)) return true;
            IntPtr[] pair;
            if (!icons.TryGetValue(iconPath, out pair) || !IsIconValid(pair[0]) || !IsIconValid(pair[1])) return true;
            return ReadWindow(window, 5) != id || ReadWindow(window, 3) != iconPath + ",0" ||
                Message(window, 0x7F, 0, IntPtr.Zero) != pair[0] || Message(window, 0x7F, 1, IntPtr.Zero) != pair[1];
        }
        public static void Apply(IntPtr window, string id, string command, string displayName, string iconPath) {
            var pair = LoadIcons(iconPath);
            var store = WindowStore(window);
            try {
                if (!originals.ContainsKey(window)) {
                    var values = new string[Fields.Length];
                    for (int i = 0; i < Fields.Length; i++) values[i] = Read(store, Fields[i]);
                    bool inherited = values[3] == id || (values[3] != null && values[3].StartsWith("Tandem.Claude.", StringComparison.Ordinal));
                    originals[window] = new Original { Values = inherited ? new string[Fields.Length] : values, Assigned = id,
                        Small = inherited ? IntPtr.Zero : Message(window, 0x7F, 0, IntPtr.Zero),
                        Large = inherited ? IntPtr.Zero : Message(window, 0x7F, 1, IntPtr.Zero) };
                }
                // Install live icons and relaunch details before publishing the
                // group identity, so the shell never sees dead HICON resources.
                Message(window, 0x80, 0, pair[0]);
                Message(window, 0x80, 1, pair[1]);
                Write(store, 2, command); Write(store, 3, iconPath + ",0");
                Write(store, 4, displayName); Write(store, 5, id);
            } finally { Marshal.ReleaseComObject(store); }
        }
        public static void RestoreAll() {
            foreach (var pair in originals) {
                if (!IsWindow(pair.Key)) continue;
                try {
                    var store = WindowStore(pair.Key);
                    try {
                        if (Read(store, 5) != pair.Value.Assigned) continue;
                        for (int i = 0; i < Fields.Length; i++) Write(store, Fields[i], pair.Value.Values[i]);
                        Message(pair.Key, 0x80, 0, IsIconValid(pair.Value.Small) ? pair.Value.Small : IntPtr.Zero);
                        Message(pair.Key, 0x80, 1, IsIconValid(pair.Value.Large) ? pair.Value.Large : IntPtr.Zero);
                    } finally { Marshal.ReleaseComObject(store); }
                } catch (COMException) { }
            }
            originals.Clear();
            foreach (var pair in icons.Values) foreach (var icon in pair) if (icon != IntPtr.Zero) DestroyIcon(icon);
            icons.Clear();
        }
        public static void NotifyShortcutChanged(string path) {
            if (String.IsNullOrEmpty(path)) throw new ArgumentException("A shortcut path is required", "path");
            IntPtr item = Marshal.StringToHGlobalUni(path);
            try {
                // SHCNE_UPDATEITEM + SHCNF_PATHW | SHCNF_FLUSH. Rewriting a .lnk
                // alone can leave other Explorer views displaying a cached icon.
                SHChangeNotify(0x2000, 0x1005, item, IntPtr.Zero);
            } finally { Marshal.FreeHGlobal(item); }
        }
        public static void SetShortcut(string path, string id) {
            object link = Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("00021401-0000-0000-C000-000000000046")));
            try {
                var file = (IPersistFile)link; file.Load(path, 2);
                var store = (PropertyStore)link; Write(store, 5, id); store.Commit(); file.Save(path, true);
            } finally { Marshal.ReleaseComObject(link); }
            NotifyShortcutChanged(path);
        }
        public static string ReadShortcut(string path) {
            object link = Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("00021401-0000-0000-C000-000000000046")));
            try { ((IPersistFile)link).Load(path, 0); return Read((PropertyStore)link, 5); }
            finally { Marshal.ReleaseComObject(link); }
        }
    }
}
