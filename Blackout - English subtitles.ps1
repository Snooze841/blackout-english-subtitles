<#
.SYNOPSIS
  Blackout (Deadline Multimedia, 1997, Swedish, 3 CDs): make copies of your own CD images with English
  subtitles burned into the films.

.DESCRIPTION
  Blackout is a Swedish interactive movie for Windows 3.1. This script contains NO game files. It reads your own
  three CDs (or images of them) and writes NEW images next to them, in which 245 films have English subtitles, and a
  folder with the three CDs together for the sound subtitles (see 'Blackout - sound subtitles.ps1'):
    1. each CD is checked (volume name BLACKOUT1/2/3) and copied to a new image (.iso);
    2. every QuickTime film (.MOV) on the copies is recognised by its fingerprint (SHA-256);
    3. FFmpeg draws the English subtitles (subtitles\*.ass) onto the picture and encodes the video again as
       Cinepak, the codec of the original. The sound stays byte for byte the same;
    4. the new film is put back in the layout of the original QuickTime file (QuickTime 2.1 for Windows 3.1 cannot
       open the files FFmpeg writes) and in the place of the original film on the copy. It always fits;
    5. the copies are checked and get their final names: "Blackout CD n (English subtitles).iso";
    6. all files of the three new images are copied to one folder: "Blackout CDs (English subtitles)".
  Your original CDs and images are only read, never changed. Nothing is installed and nothing in Windows is changed.

.PARAMETER Cd1
  CD 1: the drive letter of your CD drive (e.g. E), an .iso, or the .cue or .bin file of an image. Same for Cd2, Cd3.

.PARAMETER Output
  Folder for the new images and the CD folder (about 3 GB). Default: the folder of the CD 1 image, or
  Documents\Blackout for a CD.

.PARAMETER FFmpeg
  Path to ffmpeg.exe. Without it the script uses the copy in the folder ffmpeg next to this script, or offers to
  download the official build (FFmpeg 9.0.2 essentials from gyan.dev, checked with SHA-256).

.PARAMETER Workers
  Number of films encoded at the same time (default: number of processor cores minus 1, at most 8).

.PARAMETER KeepWork
  Keep the work folder (the subtitled films) after finishing.

.PARAMETER FolderOnly
  Only do step 6, with the three new images that are already in the folder given with -Output (for people who made
  them with version 1.0).

.PARAMETER NoWait
  Do not wait for Enter at the end.

.NOTES
  Made in October 2026 by an enthusiast with the help of Claude (Anthropic).
  Works with Windows PowerShell 5.1 (part of Windows 10 and 11).
#>
[CmdletBinding()]
param(
    [string]$Cd1,
    [string]$Cd2,
    [string]$Cd3,
    [string]$Output,
    [string]$FFmpeg,
    [int]$Workers = 0,
    [switch]$KeepWork,
    [switch]$FolderOnly,
    [switch]$NoWait
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$VERSION = '1.1 (October 2026)'

if ($PSVersionTable.PSVersion.Major -ge 6) {
    Write-Host "This script needs Windows PowerShell 5.1 (powershell.exe), not PowerShell $($PSVersionTable.PSVersion). Double-click 'Patch Blackout.bat'." -ForegroundColor Red
    if (-not $NoWait) { [void](Read-Host 'Press Enter to close this window') }
    exit 1
}

$CSharp = @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace BlackoutSubs {

public static class Util {
    public static uint BE32(byte[] d, long o) { return (uint)(d[o] << 24 | d[o + 1] << 16 | d[o + 2] << 8 | d[o + 3]); }
    public static void PutBE32(Stream s, uint v) { s.WriteByte((byte)(v >> 24)); s.WriteByte((byte)(v >> 16)); s.WriteByte((byte)(v >> 8)); s.WriteByte((byte)v); }
    public static byte[] Sub(byte[] d, long o, long n) {
        if (o > d.Length) o = d.Length;
        if (o + n > d.Length) n = d.Length - o;
        if (n < 0) n = 0;
        byte[] r = new byte[n]; Buffer.BlockCopy(d, (int)o, r, 0, (int)n); return r;
    }
    public static string Hex(byte[] h) { StringBuilder sb = new StringBuilder(); foreach (byte b in h) sb.Append(b.ToString("x2")); return sb.ToString(); }
    public static string Sha256(byte[] d) { using (SHA256 s = SHA256.Create()) return Hex(s.ComputeHash(d)); }
    public static string Sha256File(string path) {
        using (SHA256 s = SHA256.Create())
        using (FileStream f = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 1 << 20)) return Hex(s.ComputeHash(f));
    }
}

// ---------------------------------------------------------------------------------------------------------------
// Sources: a CD image (.iso, 2048 bytes per sector), a raw image (.bin, 2352 bytes per sector) or a CD drive.
// ---------------------------------------------------------------------------------------------------------------
public abstract class Source : IDisposable {
    public abstract int Read(long lba, int n, byte[] buf);   // n sectors of 2048 bytes; returns the number read
    public abstract string Name { get; }
    public virtual void Dispose() { }
    public byte[] Pvd() {
        byte[] b = new byte[2048];
        if (Read(16, 1, b) != 1 || b[0] != 1 || b[1] != 'C' || b[2] != 'D' || b[3] != '0' || b[4] != '0' || b[5] != '1')
            throw new Exception("FIX:" + Name + " is not a PC CD (no ISO 9660 file system).");
        return b;
    }
    public string VolumeId() { return Encoding.ASCII.GetString(Pvd(), 40, 32).Trim(); }
    public long Sectors() { return BitConverter.ToUInt32(Pvd(), 80); }
}

public class IsoSource : Source {
    FileStream f; string path;
    public IsoSource(string p) { path = p; f = new FileStream(p, FileMode.Open, FileAccess.Read, FileShare.Read, 1 << 16); }
    public override string Name { get { return Path.GetFileName(path); } }
    public override int Read(long lba, int n, byte[] buf) {
        f.Position = lba * 2048;
        int want = n * 2048, got = 0;
        while (got < want) { int k = f.Read(buf, got, want - got); if (k <= 0) break; got += k; }
        return got / 2048;
    }
    public override void Dispose() { f.Dispose(); }
}

public class BinSource : Source {
    FileStream f; string path; int offset; byte[] raw = new byte[64 * 2352];
    public BinSource(string p) {
        path = p; f = new FileStream(p, FileMode.Open, FileAccess.Read, FileShare.Read, 1 << 16);
        if (f.Length % 2352 != 0) throw new Exception("FIX:" + Name + " is not a raw CD image (2352 bytes per sector).");
        byte[] s = new byte[2352];
        f.Position = 16 * 2352; f.Read(s, 0, 2352);
        bool sync = s[0] == 0 && s[11] == 0;
        for (int i = 1; i < 11; i++) if (s[i] != 0xFF) sync = false;
        if (!sync) throw new Exception("FIX:" + Name + " is not a raw CD image (no sector sync).");
        if (s[15] == 1) offset = 16; else if (s[15] == 2) offset = 24;
        else throw new Exception("FIX:" + Name + ": unknown sector mode " + s[15] + ".");
    }
    public override string Name { get { return Path.GetFileName(path); } }
    public override int Read(long lba, int n, byte[] buf) {
        int done = 0;
        while (done < n) {
            int k = Math.Min(64, n - done);
            f.Position = (lba + done) * 2352;
            int want = k * 2352, got = 0;
            while (got < want) { int r = f.Read(raw, got, want - got); if (r <= 0) break; got += r; }
            int secs = got / 2352;
            for (int i = 0; i < secs; i++) Buffer.BlockCopy(raw, i * 2352 + offset, buf, (done + i) * 2048, 2048);
            done += secs;
            if (secs < k) break;
        }
        return done;
    }
    public override void Dispose() { f.Dispose(); }
}

public class DriveSource : Source {
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr sa, uint disp, uint flags, IntPtr tmpl);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool SetFilePointerEx(SafeFileHandle h, long dist, out long np, uint method);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool ReadFile(SafeFileHandle h, byte[] buf, int n, out int read, IntPtr ov);
    SafeFileHandle h; string letter;
    public DriveSource(string l) {
        letter = l;
        h = CreateFile("\\\\.\\" + l + ":", 0x80000000, 3, IntPtr.Zero, 3, 0, IntPtr.Zero);
        if (h.IsInvalid) throw new Exception("FIX:Cannot open drive " + l + ": (Windows error " + Marshal.GetLastWin32Error() + "). Is the CD in the drive?");
    }
    public override string Name { get { return "the CD in drive " + letter + ":"; } }
    bool Try(long lba, int n, byte[] buf) {
        long np; int r;
        byte[] tmp = (n * 2048 == buf.Length) ? buf : new byte[n * 2048];
        if (!SetFilePointerEx(h, lba * 2048, out np, 0) || !ReadFile(h, tmp, n * 2048, out r, IntPtr.Zero) || r != n * 2048) return false;
        if (tmp != buf) Buffer.BlockCopy(tmp, 0, buf, 0, n * 2048);
        return true;
    }
    public override int Read(long lba, int n, byte[] buf) {
        if (Try(lba, n, buf)) return n;
        byte[] one = new byte[2048];
        for (int i = 0; i < n; i++) {
            bool ok = false;
            for (int t = 0; t < 5 && !ok; t++) ok = Try(lba + i, 1, one);
            if (!ok) throw new Exception("FIX:Read error on the CD in drive " + letter + ": at sector " + (lba + i) + ". Clean the CD (soft cloth, from the centre outwards) and try again, or make an image of it with another program.");
            Buffer.BlockCopy(one, 0, buf, i * 2048, 2048);
        }
        return n;
    }
    public override void Dispose() { h.Dispose(); }
}

