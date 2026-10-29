using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Windows;

namespace LowGear.UI
{
    public sealed class DisplayArea
    {
        // Virtual-screen pixels; no display names, serial numbers or device identifiers.
        public double Left, Top, Width, Height;
        public bool Primary;
    }
    public sealed class PanelPlacement
    {
        public double Width, Height, RelativeX, RelativeY;
        public bool Maximized;
        public DisplayArea WorkArea;
    }
    public sealed class PlacementResult
    {
        public double Left, Top, Width, Height, MinWidth, MinHeight;
        public bool Maximized, Recovered;
    }
    public static class WindowPlacement
    {
        [StructLayout(LayoutKind.Sequential)] private struct NativeRect { public int Left, Top, Right, Bottom; }
        [StructLayout(LayoutKind.Sequential)] private struct MonitorInfo { public int Size; public NativeRect Monitor, Work; public int Flags; }
        private delegate bool MonitorCallback(IntPtr monitor, IntPtr dc, ref NativeRect rect, IntPtr data);
        [DllImport("user32.dll")] private static extern bool EnumDisplayMonitors(IntPtr dc, IntPtr clip, MonitorCallback callback, IntPtr data);
        [DllImport("user32.dll", CharSet = CharSet.Auto)] private static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo info);
        [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr window, out NativeRect rect);

