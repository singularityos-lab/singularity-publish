using Singularity.Apps.Publish;

class TNode {
    public string name;
    public int type;
    public uint8[] data = {};
    public Gee.ArrayList<TNode> children = new Gee.ArrayList<TNode> ();
    public uint32 start = 0xFFFFFFFEU;
    public int id = 0;

    public TNode (string name, int type) {
        this.name = name;
        this.type = type;
    }
}

class CfbWriter {
    public const uint32 FREE = 0xFFFFFFFFU;
    public const uint32 END = 0xFFFFFFFEU;
    public int ss;
    public TNode root = new TNode ("Root Entry", 5);
    public Gee.HashMap<string, uint32> starts = new Gee.HashMap<string, uint32> ();
    public int fat_sectors = 0;
    public int difat_sectors = 0;

    public CfbWriter (int sector_size = 512) {
        ss = sector_size;
    }

    public void add (string path, uint8[] data) {
        string[] parts = path.split ("/");
        var cur = root;
        for (int i = 0; i < parts.length; i++) {
            bool last = i == parts.length - 1;
            TNode? found = null;
            foreach (var c in cur.children) if (c.name == parts[i]) found = c;
            if (found == null) {
                found = new TNode (parts[i], last ? 2 : 1);
                cur.children.add (found);
            }
            if (last) found.data = data;
            cur = found;
        }
    }

    private void flatten (TNode n, Gee.ArrayList<TNode> list, string prefix, Gee.HashMap<TNode, string> paths) {
        n.id = list.size;
        list.add (n);
        foreach (var c in n.children) {
            string p = prefix == "" ? c.name : prefix + "/" + c.name;
            paths[c] = p;
            flatten (c, list, p, paths);
        }
    }

    private static void w16 (uint8[] b, int o, uint v) {
        b[o] = (uint8) (v & 0xFF);
        b[o + 1] = (uint8) ((v >> 8) & 0xFF);
    }

    private static void w32 (uint8[] b, int o, uint32 v) {
        for (int i = 0; i < 4; i++) b[o + i] = (uint8) ((v >> (8 * i)) & 0xFF);
    }

    private static int ceil_div (int a, int b) {
        return (a + b - 1) / b;
    }

    public uint8[] build () {
        var nodes = new Gee.ArrayList<TNode> ();
        var paths = new Gee.HashMap<TNode, string> ();
        flatten (root, nodes, "", paths);
        var mini = new ByteArray ();
        var minifat = new Gee.ArrayList<uint32> ();
        var big = new Gee.ArrayList<TNode> ();
        foreach (var n in nodes) {
            if (n.type != 2) continue;
            if (n.data.length == 0) {
                n.start = END;
                continue;
            }
            if (n.data.length < 4096) {
                int cnt = ceil_div (n.data.length, 64);
                uint32 st = minifat.size;
                for (int k = 0; k < cnt; k++) minifat.add (k < cnt - 1 ? st + k + 1 : END);
                mini.append (n.data);
                int pad = cnt * 64 - n.data.length;
                if (pad > 0) mini.append (new uint8[pad]);
                n.start = st;
            } else {
                big.add (n);
            }
        }
        int epp = ss / 4;
        int dir_s = ceil_div (nodes.size * 128, ss);
        int mf_s = ceil_div (minifat.size * 4, ss);
        int ms_s = ceil_div ((int) mini.len, ss);
        int content = dir_s + mf_s + ms_s;
        foreach (var n in big) content += ceil_div (n.data.length, ss);
        int f = 1, d = 0;
        for (int it = 0; it < 50; it++) {
            int total = content + f + d;
            int nf = ceil_div (total, epp);
            int nd = nf > 109 ? ceil_div (nf - 109, epp - 1) : 0;
            if (nf == f && nd == d) break;
            f = nf;
            d = nd;
        }
        fat_sectors = f;
        difat_sectors = d;
        int total = content + f + d;
        var fat = new uint32[f * epp];
        for (int i = 0; i < fat.length; i++) fat[i] = FREE;
        for (int i = 0; i < f; i++) fat[i] = 0xFFFFFFFDU;
        for (int i = 0; i < d; i++) fat[f + i] = 0xFFFFFFFCU;
        int next = f + d;
        var sectors = new uint8[total * ss];
        uint32 dir_start = next;
        for (int k = 0; k < dir_s; k++) fat[next + k] = k < dir_s - 1 ? next + k + 1 : END;
        next += dir_s;
        uint32 mf_start = mf_s > 0 ? next : END;
        for (int k = 0; k < mf_s; k++) fat[next + k] = k < mf_s - 1 ? next + k + 1 : END;
        var mfb = new uint8[mf_s * ss];
        for (int i = 0; i < mfb.length / 4; i++) w32 (mfb, i * 4, i < minifat.size ? minifat[i] : FREE);
        if (mfb.length > 0) Memory.copy (&sectors[next * ss], mfb, mfb.length);
        next += mf_s;
        root.start = ms_s > 0 ? next : END;
        for (int k = 0; k < ms_s; k++) fat[next + k] = k < ms_s - 1 ? next + k + 1 : END;
        if (mini.len > 0) Memory.copy (&sectors[next * ss], mini.data, mini.len);
        next += ms_s;
        foreach (var n in big) {
            int cnt = ceil_div (n.data.length, ss);
            n.start = next;
            for (int k = 0; k < cnt; k++) fat[next + k] = k < cnt - 1 ? next + k + 1 : END;
            Memory.copy (&sectors[next * ss], n.data, n.data.length);
            next += cnt;
        }
        foreach (var n in nodes) if (n != root && n.type == 2) starts[paths[n]] = n.start;
        var dir = new uint8[dir_s * ss];
        for (int i = 0; i < dir_s * ss / 128; i++) {
            int o = i * 128;
            if (i >= nodes.size) {
                w32 (dir, o + 68, FREE);
                w32 (dir, o + 72, FREE);
                w32 (dir, o + 76, FREE);
                continue;
            }
            var n = nodes[i];
            int ci = 0;
            unichar c;
            int bi = 0;
            while (n.name.get_next_char (ref bi, out c) && ci < 31) {
                w16 (dir, o + ci * 2, (uint) c);
                ci++;
            }
            w16 (dir, o + 64, (ci + 1) * 2);
            dir[o + 66] = (uint8) n.type;
            dir[o + 67] = 1;
            w32 (dir, o + 68, FREE);
            uint32 right = FREE;
            TNode? parent = null;
            foreach (var p in nodes) if (p.children.contains (n)) parent = p;
            if (parent != null) {
                int idx = parent.children.index_of (n);
                if (idx + 1 < parent.children.size) right = parent.children[idx + 1].id;
            }
            w32 (dir, o + 72, right);
            w32 (dir, o + 76, n.children.size > 0 ? n.children[0].id : FREE);
            if (n == root) {
                w32 (dir, o + 116, root.start);
                w32 (dir, o + 120, (uint32) mini.len);
            } else if (n.type == 2) {
                w32 (dir, o + 116, n.start);
                w32 (dir, o + 120, (uint32) n.data.length);
            } else {
                w32 (dir, o + 116, 0);
            }
        }
        Memory.copy (&sectors[dir_start * ss], dir, dir.length);
        for (int i = 0; i < f; i++) {
            for (int k = 0; k < epp; k++) w32 (sectors, i * ss + k * 4, fat[i * epp + k]);
        }
        for (int i = 0; i < d; i++) {
            int base_s = f + i;
            for (int k = 0; k < epp - 1; k++) {
                int fi = 109 + i * (epp - 1) + k;
                w32 (sectors, base_s * ss + k * 4, fi < f ? (uint32) fi : FREE);
            }
            w32 (sectors, base_s * ss + (epp - 1) * 4, i < d - 1 ? (uint32) (base_s + 1) : END);
        }
        var header = new uint8[ss];
        uint8[] sig = { 0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1 };
        for (int i = 0; i < 8; i++) header[i] = sig[i];
        w16 (header, 0x18, 0x3E);
        w16 (header, 0x1A, ss == 4096 ? 4 : 3);
        w16 (header, 0x1C, 0xFFFE);
        w16 (header, 0x1E, ss == 4096 ? 12 : 9);
        w16 (header, 0x20, 6);
        w32 (header, 0x28, ss == 4096 ? (uint32) dir_s : 0);
        w32 (header, 0x2C, f);
        w32 (header, 0x30, dir_start);
        w32 (header, 0x38, 4096);
        w32 (header, 0x3C, mf_start);
        w32 (header, 0x40, mf_s);
        w32 (header, 0x44, d > 0 ? (uint32) f : END);
        w32 (header, 0x48, d);
        for (int i = 0; i < 109; i++) w32 (header, 0x4C + i * 4, i < f ? (uint32) i : FREE);
        var outb = new ByteArray ();
        outb.append (header);
        outb.append (sectors);
        return outb.steal ();
    }
}

