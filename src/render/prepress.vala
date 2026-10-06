namespace Singularity.Apps.Publish {

    public enum PdfType {
        NULL,
        BOOL,
        NUMBER,
        STRING,
        NAME,
        ARRAY,
        DICT,
        REF,
        KEYWORD
    }

    public class PdfObj {
        public PdfType type = PdfType.NULL;
        public bool bval = false;
        public double num = 0;
        public bool is_int = true;
        public string name = "";
        public uint8[] raw = {};
        public Gee.ArrayList<PdfObj> items = new Gee.ArrayList<PdfObj> ();
        public Gee.ArrayList<string> keys = new Gee.ArrayList<string> ();
        public Gee.ArrayList<PdfObj> vals = new Gee.ArrayList<PdfObj> ();
        public int ref_num = 0;
        public int ref_gen = 0;

        public PdfObj (PdfType type = PdfType.NULL) {
            this.type = type;
        }

        public static PdfObj of_name (string n) {
            var o = new PdfObj (PdfType.NAME);
            o.name = n;
            return o;
        }

        public static PdfObj of_num (double v) {
            var o = new PdfObj (PdfType.NUMBER);
            o.num = v;
            o.is_int = Math.fabs (v - Math.round (v)) < 1e-9;
            return o;
        }

        public static PdfObj of_bool (bool v) {
            var o = new PdfObj (PdfType.BOOL);
            o.bval = v;
            return o;
        }

        public static PdfObj of_ref (int n, int gen = 0) {
            var o = new PdfObj (PdfType.REF);
            o.ref_num = n;
            o.ref_gen = gen;
            return o;
        }

        public static PdfObj array () {
            return new PdfObj (PdfType.ARRAY);
        }

        public static PdfObj dict () {
            return new PdfObj (PdfType.DICT);
        }

        public static PdfObj numbers (double[] v) {
            var a = array ();
            foreach (double x in v) a.items.add (of_num (x));
            return a;
        }

        public static PdfObj of_text (string s) {
            var o = new PdfObj (PdfType.STRING);
            bool ascii = true;
            for (int i = 0; i < s.length; i++) if (s[i] < 0x20 || s[i] > 0x7e) ascii = false;
            var b = new ByteArray ();
            if (ascii) {
                b.append ({ '(' });
                for (int i = 0; i < s.length; i++) {
                    char c = s[i];
                    if (c == '(' || c == ')' || c == '\\') b.append ({ '\\' });
                    b.append ({ (uint8) c });
                }
                b.append ({ ')' });
            } else {
                var sb = new StringBuilder ("<FEFF");
                unichar c;
                int i = 0;
                while (s.get_next_char (ref i, out c)) {
                    if (c > 0xFFFF) {
                        uint v = c - 0x10000;
                        sb.append ("%04X%04X".printf (0xD800 + (v >> 10), 0xDC00 + (v & 0x3FF)));
                    } else {
                        sb.append ("%04X".printf ((uint) c));
                    }
                }
                sb.append (">");
                b.append (sb.str.data);
            }
            o.raw = b.data;
            return o;
        }

        public static PdfObj of_hex (uint8[] data) {
            var o = new PdfObj (PdfType.STRING);
            var sb = new StringBuilder ("<");
            foreach (uint8 v in data) sb.append ("%02x".printf (v));
            sb.append (">");
            o.raw = sb.str.data;
            return o;
        }

        public PdfObj? get (string key) {
            for (int i = 0; i < keys.size; i++) if (keys[i] == key) return vals[i];
            return null;
        }

        public void set (string key, PdfObj v) {
            for (int i = 0; i < keys.size; i++) {
                if (keys[i] == key) {
                    vals[i] = v;
                    return;
                }
            }
            keys.add (key);
            vals.add (v);
        }

        public void remove (string key) {
            for (int i = 0; i < keys.size; i++) {
                if (keys[i] == key) {
                    keys.remove_at (i);
                    vals.remove_at (i);
                    return;
                }
            }
        }

        public bool is_name (string n) {
            return type == PdfType.NAME && name == n;
        }

        public string name_of (string key) {
            var v = get (key);
            return v != null && v.type == PdfType.NAME ? v.name : "";
        }

        public static string fmt (double v) {
            if (Math.fabs (v - Math.round (v)) < 1e-9) return "%.0f".printf (Math.round (v));
            string s = "%.6f".printf (v);
            while (s.has_suffix ("0")) s = s.substring (0, s.length - 1);
            if (s.has_suffix (".")) s = s.substring (0, s.length - 1);
            if (s == "-0") s = "0";
            return s;
        }

        private static bool regular (uint8 c) {
            if (c <= 0x20 || c >= 0x7f) return false;
            return "()<>[]{}/%#".index_of_char ((char) c) < 0;
        }

        public static string encode_name (string n) {
            var sb = new StringBuilder ("/");
            for (int i = 0; i < n.length; i++) {
                uint8 c = (uint8) n[i];
                if (regular (c)) sb.append_c ((char) c);
                else sb.append ("#%02X".printf (c));
            }
            return sb.str;
        }

        public void write (ByteArray b) {
            switch (type) {
                case PdfType.NULL:
                    b.append ("null".data);
                    break;
                case PdfType.BOOL:
                    b.append ((bval ? "true" : "false").data);
                    break;
                case PdfType.NUMBER:
                    b.append (fmt (num).data);
                    break;
                case PdfType.STRING:
                    b.append (raw);
                    break;
                case PdfType.NAME:
                    b.append (encode_name (name).data);
                    break;
                case PdfType.KEYWORD:
                    b.append (name.data);
                    break;
                case PdfType.REF:
                    b.append ("%d %d R".printf (ref_num, ref_gen).data);
                    break;
                case PdfType.ARRAY:
                    b.append ("[".data);
                    for (int i = 0; i < items.size; i++) {
                        if (i > 0) b.append (" ".data);
                        items[i].write (b);
                    }
                    b.append ("]".data);
                    break;
                case PdfType.DICT:
                    b.append ("<<".data);
                    for (int i = 0; i < keys.size; i++) {
                        b.append ("\n".data);
                        b.append (encode_name (keys[i]).data);
                        b.append (" ".data);
                        vals[i].write (b);
                    }
                    b.append ("\n>>".data);
                    break;
            }
        }
    }

    public class PdfEntry {
        public int num;
        public int gen;
        public PdfObj obj;
        public uint8[]? stream = null;

        public PdfEntry (int num, int gen, PdfObj obj) {
            this.num = num;
            this.gen = gen;
            this.obj = obj;
        }
    }

    public class PdfLexer {
        public unowned uint8[] d;
        public int pos = 0;

        public PdfLexer (uint8[] d, int pos = 0) {
            this.d = d;
            this.pos = pos;
        }

        public static bool is_ws (uint8 c) {
            return c == 0 || c == 9 || c == 10 || c == 12 || c == 13 || c == 32;
        }

        public static bool is_delim (uint8 c) {
            return is_ws (c) || "()<>[]{}/%".index_of_char ((char) c) >= 0;
        }

        public void skip_ws () {
            while (pos < d.length) {
                uint8 c = d[pos];
                if (is_ws (c)) {
                    pos++;
                } else if (c == '%') {
                    while (pos < d.length && d[pos] != '\n' && d[pos] != '\r') pos++;
                } else {
                    break;
                }
            }
        }

        public string word () {
            int s = pos;
            while (pos < d.length && !is_delim (d[pos])) pos++;
            return bytes_str (d, s, pos);
        }

        public static string bytes_str (uint8[] d, int s, int e) {
            var sb = new StringBuilder ();
            for (int i = s; i < e; i++) sb.append_c ((char) d[i]);
            return sb.str;
        }

        public static int skip_string (uint8[] d, int pos) {
            int depth = 0;
            int i = pos;
            while (i < d.length) {
                uint8 c = d[i];
                if (c == '\\') {
                    i += 2;
                    continue;
                }
                if (c == '(') depth++;
                else if (c == ')') {
                    depth--;
                    if (depth == 0) return i + 1;
                }
                i++;
            }
            return d.length;
        }

        private static int hexv (uint8 c) {
            if (c >= '0' && c <= '9') return c - '0';
            if (c >= 'a' && c <= 'f') return c - 'a' + 10;
            if (c >= 'A' && c <= 'F') return c - 'A' + 10;
            return -1;
        }

        public PdfObj parse () throws FormatError {
            skip_ws ();
            if (pos >= d.length) throw new FormatError.INVALID ("unexpected end of PDF");
            uint8 c = d[pos];
            if (c == '/') {
                pos++;
                int s = pos;
                while (pos < d.length && !is_delim (d[pos])) pos++;
                var sb = new StringBuilder ();
                for (int i = s; i < pos; i++) {
                    if (d[i] == '#' && i + 2 < pos && hexv (d[i + 1]) >= 0 && hexv (d[i + 2]) >= 0) {
                        sb.append_c ((char) (hexv (d[i + 1]) * 16 + hexv (d[i + 2])));
                        i += 2;
                    } else {
                        sb.append_c ((char) d[i]);
                    }
                }
                return PdfObj.of_name (sb.str);
            }
            if (c == '(') {
                int e = skip_string (d, pos);
                var o = new PdfObj (PdfType.STRING);
                o.raw = d[pos:e];
                pos = e;
                return o;
            }
            if (c == '<' && pos + 1 < d.length && d[pos + 1] == '<') {
                pos += 2;
                var o = PdfObj.dict ();
                while (true) {
                    skip_ws ();
                    if (pos >= d.length) throw new FormatError.INVALID ("unterminated dictionary");
                    if (d[pos] == '>' && pos + 1 < d.length && d[pos + 1] == '>') {
                        pos += 2;
                        break;
                    }
                    var k = parse ();
                    if (k.type != PdfType.NAME) throw new FormatError.INVALID ("bad dictionary key");
                    var v = parse ();
                    o.keys.add (k.name);
                    o.vals.add (v);
                }
                return o;
            }
            if (c == '<') {
                int s = pos;
                while (pos < d.length && d[pos] != '>') pos++;
                pos++;
                var o = new PdfObj (PdfType.STRING);
                o.raw = d[s:int.min (pos, d.length)];
                return o;
            }
            if (c == '[') {
                pos++;
                var o = PdfObj.array ();
                while (true) {
                    skip_ws ();
                    if (pos >= d.length) throw new FormatError.INVALID ("unterminated array");
                    if (d[pos] == ']') {
                        pos++;
                        break;
                    }
                    o.items.add (parse ());
                }
                return o;
            }
            if ((c >= '0' && c <= '9') || c == '+' || c == '-' || c == '.') {
                int s = pos;
                pos++;
                while (pos < d.length && ((d[pos] >= '0' && d[pos] <= '9') || d[pos] == '.')) pos++;
                string t = bytes_str (d, s, pos);
                var o = PdfObj.of_num (double.parse (t));
                o.is_int = !t.contains (".");
                if (o.is_int) {
                    int save = pos;
                    skip_ws ();
                    int s2 = pos;
                    while (pos < d.length && d[pos] >= '0' && d[pos] <= '9') pos++;
                    if (pos > s2) {
                        int gen = int.parse (bytes_str (d, s2, pos));
                        skip_ws ();
                        if (pos < d.length && d[pos] == 'R' && (pos + 1 >= d.length || is_delim (d[pos + 1]))) {
                            pos++;
                            return PdfObj.of_ref ((int) o.num, gen);
                        }
                    }
                    pos = save;
                }
                return o;
            }
            string w = word ();
            if (w == "") {
                pos++;
                throw new FormatError.INVALID ("unexpected character in PDF");
            }
            if (w == "true" || w == "false") return PdfObj.of_bool (w == "true");
            if (w == "null") return new PdfObj (PdfType.NULL);
            var k = new PdfObj (PdfType.KEYWORD);
            k.name = w;
            return k;
        }
    }

    public class PdfFile {
        public Gee.TreeMap<int, PdfEntry> objs = new Gee.TreeMap<int, PdfEntry> ();
        public PdfObj trailer = PdfObj.dict ();
        private uint8[] data;
        private Gee.HashMap<int, int> offsets = new Gee.HashMap<int, int> ();

        public static PdfFile parse (uint8[] bytes) throws Error {
            var f = new PdfFile ();
            f.data = bytes;
            if (!f.read_xref ()) f.scan_objects ();
            foreach (var n in f.offsets.keys) f.load (n);
            f.data = new uint8[0];
            return f;
        }

        private static int rfind (uint8[] d, string needle) {
            uint8[] n = needle.data;
            for (int i = d.length - n.length; i >= 0; i--) {
                bool ok = true;
                for (int k = 0; k < n.length; k++) if (d[i + k] != n[k]) {
                    ok = false;
                    break;
                }
                if (ok) return i;
            }
            return -1;
        }

        public static int find (uint8[] d, string needle, int from) {
            uint8[] n = needle.data;
            for (int i = from; i <= d.length - n.length; i++) {
                bool ok = true;
                for (int k = 0; k < n.length; k++) if (d[i + k] != n[k]) {
                    ok = false;
                    break;
                }
                if (ok) return i;
            }
            return -1;
        }

        private bool read_xref () {
            int sx = rfind (data, "startxref");
            if (sx < 0) return false;
            try {
                var lx = new PdfLexer (data, sx + 9);
                var off = lx.parse ();
                if (off.type != PdfType.NUMBER) return false;
                lx.pos = (int) off.num;
                lx.skip_ws ();
                if (lx.word () != "xref") return false;
                while (true) {
                    lx.skip_ws ();
                    int save = lx.pos;
                    string w = lx.word ();
                    if (w == "trailer") {
                        trailer = lx.parse ();
                        break;
                    }
                    lx.pos = save;
                    var start = lx.parse ();
                    var count = lx.parse ();
                    for (int i = 0; i < (int) count.num; i++) {
                        var o = lx.parse ();
                        lx.parse ();
                        lx.skip_ws ();
                        string flag = lx.word ();
                        if (flag == "n" && o.num > 0) offsets[(int) start.num + i] = (int) o.num;
                    }
                }
                return offsets.size > 0 && trailer.type == PdfType.DICT;
            } catch (Error e) {
                offsets.clear ();
                return false;
            }
        }

        private void scan_objects () throws Error {
            int i = 0;
            while (true) {
                int p = find (data, " obj", i);
                if (p < 0) break;
                int s = p - 1;
                while (s >= 0 && data[s] >= '0' && data[s] <= '9') s--;
                while (s >= 0 && data[s] == ' ') s--;
                while (s >= 0 && data[s] >= '0' && data[s] <= '9') s--;
                s++;
                try {
                    var lx = new PdfLexer (data, s);
                    var n = lx.parse ();
                    if (n.type == PdfType.NUMBER) offsets[(int) n.num] = s;
                } catch (Error e) {
                }
                i = p + 4;
            }
            int t = rfind (data, "trailer");
            if (t < 0) throw new FormatError.INVALID ("PDF trailer not found");
            var lx = new PdfLexer (data, t + 7);
            trailer = lx.parse ();
        }

        private PdfEntry? load (int n) throws Error {
            if (objs.has_key (n)) return objs[n];
            if (!offsets.has_key (n)) return null;
            var lx = new PdfLexer (data, offsets[n]);
            var num = lx.parse ();
            var gen = lx.parse ();
            lx.skip_ws ();
            if (lx.word () != "obj") throw new FormatError.INVALID ("bad object header");
            var val = lx.parse ();
            var e = new PdfEntry ((int) num.num, (int) gen.num, val);
            objs[n] = e;
            lx.skip_ws ();
            int save = lx.pos;
            if (val.type == PdfType.DICT && lx.word () == "stream") {
                if (lx.pos < data.length && data[lx.pos] == '\r') lx.pos++;
                if (lx.pos < data.length && data[lx.pos] == '\n') lx.pos++;
                int start = lx.pos;
                int len = -1;
                var lo = val.get ("Length");
                if (lo != null && lo.type == PdfType.NUMBER) len = (int) lo.num;
                else if (lo != null && lo.type == PdfType.REF) {
                    var le = load (lo.ref_num);
                    if (le != null && le.obj.type == PdfType.NUMBER) len = (int) le.obj.num;
                }
                if (len < 0 || start + len > data.length) {
                    int es = find (data, "endstream", start);
                    len = es < 0 ? data.length - start : es - start;
                    while (len > 0 && (data[start + len - 1] == '\n' || data[start + len - 1] == '\r')) len--;
                }
                e.stream = data[start:start + len];
                val.set ("Length", PdfObj.of_num (len));
            } else {
                lx.pos = save;
            }
            return e;
        }

        public PdfObj deref (PdfObj? o) {
            if (o == null) return new PdfObj (PdfType.NULL);
            int guard = 0;
            var cur = o;
            while (cur.type == PdfType.REF && guard++ < 32) {
                if (!objs.has_key (cur.ref_num)) return new PdfObj (PdfType.NULL);
                cur = objs[cur.ref_num].obj;
            }
            return cur;
        }

        public PdfEntry? entry_of (PdfObj? o) {
            if (o == null || o.type != PdfType.REF || !objs.has_key (o.ref_num)) return null;
            return objs[o.ref_num];
        }

        public int add (PdfObj obj, uint8[]? stream = null) {
            int n = objs.size > 0 ? objs.ascending_keys.last () + 1 : 1;
            var e = new PdfEntry (n, 0, obj);
            if (stream != null) {
                e.stream = stream;
                obj.set ("Length", PdfObj.of_num (stream.length));
            }
            objs[n] = e;
            return n;
        }

        public static uint8[] inflate (uint8[] input) throws Error {
            var conv = new ZlibDecompressor (ZlibCompressorFormat.ZLIB);
            var src = new MemoryInputStream.from_data (input.copy ());
            var cs = new ConverterInputStream (src, conv);
            var dst = new MemoryOutputStream.resizable ();
            dst.splice (cs, OutputStreamSpliceFlags.CLOSE_SOURCE | OutputStreamSpliceFlags.CLOSE_TARGET);
            var b = dst.steal_as_bytes ();
            uint8[] r = b.get_data ();
            return r;
        }

        public static uint8[] deflate (uint8[] input) throws Error {
            var conv = new ZlibCompressor (ZlibCompressorFormat.ZLIB, 6);
            var src = new MemoryInputStream.from_data (input.copy ());
            var cs = new ConverterInputStream (src, conv);
            var dst = new MemoryOutputStream.resizable ();
            dst.splice (cs, OutputStreamSpliceFlags.CLOSE_SOURCE | OutputStreamSpliceFlags.CLOSE_TARGET);
            var b = dst.steal_as_bytes ();
            uint8[] r = b.get_data ();
            return r;
        }

        public uint8[]? decoded (PdfEntry e) throws Error {
            if (e.stream == null) return null;
            var f = e.obj.get ("Filter");
            if (f == null) return e.stream;
            if (f.type == PdfType.ARRAY && f.items.size == 1) f = f.items[0];
            if (f.is_name ("FlateDecode") && e.obj.get ("DecodeParms") == null) return inflate (e.stream);
            return null;
        }

        public void set_stream (PdfEntry e, uint8[] content, bool compress = true) throws Error {
            e.obj.remove ("DecodeParms");
            if (compress) {
                e.stream = deflate (content);
                e.obj.set ("Filter", PdfObj.of_name ("FlateDecode"));
            } else {
                e.stream = content;
                e.obj.remove ("Filter");
            }
            e.obj.set ("Length", PdfObj.of_num (e.stream.length));
        }

        public Gee.ArrayList<PdfObj> pages () {
            var list = new Gee.ArrayList<PdfObj> ();
            var root = deref (trailer.get ("Root"));
            collect_pages (deref (root.get ("Pages")), list, 0);
            return list;
        }

        private void collect_pages (PdfObj node, Gee.ArrayList<PdfObj> list, int depth) {
            if (depth > 32 || node.type != PdfType.DICT) return;
            if (node.name_of ("Type") == "Page") {
                list.add (node);
                return;
            }
            var kids = deref (node.get ("Kids"));
            foreach (var k in kids.items) collect_pages (deref (k), list, depth + 1);
        }

        public uint8[] serialize (string version) {
            var b = new ByteArray ();
            b.append ("%%PDF-%s\n%%".printf (version).data);
            b.append ({ 0xE2, 0xE3, 0xCF, 0xD3, '\n' });
            int max = objs.size > 0 ? objs.ascending_keys.last () : 0;
            var offs = new int[max + 1];
            for (int i = 0; i <= max; i++) offs[i] = -1;
            foreach (var e in objs.values) {
                offs[e.num] = (int) b.len;
                b.append ("%d %d obj\n".printf (e.num, e.gen).data);
                e.obj.write (b);
                if (e.stream != null) {
                    b.append ("\nstream\n".data);
                    b.append (e.stream);
                    b.append ("\nendstream".data);
                }
                b.append ("\nendobj\n".data);
            }
            int xref = (int) b.len;
            var sb = new StringBuilder ();
            sb.append ("xref\n0 %d\n".printf (max + 1));
            sb.append ("0000000000 65535 f\r\n");
            for (int i = 1; i <= max; i++) {
                if (offs[i] < 0) sb.append ("0000000000 00000 f\r\n");
                else sb.append ("%010d 00000 n\r\n".printf (offs[i]));
            }
            b.append (sb.str.data);
            trailer.set ("Size", PdfObj.of_num (max + 1));
            trailer.remove ("Prev");
            trailer.remove ("XRefStm");
            b.append ("trailer\n".data);
            trailer.write (b);
            b.append ("\nstartxref\n%d\n%%%%EOF\n".printf (xref).data);
            return b.steal ();
        }
    }

    public class PdfPrepress {
        public SentinelOutput? sentinel;
        public ColorManager cm;
        public ColorMode standard = ColorMode.CMYK;
        public bool gray_plates = false;
        public string title = "";
        public Gee.ArrayList<SheetBoxes>? boxes = null;
        public DateTime? now = null;
        private PdfFile f;
        private Gee.HashSet<int> smask_forms = new Gee.HashSet<int> ();
        private Gee.HashMap<string, int> spot_spaces = new Gee.HashMap<string, int> ();
        private Gee.HashMap<string, string> spot_names = new Gee.HashMap<string, string> ();
        private int all_space = 0;

        public PdfPrepress (SentinelOutput? sentinel, ColorManager cm) {
            this.sentinel = sentinel;
            this.cm = cm;
        }

        public bool is_pdfx () {
            return standard == ColorMode.PDFX1A || standard == ColorMode.PDFX3 || standard == ColorMode.PDFX4;
        }

        public string version () {
            return standard == ColorMode.PDFX4 ? "1.6" : "1.4";
        }

        public uint8[] process (uint8[] data) throws Error {
            f = PdfFile.parse (data);
            if (standard != ColorMode.RGB && !gray_plates) convert_colors ();
            set_boxes ();
            if (is_pdfx ()) add_pdfx ();
            else if (standard != ColorMode.RGB) set_info (false);
            add_id (data);
            return f.serialize (version ());
        }

        private void find_smasks (PdfObj o, int depth) {
            if (depth > 40) return;
            if (o.type == PdfType.DICT) {
                var sm = o.get ("SMask");
                if (sm != null) {
                    var smd = f.deref (sm);
                    if (smd.type == PdfType.DICT) {
                        var g = smd.get ("G");
                        if (g != null && g.type == PdfType.REF) smask_forms.add (g.ref_num);
                    }
                }
                foreach (var v in o.vals) find_smasks (v, depth + 1);
            } else if (o.type == PdfType.ARRAY) {
                foreach (var v in o.items) find_smasks (v, depth + 1);
            }
        }

        private void convert_colors () throws Error {
            foreach (var e in f.objs.values) find_smasks (e.obj, 0);
            var entries = new Gee.ArrayList<PdfEntry> ();
            entries.add_all (f.objs.values);
            foreach (var e in entries) {
                var o = e.obj;
                if (o.type != PdfType.DICT) continue;
                if (o.name_of ("Type") == "Page") {
                    if (standard == ColorMode.PDFX1A || standard == ColorMode.PDFX3) o.remove ("Group");
                    else fix_group (o);
                    var res = page_resources (o);
                    var contents = o.get ("Contents");
                    var list = new Gee.ArrayList<PdfEntry> ();
                    if (contents != null && contents.type == PdfType.REF) {
                        var ce = f.entry_of (contents);
                        if (ce != null) list.add (ce);
                    } else if (contents != null && contents.type == PdfType.ARRAY) {
                        foreach (var it in contents.items) {
                            var ce = f.entry_of (it);
                            if (ce != null) list.add (ce);
                        }
                    }
                    foreach (var ce in list) rewrite_stream (ce, res, 0);
                    continue;
                }
                if (e.stream != null && !smask_forms.contains (e.num)) {
                    bool form = o.name_of ("Subtype") == "Form";
                    var pt = o.get ("PatternType");
                    bool tiling = pt != null && pt.type == PdfType.NUMBER && (int) pt.num == 1;
                    if (form || tiling) {
                        if (form) fix_group (o);
                        var r = o.get ("Resources");
                        if (r == null) {
                            r = PdfObj.dict ();
                            o.set ("Resources", r);
                        }
                        rewrite_stream (e, f.deref (r), -1);
                        continue;
                    }
                }
                if (o.name_of ("Subtype") == "Image" && e.stream != null) convert_image (e);
            }
            foreach (var e in entries) convert_shadings (e.obj, 0);
        }

        private void fix_group (PdfObj o) {
            var g = f.deref (o.get ("Group"));
            if (g.type == PdfType.DICT && g.name_of ("CS") == "DeviceRGB") g.set ("CS", PdfObj.of_name ("DeviceCMYK"));
        }

        private PdfObj page_resources (PdfObj page) {
            var cur = page;
            for (int i = 0; i < 32 && cur.type == PdfType.DICT; i++) {
                var r = cur.get ("Resources");
                if (r != null) return f.deref (r);
                cur = f.deref (cur.get ("Parent"));
            }
            var d = PdfObj.dict ();
            page.set ("Resources", d);
            return d;
        }

        private static bool is_num_char (uint8 c) {
            return (c >= '0' && c <= '9') || c == '+' || c == '-' || c == '.';
        }

        private class Tok {
            public int start;
            public int end;
            public bool number;
            public double value;

            public Tok (int start, int end, bool number, double value) {
                this.start = start;
                this.end = end;
                this.number = number;
                this.value = value;
            }
        }

        private static int skip_nested (uint8[] d, int i, uint8 open, uint8 close) {
            int depth = 0;
            while (i < d.length) {
                uint8 c = d[i];
                if (c == '(') {
                    i = PdfLexer.skip_string (d, i);
                    continue;
                }
                if (c == open && (open != '<' || (i + 1 < d.length && d[i + 1] == '<'))) {
                    depth++;
                    i += open == '<' ? 2 : 1;
                    continue;
                }
                if (c == close && (close != '>' || (i + 1 < d.length && d[i + 1] == '>'))) {
                    depth--;
                    i += close == '>' ? 2 : 1;
                    if (depth == 0) return i;
                    continue;
                }
                i++;
            }
            return d.length;
        }

        public string ink_ops (InkColor? ink, double r, double g, double b, bool stroke, Gee.HashSet<string> used_cs) {
            if (ink == null) {
                double c, m, y, k;
                cm.rgb_to_cmyk (r, g, b, out c, out m, out y, out k);
                return "%s %s %s %s %s".printf (PdfObj.fmt (c), PdfObj.fmt (m), PdfObj.fmt (y), PdfObj.fmt (k), stroke ? "K" : "k");
            }
            if (ink.kind == InkKind.PROCESS) return "%s %s %s %s %s".printf (PdfObj.fmt (ink.c), PdfObj.fmt (ink.m), PdfObj.fmt (ink.y), PdfObj.fmt (ink.k), stroke ? "K" : "k");
            string cs = space_for (ink);
            used_cs.add (cs);
            return "/%s %s %s %s".printf (cs, stroke ? "CS" : "cs", PdfObj.fmt (ink.tint), stroke ? "SCN" : "scn");
        }

        private int tint_function (double c, double m, double y, double k) {
            var fn = PdfObj.dict ();
            fn.set ("FunctionType", PdfObj.of_num (2));
            fn.set ("Domain", PdfObj.numbers ({ 0, 1 }));
            fn.set ("C0", PdfObj.numbers ({ 0, 0, 0, 0 }));
            fn.set ("C1", PdfObj.numbers ({ c, m, y, k }));
            fn.set ("N", PdfObj.of_num (1));
            return f.add (fn);
        }

        public string space_for (InkColor ink) {
            if (ink.kind == InkKind.ALL) {
                if (all_space == 0) {
                    var a = PdfObj.array ();
                    a.items.add (PdfObj.of_name ("Separation"));
                    a.items.add (PdfObj.of_name ("All"));
                    a.items.add (PdfObj.of_name ("DeviceCMYK"));
                    a.items.add (PdfObj.of_ref (tint_function (1, 1, 1, 1)));
                    all_space = f.add (a);
                }
                return "CSall";
            }
            if (!spot_spaces.has_key (ink.spot)) {
                var a = PdfObj.array ();
                a.items.add (PdfObj.of_name ("Separation"));
                a.items.add (PdfObj.of_name (ink.spot));
                a.items.add (PdfObj.of_name ("DeviceCMYK"));
                a.items.add (PdfObj.of_ref (tint_function (ink.c, ink.m, ink.y, ink.k)));
                spot_spaces[ink.spot] = f.add (a);
                spot_names[ink.spot] = "CSs%d".printf (spot_names.size);
            }
            return spot_names[ink.spot];
        }

        private int space_ref (string cs) {
            if (cs == "CSall") return all_space;
            foreach (var e in spot_names.entries) if (e.value == cs) return spot_spaces[e.key];
            return 0;
        }

        public uint8[] rewrite_content (uint8[] d, int initial_state, Gee.HashSet<string> used_cs, Gee.HashSet<string> used_gs) {
            var out_b = new ByteArray ();
            var ops = new Gee.ArrayList<Tok> ();
            var stack = new Gee.ArrayList<int> ();
            int state = initial_state;
            int last = 0;
            int i = 0;
            int n = d.length;
            while (i < n) {
                uint8 c = d[i];
                if (PdfLexer.is_ws (c)) {
                    i++;
                    continue;
                }
                if (c == '%') {
                    while (i < n && d[i] != '\n' && d[i] != '\r') i++;
                    continue;
                }
                int start = i;
                if (c == '/') {
                    i++;
                    while (i < n && !PdfLexer.is_delim (d[i])) i++;
                    ops.add (new Tok (start, i, false, 0));
                    continue;
                }
                if (c == '(') {
                    i = PdfLexer.skip_string (d, i);
                    ops.add (new Tok (start, i, false, 0));
                    continue;
                }
                if (c == '<') {
                    if (i + 1 < n && d[i + 1] == '<') i = skip_nested (d, i, '<', '>');
                    else {
                        while (i < n && d[i] != '>') i++;
                        i++;
                    }
                    ops.add (new Tok (start, int.min (i, n), false, 0));
                    continue;
                }
                if (c == '[') {
                    i = skip_nested (d, i, '[', ']');
                    ops.add (new Tok (start, i, false, 0));
                    continue;
                }
                if (is_num_char (c)) {
                    i++;
                    while (i < n && is_num_char (d[i])) i++;
                    ops.add (new Tok (start, i, true, double.parse (PdfLexer.bytes_str (d, start, i))));
                    continue;
                }
                while (i < n && !PdfLexer.is_delim (d[i])) i++;
                if (i == start) {
                    i++;
                    ops.clear ();
                    continue;
                }
                string op = PdfLexer.bytes_str (d, start, i);
                if (op == "true" || op == "false" || op == "null") {
                    ops.add (new Tok (start, i, false, 0));
                    continue;
                }
                if (op == "BI") {
                    int p = i;
                    while (p < n) {
                        if (d[p] == 'E' && p + 1 < n && d[p + 1] == 'I' && p > 0 && PdfLexer.is_ws (d[p - 1]) && (p + 2 >= n || PdfLexer.is_ws (d[p + 2]))) break;
                        p++;
                    }
                    i = int.min (n, p + 2);
                    ops.clear ();
                    continue;
                }
                if (op == "q") stack.add (state);
                else if (op == "Q") {
                    if (stack.size > 0) state = stack.remove_at (stack.size - 1);
                } else if ((op == "rg" || op == "RG") && ops.size >= 3 && ops[ops.size - 1].number && ops[ops.size - 2].number && ops[ops.size - 3].number) {
                    double r = ops[ops.size - 3].value, g = ops[ops.size - 2].value, b = ops[ops.size - 1].value;
                    bool op_flag = false;
                    InkColor? ink = sentinel != null ? sentinel.decode (r, g, b, out op_flag) : null;
                    var sb = new StringBuilder ();
                    int want = op_flag ? 1 : 0;
                    if (want != state) {
                        string gs = op_flag ? "GSop" : "GSko";
                        used_gs.add (gs);
                        sb.append ("/%s gs ".printf (gs));
                        state = want;
                    }
                    sb.append (ink_ops (ink, r, g, b, op == "RG", used_cs));
                    int first = ops[ops.size - 3].start;
                    out_b.append (d[last:first]);
                    out_b.append (sb.str.data);
                    last = i;
                }
                ops.clear ();
            }
            if (last < n) out_b.append (d[last:n]);
            return out_b.steal ();
        }

        private void rewrite_stream (PdfEntry e, PdfObj res, int initial_state) throws Error {
            var content = f.decoded (e);
            if (content == null) return;
            var used_cs = new Gee.HashSet<string> ();
            var used_gs = new Gee.HashSet<string> ();
            var out_data = rewrite_content (content, initial_state, used_cs, used_gs);
            f.set_stream (e, out_data, true);
            if (res.type != PdfType.DICT) return;
            if (used_cs.size > 0) {
                var csd = f.deref (res.get ("ColorSpace"));
                if (csd.type != PdfType.DICT) {
                    csd = PdfObj.dict ();
                    res.set ("ColorSpace", csd);
                }
                foreach (string cs in used_cs) csd.set (cs, PdfObj.of_ref (space_ref (cs)));
            }
            if (used_gs.size > 0) {
                var gsd = f.deref (res.get ("ExtGState"));
                if (gsd.type != PdfType.DICT) {
                    gsd = PdfObj.dict ();
                    res.set ("ExtGState", gsd);
                }
                foreach (string gs in used_gs) {
                    var g = PdfObj.dict ();
                    g.set ("Type", PdfObj.of_name ("ExtGState"));
                    bool on = gs == "GSop";
                    g.set ("OP", PdfObj.of_bool (on));
                    g.set ("op", PdfObj.of_bool (on));
                    g.set ("OPM", PdfObj.of_num (on ? 1 : 0));
                    gsd.set (gs, g);
                }
            }
        }

        private void convert_image (PdfEntry e) throws Error {
            var o = e.obj;
            if (!f.deref (o.get ("ColorSpace")).is_name ("DeviceRGB")) return;
            var bpc = o.get ("BitsPerComponent");
            if (bpc == null || (int) bpc.num != 8) return;
            var raw = f.decoded (e);
            if (raw == null) return;
            int w = (int) f.deref (o.get ("Width")).num, h = (int) f.deref (o.get ("Height")).num;
            if (w <= 0 || h <= 0 || raw.length < w * h * 3) return;
            var cmyk = cm.rgb8_to_cmyk8 (raw, w * h);
            f.set_stream (e, cmyk, true);
            o.set ("ColorSpace", PdfObj.of_name ("DeviceCMYK"));
            o.remove ("Decode");
        }

        private void convert_shadings (PdfObj o, int depth) throws Error {
            if (depth > 40) return;
            if (o.type == PdfType.DICT) {
                if (o.get ("ShadingType") != null && f.deref (o.get ("ColorSpace")).is_name ("DeviceRGB")) convert_shading (o);
                foreach (var v in o.vals) convert_shadings (v, depth + 1);
            } else if (o.type == PdfType.ARRAY) {
                foreach (var v in o.items) convert_shadings (v, depth + 1);
            }
        }

        private void collect_type2 (PdfObj fn, Gee.ArrayList<PdfObj> list, int depth) {
            if (depth > 8) return;
            var d = f.deref (fn);
            if (d.type != PdfType.DICT) return;
            int t = (int) f.deref (d.get ("FunctionType")).num;
            if (t == 2) list.add (d);
            else if (t == 3) foreach (var s in f.deref (d.get ("Functions")).items) collect_type2 (s, list, depth + 1);
        }

        private PdfObj copy_function (PdfObj fn, Gee.HashMap<PdfObj, PdfObj> replaced, int depth) {
            var d = f.deref (fn);
            if (replaced.has_key (d)) return replaced[d];
            var n = PdfObj.dict ();
            for (int i = 0; i < d.keys.size; i++) {
                if (d.keys[i] == "Functions") {
                    var arr = PdfObj.array ();
                    foreach (var s in f.deref (d.vals[i]).items) arr.items.add (copy_function (s, replaced, depth + 1));
                    n.set ("Functions", arr);
                } else {
                    n.set (d.keys[i], d.vals[i]);
                }
            }
            return n;
        }

        private void convert_shading (PdfObj sh) {
            var fn = sh.get ("Function");
            if (fn == null || f.deref (fn).type == PdfType.ARRAY) return;
            var type2 = new Gee.ArrayList<PdfObj> ();
            collect_type2 (fn, type2, 0);
            if (type2.size == 0) return;
            var inks = new Gee.ArrayList<InkColor?> ();
            var rgbs = new Gee.ArrayList<double?> ();
            foreach (var t in type2) {
                foreach (string key in new string[] { "C0", "C1" }) {
                    var a = f.deref (t.get (key));
                    double r = key == "C0" ? 0 : 1, g = r, b = r;
                    if (a.type == PdfType.ARRAY && a.items.size >= 3) {
                        r = f.deref (a.items[0]).num;
                        g = f.deref (a.items[1]).num;
                        b = f.deref (a.items[2]).num;
                    }
                    bool opf;
                    inks.add (sentinel != null ? sentinel.decode (r, g, b, out opf) : null);
                    rgbs.add (r);
                    rgbs.add (g);
                    rgbs.add (b);
                }
            }
            string? spot = null;
            bool single = true;
            foreach (var ink in inks) {
                if (ink == null || ink.kind == InkKind.PROCESS) {
                    single = false;
                    break;
                }
                string key = ink.kind == InkKind.ALL ? "\x01all" : ink.spot;
                if (spot == null) spot = key;
                else if (spot != key) single = false;
            }
            var replaced = new Gee.HashMap<PdfObj, PdfObj> ();
            int idx = 0;
            foreach (var t in type2) {
                var n = PdfObj.dict ();
                for (int i = 0; i < t.keys.size; i++) n.set (t.keys[i], t.vals[i]);
                foreach (string key in new string[] { "C0", "C1" }) {
                    var ink = inks[idx];
                    double r = rgbs[idx * 3], g = rgbs[idx * 3 + 1], b = rgbs[idx * 3 + 2];
                    if (single) {
                        n.set (key, PdfObj.numbers ({ ink.tint }));
                    } else {
                        double c, m, y, k;
                        if (ink == null) cm.rgb_to_cmyk (r, g, b, out c, out m, out y, out k);
                        else ink.process_values (out c, out m, out y, out k);
                        n.set (key, PdfObj.numbers ({ c, m, y, k }));
                    }
                    idx++;
                }
                replaced[t] = n;
            }
            var nf = copy_function (fn, replaced, 0);
            sh.set ("Function", PdfObj.of_ref (f.add (nf)));
            if (single) {
                var used = new Gee.HashSet<string> ();
                string cs = space_for (inks[0]);
                used.add (cs);
                sh.set ("ColorSpace", PdfObj.of_ref (space_ref (cs)));
            } else {
                sh.set ("ColorSpace", PdfObj.of_name ("DeviceCMYK"));
            }
        }

        private PdfObj box (SheetBoxes b, Rect r) {
            return PdfObj.numbers ({ r.x, b.height - r.y2 (), r.x2 (), b.height - r.y });
        }

        private void set_boxes () {
            if (boxes == null) return;
            var pages = f.pages ();
            for (int i = 0; i < pages.size && i < boxes.size; i++) {
                var b = boxes[i];
                pages[i].set ("TrimBox", box (b, b.trim));
                pages[i].set ("BleedBox", box (b, b.bleed));
            }
        }

        private string pdf_date (DateTime t) {
            var off = t.get_utc_offset ();
            int mins = (int) (off / TimeSpan.MINUTE);
            string sign = mins < 0 ? "-" : "+";
            mins = mins.abs ();
            return "D:%s%s%02d'%02d'".printf (t.format ("%Y%m%d%H%M%S"), sign, mins / 60, mins % 60);
        }

        private string xmp_date (DateTime t) {
            var off = t.get_utc_offset ();
            int mins = (int) (off / TimeSpan.MINUTE);
            string sign = mins < 0 ? "-" : "+";
            mins = mins.abs ();
            return "%s%s%02d:%02d".printf (t.format ("%Y-%m-%dT%H:%M:%S"), sign, mins / 60, mins % 60);
        }

        public const string PRODUCER = "Singularity Publish";

        private PdfObj set_info (bool pdfx) {
            var t = now ?? new DateTime.now_local ();
            var info_ref = f.trailer.get ("Info");
            PdfObj info = f.deref (info_ref);
            if (info.type != PdfType.DICT) {
                info = PdfObj.dict ();
                f.trailer.set ("Info", PdfObj.of_ref (f.add (info)));
            }
            if (title != "") info.set ("Title", PdfObj.of_text (title));
            info.set ("Creator", PdfObj.of_text (PRODUCER));
            info.set ("Producer", PdfObj.of_text (PRODUCER));
            info.set ("CreationDate", PdfObj.of_text (pdf_date (t)));
            info.set ("ModDate", PdfObj.of_text (pdf_date (t)));
            info.set ("Trapped", PdfObj.of_name ("False"));
            if (pdfx && standard == ColorMode.PDFX1A) {
                info.set ("GTS_PDFXVersion", PdfObj.of_text ("PDF/X-1:2003"));
                info.set ("GTS_PDFXConformance", PdfObj.of_text ("PDF/X-1a:2003"));
            } else if (pdfx && standard == ColorMode.PDFX3) {
                info.set ("GTS_PDFXVersion", PdfObj.of_text ("PDF/X-3:2003"));
            } else if (pdfx && standard == ColorMode.PDFX4) {
                info.set ("GTS_PDFXVersion", PdfObj.of_text ("PDF/X-4"));
            }
            return info;
        }

        private static string uuid () {
            return Uuid.string_random ();
        }

        private void add_pdfx () throws Error {
            var t = now ?? new DateTime.now_local ();
            set_info (true);
            var root = f.deref (f.trailer.get ("Root"));
            var icc = PdfObj.dict ();
            icc.set ("N", PdfObj.of_num (4));
            icc.set ("Alternate", PdfObj.of_name ("DeviceCMYK"));
            int icc_ref = f.add (icc, new uint8[0]);
            f.set_stream (f.objs[icc_ref], cm.profile_data (), true);
            var intent = PdfObj.dict ();
            intent.set ("Type", PdfObj.of_name ("OutputIntent"));
            intent.set ("S", PdfObj.of_name ("GTS_PDFX"));
            intent.set ("OutputConditionIdentifier", PdfObj.of_text (cm.output_condition ()));
            intent.set ("OutputCondition", PdfObj.of_text (cm.description ()));
            intent.set ("RegistryName", PdfObj.of_text ("http://www.color.org"));
            intent.set ("Info", PdfObj.of_text (cm.description ()));
            intent.set ("DestOutputProfile", PdfObj.of_ref (icc_ref));
            var intents = PdfObj.array ();
            intents.items.add (intent);
            root.set ("OutputIntents", intents);
            string version = standard == ColorMode.PDFX4 ? "PDF/X-4" : (standard == ColorMode.PDFX3 ? "PDF/X-3:2003" : "PDF/X-1:2003");
            var sb = new StringBuilder ();
            sb.append ("<?xpacket begin=\"\xef\xbb\xbf\" id=\"W5M0MpCehiHzreSzNTczkc9d\"?>\n");
            sb.append ("<x:xmpmeta xmlns:x=\"adobe:ns:meta/\">\n<rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\">\n");
            sb.append ("<rdf:Description rdf:about=\"\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:xmp=\"http://ns.adobe.com/xap/1.0/\" xmlns:pdf=\"http://ns.adobe.com/pdf/1.3/\" xmlns:xmpMM=\"http://ns.adobe.com/xap/1.0/mm/\" xmlns:pdfxid=\"http://www.npes.org/pdfx/ns/id/\" xmlns:pdfx=\"http://ns.adobe.com/pdfx/1.3/\">\n");
            sb.append ("<dc:format>application/pdf</dc:format>\n");
            if (title != "") sb.append ("<dc:title><rdf:Alt><rdf:li xml:lang=\"x-default\">%s</rdf:li></rdf:Alt></dc:title>\n".printf (Markup.escape_text (title)));
            string date = xmp_date (t);
            sb.append ("<xmp:CreateDate>%s</xmp:CreateDate>\n<xmp:ModifyDate>%s</xmp:ModifyDate>\n<xmp:MetadataDate>%s</xmp:MetadataDate>\n".printf (date, date, date));
            sb.append ("<xmp:CreatorTool>%s</xmp:CreatorTool>\n<pdf:Producer>%s</pdf:Producer>\n<pdf:Trapped>False</pdf:Trapped>\n".printf (PRODUCER, PRODUCER));
            sb.append ("<xmpMM:DocumentID>uuid:%s</xmpMM:DocumentID>\n<xmpMM:InstanceID>uuid:%s</xmpMM:InstanceID>\n<xmpMM:VersionID>1</xmpMM:VersionID>\n<xmpMM:RenditionClass>default</xmpMM:RenditionClass>\n".printf (uuid (), uuid ()));
            sb.append ("<pdfxid:GTS_PDFXVersion>%s</pdfxid:GTS_PDFXVersion>\n".printf (version));
            if (standard != ColorMode.PDFX4) sb.append ("<pdfx:GTS_PDFXVersion>%s</pdfx:GTS_PDFXVersion>\n".printf (version));
            if (standard == ColorMode.PDFX1A) sb.append ("<pdfx:GTS_PDFXConformance>PDF/X-1a:2003</pdfx:GTS_PDFXConformance>\n");
            sb.append ("</rdf:Description>\n</rdf:RDF>\n</x:xmpmeta>\n<?xpacket end=\"w\"?>");
            var meta = PdfObj.dict ();
            meta.set ("Type", PdfObj.of_name ("Metadata"));
            meta.set ("Subtype", PdfObj.of_name ("XML"));
            int meta_ref = f.add (meta, new uint8[0]);
            f.set_stream (f.objs[meta_ref], sb.str.data, false);
            root.set ("Metadata", PdfObj.of_ref (meta_ref));
        }

        private void add_id (uint8[] data) {
            var sum = Checksum.compute_for_data (ChecksumType.MD5, data);
            var bin = new uint8[16];
            for (int i = 0; i < 16; i++) {
                uint64 v;
                uint64.try_parse (sum.substring (i * 2, 2), out v, null, 16);
                bin[i] = (uint8) v;
            }
            var id = PdfObj.array ();
            id.items.add (PdfObj.of_hex (bin));
            id.items.add (PdfObj.of_hex (bin));
            f.trailer.set ("ID", id);
        }
    }
}
