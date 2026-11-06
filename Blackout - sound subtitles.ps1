<#
.SYNOPSIS
  Blackout - English text for the spoken moments without picture (phone calls, voices, narration).

.DESCRIPTION
  Shows a strip with English text over DOSBox while Blackout plays a spoken sound. Start this script first (with
  'Start sound subtitles.bat') and then play Blackout as usual.

  How it works: when DOSBox has the CD as a FOLDER (mount D "..." -t cdrom), it opens a real file on your PC for every
  film or sound the game opens. A few times per second this script looks which .MOV files DOSBox has open (it only
  reads their names) and shows the text that belongs to that sound. It does not touch the game, DOSBox or your files.
  It ends by itself when DOSBox closes.

.NOTES
  Made in October 2026 by an enthusiast with the help of Claude (Anthropic).
  Works with Windows PowerShell 5.1 (part of Windows 10 and 11).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$CSharp = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

namespace BlackoutSound {

public class Line {
    public double A, B; public string Text;
    public Line(double a, double b, string text) { A = a; B = b; Text = text; }
}

static class Native {
    [DllImport("kernel32.dll", SetLastError = true)] public static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll")] public static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll", SetLastError = true)] public static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll", SetLastError = true)] public static extern bool DuplicateHandle(IntPtr srcProc, IntPtr src, IntPtr dstProc, out IntPtr dst, uint access, bool inherit, uint options);
    [DllImport("kernel32.dll")] public static extern uint GetFileType(IntPtr h);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] public static extern uint GetFinalPathNameByHandleW(IntPtr h, StringBuilder path, uint size, uint flags);
    [DllImport("ntdll.dll")] public static extern int NtQueryInformationProcess(IntPtr proc, int cls, IntPtr buf, uint len, out uint ret);
    [DllImport("ntdll.dll")] public static extern int NtQueryObject(IntPtr h, int cls, IntPtr buf, uint len, out uint ret);
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc f, IntPtr l);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int hh, uint flags);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
}

// Which .MOV files of the game has this process open? Only reads names. The path is asked again every time: DOSBox
// often gets the same handle number for the next file, so remembering by number would miss new sounds.
public class Watcher : IDisposable {
    readonly IntPtr proc; readonly Dictionary<int, string> types = new Dictionary<int, string>();
    int size = 1 << 16; IntPtr buf;
    public readonly int Pid;
    public Watcher(int pid) { Pid = pid; proc = Native.OpenProcess(0x0400 | 0x0040, false, pid); buf = Marshal.AllocHGlobal(size); }
    public bool Ok { get { return proc != IntPtr.Zero; } }
    public void Dispose() { if (proc != IntPtr.Zero) Native.CloseHandle(proc); Marshal.FreeHGlobal(buf); }

    IntPtr Dup(long h) {
        IntPtr d;
        return Native.DuplicateHandle(proc, new IntPtr(h), Native.GetCurrentProcess(), out d, 0, false, 2) ? d : IntPtr.Zero;
    }
    string TypeOf(int index, long h) {
        string name;
        if (types.TryGetValue(index, out name)) return name;
        name = null;
        IntPtr d = Dup(h);
        if (d != IntPtr.Zero) {
            IntPtr b = Marshal.AllocHGlobal(1024); uint ret;
            if (Native.NtQueryObject(d, 2, b, 1024, out ret) == 0) {          // ObjectTypeInformation (never blocks)
                int len = (ushort)Marshal.ReadInt16(b, 0);
                name = Marshal.PtrToStringUni(Marshal.ReadIntPtr(b, IntPtr.Size), len / 2);
            }
            Marshal.FreeHGlobal(b); Native.CloseHandle(d);
        }
        types[index] = name;
        return name;
    }
    public Dictionary<long, string> OpenFilms() {
        Dictionary<long, string> found = new Dictionary<long, string>();
        if (!Ok) return found;
        uint ret; int st;
        while (true) {
            st = Native.NtQueryInformationProcess(proc, 51, buf, (uint)size, out ret);   // ProcessHandleInformation
            if (st != unchecked((int)0xC0000004)) break;                                 // STATUS_INFO_LENGTH_MISMATCH
            size = Math.Max((int)ret + 4096, size * 2);
            Marshal.FreeHGlobal(buf); buf = Marshal.AllocHGlobal(size);
        }
        if (st != 0) return found;
        int ptr = IntPtr.Size;
        long count = Marshal.ReadIntPtr(buf, 0).ToInt64();
        int entry = 3 * ptr + 16;
        for (long i = 0; i < count; i++) {
            int o = 2 * ptr + (int)i * entry;
            long h = Marshal.ReadIntPtr(buf, o).ToInt64();
            int index = Marshal.ReadInt32(buf, o + 3 * ptr + 4);
            if (TypeOf(index, h) != "File") continue;
            IntPtr d = Dup(h);
            if (d == IntPtr.Zero) continue;
            if (Native.GetFileType(d) == 1) {                                            // FILE_TYPE_DISK
                StringBuilder sb = new StringBuilder(1024);
                if (Native.GetFinalPathNameByHandleW(d, sb, 1024, 0) > 0) {
                    string p = sb.ToString().ToUpperInvariant();
                    int at = p.IndexOf("\\BODATA\\");
                    if (at >= 0 && p.EndsWith(".MOV")) found[h] = p.Substring(at + 1);
                }
            }
            Native.CloseHandle(d);
        }
        return found;
    }
}

