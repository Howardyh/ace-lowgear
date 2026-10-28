using System;
using System.IO;
using System.Text;
using System.Threading;
using System.Diagnostics;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Web.Script.Serialization;

namespace LowGear {
    public sealed class Sample {
        public string Image;
        public int? ProcessId;
        public string CreationUtc;
        public bool Running;
        public uint? CpuClass;
        public int? IoPriority;
        public int? EffectiveIoPriority;
        public string EffectiveIoStatus;
        public string Affinity;
        public bool? AffinityMatched;
        public bool Verified;
        public int Changes;
        public List<string> Errors = new List<string>();
    }
    public sealed class Topology {
        public uint LogicalProcessors;
        public ushort Groups;
        public int? LastCpu;
        public string LastMask;
    }
    public sealed class Policy {
        public int Schema = 1;
        public bool BindLastCpu = false;
        public int IntervalSeconds = 3;
    }
    public sealed class SessionTracker {
        string identity = "";
        public int Matches;
        public int Observe(Sample[] samples, bool probe) {
            var parts = new List<string>();
            foreach (var s in samples) if (s.Running) parts.Add(s.Image + ":" + s.ProcessId + ":" + s.CreationUtc);
            parts.Sort(StringComparer.Ordinal);
            string next = String.Join("|", parts.ToArray());
            if (!Runtime.SessionMatches(samples, probe)) { Matches = 0; identity = ""; }
            else { Matches = identity == next ? Matches + 1 : 1; identity = next; }
            return Matches;
        }
    }
    public sealed class Session {
        public int Schema = 1;
        public string Product = "ACE LowGear";
        public string Version = Runtime.Version;
        public string SessionId = Guid.NewGuid().ToString("N");
        public string StartedAtUtc = DateTime.UtcNow.ToString("o");
        public string TimestampUtc;
        public string EndedAtUtc;
        public long ElapsedMilliseconds;
        public int WorkerId = Process.GetCurrentProcess().Id;
        public string SessionState = "Starting";
        public string ErrorCode;
        public long Corrections;
        public Sample[] Processes = new Sample[0];
    }
    public static class Runtime {
        public const string Version = "__LOWGEAR_VERSION__";
        public static readonly string[] Targets = { "SGuard64.exe", "SGuardSvc64.exe", "ACE-Service64.exe" };
        static readonly JavaScriptSerializer Json = new JavaScriptSerializer();
        [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
        [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
        [DllImport("kernel32.dll", SetLastError=true)] static extern uint GetPriorityClass(IntPtr handle);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetPriorityClass(IntPtr handle, uint value);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetProcessTimes(IntPtr handle, out long created, out long exited, out long kernel, out long user);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool QueryFullProcessImageName(IntPtr handle, uint flags, StringBuilder name, ref uint size);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetProcessAffinityMask(IntPtr handle, out UIntPtr process, out UIntPtr system);
        [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetProcessAffinityMask(IntPtr handle, UIntPtr mask);
        [DllImport("kernel32.dll")] static extern ushort GetActiveProcessorGroupCount();
        [DllImport("kernel32.dll")] static extern uint GetActiveProcessorCount(ushort group);
        [DllImport("ntdll.dll")] static extern int NtQueryInformationProcess(IntPtr handle, int type, out int value, uint size, out uint returned);
        [DllImport("ntdll.dll")] static extern int NtSetInformationProcess(IntPtr handle, int type, ref int value, uint size);
        static string Win32(string operation) { return operation + ": Win32 " + Marshal.GetLastWin32Error(); }
        static bool Unsupported(int code) { return code == unchecked((int)0xC0000003) || code == unchecked((int)0xC0000002) || code == unchecked((int)0xC00000BB); }
        public static Topology GetTopology() {
            var t = new Topology { LogicalProcessors = GetActiveProcessorCount(ushort.MaxValue), Groups = GetActiveProcessorGroupCount() };
            if (t.Groups == 1 && IntPtr.Size == 8) {
                UIntPtr process, system;
                using (var self = Process.GetCurrentProcess()) {
                    if (GetProcessAffinityMask(self.Handle, out process, out system)) {
                        ulong value = system.ToUInt64(); int index = -1;
                        while (value != 0) { index++; value >>= 1; }
                        if (index >= 0) { t.LastCpu = index; t.LastMask = (1UL << index).ToString("X"); }
                    }
                }
            }
            return t;
        }
        static bool IdentityMatches(IntPtr handle, string image, List<string> errors) {
            var path = new StringBuilder(32768); uint size = (uint)path.Capacity;
            if (!QueryFullProcessImageName(handle, 0, path, ref size)) { errors.Add(Win32("Identity")); return false; }
            if (!String.Equals(Path.GetFileName(path.ToString()), image, StringComparison.OrdinalIgnoreCase)) {
                errors.Add("Process identity changed; operation skipped."); return false;
            }
            return true;
        }
        static void Read(IntPtr handle, Sample result, bool last) {
            uint cpu = GetPriorityClass(handle);
            if (cpu != 0) result.CpuClass = cpu; else result.Errors.Add(Win32("CPU query"));
            int value; uint length;
            int status = NtQueryInformationProcess(handle, 33, out value, 4, out length);
            if (status >= 0 && length == 4) result.IoPriority = value;
            else result.Errors.Add("I/O query: NTSTATUS 0x" + status.ToString("X8"));
            status = NtQueryInformationProcess(handle, 110, out value, 4, out length);
            if (status >= 0 && length == 4) result.EffectiveIoPriority = value;
            else {
                result.EffectiveIoStatus = "NTSTATUS 0x" + status.ToString("X8");
                if (!Unsupported(status)) result.Errors.Add("Effective I/O query: " + result.EffectiveIoStatus);
            }
            UIntPtr processMask, systemMask;
            if (GetActiveProcessorGroupCount() == 1 && GetProcessAffinityMask(handle, out processMask, out systemMask)) {
                result.Affinity = "0x" + processMask.ToUInt64().ToString("X");
                var topology = GetTopology();
                if (last && topology.LastCpu.HasValue) result.AffinityMatched = processMask.ToUInt64() == (1UL << topology.LastCpu.Value);
            }
            if (last && !result.AffinityMatched.HasValue) result.Errors.Add("Last-CPU affinity unavailable on this processor topology.");
        }
        public static Sample Inspect(int pid, string image, bool apply, bool last) {
            var result = new Sample { Image = image, ProcessId = pid, Running = true };
            IntPtr read = OpenProcess(0x1400, false, pid);
            if (read == IntPtr.Zero) read = OpenProcess(0x1000, false, pid);
            if (read == IntPtr.Zero) { result.Errors.Add(Win32("OpenProcess")); return result; }
            try {
                if (!IdentityMatches(read, image, result.Errors)) return result;
                long created, exited, kernel, user;
                if (GetProcessTimes(read, out created, out exited, out kernel, out user)) result.CreationUtc = DateTime.FromFileTimeUtc(created).ToString("o");
                Read(read, result, last);
                if (apply && (result.CpuClass != 64 || result.IoPriority != 0 || (last && result.AffinityMatched != true))) {
                    IntPtr write = OpenProcess(0x1200, false, pid);
                    if (write == IntPtr.Zero) result.Errors.Add(Win32("Set access"));
                    else try {
                        if (IdentityMatches(write, image, result.Errors)) {
                            if (result.CpuClass.HasValue && result.CpuClass != 64) {
                                if (SetPriorityClass(write, 64)) result.Changes++; else result.Errors.Add(Win32("CPU set"));
                            }
                            if (result.IoPriority.HasValue && result.IoPriority != 0) {
                                int low = 0; int status = NtSetInformationProcess(write, 33, ref low, 4);
                                if (status >= 0) result.Changes++; else result.Errors.Add("I/O set: NTSTATUS 0x" + status.ToString("X8"));
                            }
                            if (last && result.AffinityMatched != true) {
                                var t = GetTopology();
                                if (t.LastCpu.HasValue && SetProcessAffinityMask(write, new UIntPtr(1UL << t.LastCpu.Value))) result.Changes++;
                                else result.Errors.Add("Last-CPU affinity could not be set.");
                            }
                        }
                    } finally { CloseHandle(write); }
                    // Re-read through the same process handle to avoid PID reuse.
                    result.CpuClass = null; result.IoPriority = null; result.EffectiveIoPriority = null;
                    Read(read, result, last);
                }
                result.Verified = result.CpuClass == 64 && result.IoPriority == 0 &&
                    (!result.EffectiveIoPriority.HasValue || result.EffectiveIoPriority == 0) &&
                    (!last || result.AffinityMatched == true) && result.Errors.Count == 0;
                return result;
            } finally { CloseHandle(read); }
        }
        public static Sample[] Scan(bool apply, bool last, string probe) {
            string[] targets = Targets;
            if (!String.IsNullOrEmpty(probe)) {
                if (!System.Text.RegularExpressions.Regex.IsMatch(probe, @"^LowGearProbe-[a-f0-9]{32}\.exe$")) throw new ArgumentException("Invalid probe image.");
                targets = new[] { probe };
            }
            var result = new List<Sample>();
            foreach (string image in targets) {
                Process[] processes = Process.GetProcessesByName(Path.GetFileNameWithoutExtension(image));
                if (processes.Length == 0) result.Add(new Sample { Image = image, Running = false });
                foreach (var p in processes) {
                    try { result.Add(Inspect(p.Id, image, apply, last)); }
                    catch (Exception e) { var s = new Sample { Image = image, Running = true }; s.Errors.Add(e.GetType().Name); result.Add(s); }
                    finally { p.Dispose(); }
                }
            }
            return result.ToArray();
        }
        public static void WriteJson(string path, object value) {
            string temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
            try {
                File.WriteAllText(temporary, Json.Serialize(value), new UTF8Encoding(false));
                if (File.Exists(path)) File.Replace(temporary, path, null); else File.Move(temporary, path);
            } finally { if (File.Exists(temporary)) File.Delete(temporary); }
        }
        public static bool SessionMatches(Sample[] samples, bool probe) {
            bool first = false, second = false, found = false;
            foreach (var sample in samples) {
                if (!sample.Running) continue;
                found = true;
                if (!sample.Verified) return false;
                if (String.Equals(sample.Image, "SGuard64.exe", StringComparison.OrdinalIgnoreCase)) first = true;
                if (String.Equals(sample.Image, "SGuardSvc64.exe", StringComparison.OrdinalIgnoreCase)) second = true;
            }
            return probe ? found : first && second;
        }
        public static int Worker(string root, string probe, int duration) {
            bool test = !String.IsNullOrEmpty(probe);
            if (test && (duration < 1 || duration > 60)) throw new ArgumentException("A probe worker must have a bounded lifetime.");
            bool owns = false;
            using (var mutex = new Mutex(false, test ? "Local\\LowGearProbe-" + probe : "Global\\ACE-LowGear-1")) {
                Session session = null; var clock = Stopwatch.StartNew();
                try { try { owns = mutex.WaitOne(0); } catch (AbandonedMutexException) { owns = true; } if (!owns) return 0;
                    session = new Session(); var tracker = new SessionTracker();
                    SaveSession(root, session, clock, false);
                    double limit = test ? duration : 45;
                    if (!test) Thread.Sleep(5000);
                    Sample[] samples = new Sample[0];
                    while (clock.Elapsed.TotalSeconds < limit) {
                        Policy policy = Json.Deserialize<Policy>(File.ReadAllText(Path.Combine(root, "policy.json")));
                        if (policy.Schema != 1 || policy.IntervalSeconds < 2 || policy.IntervalSeconds > 10) throw new InvalidDataException("Unsupported policy.");
                        samples = Scan(true, policy.BindLastCpu, probe);
                        int changes = 0; int running = 0;
                        foreach (var sample in samples) {
                            changes += sample.Changes;
                            if (sample.Running) {
                                running++;
                            }
                        }
                        session.Corrections += changes;
                        int consecutiveMatches = tracker.Observe(samples, test);
                        string state = consecutiveMatches >= (test ? 2 : 3) ? "Completed" : running == 0 ? "NoTargets" : "Verifying";
                        session.Processes = samples; session.SessionState = state;
                        SaveSession(root, session, clock, state == "Completed" || (!test && state == "NoTargets"));
                        if (state == "Completed" || (!test && state == "NoTargets")) return 0;
                        int remaining = (int)Math.Max(0, (limit - clock.Elapsed.TotalSeconds) * 1000);
                        Thread.Sleep(Math.Min(policy.IntervalSeconds * 1000, remaining));
                    }
                    session.SessionState = "Incomplete"; session.Processes = samples;
                    SaveSession(root, session, clock, true);
                    return 2;
                } catch (Exception error) {
                    if (session != null) {
                        session.SessionState = "Failed"; session.ErrorCode = "RUNTIME_FAILURE";
                        SaveSession(root, session, clock, true);
                        WriteJson(Path.Combine(root, "fault.json"), new { SessionId = session.SessionId, Version = Version, Error = error.GetType().Name + ": " + error.Message });
                    }
                    return 1;
                } finally { if (owns) mutex.ReleaseMutex(); }
            }
        }
        static void SaveSession(string root, Session session, Stopwatch clock, bool ended) {
            session.TimestampUtc = DateTime.UtcNow.ToString("o");
            session.ElapsedMilliseconds = clock.ElapsedMilliseconds;
            if (ended) session.EndedAtUtc = session.TimestampUtc;
            WriteJson(Path.Combine(root, "last-run.json"), session);
        }
        [STAThread] public static int Main(string[] args) {
            try {
                if (args.Length == 2 && args[0] == "--once") return Worker(args[1], null, 0);
                if (args.Length == 4 && args[0] == "--probe") return Worker(args[1], args[2], Int32.Parse(args[3]));
                return 2;
            } catch (Exception error) {
                try {
                    if (args.Length >= 2 && (args[0] == "--once" || args[0] == "--probe"))
                        WriteJson(Path.Combine(args[1],"fault.json"),new { Version = Version, TimestampUtc = DateTime.UtcNow.ToString("o"), Error = error.GetType().Name + ": " + error.Message });
                } catch { }
                return 1;
            }
        }
    }
}