        private static bool Finite(double value) { return !Double.IsNaN(value) && !Double.IsInfinity(value) && Math.Abs(value) < 10000000; }
        public static bool ValidArea(DisplayArea area) { return area != null && Finite(area.Left) && Finite(area.Top) && Finite(area.Width) && Finite(area.Height) && area.Width > 0 && area.Height > 0; }
        public static bool Valid(PanelPlacement placement)
        {
            return placement != null && ValidArea(placement.WorkArea) && Finite(placement.Width) && Finite(placement.Height) && placement.Width > 0 && placement.Height > 0 &&
                Finite(placement.RelativeX) && Finite(placement.RelativeY) && placement.RelativeX >= 0 && placement.RelativeX <= 1 && placement.RelativeY >= 0 && placement.RelativeY <= 1;
        }
        public static DisplayArea[] GetAreas()
        {
            List<DisplayArea> areas = new List<DisplayArea>();
            try
            {
                MonitorCallback callback = delegate(IntPtr monitor, IntPtr dc, ref NativeRect rect, IntPtr data)
                {
                    MonitorInfo info = new MonitorInfo(); info.Size = Marshal.SizeOf(typeof(MonitorInfo));
                    if (GetMonitorInfo(monitor, ref info))
                    {
                        DisplayArea area = new DisplayArea { Left = info.Work.Left, Top = info.Work.Top, Width = info.Work.Right - info.Work.Left, Height = info.Work.Bottom - info.Work.Top, Primary = (info.Flags & 1) != 0 };
                        if (ValidArea(area)) areas.Add(area);
                    }
                    return true;
                };
                EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, callback, IntPtr.Zero);
                GC.KeepAlive(callback);
            }
            catch { }
            return areas.ToArray();
        }
        private static Rect Rectangle(DisplayArea area) { return new Rect(area.Left, area.Top, area.Width, area.Height); }
        private static double Intersection(Rect first, Rect second)
        {
            Rect value = Rect.Intersect(first, second); return value.IsEmpty ? 0 : value.Width * value.Height;
        }
        private static DisplayArea Primary(DisplayArea[] areas)
        {
            if (areas == null || areas.Length == 0) throw new ArgumentException("A usable work area is required.");
            foreach (DisplayArea area in areas) if (ValidArea(area) && area.Primary) return area;
            foreach (DisplayArea area in areas) if (ValidArea(area)) return area;
            throw new ArgumentException("A usable work area is required.");
        }
        private static DisplayArea Best(Rect rectangle, DisplayArea[] areas, out bool overlaps)
        {
            DisplayArea selected = Primary(areas); double largest = 0;
            foreach (DisplayArea area in areas)
            {
                if (!ValidArea(area)) continue;
                double size = Intersection(rectangle, Rectangle(area));
                if (size > largest) { selected = area; largest = size; }
            }
            overlaps = largest > 0; return selected;
        }
        private static double Scale(double value) { return Finite(value) && value > 0 ? value : 1; }
        private static double Clamp(double value, double minimum, double maximum) { return Math.Max(minimum, Math.Min(maximum, value)); }
        public static Rect CurrentBounds(IntPtr window, double scaleX, double scaleY)
        {
            NativeRect rect;
            if (window == IntPtr.Zero || !GetWindowRect(window, out rect) || rect.Right <= rect.Left || rect.Bottom <= rect.Top) return Rect.Empty;
            return new Rect(rect.Left / Scale(scaleX), rect.Top / Scale(scaleY), (rect.Right - rect.Left) / Scale(scaleX), (rect.Bottom - rect.Top) / Scale(scaleY));
        }
        public static PanelPlacement Capture(Rect bounds, bool maximized, DisplayArea[] areas, double scaleX, double scaleY)
        {
            if (bounds.IsEmpty || !Finite(bounds.Left) || !Finite(bounds.Top) || !Finite(bounds.Width) || !Finite(bounds.Height) || bounds.Width <= 0 || bounds.Height <= 0) return null;
            scaleX = Scale(scaleX); scaleY = Scale(scaleY);
            bool overlaps; DisplayArea area = Best(new Rect(bounds.Left * scaleX, bounds.Top * scaleY, bounds.Width * scaleX, bounds.Height * scaleY), areas, out overlaps);
            double paddingX = Math.Min(8, area.Width / scaleX / 4), paddingY = Math.Min(8, area.Height / scaleY / 4);
            double availableX = area.Width / scaleX - 2 * paddingX - bounds.Width, availableY = area.Height / scaleY - 2 * paddingY - bounds.Height;
            return new PanelPlacement {
                Width = bounds.Width, Height = bounds.Height, Maximized = maximized,
                RelativeX = !overlaps || availableX <= 0 ? 0.5 : Clamp((bounds.Left - area.Left / scaleX - paddingX) / availableX, 0, 1),
                RelativeY = !overlaps || availableY <= 0 ? 0.5 : Clamp((bounds.Top - area.Top / scaleY - paddingY) / availableY, 0, 1),
                WorkArea = new DisplayArea { Left = area.Left, Top = area.Top, Width = area.Width, Height = area.Height }
            };
        }
        private static PlacementResult Fit(PanelPlacement saved, DisplayArea area, double scaleX, double scaleY, bool recovered)
        {
            double x = area.Left / Scale(scaleX), y = area.Top / Scale(scaleY), width = area.Width / Scale(scaleX), height = area.Height / Scale(scaleY);
            double paddingX = Math.Min(8, width / 4), paddingY = Math.Min(8, height / 4);
            double maximumWidth = Math.Max(1, width - 2 * paddingX), maximumHeight = Math.Max(1, height - 2 * paddingY);
            double minimumWidth = Math.Min(880, maximumWidth), minimumHeight = Math.Min(600, maximumHeight);
            double panelWidth = Clamp(saved == null ? 1060 : saved.Width, minimumWidth, maximumWidth), panelHeight = Clamp(saved == null ? 800 : saved.Height, minimumHeight, maximumHeight);
            double relativeX = saved == null || recovered ? 0.5 : saved.RelativeX, relativeY = saved == null || recovered ? 0.5 : saved.RelativeY;
            return new PlacementResult {
                Left = x + paddingX + (maximumWidth - panelWidth) * relativeX, Top = y + paddingY + (maximumHeight - panelHeight) * relativeY,
                Width = panelWidth, Height = panelHeight, MinWidth = minimumWidth, MinHeight = minimumHeight,
                Maximized = saved != null && saved.Maximized, Recovered = recovered
            };
        }
        public static PlacementResult Resolve(PanelPlacement saved, DisplayArea[] areas, double scaleX, double scaleY)
        {
            if (!Valid(saved)) return Fit(null, Primary(areas), scaleX, scaleY, saved != null);
            bool overlaps; DisplayArea selected = Best(Rectangle(saved.WorkArea), areas, out overlaps);
            return Fit(saved, selected, scaleX, scaleY, !overlaps);
        }
        public static PlacementResult DefaultFor(Rect current, DisplayArea[] areas, double scaleX, double scaleY)
        {
            scaleX = Scale(scaleX); scaleY = Scale(scaleY); bool overlaps;
            DisplayArea selected = current.IsEmpty ? Primary(areas) : Best(new Rect(current.Left * scaleX, current.Top * scaleY, current.Width * scaleX, current.Height * scaleY), areas, out overlaps);
            return Fit(null, selected, scaleX, scaleY, false);
        }
        public static bool Reachable(Rect bounds, DisplayArea[] areas, double scaleX, double scaleY)
        {
            if (bounds.IsEmpty || !Finite(bounds.Width) || !Finite(bounds.Height) || bounds.Width <= 0 || bounds.Height <= 0 || !Finite(bounds.Left) || !Finite(bounds.Top)) return false;
            scaleX = Scale(scaleX); scaleY = Scale(scaleY);
            Rect caption = new Rect(bounds.Left * scaleX, bounds.Top * scaleY, bounds.Width * scaleX, Math.Min(32, bounds.Height) * scaleY);
            foreach (DisplayArea area in areas)
            {
                if (!ValidArea(area)) continue;
                Rect intersection = Rect.Intersect(caption, Rectangle(area));
                if (!intersection.IsEmpty && intersection.Width >= Math.Min(160, bounds.Width) * scaleX && intersection.Height >= Math.Min(24, bounds.Height) * scaleY) return true;
            }
            return false;
        }
    }
}