// The strip: a see-through window over DOSBox; clicks go through it.
public class Strip : Form {
    static readonly Color Key = Color.FromArgb(1, 2, 3);
    public string Line = null; Font font; int px;
    public Strip() {
        FormBorderStyle = FormBorderStyle.None; ShowInTaskbar = false; TopMost = true;
        BackColor = Key; TransparencyKey = Key; StartPosition = FormStartPosition.Manual;
        SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint, true);
    }
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override CreateParams CreateParams {
        get { CreateParams c = base.CreateParams; c.ExStyle |= 0x80000 | 0x20 | 0x80 | 0x08000000; return c; }   // layered, click-through, tool, no activate
    }
    public void Put(string text, int x, int y, int w, int h) {
        int height = Math.Max(80, h / 4), size = Math.Max(16, h / 24);
        if (size != px) { if (font != null) font.Dispose(); font = new Font("Arial", size, FontStyle.Bold, GraphicsUnit.Pixel); px = size; Invalidate(); }
        Rectangle r = new Rectangle(x, y + h - height, w, height);
        if (Bounds != r) { Bounds = r; Invalidate(); }
        if (Line != text) { Line = text; Invalidate(); }
        if (!Visible) Show();
        Native.SetWindowPos(Handle, new IntPtr(-1), 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0010);        // stay on top, without activating
    }
    protected override void OnPaint(PaintEventArgs e) {
        e.Graphics.Clear(Key);
        if (Line == null || font == null) return;
        e.Graphics.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
        int margin = Width * 7 / 100, edge = Math.Max(2, px / 12);
        using (StringFormat f = new StringFormat()) {
            f.Alignment = StringAlignment.Center; f.LineAlignment = StringAlignment.Far;
            RectangleF r = new RectangleF(margin, 0, Width - 2 * margin, Height - px / 2);
            for (int dx = -edge; dx <= edge; dx++)
                for (int dy = -edge; dy <= edge; dy++)
                    if (dx != 0 || dy != 0) e.Graphics.DrawString(Line, font, Brushes.Black, new RectangleF(r.X + dx, r.Y + dy, r.Width, r.Height), f);
            e.Graphics.DrawString(Line, font, Brushes.White, r, f);
        }
    }
}