uint8[] pattern (int n, int seed) {
    var d = new uint8[n];
    for (int i = 0; i < n; i++) d[i] = (uint8) ((i * 31 + seed * 7 + (i >> 8)) & 0xFF);
    return d;
}

bool same (uint8[] a, uint8[] b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) if (a[i] != b[i]) return false;
    return true;
}

void roundtrip (int ss) throws Error {
    var w = new CfbWriter (ss);
    int[] sizes = { 0, 1, 63, 64, 65, 4095, 4096, 5000, 70000 };
    foreach (int s in sizes) w.add ("Data/s%d".printf (s), pattern (s, s));
    w.add ("Top", pattern (100, 3));
    var cf = new CompoundFile (w.build ());
    assert (cf.sector_size == ss);
    foreach (int s in sizes) {
        string p = "Data/s%d".printf (s);
        assert (cf.has (p));
        assert (same (cf.read (p), pattern (s, s)));
    }
    assert (same (cf.read ("top"), pattern (100, 3)));
    assert (cf.streams ().size == sizes.length + 1);
}

void test_roundtrip_512 () {
    try {
        roundtrip (512);
    } catch (Error e) {
        error (e.message);
    }
}

void test_roundtrip_4096 () {
    try {
        roundtrip (4096);
    } catch (Error e) {
        error (e.message);
    }
}

void test_empty_and_exact () {
    try {
        var w = new CfbWriter ();
        w.add ("Empty", new uint8[0]);
        w.add ("Exact", pattern (4096, 9));
        w.add ("Below", pattern (4095, 2));
        var cf = new CompoundFile (w.build ());
        assert (cf.read ("Empty").length == 0);
        assert (same (cf.read ("Exact"), pattern (4096, 9)));
        assert (same (cf.read ("Below"), pattern (4095, 2)));
        assert (cf.entry ("Exact").start != 0xFFFFFFFEU);
    } catch (Error e) {
        error (e.message);
    }
}

void test_deep_tree () {
    try {
        var w = new CfbWriter ();
        string p = "";
        for (int i = 0; i < 20; i++) p += "Level%d/".printf (i);
        w.add (p + "Leaf", pattern (300, 5));
        for (int i = 0; i < 12; i++) w.add ("Wide/Child%02d".printf (i), pattern (10 + i, i));
        var cf = new CompoundFile (w.build ());
        assert (same (cf.read (p + "Leaf"), pattern (300, 5)));
        for (int i = 0; i < 12; i++) assert (same (cf.read ("Wide/Child%02d".printf (i)), pattern (10 + i, i)));
        assert (cf.entry ("Level0/Level1").type == 1);
    } catch (Error e) {
        error (e.message);
    }
}