// Copies a source to a new .iso in steps (so that PowerShell can show progress) and computes its SHA-256.
public class Copier : IDisposable {
    Source src; FileStream dst; SHA256 sha = SHA256.Create(); byte[] buf = new byte[64 * 2048];
    public long Done, Total;
    public Copier(Source s, string path, long total) { src = s; Total = total; dst = new FileStream(path, FileMode.Create, FileAccess.Write, FileShare.None, 1 << 20); }
    public bool Step(int sectors) {
        long end = Math.Min(Total, Done + sectors);
        while (Done < end) {
            int n = (int)Math.Min(64, end - Done);
            int got = src.Read(Done, n, buf);
            if (got != n) throw new Exception("FIX:" + src.Name + " ends at sector " + (Done + got) + ", but the CD has " + Total + " sectors. The image is incomplete; make it again.");
            dst.Write(buf, 0, n * 2048);
            sha.TransformBlock(buf, 0, n * 2048, null, 0);
            Done += n;
        }
        return Done < Total;
    }
    public string Finish() { sha.TransformFinalBlock(buf, 0, 0); dst.Flush(true); dst.Dispose(); dst = null; return Util.Hex(sha.Hash); }
    public void Dispose() { if (dst != null) dst.Dispose(); sha.Dispose(); }
}

// ---------------------------------------------------------------------------------------------------------------
// ISO 9660 (+ Joliet): all files, and the films (.MOV) grouped by their place on the CD.
// ---------------------------------------------------------------------------------------------------------------
public class Film {
    public long Lba, Size; public string Path; public string Sha; public List<long> RecordPos = new List<long>();
}

