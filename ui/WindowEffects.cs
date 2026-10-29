using System;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Interop;
using System.Management.Automation;
using System.Management.Automation.Runspaces;

namespace LowGear.UI
{
    // This observer exists only while the panel window exists. No service or polling task is registered.
    public sealed class WindowEffects : IDisposable
    {
        private HwndSource source;
        private HwndSourceHook hook;
        private int changed = 1;
        private readonly IntPtr handle;

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct VersionInfo
        {
            public int Size, Major, Minor, Build, Platform;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string ServicePack;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct Margins { public int Left, Right, Top, Bottom; }
        [StructLayout(LayoutKind.Sequential)]
        private struct PowerStatus
        {
            public byte AcLine, BatteryFlag, BatteryPercent, SystemStatus;
            public int BatteryLife, BatteryFullLife;
        }
        [DllImport("ntdll.dll", CharSet = CharSet.Unicode)] private static extern int RtlGetVersion(ref VersionInfo version);
        [DllImport("dwmapi.dll")] private static extern int DwmSetWindowAttribute(IntPtr window, int attribute, ref int value, int size);
        [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(IntPtr window, int attribute, out int value, int size);
        [DllImport("dwmapi.dll")] private static extern int DwmExtendFrameIntoClientArea(IntPtr window, ref Margins margins);
        [DllImport("kernel32.dll")] private static extern bool GetSystemPowerStatus(out PowerStatus status);

        public static int Build
        {
            get
            {
                try { VersionInfo info = new VersionInfo(); info.Size = Marshal.SizeOf(typeof(VersionInfo)); return RtlGetVersion(ref info) == 0 ? info.Build : 0; }
                catch { return 0; }
            }
        }
        public static bool BatterySaver
        {
            get { try { PowerStatus status; return GetSystemPowerStatus(out status) && status.SystemStatus == 1; } catch { return false; } }
        }
        public WindowEffects(IntPtr window)
        {
            handle = window;
            source = HwndSource.FromHwnd(window);
            if (source != null) { hook = OnMessage; source.AddHook(hook); }
        }
        private IntPtr OnMessage(IntPtr window, int message, IntPtr wParam, IntPtr lParam, ref bool handled)
        {
            // Settings, system colours, DWM composition/colour and power policy.
            if (message == 0x001A || message == 0x0015 || message == 0x031A || message == 0x031E || message == 0x0218)
                Interlocked.Exchange(ref changed, 1);
            return IntPtr.Zero;
        }
        public bool TakeChange() { return Interlocked.Exchange(ref changed, 0) != 0; }
        public bool Apply(bool dark, bool mica, bool highContrast)
        {
            try
            {
                if (Build >= 22000)
                {
                    int value = dark ? 1 : 0;
                    DwmSetWindowAttribute(handle, 20, ref value, 4);
                    value = 2; DwmSetWindowAttribute(handle, 33, ref value, 4);
                    value = highContrast || mica ? -1 : (dark ? 0x202020 : 0xF3F3F3);
                    DwmSetWindowAttribute(handle, 35, ref value, 4);
                    value = highContrast ? -1 : (dark ? 0xF2F2F2 : 0x1A1A1A);
                    DwmSetWindowAttribute(handle, 36, ref value, 4);
                }
                if (mica && Build >= 22621 && source != null)
                {
                    int value = 2;
                    int result = DwmSetWindowAttribute(handle, 38, ref value, 4);
                    Margins margins = new Margins { Left = -1, Right = -1, Top = -1, Bottom = -1 };
                    if (result >= 0 && DwmExtendFrameIntoClientArea(handle, ref margins) >= 0)
                    {
                        source.CompositionTarget.BackgroundColor = System.Windows.Media.Colors.Transparent;
                        return true;
                    }
                }
            }
            catch { /* Optional material must never prevent a usable solid window. */ }
            ResetBackdrop();
            return false;
        }
        private void ResetBackdrop()
        {
            try
            {
                if (Build >= 22621) { int value = 1; DwmSetWindowAttribute(handle, 38, ref value, 4); }
                Margins margins = new Margins(); DwmExtendFrameIntoClientArea(handle, ref margins);
            }
            catch { }
        }
        public int BackdropType
        {
            get { try { int value; return DwmGetWindowAttribute(handle, 38, out value, 4) >= 0 ? value : -1; } catch { return -1; } }
        }
        public void Dispose()
        {
            try { if (source != null && hook != null) { source.RemoveHook(hook); } } catch { }
            hook = null; source = null;
        }
        public static void ReleaseQuery(PowerShell pipeline, Runspace runspace)
        {
            // Stop/dispose away from the dispatcher, including a slow provider during window close.
            ThreadPool.QueueUserWorkItem(delegate
            {
                try { if (pipeline != null) { try { pipeline.Stop(); } catch { } pipeline.Dispose(); } }
                finally { if (runspace != null) { try { runspace.Close(); } catch { } runspace.Dispose(); } }
            });
        }
    }
}