void test_many_fat_sectors () {
    try {
        var w = new CfbWriter ();
        w.add ("Big", pattern (300000, 1));
        w.add ("Small", pattern (10, 1));
        var data = w.build ();
        assert (w.fat_sectors > 1 && w.difat_sectors == 0);
        var cf = new CompoundFile (data);
        assert (same (cf.read ("Big"), pattern (300000, 1)));
    } catch (Error e) {
        error (e.message);
    }
}

void test_difat () {
    try {
        var w = new CfbWriter ();
        w.add ("Huge", pattern (7400000, 4));
        var data = w.build ();
        assert (w.difat_sectors > 0);
        var cf = new CompoundFile (data);
        assert (same (cf.read ("Huge"), pattern (7400000, 4)));
    } catch (Error e) {
        error (e.message);
    }
}

void test_invalid_signature () {
    var d = pattern (2048, 1);
    bool failed = false;
    try {
        new CompoundFile (d);
    } catch (Error e) {
        failed = true;
    }
    assert (failed);
    assert (!CompoundFile.is_cfb (d));
}

void test_truncated () {
    var w = new CfbWriter ();
    w.add ("Big", pattern (20000, 1));
    var d = w.build ();
    bool failed = false;
    try {
        var cf = new CompoundFile (d[0:d.length / 2]);
        cf.read ("Big");
    } catch (Error e) {
        failed = true;
    }
    assert (failed);
    failed = false;
    try {
        new CompoundFile (d[0:300]);
    } catch (Error e) {
        failed = true;
    }
    assert (failed);
}

void test_cycle () {
    var w = new CfbWriter ();
    w.add ("Big", pattern (5000, 1));
    var d = w.build ();
    uint32 s = w.starts["Big"];
    int epp = 128;
    int off = (int) ((s / epp + 1) * 512 + (s % epp) * 4);
    d[off] = (uint8) (s & 0xFF);
    d[off + 1] = (uint8) ((s >> 8) & 0xFF);
    d[off + 2] = 0;
    d[off + 3] = 0;
    bool failed = false;
    string msg = "";
    try {
        var cf = new CompoundFile (d);
        cf.read ("Big");
    } catch (Error e) {
        failed = true;
        msg = e.message;
    }
    assert (failed);
    assert (msg.contains ("loop"));
}

uint8[] image_bytes (string fmt) {
    var pb = new Gdk.Pixbuf (Gdk.Colorspace.RGB, false, 8, 6, 4);
    pb.fill ((uint32) 0x3366ccff);
    uint8[] buf;
    try {
        pb.save_to_buffer (out buf, fmt);
    } catch (Error e) {
        error (e.message);
    }
    return buf;
}

uint8[] utf16 (string s) {
    var b = new ByteArray ();
    unichar c;
    int i = 0;
    while (s.get_next_char (ref i, out c)) {
        uint16 u = (uint16) c;
        b.append ({ (uint8) (u & 0xFF), (uint8) (u >> 8) });
    }
    return b.steal ();
}

void put32 (ByteArray b, uint32 v) {
    b.append ({ (uint8) (v & 0xFF), (uint8) ((v >> 8) & 0xFF), (uint8) ((v >> 16) & 0xFF), (uint8) (v >> 24) });
}

void put16 (ByteArray b, uint v) {
    b.append ({ (uint8) (v & 0xFF), (uint8) ((v >> 8) & 0xFF) });
}

uint8[] contents (string text, int[] story_lengths) {
    var txt = utf16 (text);
    var tcd = new ByteArray ();
    put32 (tcd, story_lengths.length);
    put32 (tcd, 0);
    foreach (int l in story_lengths) put32 (tcd, 0);
    foreach (int l in story_lengths) put32 (tcd, l);
    var stsh = pattern (40, 2);
    string[] names = { "TEXT", "STSH", "TCD " };
    var blobs = new Gee.ArrayList<Bytes> ();
    blobs.add (new Bytes (txt));
    blobs.add (new Bytes (stsh));
    blobs.add (new Bytes (tcd.data));
    int nchunks = names.length;
    int data_off = 0x20 + nchunks * 24;
    var b = new ByteArray ();
    b.append ("CHNKINK ".data);
    b.append (new uint8[0x1A - 8]);
    put16 (b, nchunks);
    b.append (new uint8[0x20 - 0x1C]);
    int off = data_off;
    for (int i = 0; i < nchunks; i++) {
        put16 (b, 0x18);
        b.append (names[i].data);
        put16 (b, 0);
        put16 (b, i + 1);
        put32 (b, 0);
        put32 (b, off);
        put32 (b, (uint32) blobs[i].length);
        put16 (b, 0);
        off += (int) blobs[i].length;
    }
    for (int i = 0; i < nchunks; i++) b.append (blobs[i].get_data ());
    return b.steal ();
}

uint8[] blip (uint type, uint inst, uint8[] payload) {
    var b = new ByteArray ();
    put16 (b, inst << 4);
    put16 (b, type);
    int header = (inst & 1) == 1 ? 33 : 17;
    put32 (b, header + payload.length);
    b.append (new uint8[header]);
    b.append (payload);
    return b.steal ();
}

uint8[] dib () {
    var b = new ByteArray ();
    put32 (b, 40);
    put32 (b, 2);
    put32 (b, 2);
    put16 (b, 1);
    put16 (b, 24);
    put32 (b, 0);
    put32 (b, 16);
    put32 (b, 2835);
    put32 (b, 2835);
    put32 (b, 0);
    put32 (b, 0);
    for (int r = 0; r < 2; r++) {
        b.append ({ 255, 0, 0, 0, 255, 0, 0, 0 });
    }
    return b.steal ();
}