public static class Iso {
    static byte[] ReadAt(FileStream f, long pos, int n) {
        byte[] b = new byte[n]; f.Position = pos; int got = 0;
        while (got < n) { int k = f.Read(b, got, n - got); if (k <= 0) break; got += k; }
        return b;
    }
    public static List<Film> Films(string iso) {
        Dictionary<long, Film> byLba = new Dictionary<long, Film>();
        List<Film> order = new List<Film>();
        using (FileStream f = new FileStream(iso, FileMode.Open, FileAccess.Read, FileShare.Read, 1 << 16)) {
            List<long[]> trees = new List<long[]>();     // {joliet, root lba, root size}
            for (int s = 16; s < 40; s++) {
                byte[] vd = ReadAt(f, s * 2048L, 2048);
                if (vd[1] != 'C' || vd[2] != 'D' || vd[3] != '0' || vd[4] != '0' || vd[5] != '1' || vd[0] == 255) break;
                if (vd[0] == 1 || vd[0] == 2) trees.Add(new long[] { vd[0] == 2 ? 1 : 0, BitConverter.ToUInt32(vd, 156 + 2), BitConverter.ToUInt32(vd, 156 + 10) });
            }
            foreach (long[] t in trees) {
                bool joliet = t[0] == 1;
                Stack<object[]> stack = new Stack<object[]>();
                stack.Push(new object[] { t[1], t[2], "" });
                while (stack.Count > 0) {
                    object[] top = stack.Pop();
                    long lba = (long)top[0], size = (long)top[1]; string prefix = (string)top[2];
                    byte[] data = ReadAt(f, lba * 2048, (int)size);
                    int i = 0;
                    while (i < data.Length) {
                        int ln = data[i];
                        if (ln == 0) { i = (i / 2048 + 1) * 2048; continue; }
                        long pos = lba * 2048 + i;
                        byte[] rec = Util.Sub(data, i, ln);
                        i += ln;
                        int nl = rec[32];
                        if ((nl == 1 && (rec[33] == 0 || rec[33] == 1)) || (rec[25] & 4) != 0) continue;
                        string name = joliet ? Encoding.BigEndianUnicode.GetString(rec, 33, nl) : Encoding.GetEncoding(28591).GetString(rec, 33, nl);
                        int semi = name.IndexOf(';'); if (semi >= 0) name = name.Substring(0, semi);
                        name = name.TrimEnd('.');
                        long eLba = BitConverter.ToUInt32(rec, 2), eSize = BitConverter.ToUInt32(rec, 10);
                        if ((rec[25] & 2) != 0) { stack.Push(new object[] { eLba, eSize, prefix + name + "\\" }); continue; }
                        string full = (prefix + name).ToUpperInvariant();
                        if (!full.EndsWith(".MOV")) continue;
                        Film film;
                        if (!byLba.TryGetValue(eLba, out film)) {
                            film = new Film(); film.Lba = eLba; film.Size = eSize; film.Path = full;
                            byLba[eLba] = film; order.Add(film);
                        }
                        film.RecordPos.Add(pos);
                    }
                }
            }
            using (SHA256 sha = SHA256.Create())
                foreach (Film film in order) film.Sha = Util.Hex(sha.ComputeHash(ReadAt(f, film.Lba * 2048, (int)film.Size)));
        }
        return order;
    }
    // All files of a CD into a folder (Joliet names when the CD has them). Files that are already there stay: the three
    // CDs share many files, and the script can continue after an interruption.
    public static int Extract(string iso, string dest) {
        int written = 0;
        using (FileStream f = new FileStream(iso, FileMode.Open, FileAccess.Read, FileShare.Read, 1 << 20)) {
            long rootLba = -1, rootSize = 0; bool joliet = false;
            for (int s = 16; s < 40; s++) {
                byte[] vd = ReadAt(f, s * 2048L, 2048);
                if (vd[1] != 'C' || vd[2] != 'D' || vd[3] != '0' || vd[4] != '0' || vd[5] != '1' || vd[0] == 255) break;
                bool jol = vd[0] == 2 && vd[88] == '%' && vd[89] == '/';
                if ((vd[0] == 1 && rootLba < 0) || jol) { rootLba = BitConverter.ToUInt32(vd, 156 + 2); rootSize = BitConverter.ToUInt32(vd, 156 + 10); joliet = jol; }
            }
            if (rootLba < 0) throw new Exception("FIX:" + iso + " is not a CD image.");
            Stack<object[]> stack = new Stack<object[]>();
            stack.Push(new object[] { rootLba, rootSize, dest });
            byte[] block = new byte[1 << 20];
            while (stack.Count > 0) {
                object[] top = stack.Pop();
                long lba = (long)top[0], size = (long)top[1]; string dir = (string)top[2];
                Directory.CreateDirectory(dir);
                byte[] data = ReadAt(f, lba * 2048, (int)size);
                int i = 0;
                while (i < data.Length) {
                    int ln = data[i];
                    if (ln == 0) { i = (i / 2048 + 1) * 2048; continue; }
                    byte[] rec = Util.Sub(data, i, ln);
                    i += ln;
                    int nl = rec[32];
                    if ((nl == 1 && (rec[33] == 0 || rec[33] == 1)) || (rec[25] & 4) != 0) continue;
                    string name = joliet ? Encoding.BigEndianUnicode.GetString(rec, 33, nl) : Encoding.GetEncoding(28591).GetString(rec, 33, nl);
                    int semi = name.IndexOf(';'); if (semi >= 0) name = name.Substring(0, semi);
                    name = name.TrimEnd('.');
                    long eLba = BitConverter.ToUInt32(rec, 2), eSize = BitConverter.ToUInt32(rec, 10);
                    string full = Path.Combine(dir, name);
                    if ((rec[25] & 2) != 0) { stack.Push(new object[] { eLba, eSize, full }); continue; }
                    if (File.Exists(full)) continue;
                    string part = full + ".part";
                    using (FileStream o = new FileStream(part, FileMode.Create, FileAccess.Write)) {
                        f.Position = eLba * 2048; long left = eSize;
                        while (left > 0) {
                            int k = f.Read(block, 0, (int)Math.Min(left, block.Length));
                            if (k <= 0) throw new Exception("FIX:" + iso + " ends too soon.");
                            o.Write(block, 0, k); left -= k;
                        }
                    }
                    File.Move(part, full);
                    written++;
                }
            }
        }
        return written;
    }
    public static byte[] ReadFilm(string iso, Film film) {
        using (FileStream f = new FileStream(iso, FileMode.Open, FileAccess.Read, FileShare.Read)) return ReadAt(f, film.Lba * 2048, (int)film.Size);
    }
    // The new film in the place of the original (the rest of the last sector filled with zeros) and the new size in
    // all directory records (ISO 9660 and Joliet; both byte orders).
    public static void Patch(FileStream f, Film film, byte[] data) {
        long space = (film.Size + 2047) / 2048 * 2048;
        if (data.Length > space) throw new Exception("FIX:The new film " + film.Path + " does not fit (" + data.Length + " > " + space + " bytes).");
        f.Position = film.Lba * 2048;
        f.Write(data, 0, data.Length);
        f.Write(new byte[space - data.Length], 0, (int)(space - data.Length));
        foreach (long pos in film.RecordPos) {
            f.Position = pos + 10;
            byte[] le = BitConverter.GetBytes((uint)data.Length);
            f.Write(le, 0, 4);
            f.WriteByte(le[3]); f.WriteByte(le[2]); f.WriteByte(le[1]); f.WriteByte(le[0]);
        }
    }
}

// ---------------------------------------------------------------------------------------------------------------
// QuickTime: rebuild the new film in the layout of the original (QuickTime 2.1 for Windows 3.1 does not open the MOV
// files that FFmpeg writes). The moov of the original is kept; only the video frames (stsz/stss/stco) change. The
// sound stays byte for byte the same and the chunks keep the order of the original.
// ---------------------------------------------------------------------------------------------------------------
public class Atom {
    public string T; public byte[] V; public List<Atom> K;
    public Atom(string t, byte[] v, List<Atom> k) { T = t; V = v; K = k; }
}

public static class Mov {
    static readonly HashSet<string> CONT = new HashSet<string>(new string[] { "moov", "trak", "mdia", "minf", "stbl", "edts", "dinf" });

    public static List<Atom> Parse(byte[] d, long o, long e) {
        List<Atom> r = new List<Atom>();
        while (o + 8 <= e) {
            long sz = Util.BE32(d, o);
            string t = Encoding.ASCII.GetString(d, (int)o + 4, 4);
            if (sz < 8 || o + sz > e) break;
            if (CONT.Contains(t)) r.Add(new Atom(t, null, Parse(d, o + 8, o + sz)));
            else r.Add(new Atom(t, Util.Sub(d, o + 8, sz - 8), null));
            o += sz;
        }
        return r;
    }
    static void SerTo(MemoryStream m, List<Atom> atoms) {
        foreach (Atom a in atoms) {
            byte[] body;
            if (a.K != null) { MemoryStream sub = new MemoryStream(); SerTo(sub, a.K); body = sub.ToArray(); } else body = a.V;
            Util.PutBE32(m, (uint)(body.Length + 8));
            byte[] t = Encoding.ASCII.GetBytes(a.T); m.Write(t, 0, 4);
            m.Write(body, 0, body.Length);
        }
    }
    public static byte[] Ser(List<Atom> atoms) { MemoryStream m = new MemoryStream(); SerTo(m, atoms); return m.ToArray(); }
    static Atom Kind(List<Atom> atoms, string t) {
        foreach (Atom a in atoms) if (a.T == t) return a;
        throw new Exception("atom " + t + " not found");
    }
    static void SetAtom(List<Atom> stbl, string t, byte[] body) {
        foreach (Atom a in stbl) if (a.T == t) { a.V = body; return; }
        throw new Exception("atom " + t + " not found");
    }
    // (handler type, stbl) per track
    static List<KeyValuePair<string, List<Atom>>> Tracks(List<Atom> moov) {
        List<KeyValuePair<string, List<Atom>>> r = new List<KeyValuePair<string, List<Atom>>>();
        foreach (Atom a in moov) {
            if (a.T != "trak") continue;
            List<Atom> mdia = Kind(a.K, "mdia").K;
            byte[] hd = Kind(mdia, "hdlr").V;
            r.Add(new KeyValuePair<string, List<Atom>>(Encoding.ASCII.GetString(hd, 8, 4), Kind(Kind(mdia, "minf").K, "stbl").K));
        }
        return r;
    }
    static byte[] Be32Table(uint first, uint second, List<uint> values) {
        MemoryStream m = new MemoryStream();
        Util.PutBE32(m, first); Util.PutBE32(m, second);
        foreach (uint v in values) Util.PutBE32(m, v);
        return m.ToArray();
    }
    static uint[] Stco(List<Atom> stbl) {
        byte[] s = Kind(stbl, "stco").V;
        uint n = Util.BE32(s, 4); uint[] r = new uint[n];
        for (int i = 0; i < n; i++) r[i] = Util.BE32(s, 8 + 4 * i);
        return r;
    }
    // sample sizes, and per chunk the sample numbers in it
    static void Samples(List<Atom> stbl, out List<uint> sizes, out List<List<int>> chunks) {
        byte[] stsz = Kind(stbl, "stsz").V;
        uint fixd = Util.BE32(stsz, 4), n = Util.BE32(stsz, 8);
        sizes = new List<uint>();
        for (int i = 0; i < n; i++) sizes.Add(fixd != 0 ? fixd : Util.BE32(stsz, 12 + 4 * i));
        uint[] offs = Stco(stbl);
        byte[] stsc = Kind(stbl, "stsc").V;
        uint ne = Util.BE32(stsc, 4);
        chunks = new List<List<int>>();
        int s = 0;
        for (int ci = 0; ci < offs.Length; ci++) {
            uint per = 0;
            for (int k = (int)ne - 1; k >= 0; k--) if (Util.BE32(stsc, 8 + 12 * k) <= ci + 1) { per = Util.BE32(stsc, 12 + 12 * k); break; }
            List<int> idx = new List<int>();
            for (int j = 0; j < per; j++) idx.Add(s + j);
            chunks.Add(idx);
            s += (int)per;
        }
    }