public static class Program {
    public static readonly Dictionary<string, List<Line>> Text = new Dictionary<string, List<Line>>();
    public static void AddLine(string path, double a, double b, string text) {
        List<Line> l;
        if (!Text.TryGetValue(path, out l)) { l = new List<Line>(); Text[path] = l; }
        l.Add(new Line(a, b, text));
    }
    static string logPath; static int logged;
    static void Log(string s) {
        if (logged++ > 5000) return;
        try { File.AppendAllText(logPath, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss ") + s + "\r\n"); } catch { }
    }
    static IntPtr GameWindow(int pid) {
        IntPtr best = IntPtr.Zero; long area = 0;
        Native.EnumWindows(delegate(IntPtr h, IntPtr l) {
            uint p; Native.GetWindowThreadProcessId(h, out p);
            if (p == pid && Native.IsWindowVisible(h)) {
                Native.RECT r; Native.GetClientRect(h, out r);
                long a = (long)r.Right * r.Bottom;
                if (a > area) { area = a; best = h; }
            }
            return true;
        }, IntPtr.Zero);
        return best;
    }
    static Process FindDosbox() {
        foreach (Process p in Process.GetProcesses())
            if (p.ProcessName.StartsWith("dosbox", StringComparison.OrdinalIgnoreCase)) return p;
        return null;
    }

    public static void Run(string log) {
        logPath = log;
        Native.SetProcessDPIAware();
        Application.EnableVisualStyles();
        Strip strip = new Strip();
        strip.CreateControl();                             // make the window, keep it hidden
        Process dosbox = null; Watcher watch = null; bool running = false; int idle = 0;
        HashSet<long> open = new HashSet<long>();
        Dictionary<long, string> names = new Dictionary<long, string>();
        long clip = -1; string clipName = null; Stopwatch clock = new Stopwatch();
        Timer timer = new Timer(); timer.Interval = 120;
        timer.Tick += delegate {
            try {
                if (dosbox == null) {
                    if (++idle % 12 != 0) return;
                    dosbox = FindDosbox();
                    if (dosbox == null) return;
                    watch = new Watcher(dosbox.Id);
                    Log("Found DOSBox (" + dosbox.ProcessName + ", process " + dosbox.Id + "), access: " + watch.Ok);
                    Console.WriteLine("DOSBox found. Waiting for the game...");
                    return;
                }
                if (dosbox.HasExited) {
                    Log("DOSBox closed."); timer.Stop(); Application.Exit(); return;
                }
                Dictionary<long, string> films = watch.OpenFilms();
                foreach (long h in new List<long>(open))
                    if (!films.ContainsKey(h)) {
                        if (h == clip) { clip = -1; clipName = null; }
                        open.Remove(h);
                    }
                foreach (KeyValuePair<long, string> f in films) {
                    string old;
                    bool isNew = !open.Contains(f.Key) || !names.TryGetValue(f.Key, out old) || old != f.Value;
                    names[f.Key] = f.Value; open.Add(f.Key);
                    if (!isNew) continue;
                    if (!running) { running = true; Console.WriteLine("The game is playing from the CD folder: text appears when someone speaks."); }
                    bool hasText = Text.ContainsKey(f.Value);
                    Log((hasText ? "text    " : "no text ") + f.Value);
                    if (hasText) { clip = f.Key; clipName = f.Value; clock.Restart(); }     // a sound effect does not chase away a spoken text
                }
                string line = null;
                if (clipName != null) {
                    double t = clock.Elapsed.TotalSeconds;
                    foreach (Line l in Text[clipName]) if (l.A - 0.1 <= t && t < l.B + 0.4) { line = l.Text; break; }
                }
                IntPtr w = line != null ? GameWindow(dosbox.Id) : IntPtr.Zero;
                if (line != null && w != IntPtr.Zero && !Native.IsIconic(w)) {
                    Native.RECT r; Native.GetClientRect(w, out r);
                    Native.POINT p = new Native.POINT(); Native.ClientToScreen(w, ref p);
                    strip.Put(line, p.X, p.Y, r.Right, r.Bottom);
                } else if (strip.Visible) strip.Hide();
            } catch (Exception e) { Log("error: " + e.Message); }
        };
        timer.Start();
        Application.Run();
        if (watch != null) watch.Dispose();
    }
}
}
'@

try {
    $here = Split-Path -Parent $MyInvocation.MyCommand.Path
    $json = Join-Path $here 'subtitles\sound.json'
    if (-not (Test-Path -LiteralPath $json)) { throw "The file subtitles\sound.json is missing next to this script. Extract the WHOLE zip file again." }
    Add-Type -TypeDefinition $CSharp -Language CSharp -ReferencedAssemblies System, System.Core, System.Drawing, System.Windows.Forms
    $data = Get-Content -LiteralPath $json -Raw -Encoding UTF8 | ConvertFrom-Json
    $n = 0
    foreach ($p in $data.PSObject.Properties) {
        $n++
        foreach ($l in $p.Value) { [BlackoutSound.Program]::AddLine($p.Name, [double]$l[0], [double]$l[1], [string]$l[2]) }
    }
    $host.UI.RawUI.WindowTitle = 'Blackout - sound subtitles'
    Write-Host "Blackout - sound subtitles ($n spoken sounds)" -ForegroundColor White
    Write-Host 'Leave this window open and start Blackout in DOSBox now. It closes by itself when DOSBox closes.' -ForegroundColor Green
    Write-Host 'To stop earlier: close this window.' -ForegroundColor Gray
    [BlackoutSound.Program]::Run((Join-Path $here 'blackout-sound-subtitles.log'))
}
catch {
    Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
    [void](Read-Host 'Press Enter to close this window')
    exit 1
}