uint8[] escher_store (uint8[] embedded) {
    var fbse1 = new ByteArray ();
    put16 (fbse1, 0x2 | (6 << 4));
    put16 (fbse1, 0xF007);
    put32 (fbse1, 36);
    fbse1.append (new uint8[36]);
    var fbse2 = new ByteArray ();
    put16 (fbse2, 0x2 | (6 << 4));
    put16 (fbse2, 0xF007);
    put32 (fbse2, 36 + embedded.length);
    fbse2.append (new uint8[36]);
    fbse2.append (embedded);
    var b = new ByteArray ();
    put16 (b, 0xF | (2 << 4));
    put16 (b, 0xF001);
    put32 (b, fbse1.len + fbse2.len);
    b.append (fbse1.data);
    b.append (fbse2.data);
    return b.steal ();
}

uint8[] publisher_file (string text, int[] lengths, bool with_images = true, bool broken_text = false) {
    var w = new CfbWriter ();
    w.add ("Contents", pattern (700, 8));
    w.add ("Quill/QuillSub/CONTENTS", broken_text ? pattern (500, 1) : contents (text, lengths));
    w.add ("Envelope", pattern (30, 2));
    if (with_images) {
        var delay = new ByteArray ();
        delay.append (blip (0xF01E, 0x6E0, image_bytes ("png")));
        delay.append (blip (0xF01D, 0x46A, image_bytes ("jpeg")));
        delay.append (blip (0xF01A, 0x3D4, pattern (60, 1)));
        delay.append (blip (0xF01E, 0x6E0, image_bytes ("png")));
        w.add ("Escher/EscherDelayStm", delay.data);
        w.add ("Escher/EscherStm", escher_store (blip (0xF01F, 0x7A8, dib ())));
    }
    return w.build ();
}

void test_pub_import () {
    string s1 = "Spring Newsletter\rWelcome to our $5 sale.\tNow\vnext line\r";
    string s2 = "Second story\rMore text here";
    int[] lens = { s1.char_count (), s2.char_count () };
    try {
        var r = new PubReader ();
        var pub = r.read (publisher_file (s1 + s2, lens));
        assert (r.stories.size == 2);
        assert (r.stories[0].has_prefix ("Spring Newsletter\nWelcome"));
        assert (r.stories[0].contains ("\tNow\u2028next line"));
        assert (r.stories[1] == "Second story\nMore text here");
        assert (r.images.size == 3);
        assert (r.letter);
        assert (Math.fabs (pub.settings.width - 612) < 0.1);
        assert (r.notes ().contains ("Publisher layout, fonts and positions are not read"));
        assert (r.notes ().contains ("metafile"));
        assert (pub.stories.size == 2);
        int frames = 0, imgs = 0;
        foreach (var ref_item in pub.all_items ()) {
            if (ref_item.item is TextFrame) frames++;
            if (ref_item.item is ImageFrame) imgs++;
        }
        assert (frames == 2 && imgs == 3);
        assert (pub.media.size == 3);
        foreach (var m in pub.media.values) assert (ImageStore.decode (m.get_data ()) != null);
        var cache = new LayoutCache (pub);
        foreach (var st in pub.stories.values) assert (!cache.story (st.id).overset);
        string note;
        var p2 = Document.load_bytes (publisher_file (s1 + s2, lens), "x.pub", out note);
        assert (p2.pages.size == pub.pages.size);
        assert (note.contains ("reflowed"));
    } catch (Error e) {
        error (e.message);
    }
}

void test_pub_long_text () {
    var sb = new StringBuilder ();
    for (int i = 0; i < 80; i++) sb.append ("Paragraph %d of a long Publisher story about gardens, trains and the price of € tickets in the old town square.\r".printf (i));
    try {
        var r = new PubReader ();
        var pub = r.read (publisher_file (sb.str, { sb.str.char_count () }, false));
        assert (!r.letter);
        assert (Math.fabs (pub.settings.width - 210 * Units.PT_PER_MM) < 0.1);
        assert (pub.stories.size == 1);
        var st = pub.stories.values.to_array ()[0];
        assert (st.paras.size == 80);
        assert (st.frames.size > 1);
        assert (pub.pages.size == st.frames.size);
        var cache = new LayoutCache (pub);
        assert (!cache.story (st.id).overset);
    } catch (Error e) {
        error (e.message);
    }
}

void test_pub_broken_text () {
    try {
        var r = new PubReader ();
        var pub = r.read (publisher_file ("", { 0 }, true, true));
        assert (r.stories.size == 0);
        assert (r.images.size == 3);
        assert (r.notes ().contains ("not recognised"));
        assert (pub.pages.size == 1);
    } catch (Error e) {
        error (e.message);
    }
    bool failed = false;
    try {
        new PubReader ().read (publisher_file ("", { 0 }, false, true));
    } catch (Error e) {
        failed = true;
    }
    assert (failed);
}

void test_not_publisher () {
    var w = new CfbWriter ();
    w.add ("WordDocument", pattern (900, 1));
    bool failed = false;
    try {
        new PubReader ().read (w.build ());
    } catch (Error e) {
        failed = true;
        assert (e.message.contains ("Publisher"));
    }
    assert (failed);
    assert (FileKind.sniff (w.build ()) == FileKind.PUB);
}