    public static byte[] Rebuild(byte[] d, byte[] f) {
        List<Atom> top = Parse(d, 0, d.Length);
        List<Atom> moov = Kind(top, "moov").K;
        List<Atom> beforeMdat = new List<Atom>();
        foreach (Atom a in top) if (a.T != "mdat") beforeMdat.Add(a);
        long origHead = Ser(beforeMdat).Length;      // before the tables change

        // the new video frames from the FFmpeg file
        List<Atom> fvst = null;
        foreach (KeyValuePair<string, List<Atom>> tr in Tracks(Kind(Parse(f, 0, f.Length), "moov").K)) if (tr.Key == "vide") { fvst = tr.Value; break; }
        if (fvst == null) throw new Exception("no video in the FFmpeg file");
        List<uint> fsizes; List<List<int>> fchunks;
        Samples(fvst, out fsizes, out fchunks);
        uint[] foffs = Stco(fvst);
        List<byte[]> frames = new List<byte[]>();
        for (int ci = 0; ci < fchunks.Count; ci++) {
            long o = foffs[ci];
            foreach (int i in fchunks[ci]) { frames.Add(Util.Sub(f, o, fsizes[i])); o += fsizes[i]; }
        }
        byte[] fstss = Kind(fvst, "stss").V;
        uint nk = Util.BE32(fstss, 4);
        List<uint> keys = new List<uint>();
        for (int i = 0; i < nk; i++) keys.Add(Util.BE32(fstss, 8 + 4 * i));

        // all chunks of the original (all tracks), in file order
        List<KeyValuePair<string, List<Atom>>> tracks = Tracks(moov);
        List<long[]> all = new List<long[]>();        // {offset, track, chunk}
        for (int tn = 0; tn < tracks.Count; tn++) {
            uint[] offs = Stco(tracks[tn].Value);
            for (int ci = 0; ci < offs.Length; ci++) all.Add(new long[] { offs[ci], tn, ci });
        }
        all.Sort(delegate (long[] a, long[] b) {
            int c = a[0].CompareTo(b[0]); if (c != 0) return c;
            c = a[1].CompareTo(b[1]); if (c != 0) return c;
            return a[2].CompareTo(b[2]);
        });
        long pos = 0, mdatEnd = d.Length; bool hasMdat = false, moovFirst = false, seenMoov = false;
        foreach (Atom a in top) {
            long sz = (a.K != null) ? Ser(new List<Atom> { a }).Length : a.V.Length + 8;
            if (a.T == "moov") seenMoov = true;
            if (a.T == "mdat") { hasMdat = true; mdatEnd = pos + sz; moovFirst = seenMoov; }
            pos += sz;
        }
        bool bare = !hasMdat;                          // some films: raw data right after the moov, without an mdat header
        List<long[]> chunks = new List<long[]>();      // {offset, track, chunk, length}
        for (int k = 0; k < all.Count; k++) {
            long next = k + 1 < all.Count ? all[k + 1][0] : mdatEnd;
            chunks.Add(new long[] { all[k][0], all[k][1], all[k][2], next - all[k][0] });
        }
        int vt = -1;
        for (int tn = 0; tn < tracks.Count; tn++) if (tracks[tn].Key == "vide") { vt = tn; break; }
        List<uint> vsizes; List<List<int>> vchunks;
        Samples(tracks[vt].Value, out vsizes, out vchunks);
        if (frames.Count != vsizes.Count) throw new Exception("number of frames differs: " + frames.Count + " new, " + vsizes.Count + " original");
        List<byte[]> newChunk = new List<byte[]>();
        foreach (List<int> idx in vchunks) {
            MemoryStream m = new MemoryStream();
            foreach (int i in idx) m.Write(frames[i], 0, frames[i].Length);
            newChunk.Add(m.ToArray());
        }
        List<Atom> vst = tracks[vt].Value;
        List<uint> fl = new List<uint>();
        foreach (byte[] fr in frames) fl.Add((uint)fr.Length);
        MemoryStream stsz = new MemoryStream();
        Util.PutBE32(stsz, 0); Util.PutBE32(stsz, 0); Util.PutBE32(stsz, (uint)frames.Count);
        foreach (uint v in fl) Util.PutBE32(stsz, v);
        SetAtom(vst, "stsz", stsz.ToArray());
        SetAtom(vst, "stss", Be32Table(0, (uint)keys.Count, keys));

        long head = Ser(beforeMdat).Length;
        long dataStart = head + (bare ? 0 : 8);
        MemoryStream body = new MemoryStream();
        if (bare) { byte[] gap = Util.Sub(d, origHead, all[0][0] - origHead); body.Write(gap, 0, gap.Length); }
        Dictionary<long, uint>[] newOffs = new Dictionary<long, uint>[tracks.Count];
        for (int tn = 0; tn < tracks.Count; tn++) newOffs[tn] = new Dictionary<long, uint>();
        foreach (long[] c in chunks) {
            newOffs[c[1]][c[2]] = (uint)(dataStart + body.Length);
            byte[] b = (c[1] == vt) ? newChunk[(int)c[2]] : Util.Sub(d, c[0], c[3]);
            body.Write(b, 0, b.Length);
        }
        for (int tn = 0; tn < tracks.Count; tn++) {
            List<uint> o = new List<uint>();
            for (int i = 0; i < newOffs[tn].Count; i++) o.Add(newOffs[tn][i]);
            SetAtom(tracks[tn].Value, "stco", Be32Table(0, (uint)o.Count, o));
        }
        byte[] head2 = Ser(beforeMdat);
        if (head2.Length != head) throw new Exception("moov size changed");
        MemoryStream outp = new MemoryStream();
        outp.Write(head2, 0, head2.Length);
        if (!bare) {
            if (!moovFirst) throw new Exception("mdat before moov");
            Util.PutBE32(outp, (uint)(body.Length + 8));
            outp.Write(Encoding.ASCII.GetBytes("mdat"), 0, 4);
        }
        body.Position = 0; body.CopyTo(outp);
        return outp.ToArray();
    }
}
}
'@