void test_helpers () {
    var bmp = PubReader.dib_to_bmp (dib ());
    assert (bmp[0] == 'B' && bmp[1] == 'M');
    assert (bmp[10] == 54);
    assert (PubReader.dib_to_bmp (new uint8[10]).length == 0);
    assert (PubReader.clean ("a\rb\x01" + "c\r\r") == "a\nbc");
    assert (PubReader.decode_utf16 (utf16 ("Hé"), 0, 4) == "Hé");
    uint8[] sur = { 0x3D, 0xD8, 0x00, 0xDE };
    assert (PubReader.decode_utf16 (sur, 0, 4) == "\xf0\x9f\x98\x80");
    bool failed = false;
    try {
        PubReader.parse_chunks (pattern (100, 1));
    } catch (Error e) {
        failed = true;
    }
    assert (failed);
    var c = contents ("abc", { 3 });
    c[0x1A] = 200;
    try {
        var chunks = PubReader.parse_chunks (c);
        assert (chunks.size >= 3);
    } catch (Error e) {
        error (e.message);
    }
}

uint8[] pblk (int id, int type, uint32 v) {
    var b = new ByteArray ();
    b.append ({ (uint8) id, (uint8) type });
    int l = Singularity.Apps.Publish.PubLayout.block_length (type);
    if (l == 2) put16 (b, v);
    else if (l == 4) put32 (b, v);
    return b.steal ();
}

uint8[] pcont (int id, uint8[] body, int type = 0x88) {
    var b = new ByteArray ();
    b.append ({ (uint8) id, (uint8) type });
    put32 (b, body.length + 4);
    b.append (body);
    return b.steal ();
}

uint8[] pcat (uint8[] a, uint8[] b) {
    var r = new ByteArray ();
    r.append (a);
    r.append (b);
    return r.steal ();
}

uint8[] pchunk (uint8[] body) {
    var b = new ByteArray ();
    put32 (b, body.length + 4);
    b.append (body);
    return b.steal ();
}

class ContentsBuilder {
    public Gee.ArrayList<Bytes> chunks = new Gee.ArrayList<Bytes> ();
    public Gee.ArrayList<int> types = new Gee.ArrayList<int> ();

    public int add (int type, uint8[] body) {
        chunks.add (new Bytes (pchunk (body)));
        types.add (type);
        return chunks.size - 1;
    }

    public uint8[] build () {
        var b = new ByteArray ();
        b.append (new uint8[0x20]);
        var offsets = new Gee.ArrayList<int> ();
        foreach (var c in chunks) {
            offsets.add ((int) b.len);
            b.append (c.get_data ());
        }
        var dir = new ByteArray ();
        put32 (dir, 0);
        for (int i = 0; i < chunks.size; i++) {
            var e = new ByteArray ();
            e.append (pblk (0x02, 0x68, types[i]));
            e.append (pblk (0x04, 0x68, offsets[i]));
            e.append (pblk (0x05, 0x68, 0));
            dir.append (pcont (0, e.data));
        }
        uint32 trailer = b.len;
        var t = new ByteArray ();
        t.append ({ 0, 0x90 });
        put32 (t, dir.len);
        t.append (dir.data[4:dir.len]);
        t.append (pblk (0, 0x78, 0));
        t.append (pblk (0, 0x78, 0));
        put32 (b, t.len + 4);
        b.append (t.data);
        b.data[0x1A] = (uint8) (trailer & 0xFF);
        b.data[0x1B] = (uint8) ((trailer >> 8) & 0xFF);
        b.data[0x1C] = (uint8) ((trailer >> 16) & 0xFF);
        b.data[0x1D] = (uint8) (trailer >> 24);
        return b.steal ();
    }
}

uint8[] qstyle (uint8[] blocks) {
    var b = new ByteArray ();
    put32 (b, blocks.length + 4);
    b.append (blocks);
    return b.steal ();
}

uint8[] quill_fdp (int text_off, int[] ends, Gee.ArrayList<Bytes> styles) {
    var b = new ByteArray ();
    put16 (b, ends.length);
    b.append (new uint8[6]);
    foreach (int e in ends) put32 (b, text_off + e);
    int base_len = 8 + ends.length * 6;
    int off = base_len;
    foreach (var st in styles) {
        put16 (b, off);
        off += (int) st.length;
    }
    foreach (var st in styles) b.append (st.get_data ());
    return b.steal ();
}

uint8[] quill_stream (string[] texts, uint32[] ids, uint8[] fdpc_styles_first, int[] para_align) {
    var names = new Gee.ArrayList<string> ();
    var blobs = new Gee.ArrayList<Bytes> ();
    var all = new StringBuilder ();
    foreach (string t in texts) all.append (t);
    var text = utf16 (all.str);
    int data_off = 0x18 + 8 + 9 * 24;
    int text_off = data_off;
    names.add ("TEXT");
    blobs.add (new Bytes (text));
    var strs = new ByteArray ();
    put32 (strs, texts.length);
    put32 (strs, 4);
    foreach (string t in texts) put32 (strs, t.char_count ());
    names.add ("STRS");
    blobs.add (new Bytes (strs.data));
    var syid = new ByteArray ();
    put32 (syid, 0);
    put32 (syid, ids.length);
    foreach (uint32 i in ids) put32 (syid, i);
    names.add ("SYID");
    blobs.add (new Bytes (syid.data));
    int first_end = texts[0].char_count () * 2;
    int total = all.str.char_count () * 2;
    var cstyles = new Gee.ArrayList<Bytes> ();
    cstyles.add (new Bytes (qstyle (fdpc_styles_first)));
    cstyles.add (new Bytes (qstyle (new uint8[0])));
    names.add ("FDPC");
    blobs.add (new Bytes (quill_fdp (text_off, { first_end, total }, cstyles)));
    var pends = new Gee.ArrayList<int> ();
    int pos = 0;
    foreach (string t in texts) {
        int k = 0;
        unichar c;
        int i = 0;
        while (t.get_next_char (ref i, out c)) {
            k++;
            if (c == '\r') pends.add ((pos + k) * 2);
        }
        pos += t.char_count ();
    }
    var pstyles = new Gee.ArrayList<Bytes> ();
    for (int i = 0; i < pends.size; i++) pstyles.add (new Bytes (qstyle (i < para_align.length ? pblk (0x04, 0x68, para_align[i]) : new uint8[0])));
    names.add ("FDPP");
    blobs.add (new Bytes (quill_fdp (text_off, pends.to_array (), pstyles)));
    names.add ("STSH");
    blobs.add (new Bytes (new uint8[8]));
    var stsh = new ByteArray ();
    put32 (stsh, 0);
    put32 (stsh, 2);
    stsh.append (new uint8[12]);
    var cdef = qstyle (pcat (pblk (0x0C, 0x68, 127000), pblk (0x2E, 0x68, 1)));
    var pdef = qstyle (new uint8[0]);
    put32 (stsh, 8);
    put32 (stsh, 8 + 2 + cdef.length);
    put16 (stsh, 0);
    stsh.append (cdef);
    put16 (stsh, 0);
    stsh.append (pdef);
    names.add ("STSH");
    blobs.add (new Bytes (stsh.data));
    var font = new ByteArray ();
    put32 (font, 0);
    put32 (font, 2);
    font.append (new uint8[12 + 8]);
    foreach (string f in new string[] { "Times New Roman", "Georgia" }) {
        put16 (font, f.char_count ());
        font.append (utf16 (f));
        put32 (font, 0);
    }
    names.add ("FONT");
    blobs.add (new Bytes (font.data));
    var pl = new ByteArray ();
    put32 (pl, 2);
    pl.append (new uint8[8]);
    foreach (uint32 v in new uint32[] { 0x08000001, 0x00336699 }) {
        var blk = pblk (0x01, 0x68, v);
        put32 (pl, blk.length + 4);
        pl.append (blk);
    }
    names.add ("PL  ");
    blobs.add (new Bytes (pl.data));
    var b = new ByteArray ();
    b.append (new uint8[0x18]);
    put16 (b, 0);
    put16 (b, names.size);
    put32 (b, 0xFFFFFFFFu);
    int off = data_off;
    for (int i = 0; i < names.size; i++) {
        put16 (b, 0x18);
        b.append (names[i].data);
        put16 (b, 0);
        put32 (b, 1);
        b.append (names[i].data);
        put32 (b, off);
        put32 (b, (uint32) blobs[i].length);
        off += (int) blobs[i].length;
    }
    while (b.len < data_off) b.append ({ 0 });
    foreach (var bl in blobs) b.append (bl.get_data ());
    return b.steal ();
}

uint8[] erec (int type, int inst, int ver, uint8[] body) {
    var b = new ByteArray ();
    put16 (b, (inst << 4) | ver);
    put16 (b, type);
    put32 (b, body.length);
    b.append (body);
    if (type == 0xF000 || type == 0xF002) put32 (b, 0);
    return b.steal ();
}

uint8[] econt (int type, uint8[] body) {
    return erec (type, 0, 0xF, body);
}

uint8[] evals (uint32[] pairs, bool dup_len) {
    var b = new ByteArray ();
    if (dup_len) put32 (b, pairs.length / 2 * 6);
    for (int i = 0; i + 1 < pairs.length; i += 2) {
        put16 (b, pairs[i]);
        put32 (b, pairs[i + 1]);
    }
    return b.steal ();
}

uint8[] eshape (int mso, uint32 flags, uint32[] opt, uint8[]? anchor, uint32 seq, uint8[]? child = null, uint8[]? fspgr = null) {
    var parts = new Gee.ArrayList<Bytes> ();
    if (fspgr != null) parts.add (new Bytes (erec (0xF009, 0, 1, fspgr)));
    var fsp = new ByteArray ();
    put32 (fsp, 0x400);
    put32 (fsp, flags);
    parts.add (new Bytes (erec (0xF00A, mso, 2, fsp.data)));
    if (opt.length > 0) parts.add (new Bytes (erec (0xF00B, opt.length / 2, 3, evals (opt, false))));
    if (anchor != null) parts.add (new Bytes (erec (0xF010, 0, 0, anchor)));
    if (child != null) parts.add (new Bytes (erec (0xF00F, 0, 0, child)));
    parts.add (new Bytes (erec (0xF011, 0, 0, evals ({ 0x6801, seq }, true))));
    var b = new ByteArray ();
    foreach (var p in parts) b.append (p.get_data ());
    return erec (0xF004, 0, 0xF, b.data);
}

uint8[] ecoords (double x, double y, double w, double h, double pw, double ph) {
    int32 xs = (int32) Math.round ((x - pw / 2) * 12700), ys = (int32) Math.round ((y - ph / 2) * 12700);
    int32 xe = xs + (int32) Math.round (w * 12700), ye = ys + (int32) Math.round (h * 12700);
    return evals ({ 0x2001, (uint32) xs, 0x2002, (uint32) ys, 0x2003, (uint32) xe, 0x2004, (uint32) ye }, true);
}

uint8[] rect16 (int32 a, int32 b, int32 c, int32 d) {
    var r = new ByteArray ();
    put32 (r, (uint32) a);
    put32 (r, (uint32) b);
    put32 (r, (uint32) c);
    put32 (r, (uint32) d);
    return r.steal ();
}