# ------------------------------------------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------------------------------------------
$script:LogFile = $null
$script:LogQueue = New-Object System.Collections.Generic.List[string]
function Say([string]$text, [string]$color = 'Gray') {
    Write-Host $text -ForegroundColor $color
    $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  ' + $text
    if ($script:LogFile) { try { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 } catch { } }
    else { $script:LogQueue.Add($line) }
}
function Start-Log([string]$path) {
    $script:LogFile = $path
    try { Add-Content -LiteralPath $path -Value ([string[]]$script:LogQueue) -Encoding UTF8 } catch { }
    $script:LogQueue.Clear()
}
function Step([string]$text) { Say ''; Say $text 'Cyan' }
function Ok([string]$text) { Say ('   OK: ' + $text) 'Green' }
function Info([string]$text) { Say ('   ' + $text) 'Gray' }
function Warn([string]$text) { Say ('   NOTE: ' + $text) 'Yellow' }
function Fail([string]$text) { throw ('FIX:' + $text) }
function Inner-Message($e) { $x = $e; while ($x.InnerException) { $x = $x.InnerException }; $x.Message }
function Ask([string]$prompt) {
    $a = Read-Host $prompt
    if ($null -eq $a) { Fail 'Nothing can be typed here: give the CDs with -Cd1, -Cd2 and -Cd3.' }
    $a.Trim().Trim('"').Trim("'")
}
function Mb([double]$bytes) { ($bytes / 1MB).ToString('N0', [Globalization.CultureInfo]::InvariantCulture) + ' MB' }

$SUBS = Join-Path $PSScriptRoot 'subtitles'

# The subtitles for a film on CD n: recognised by its fingerprint. A few films occur under several names with the same
# content but have their own subtitles; then the name on the CD decides.
function Pick-Clip([int]$n, $film) {
    if (-not $bySha.ContainsKey($film.Sha)) { return $null }
    $c = @($bySha[$film.Sha])
    if ($c.Count -gt 1) {
        $key = "CD$n\" + $film.Path
        foreach ($x in $c) { if ($x.paths -contains $key) { return $x } }
    }
    $c[0]
}
$FINAL_NAME = 'Blackout CD {0} (English subtitles).iso'
$FOLDER_NAME = 'Blackout CDs (English subtitles)'

# ------------------------------------------------------------------------------------------------------------------
# FFmpeg: the official build 9.0.2 "essentials" of gyan.dev (linked from ffmpeg.org). With exactly this version the
# films come out byte for byte the same as in the tested version.
# ------------------------------------------------------------------------------------------------------------------
$FF_URLS = @('https://www.gyan.dev/ffmpeg/builds/packages/ffmpeg-9.0.2-essentials_build.zip',
             'https://github.com/GyanD/codexffmpeg/releases/download/9.0.2/ffmpeg-9.0.2-essentials_build.zip')
$FF_ZIP_SHA = '60f467265b1e312373dbcd92200c2618a74850f98d3d078e94296bb3fa2047ba'
$FF_EXE_SHA = '3256173f3f8bffd7df12227c68adf68025edb1832273a9530688a7bb1ed8edec'

function Test-FFmpeg([string]$exe) {
    $ErrorActionPreference = 'Continue'   # (only here) output of FFmpeg on stderr is not an error
    $enc = & $exe -hide_banner -encoders 2>$null | Out-String
    $flt = & $exe -hide_banner -filters 2>$null | Out-String
    if ($enc -notmatch '\bcinepak\b') { Fail "$exe has no Cinepak encoder." }
    if ($flt -notmatch '\bsubtitles\b') { Fail "$exe has no 'subtitles' filter (libass). Use the official build from gyan.dev." }
    $v = (& $exe -hide_banner -version 2>$null | Select-Object -First 1)
    $v
}