uint8[] laid_out_publication () {
    double pw = 595.2756, ph = 841.8898;
    var cb = new ContentsBuilder ();
    int page_seq = 2, text_seq = 3, pic_seq = 4, rect_seq = 5, group_seq = 6, c1 = 7, c2 = 8, table_seq = 9, master_seq = 10;
    var doc = pcat (pcont (0x12, pcat (pblk (0x01, 0x68, 7560000), pblk (0x02, 0x68, 10692000))), pcont (0x02, pcat (pblk (0, 0x68, master_seq), pblk (0, 0x68, page_seq))));
    cb.add (0x44, doc);
    var pal = new ByteArray ();
    pal.append (pcont (0, pblk (0x01, 0x68, 0x00000000)));
    pal.append (pcont (0, pblk (0x01, 0x68, 0x000000FF)));
    cb.add (0x5C, pcont (0, pal.data, 0xA0));
    var shapes_list = new ByteArray ();
    foreach (int sq in new int[] { text_seq, pic_seq, rect_seq, group_seq, table_seq }) shapes_list.append (pblk (0, 0x70, sq));
    cb.add (0x43, pcont (0x02, shapes_list.data));
    cb.add (0x01, pblk (0x27, 0x68, 7));
    cb.add (0x01, new uint8[0]);
    cb.add (0x01, new uint8[0]);
    cb.add (0x30, new uint8[0]);
    cb.add (0x01, new uint8[0]);
    cb.add (0x01, new uint8[0]);
    var rc = new ByteArray ();
    foreach (int sz in new int[] { 914400, 914400, 457200, 457200 }) rc.append (pcont (0, pblk (0x02, 0x68, sz)));
    cb.add (0x10, pcat (pcat (pcat (pblk (0x66, 0x68, 2), pblk (0x67, 0x68, 2)), pblk (0x27, 0x68, 9)), pcont (0x6D, rc.data)));
    cb.add (0x43, pcont (0x0E, "M".data, 0xC0));
    var contents = cb.build ();
    uint8[] bold_style = pcat (pcat (pcat (pblk (0x02, 0x78, 0), pblk (0x0C, 0x68, 177800)), pblk (0x2E, 0x68, 0)), pcont (0x24, pcont (0, pblk (0, 0x68, 1))));
    var quill = quill_stream ({ "Hello Publisher\r", "A\rB\rC\rD\r" }, { 7, 9 }, bold_style, { 2 });
    var png = image_bytes ("png");
    var delay = blip (0xF01E, 0x6E0, png);
    var fbse = new ByteArray ();
    fbse.append ({ 6, 6 });
    for (int i = 0; i < 16; i++) fbse.append ({ (uint8) (i + 1) });
    put16 (fbse, 0);
    put32 (fbse, delay.length);
    put32 (fbse, 1);
    put32 (fbse, 0);
    fbse.append ({ 0, 0, 0, 0 });
    var dgg = econt (0xF000, pcat (erec (0xF006, 0, 0, new uint8[16]), econt (0xF001, erec (0xF007, 6, 2, fbse.data))));
    var patriarch = eshape (0, 5, {}, null, 0, null, new uint8[16]);
    var text = eshape (202, 0xA00, { 0x0081, 12700, 0x01BF, 0x100000, 0x01FF, 0x80000 }, ecoords (72, 72, 300, 60, pw, ph), text_seq);
    var pic = eshape (75, 0xA00, { 0x4104, 1, 0x0109, 16384, 0x01FF, 0x80000 }, ecoords (72, 160, 200, 150, pw, ph), pic_seq);
    var rect = eshape (1, 0xA00, { 0x0004, 30 << 16, 0x0181, 0x0000FF00, 0x01BF, 0x100010, 0x01C0, 0x08000001, 0x01CB, 25400, 0x01FF, 0x80008 }, ecoords (320, 160, 100, 80, pw, ph), rect_seq);
    var leader = eshape (0, 0x201, {}, ecoords (72, 400, 200, 100, pw, ph), group_seq, null, rect16 (0, 0, 1000, 1000));
    var e1 = eshape (3, 0xA02, { 0x0181, 0x000000FF, 0x01BF, 0x100010 }, null, c1, rect16 (0, 0, 500, 1000));
    var e2 = eshape (3, 0xA02, { 0x0181, 0x00FF0000, 0x01BF, 0x100010 }, null, c2, rect16 (500, 0, 1000, 1000));
    var group = econt (0xF003, pcat (pcat (leader, e1), e2));
    var table = eshape (1, 0xA00, { 0x01FF, 0x80000 }, ecoords (320, 400, 144, 72, pw, ph), table_seq);
    var dg = econt (0xF002, pcat (erec (0xF008, 0, 0, new uint8[8]), econt (0xF003, pcat (pcat (pcat (pcat (pcat (patriarch, text), pic), rect), group), table))));
    var esc = pcat (dgg, dg);
    var w = new CfbWriter ();
    w.add ("Contents", contents);
    w.add ("Quill/QuillSub/CONTENTS", quill);
    w.add ("Escher/EscherStm", esc);
    w.add ("Escher/EscherDelayStm", delay);
    w.add ("Envelope", pattern (30, 2));
    return w.build ();
}

void test_pub_layout_synthetic () {
    try {
        var r = new PubReader ();
        var pub = r.read (laid_out_publication ());
        assert (Math.fabs (pub.settings.width - 595.28) < 0.1);
        assert (Math.fabs (pub.settings.height - 841.89) < 0.1);
        assert (pub.settings.page_size == "a4");
        assert (pub.pages.size == 1);
        assert (!r.notes ().contains ("reflowed"));
        var items = pub.pages[0].items;
        assert (items.size == 5);
        var t = items[0] as TextFrame;
        assert (t != null);
        assert (Math.fabs (t.x - 72) < 0.05 && Math.fabs (t.y - 72) < 0.05);
        assert (Math.fabs (t.w - 300) < 0.05 && Math.fabs (t.h - 60) < 0.05);
        assert (Math.fabs (t.inset_left - 1) < 0.01);
        var st = pub.stories[t.story];
        assert (st.paras.size == 1);
        assert (st.paras[0].text () == "Hello Publisher");
        var run = st.paras[0].runs[0];
        assert (run.fmt.bold == 1);
        assert (Math.fabs (run.fmt.size - 14) < 0.01);
        assert (run.fmt.font == "Georgia");
        assert (run.fmt.color == "#ff0000");
        assert (st.paras[0].fmt.align == 1);
        var im = items[1] as ImageFrame;
        assert (im != null && im.media != "");
        assert (ImageStore.decode (pub.media[im.media].get_data ()) != null);
        assert (Math.fabs (im.y - 160) < 0.05);
        assert (Math.fabs (im.brightness - 0.5) < 0.01);
        var rect = items[2] as ShapeItem;
        assert (rect != null && rect.shape == ShapeKind.RECT);
        assert (Math.fabs (rect.rotation - 30) < 0.01);
        assert (rect.fill.kind == FillKind.SOLID && rect.fill.color == "#00ff00");
        assert (rect.stroke.color == "#ff0000" && Math.fabs (rect.stroke.width - 2) < 0.01);
        var g = items[3] as GroupItem;
        assert (g != null && g.children.size == 2);
        var left = g.children[0] as ShapeItem;
        assert (left.shape == ShapeKind.ELLIPSE);
        assert (Math.fabs (left.x - 72) < 0.1 && Math.fabs (left.w - 100) < 0.1 && Math.fabs (left.h - 100) < 0.1);
        assert (Math.fabs (g.children[1].x - 172) < 0.1);
        assert (((ShapeItem) g.children[1]).fill.color == "#0000ff");
        var tb = items[4] as TableItem;
        assert (tb != null && tb.rows == 2 && tb.cols == 2);
        assert (Math.fabs (tb.col_w[0] - 72) < 0.1 && Math.fabs (tb.row_h[1] - 36) < 0.1);
        assert (tb.cell (0, 0).story.paras[0].text () == "A");
        assert (tb.cell (1, 1).story.paras[0].text () == "D");
        assert (Math.fabs (tb.cell (1, 1).story.paras[0].runs[0].fmt.size - 10) < 0.01);
        var cache = new LayoutCache (pub);
        assert (!cache.story (st.id).overset);
        string note;
        var p2 = Document.load_bytes (laid_out_publication (), "layout.pub", out note);
        assert (p2.pages.size == 1);
        assert (!note.contains ("reflowed"));
    } catch (Error e) {
        error (e.message);
    }
}

void test_pub_layout_real () {
    string dir = Environment.get_variable ("PUBLISH_FIXTURES") ?? "tests/fixtures";
    uint8[] data;
    try {
        FileUtils.get_data (Path.build_filename (dir, "pub", "text-frames.pub"), out data);
        var r = new PubReader ();
        var pub = r.read (data);
        assert (pub.settings.page_size == "a4");
        assert (pub.pages.size == 1);
        var items = pub.pages[0].items;
        assert (items.size == 2);
        var a = items[0] as TextFrame;
        var b = items[1] as TextFrame;
        assert (a != null && b != null);
        assert (Math.fabs (a.x - 56.69) < 0.05 && Math.fabs (a.y - 62.36) < 0.05);
        assert (Math.fabs (a.w - 470.55) < 0.05 && Math.fabs (a.h - 56.69) < 0.05);
        assert (Math.fabs (a.inset_left - 2.88) < 0.01);
        var sa = pub.stories[a.story];
        assert (sa.paras.size == 3);
        assert (sa.paras[0].text () == "0123456789");
        assert (sa.paras[2].text () == "0123456789abcdef0123456789abcdef");
        assert (sa.paras[0].runs[0].fmt.font == "Times New Roman");
        assert (Math.fabs (sa.paras[0].runs[0].fmt.size - 10) < 0.01);
        var sb = pub.stories[b.story];
        assert (sb.paras.size == 4);
        assert (sb.paras[3].text ().has_prefix ("0123456789abcdef0123456789abcdef0123456789abcdef"));
        assert (a.fill.kind == FillKind.NONE);
        assert (a.stroke.color == ColorRef.NONE);
        var cache = new LayoutCache (pub);
        assert (!cache.story (sa.id).overset);
    } catch (Error e) {
        error (e.message);
    }
}

int main (string[] args) {
    Intl.setlocale (LocaleCategory.ALL, "C.UTF-8");
    Test.init (ref args);
    Test.add_func ("/cfb/roundtrip-512", test_roundtrip_512);
    Test.add_func ("/cfb/roundtrip-4096", test_roundtrip_4096);
    Test.add_func ("/cfb/empty-and-exact", test_empty_and_exact);
    Test.add_func ("/cfb/deep-tree", test_deep_tree);
    Test.add_func ("/cfb/many-fat-sectors", test_many_fat_sectors);
    Test.add_func ("/cfb/difat", test_difat);
    Test.add_func ("/cfb/invalid-signature", test_invalid_signature);
    Test.add_func ("/cfb/truncated", test_truncated);
    Test.add_func ("/cfb/cycle", test_cycle);
    Test.add_func ("/pub/import", test_pub_import);
    Test.add_func ("/pub/long-text", test_pub_long_text);
    Test.add_func ("/pub/broken-text", test_pub_broken_text);
    Test.add_func ("/pub/not-publisher", test_not_publisher);
    Test.add_func ("/pub/helpers", test_helpers);
    Test.add_func ("/pub/layout-synthetic", test_pub_layout_synthetic);
    Test.add_func ("/pub/layout-real", test_pub_layout_real);
    return Test.run ();
}