function Get-FFmpeg {
    if ($script:FFmpeg) {
        $p = $script:FFmpeg.Trim().Trim('"')
        if (Test-Path -LiteralPath $p -PathType Container) { $p = Join-Path $p 'ffmpeg.exe' }
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { Fail "FFmpeg not found: $p" }
        return (Resolve-Path -LiteralPath $p).ProviderPath
    }
    $local = Join-Path $PSScriptRoot 'ffmpeg\ffmpeg.exe'
    if ((Test-Path -LiteralPath $local) -and ([BlackoutSubs.Util]::Sha256File($local) -eq $FF_EXE_SHA)) { return $local }
    Say ''
    Say 'This script needs FFmpeg (a free program for films) to draw the subtitles.' 'White'
    Say "  It can download the official build now: FFmpeg 9.0.2 'essentials' from gyan.dev (115 MB, GPL licence)." 'White'
    Say '  The download is checked with SHA-256; only ffmpeg.exe and its licence are kept, in the folder ffmpeg.' 'White'
    Say '  (Or close this window and start the script with -FFmpeg "<path to ffmpeg.exe>".)' 'White'
    $a = Ask 'Download FFmpeg now? (Y/N)'
    if ($a -notmatch '^(y|yes|j|ja)$') { Fail 'No FFmpeg. Start the script again with -FFmpeg "<path to ffmpeg.exe>", or let it download FFmpeg.' }
    $dir = Join-Path $PSScriptRoot 'ffmpeg'
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $zip = Join-Path $dir 'ffmpeg-9.0.2-essentials_build.zip'
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $done = $false
    foreach ($u in $FF_URLS) {
        try {
            Info "Downloading $u ..."
            (New-Object Net.WebClient).DownloadFile($u, $zip)
            $h = [BlackoutSubs.Util]::Sha256File($zip)
            if ($h -eq $FF_ZIP_SHA) { $done = $true; break }
            Warn "The download from $u has another fingerprint ($h); not used."
        } catch { Warn "Download from $u failed: $((Inner-Message $_.Exception))" }
    }
    if (-not $done) {
        if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
        Fail 'FFmpeg could not be downloaded. Download ffmpeg-9.0.2-essentials_build.zip yourself from https://www.gyan.dev/ffmpeg/builds/ and start the script with -FFmpeg "<path to bin\ffmpeg.exe>".'
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $z = [IO.Compression.ZipFile]::OpenRead($zip)
    try {
        foreach ($e in $z.Entries) {
            if ($e.FullName -eq 'ffmpeg-9.0.2-essentials_build/bin/ffmpeg.exe') { [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $local, $true) }
            if ($e.FullName -eq 'ffmpeg-9.0.2-essentials_build/LICENSE') { [IO.Compression.ZipFileExtensions]::ExtractToFile($e, (Join-Path $dir 'LICENSE.txt'), $true) }
        }
    } finally { $z.Dispose() }
    Remove-Item -LiteralPath $zip -Force
    if (-not (Test-Path -LiteralPath $local) -or [BlackoutSubs.Util]::Sha256File($local) -ne $FF_EXE_SHA) { Fail 'ffmpeg.exe from the download is not the expected file.' }
    Ok "FFmpeg 9.0.2 downloaded and checked: $local"
    $local
}

# ------------------------------------------------------------------------------------------------------------------
# CDs
# ------------------------------------------------------------------------------------------------------------------
function Open-Source([string]$c) {
    if ($c -match '^([A-Za-z])(:\\?)?$') {
        $letter = $Matches[1].ToUpper()
        $drive = [IO.DriveInfo]::GetDrives() | Where-Object { $_.Name -ieq ($letter + ':\') }
        if (-not $drive) { Fail "Drive $letter`: does not exist." }
        if (-not $drive.IsReady) { Fail "There is no CD in drive $letter`: (or Windows is still reading it; wait a moment and try again)." }
        return (New-Object BlackoutSubs.DriveSource $letter)
    }
    if (-not (Test-Path -LiteralPath $c -PathType Leaf)) { Fail "The file '$c' does not exist." }
    $c = (Resolve-Path -LiteralPath $c).ProviderPath
    $ext = [IO.Path]::GetExtension($c).ToLowerInvariant()
    if ($ext -eq '.cue') {
        $dir = Split-Path -Parent $c
        $file = $null; $mode = $null
        foreach ($r in [IO.File]::ReadAllLines($c, [Text.Encoding]::Default)) {
            if (-not $file -and ($r -match '^\s*FILE\s+"(.+)"\s+\S+\s*$' -or $r -match '^\s*FILE\s+(\S+)\s+\S+\s*$')) { $file = $Matches[1] }
            if (-not $mode -and $r -match '^\s*TRACK\s+\d+\s+(\S+)') { $mode = $Matches[1].ToUpper() }
        }
        if (-not $file) { Fail "No FILE line in '$c'." }
        $bin = if ([IO.Path]::IsPathRooted($file)) { $file } else { Join-Path $dir $file }
        if (-not (Test-Path -LiteralPath $bin -PathType Leaf)) {
            $same = [IO.Path]::ChangeExtension($c, '.bin')
            if (Test-Path -LiteralPath $same -PathType Leaf) { $bin = $same } else { Fail "The file '$bin' (named in the .cue file) does not exist." }
        }
        if ($mode -eq 'MODE1/2048') { return (New-Object BlackoutSubs.IsoSource $bin) }
        return (New-Object BlackoutSubs.BinSource $bin)
    }
    if ($ext -eq '.bin' -or $ext -eq '.img') {
        if ((Get-Item -LiteralPath $c).Length % 2352 -eq 0) { return (New-Object BlackoutSubs.BinSource $c) }
        return (New-Object BlackoutSubs.IsoSource $c)
    }
    if ($ext -eq '.iso') { return (New-Object BlackoutSubs.IsoSource $c) }
    Fail "'$c' is not an .iso, .cue or .bin file. (A .chd must first be converted with chdman: chdman extractcd -i x.chd -o x.cue)"
}

# For CD 2 and 3: the same path as CD 1 with another number (e.g. "...CD1...\Blackout CD 1.iso"), if it exists.
# The number is tried in the whole path, in the last two parts (folder + file) and in the file name only.
function Guess-Path([string]$first, [int]$n) {
    if (-not $first -or $first -match '^[A-Za-z](:\\?)?$' -or -not (Test-Path -LiteralPath $first -PathType Leaf)) { return $null }
    $first = (Resolve-Path -LiteralPath $first).ProviderPath
    $pattern = '(?i)(cd[ _-]?|disc[ _-]?|disk[ _-]?)1(?!\d)'
    $parts = $first.Split('\')
    foreach ($keep in @(0, ($parts.Count - 2), ($parts.Count - 1))) {
        if ($keep -lt 0) { continue }
        $head = ($parts[0..($keep - 1)] -join '\')
        if ($keep -eq 0) { $head = '' }
        $tail = ($parts[$keep..($parts.Count - 1)] -join '\')
        $t2 = [regex]::Replace($tail, $pattern, { param($m) $m.Groups[1].Value + $n })
        $g = if ($head) { $head + '\' + $t2 } else { $t2 }
        if ($g -ne $first -and (Test-Path -LiteralPath $g -PathType Leaf)) { return $g }
    }
    $null
}

function Choose-Output([string]$first) {
    if (-not $script:Output) {
        $def = if ($first -and (Test-Path -LiteralPath $first -PathType Leaf)) { Split-Path -Parent (Resolve-Path -LiteralPath $first).ProviderPath }
               else { Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Blackout' }
        Say ''
        Say 'In which folder should the new images and the CD folder go? (about 3 GB)' 'White'
        Say "  Press Enter for $def, or type another folder." 'White'
        $a = Ask 'Folder'
        $script:Output = if ($a) { $a } else { $def }
    }
    try { $d = [IO.Path]::GetFullPath($script:Output.Trim().Trim('"')).TrimEnd('\') } catch { Fail "'$($script:Output)' is not a valid folder." }
    if ($d -match '^[A-Za-z]:$') { $d += '\' }
    if (Test-Path -LiteralPath $d -PathType Leaf) { Fail "'$d' is a file, not a folder." }
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d | Out-Null }
    $d
}

# ------------------------------------------------------------------------------------------------------------------
# The three new images together as one folder: DOSBox then opens a real file for every sound, and that is how the
# sound subtitles know what is playing. The game only checks that BODATA\1DISK, 2DISK and 3DISK exist, so no CD swaps.
# ------------------------------------------------------------------------------------------------------------------
function Make-Folder([string]$outDir) {
    $folder = Join-Path $outDir $FOLDER_NAME
    foreach ($n in 1, 2, 3) {        # 23 files differ per CD: the version of the lowest CD stays (the tested folder)
        $iso = Join-Path $outDir ($FINAL_NAME -f $n)
        if (-not (Test-Path -LiteralPath $iso)) { Fail "$iso is missing." }
        $count = [BlackoutSubs.Iso]::Extract($iso, $folder)
        Ok "CD $n`: $count files"
    }
    foreach ($m in '1DISK', '2DISK', '3DISK') {
        if (-not (Test-Path -LiteralPath (Join-Path $folder "BODATA\$m"))) { Fail "BODATA\$m is missing in the folder: these are not the three CDs of Blackout." }
    }
    Ok "CD folder: $folder"
    Say ''
    Say 'Done! Two ways to play:' 'Green'
    Say '  A) Only the films with subtitles: use the three new images, for example in DOSBox:' 'White'
    Say '       imgmount D "Blackout CD 1 (English subtitles).iso" "Blackout CD 2 (English subtitles).iso" "Blackout CD 3 (English subtitles).iso" -t iso' 'White'
    Say '  B) Also text for the spoken moments without picture (recommended): use the folder, in your DOSBox settings:' 'White'
    Say "       mount D `"$folder`" -t cdrom -label BLACKOUT1" 'White'
    Say "     Double-click 'Start sound subtitles.bat', then start the game. No CD swaps are needed." 'White'
    Say "They are in $outDir. Your original CDs and images have not been changed." 'Green'
    Say 'The new images and the folder are for your own use only: do not share them or put them online.' 'DarkGray'
}

# ------------------------------------------------------------------------------------------------------------------
# Main program
# ------------------------------------------------------------------------------------------------------------------
$failed = $false
$work = $null
$tmpIsos = @()
$running = @()
try {
    $tStart = Get-Date
    Say "Blackout - English subtitles, version $VERSION" 'White'
    Say 'This script contains no game files: everything comes from your own CDs.' 'DarkGray'
    if (-not (Test-Path -LiteralPath (Join-Path $SUBS 'clips.json'))) {
        Fail "The folder 'subtitles' is missing next to this script. First extract the WHOLE zip file (right-click > Extract All) and then start 'Patch Blackout.bat' in the extracted folder."
    }
    Add-Type -TypeDefinition $CSharp -Language CSharp -ReferencedAssemblies System, System.Core
    $DATA = Get-Content -LiteralPath (Join-Path $SUBS 'clips.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $bySha = @{}; $byOutSha = @{}
    foreach ($c in $DATA.clips) {
        if (-not (Test-Path -LiteralPath (Join-Path $SUBS ($c.id + '.ass')))) { Fail "subtitles\$($c.id).ass is missing. Extract the whole zip file again." }
        if (-not $bySha.ContainsKey($c.sha)) { $bySha[$c.sha] = @() }
        $bySha[$c.sha] += $c; $byOutSha[$c.out_sha] = $c
    }
    Info "$($DATA.clips.Count) films with English subtitles known."
    if ($FolderOnly) {
        # for people who already made the three images with version 1.0
        if (-not $Output) { Fail 'Use -FolderOnly together with -Output "<folder with the three new images>".' }
        $outDir = (Resolve-Path -LiteralPath $Output).ProviderPath
        $free = (New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($outDir))).AvailableFreeSpace
        if ($free -lt 1.3GB) { Fail "Not enough free space: $(Mb $free) free, about 1,300 MB needed." }
        Step 'Make the CD folder for the sound subtitles'
        Make-Folder $outDir
        return
    }

    # --- step 1: FFmpeg ---
    Step 'Step 1 of 6: FFmpeg'
    $ff = Get-FFmpeg
    $ffVersion = Test-FFmpeg $ff
    Ok "$ffVersion"
    $exact = ([BlackoutSubs.Util]::Sha256File($ff) -eq $FF_EXE_SHA)
    if (-not $exact) { Warn 'This is not FFmpeg 9.0.2 from gyan.dev. That usually works, but the films will differ slightly from the tested version.' }

    # --- step 2: copy the CDs ---
    Step 'Step 2 of 6: copy your CDs to new images'
    $given = @($Cd1, $Cd2, $Cd3)
    $isoSha = @{}
    $outDir = $null
    for ($n = 1; $n -le 3; $n++) {
        $src = $null
        while (-not $src) {
            $c = $given[$n - 1]
            if (-not $c) {
                $guess = if ($n -gt 1) { Guess-Path $given[0] $n } else { $null }
                Say ''
                Say "Where is CD $n of Blackout?" 'White'
                Say "  - type the drive letter of your CD drive (e.g. E) and put CD $n in it, or" 'White'
                Say "  - drag the .iso, .cue or .bin file of CD $n into this window and press Enter." 'White'
                if ($guess) { Say "  Press Enter for $guess" 'White' }
                $c = Ask "CD $n"
                if (-not $c -and $guess) { $c = $guess }
                if (-not $c) { continue }
            }
            $given[$n - 1] = $c
            $s = Open-Source $c
            try {
                $vol = $s.VolumeId()
                $want = ($DATA.cds | Where-Object { $_.n -eq $n })
                if ($vol -ne $want.volume) {
                    $other = $DATA.cds | Where-Object { $_.volume -eq $vol }
                    $msg = if ($other) { "$($s.Name) is CD $($other.n) of Blackout, not CD $n." } else { "$($s.Name) is not a CD of Blackout (volume name '$vol')." }
                    if (-not ($Cd1 -or $Cd2 -or $Cd3)) { Warn "$msg Give CD $n."; $s.Dispose(); $given[$n - 1] = $null; continue }
                    Fail $msg
                }
                $src = $s
            } catch { $s.Dispose(); throw }
        }
        try {
            if (-not $outDir) {
                $outDir = Choose-Output $given[0]
                Start-Log (Join-Path $outDir 'blackout-english-subtitles.log')
                Info "Output folder: $outDir"
                $free = (New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($outDir))).AvailableFreeSpace
                if ($free -lt 3.6GB) { Fail "Not enough free space on $([IO.Path]::GetPathRoot($outDir)): $(Mb $free) free, about 3,600 MB needed. Choose another folder." }
                $work = Join-Path $outDir 'blackout-subtitles-work'
                if (-not (Test-Path -LiteralPath $work)) { New-Item -ItemType Directory -Path $work | Out-Null }
            }
            $sectors = $src.Sectors()
            $dst = Join-Path $outDir (($FINAL_NAME -f $n) + '.tmp')
            foreach ($k in 1..3) {
                $final = Join-Path $outDir ($FINAL_NAME -f $k)
                if ($c -notmatch '^[A-Za-z](:\\?)?$' -and (Test-Path -LiteralPath $c) -and ((Resolve-Path -LiteralPath $c).ProviderPath -ieq $final)) {
                    Fail "CD $n is one of the new images ($final). Give the original image."
                }
            }
            Info "CD $n`: $($src.Name) ($(Mb ($sectors * 2048)))"
            $cp = New-Object BlackoutSubs.Copier $src, $dst, $sectors
            $tmpIsos += $dst
            try {
                $last = Get-Date
                while ($cp.Step(4096)) {
                    if (((Get-Date) - $last).TotalSeconds -ge 2) { Write-Host ("`r   copying ... {0,3}%" -f [int](100 * $cp.Done / $sectors)) -NoNewline; $last = Get-Date }
                }
                $isoSha[$n] = $cp.Finish()
            } finally { $cp.Dispose() }
            Write-Host ("`r" + (' ' * 30) + "`r") -NoNewline
            $ref = ($DATA.cds | Where-Object { $_.n -eq $n })
            if ($isoSha[$n] -eq $ref.sha256) { Ok "CD $n copied; identical to the tested image." }
            else { Ok "CD $n copied (not exactly the same image as the tested one; the films are checked one by one)." }
        } finally { $src.Dispose() }
    }

    # --- step 3: recognise the films ---
    Step 'Step 3 of 6: recognise the films'
    $films = @{}
    $need = @{}
    for ($n = 1; $n -le 3; $n++) {
        $list = [BlackoutSubs.Iso]::Films($tmpIsos[$n - 1])
        $films[$n] = $list
        $known = 0; $already = 0
        foreach ($f in $list) {
            $clip = Pick-Clip $n $f
            if ($clip) { $known++; $need[$clip.id] = @{ Clip = $clip; Cd = $n; Film = $f } }
            elseif ($byOutSha.ContainsKey($f.Sha)) { $already++ }
        }
        if ($already -gt 0) { Fail "CD $n already has English subtitles ($already films). Give the original CD or image." }
        $ref = ($DATA.cds | Where-Object { $_.n -eq $n })
        Info "CD $n`: $($list.Count) QuickTime films, $known with speech that get subtitles (expected: $($ref.films))."
        if ($known -lt $ref.films) { Warn "On CD $n, $($ref.films - $known) films are not recognised (damaged image or another release); those stay without subtitles." }
    }
    if ($need.Count -eq 0) { Fail 'No known films found: this is not the Swedish release of Blackout.' }
    Ok "$($need.Count) different films get English subtitles."

    # --- step 4: subtitles into the films ---
    $nw = if ($Workers -gt 0) { $Workers } else { [Math]::Max(1, [Math]::Min(8, [Environment]::ProcessorCount - 1)) }
    Step "Step 4 of 6: draw the subtitles into the films ($($need.Count) films, $nw at a time)"
    Info 'This takes a while (about 30 to 90 minutes, depending on your computer). If it is interrupted, start the script'
    Info 'again with the same folders: films that are already done are not made again.'
    $QS = @($null, 4, 8, 16, 32, 64)
    $queue = New-Object System.Collections.Generic.Queue[object]
    $done = 0; $same = 0; $total = $need.Count
    foreach ($e in ($need.Values | Sort-Object { $_.Clip.id })) {
        $id = $e.Clip.id
        $res = Join-Path $work ($id + '.MOV')
        if ((Test-Path -LiteralPath $res) -and (Get-Item -LiteralPath $res).Length -le [Math]::Ceiling($e.Clip.size / 2048) * 2048) {
            $done++; if ([BlackoutSubs.Util]::Sha256File($res) -eq $e.Clip.out_sha) { $same++ }
            continue
        }
        $qi = if ($null -ne $e.Clip.q) { [Array]::IndexOf($QS, [int]$e.Clip.q) } else { 0 }; if ($qi -lt 0) { $qi = 0 }
        $queue.Enqueue(@{ E = $e; Qi = $qi })
    }
    if ($done -gt 0) { Info "$done films were already done the last time." }
    $t0 = Get-Date; $lastShown = Get-Date; $firstDone = ($queue.Count -eq 0)
    while ($queue.Count -gt 0 -or $running.Count -gt 0) {
        # the first film alone (FFmpeg then prepares its font list once), after that $nw at a time
        $limit = if ($firstDone) { $nw } else { 1 }
        while ($queue.Count -gt 0 -and $running.Count -lt $limit) {
            $job = $queue.Dequeue()
            $id = $job.E.Clip.id
            $orig = Join-Path $work ($id + '.orig.mov')
            if (-not (Test-Path -LiteralPath $orig)) { [IO.File]::WriteAllBytes($orig, [BlackoutSubs.Iso]::ReadFilm($tmpIsos[$job.E.Cd - 1], $job.E.Film)) }
            Copy-Item -LiteralPath (Join-Path $SUBS ($id + '.ass')) -Destination (Join-Path $work ($id + '.ass')) -Force
            $q = $QS[$job.Qi]
            $qArg = if ($null -ne $q) { " -q:v $q" } else { '' }
            # Cinepak works in blocks of 4x4: the originals store e.g. 293x240 as 296x240 (the header keeps 293)
            $arg = "-nostdin -hide_banner -v error -y -ignore_editlist 1 -i `"$id.orig.mov`" -vf `"subtitles=$id.ass,pad=ceil(iw/4)*4:ceil(ih/4)*4`" " +
                   "-an -c:v cinepak -g 12 -fps_mode passthrough -pix_fmt rgb24$qArg -f mov `"$id.ff.mov`""
            $p = Start-Process -FilePath $ff -ArgumentList $arg -WorkingDirectory $work -NoNewWindow -PassThru -RedirectStandardError (Join-Path $work ($id + '.err.txt'))
            $null = $p.Handle   # keeps the exit code available
            $job.P = $p
            $running += $job
        }
        Start-Sleep -Milliseconds 250
        $still = @()
        foreach ($job in $running) {
            if (-not $job.P.HasExited) { $still += $job; continue }
            $job.P.WaitForExit()
            $id = $job.E.Clip.id
            $ffOut = Join-Path $work ($id + '.ff.mov')
            $errFile = Join-Path $work ($id + '.err.txt')
            if ($job.P.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $ffOut)) {
                $err = if (Test-Path -LiteralPath $errFile) { (Get-Content -LiteralPath $errFile -Raw) } else { '' }
                Fail "FFmpeg could not make film $id (exit code $($job.P.ExitCode)): $err"
            }
            $space = [Math]::Ceiling($job.E.Clip.size / 2048) * 2048
            $movBytes = [BlackoutSubs.Mov]::Rebuild([IO.File]::ReadAllBytes((Join-Path $work ($id + '.orig.mov'))), [IO.File]::ReadAllBytes($ffOut))
            Remove-Item -LiteralPath $ffOut -Force
            if ($movBytes.Length -gt $space) {
                if ($job.Qi + 1 -ge $QS.Count) { Fail "Film $id does not fit in the space of the original, even at the lowest quality." }
                $job.Qi++; $job.Remove('P'); $queue.Enqueue($job)   # again, a little smaller
                continue
            }
            $res = Join-Path $work ($id + '.MOV')
            [IO.File]::WriteAllBytes($res + '.tmp', $movBytes)
            Move-Item -LiteralPath ($res + '.tmp') -Destination $res -Force
            foreach ($x in @('.orig.mov', '.ass', '.err.txt')) { $p2 = Join-Path $work ($id + $x); if (Test-Path -LiteralPath $p2) { Remove-Item -LiteralPath $p2 -Force } }
            $done++
            if ([BlackoutSubs.Util]::Sha256($movBytes) -eq $job.E.Clip.out_sha) { $same++ }
            $firstDone = $true
        }
        $running = $still
        if (((Get-Date) - $lastShown).TotalSeconds -ge 15 -or ($queue.Count -eq 0 -and $running.Count -eq 0)) {
            $lastShown = Get-Date
            $el = ((Get-Date) - $t0).TotalMinutes
            Info ("{0} of {1} films done ({2:N0} min)" -f $done, $total, $el)
        }
    }
    Ok "$total films with subtitles; $same of them byte for byte the same as in the tested version."

    # --- step 5: put the films on the copies ---
    Step 'Step 5 of 6: put the films on the new images and check them'
    for ($n = 1; $n -le 3; $n++) {
        $iso = $tmpIsos[$n - 1]
        $fs = New-Object IO.FileStream $iso, 'Open', 'ReadWrite', 'None'
        $count = 0
        try {
            foreach ($f in $films[$n]) {
                $clip = Pick-Clip $n $f
                if (-not $clip) { continue }
                $movBytes = [IO.File]::ReadAllBytes((Join-Path $work ($clip.id + '.MOV')))
                [BlackoutSubs.Iso]::Patch($fs, $f, $movBytes)
                $count++
            }
            $fs.Flush($true)
        } finally { $fs.Dispose() }
        # check: every film on the copy is now the new one
        $check = [BlackoutSubs.Iso]::Films($iso)
        $wrong = 0
        foreach ($f in $check) { if ($bySha.ContainsKey($f.Sha)) { $wrong++ } }
        if ($wrong) { Fail "Check failed: $wrong films on CD $n are still the original." }
        $final = Join-Path $outDir ($FINAL_NAME -f $n)
        if (Test-Path -LiteralPath $final) { Remove-Item -LiteralPath $final -Force }
        Move-Item -LiteralPath $iso -Destination $final
        $tmpIsos[$n - 1] = $final
        $ref = ($DATA.cds | Where-Object { $_.n -eq $n })
        $msg = "CD $n`: $count films with subtitles -> $final"
        if ($isoSha[$n] -eq $ref.sha256 -and $exact) {
            if ([BlackoutSubs.Util]::Sha256File($final) -eq $ref.sha256_english) { $msg += ' (identical to the tested version)' }
            else { Warn "CD $n differs from the tested version, although the CD and FFmpeg are the same." }
        }
        Ok $msg
    }
    $tmpIsos = @()
    if (-not $KeepWork) { Remove-Item -LiteralPath $work -Recurse -Force; $work = $null }

    # --- step 6: the CD folder for the sound subtitles ---
    Step 'Step 6 of 6: make the CD folder for the sound subtitles'
    Say ''
    Info ("Images done in {0:N0} minute(s)." -f ((Get-Date) - $tStart).TotalMinutes)
    Make-Folder $outDir
}
catch {
    $failed = $true
    Say ''
    $m = Inner-Message $_.Exception
    if ($m.StartsWith('FIX:')) { Say ('ERROR: ' + $m.Substring(4)) 'Red' }
    else {
        Say ('UNEXPECTED ERROR: ' + $m) 'Red'
        Say ('(line ' + $_.InvocationInfo.ScriptLineNumber + ': ' + $_.InvocationInfo.Line.Trim() + ')') 'DarkGray'
    }
    foreach ($job in $running) { try { if (-not $job.P.HasExited) { $job.P.Kill() } } catch { } }
    foreach ($t in $tmpIsos) { if ($t -like '*.tmp' -and (Test-Path -LiteralPath $t)) { try { Remove-Item -LiteralPath $t -Force } catch { } } }
    if ($work -and (Test-Path -LiteralPath $work)) { Say 'Films that were already done stay in the work folder; start the script again to continue.' 'Yellow' }
    Say 'Your original CDs and images have not been changed. Solve the problem and start the script again.' 'Gray'
}
finally {
    if (-not $NoWait) { Say ''; [void](Read-Host 'Press Enter to close this window') }
}
if ($failed) { exit 1 }
