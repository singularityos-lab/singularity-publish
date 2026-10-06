namespace Singularity.Apps.Publish {

    public class PubBlock {
        public int id;
        public int type;
        public int data_off;
        public int end;
        public uint32 data;
        public bool var_len;
    }

    public class PubCharStyle {
        public int bold = -1;
        public int italic = -1;
        public int underline = -1;
        public double size = double.NAN;
        public int color = -1;
        public int font = -1;
        public int position = -1;
        public int caps = -1;
        public bool outline = false;
        public bool shadow = false;
        public bool emboss = false;
    }

    public class PubParaStyle {
        public int align = -1;
        public int default_char = -1;
        public double leading_pt = double.NAN;
        public double leading_mult = double.NAN;
        public double before = double.NAN;
        public double after = double.NAN;
        public double first = double.NAN;
        public double left = double.NAN;
        public double right = double.NAN;
        public int drop_lines = -1;
        public int drop_letters = -1;
        public bool list = false;
        public uint32 bullet = 0;
        public int number_start = -1;
        public Gee.ArrayList<double?> tabs = new Gee.ArrayList<double?> ();
    }

    public class PubSpan {
        public string text;
        public PubCharStyle style;

        public PubSpan (string text, PubCharStyle style) {
            this.text = text;
            this.style = style;
        }
    }

    public class PubPara {
        public Gee.ArrayList<PubSpan> spans = new Gee.ArrayList<PubSpan> ();
        public PubParaStyle style;

        public PubPara (PubParaStyle style) {
            this.style = style;
        }
    }

    public class PubCellInfo {
        public int r0;
        public int r1;
        public int c0;
        public int c1;
    }

    public class PubShapeInfo {
        public uint32 seq;
        public int chunk_type;
        public int text_id = -1;
        public int valign = -1;
        public uint32 page = 0;
        public int rows = 0;
        public int cols = 0;
        public uint32 cells_seq = 0;
        public int rowcol_off = -1;
        public Gee.ArrayList<double?> col_w = new Gee.ArrayList<double?> ();
        public Gee.ArrayList<double?> row_h = new Gee.ArrayList<double?> ();
        public Gee.ArrayList<PubCellInfo> cells = new Gee.ArrayList<PubCellInfo> ();
    }

    public class PubPageInfo {
        public uint32 seq;
        public bool master = false;
        public uint32 applied = 0;
        public uint32 bg = 0;
        public Gee.ArrayList<uint32> shapes = new Gee.ArrayList<uint32> ();
    }

    public class PubChunkRef {
        public uint32 seq;
        public int type;
        public int offset;
        public uint32 parent;
    }

    public class PubLayout {
        public const double EMU_PT = 12700.0;
        public Gee.ArrayList<string> warnings = new Gee.ArrayList<string> ();
        public double width = 0;
        public double height = 0;
        public int placed_text = 0;
        public int placed_images = 0;
        public int placed_shapes = 0;
        public int placed_tables = 0;
        public int page_count = 0;
        public string font_list = "";

        private uint8[] contents;
        private uint8[] quill;
        private uint8[] escher = new uint8[0];
        private uint8[] delay = new uint8[0];
        private Gee.ArrayList<PubChunkRef> chunks = new Gee.ArrayList<PubChunkRef> ();
        private Gee.ArrayList<uint32> page_order = new Gee.ArrayList<uint32> ();
        private Gee.HashMap<uint32, PubPageInfo> pages = new Gee.HashMap<uint32, PubPageInfo> ();
        private Gee.HashMap<uint32, PubShapeInfo> shapes = new Gee.HashMap<uint32, PubShapeInfo> ();
        private Gee.HashMap<uint32, uint32> shape_page = new Gee.HashMap<uint32, uint32> ();
        private Gee.ArrayList<uint32> palette = new Gee.ArrayList<uint32> ();
        private Gee.ArrayList<uint32> text_colors = new Gee.ArrayList<uint32> ();
        private Gee.ArrayList<string> fonts = new Gee.ArrayList<string> ();
        private Gee.ArrayList<PubCharStyle> default_chars = new Gee.ArrayList<PubCharStyle> ();
        private Gee.ArrayList<PubParaStyle> default_paras = new Gee.ArrayList<PubParaStyle> ();
        private Gee.HashMap<uint32, Gee.ArrayList<PubPara>> texts = new Gee.HashMap<uint32, Gee.ArrayList<PubPara>> ();
        private Gee.HashMap<uint32, Gee.ArrayList<int>> cell_ends = new Gee.HashMap<uint32, Gee.ArrayList<int>> ();
        private Gee.ArrayList<Bytes?> blips = new Gee.ArrayList<Bytes?> ();
        private Gee.ArrayList<string> blip_ext = new Gee.ArrayList<string> ();
        private Gee.HashMap<int, string> media_ids = new Gee.HashMap<int, string> ();
        private Gee.HashSet<uint32> used_text = new Gee.HashSet<uint32> ();
        private int metafiles = 0;
        private int custom_paths = 0;
        private Publication pub;

        private static uint16 r16 (uint8[] d, int o) {
            if (o < 0 || o + 2 > d.length) return 0;
            return (uint16) ((uint) d[o] | ((uint) d[o + 1] << 8));
        }

        private static uint32 r32 (uint8[] d, int o) {
            if (o < 0 || o + 4 > d.length) return 0;
            return (uint32) d[o] | ((uint32) d[o + 1] << 8) | ((uint32) d[o + 2] << 16) | ((uint32) d[o + 3] << 24);
        }

        public static int block_length (int type) {
            switch (type) {
                case 0x78:
                case 0x05:
                case 0x08:
                case 0x0A:
                    return 0;
                case 0x10:
                case 0x12:
                case 0x18:
                case 0x1A:
                case 0x07:
                    return 2;
                case 0x20:
                case 0x22:
                case 0x58:
                case 0x68:
                case 0x70:
                case 0xB8:
                    return 4;
                case 0x28:
                    return 8;
                case 0x38:
                    return 16;
                case 0x48:
                    return 24;
                case 0xC0:
                case 0x80:
                case 0x82:
                case 0x88:
                case 0x8A:
                case 0x90:
                case 0x98:
                case 0xA0:
                    return -1;
                default:
                    return 0;
            }
        }

        public static PubBlock block (uint8[] d, int p) {
            var b = new PubBlock ();
            b.id = p < d.length ? d[p] : 0;
            b.type = p + 1 < d.length ? d[p + 1] : 0;
            b.data_off = p + 2;
            int len = block_length (b.type);
            if (len < 0) {
                b.var_len = true;
                uint32 l = r32 (d, b.data_off);
                if (l < 4 || l > d.length - b.data_off) l = uint32.max (4, (uint32) int.max (0, d.length - b.data_off));
                b.end = b.data_off + (int) l;
                b.data = 0;
            } else {
                b.end = b.data_off + len;
                if (len == 2) b.data = r16 (d, b.data_off);
                else if (len == 4) b.data = r32 (d, b.data_off);
                else if (len == 1) b.data = b.data_off < d.length ? d[b.data_off] : 0;
            }
            return b;
        }

        public static Gee.ArrayList<PubBlock> blocks (uint8[] d, int start, int end) {
            var list = new Gee.ArrayList<PubBlock> ();
            int p = start;
            int lim = int.min (end, d.length);
            while (p + 2 <= lim && list.size < 100000) {
                var b = block (d, p);
                list.add (b);
                if (b.end <= p) break;
                p = b.end;
            }
            return list;
        }

        private static Gee.ArrayList<PubBlock> children (uint8[] d, PubBlock b) {
            return blocks (d, b.data_off + 4, b.end);
        }

        public PubLayout (uint8[] contents, uint8[] quill) {
            this.contents = contents;
            this.quill = quill;
        }

        public void set_escher (uint8[] escher, uint8[] delay) {
            this.escher = escher;
            this.delay = delay;
        }

        public bool parse () {
            if (!parse_contents ()) return false;
            parse_quill ();
            parse_escher_store ();
            return width > 0 && height > 0;
        }

        private bool parse_contents () {
            var c = contents;
            if (c.length < 0x20) return false;
            int trailer = (int) r32 (c, 0x1A);
            if (trailer <= 0 || trailer + 4 > c.length) return false;
            int p = trailer + 4;
            int64 seq = -1;
            for (int part = 0; part < 3 && p + 2 < c.length; part++) {
                var b = block (c, p);
                if (b.type == 0x90) {
                    int q = b.data_off + 4;
                    while (q + 2 <= b.end && q + 2 <= c.length) {
                        var bb = block (c, q);
                        seq++;
                        if (bb.type == 0x88) {
                            int type = -1, off = -1;
                            uint32 parent = 0;
                            foreach (var s in children (c, bb)) {
                                if (s.id == 0x02) type = (int) s.data;
                                else if (s.id == 0x04) off = (int) s.data;
                                else if (s.id == 0x05) parent = s.data;
                            }
                            if (type >= 0 && off > 0 && off + 4 <= c.length) {
                                var r = new PubChunkRef ();
                                r.seq = (uint32) seq;
                                r.type = type;
                                r.offset = off;
                                r.parent = parent;
                                chunks.add (r);
                            }
                        }
                        if (bb.end <= q) break;
                        q = bb.end;
                    }
                }
                if (b.end <= p) break;
                p = b.end;
            }
            bool doc = false;
            foreach (var r in chunks) {
                switch (r.type) {
                    case 0x44:
                        doc = parse_document (r) || doc;
                        break;
                    case 0x43:
                        parse_page (r);
                        break;
                    case 0x5C:
                        parse_palette (r);
                        break;
                    case 0x01:
                    case 0x20:
                    case 0x30:
                    case 0x31:
                    case 0x10:
                        parse_shape (r);
                        break;
                    default:
                        break;
                }
            }
            foreach (var s in shapes.values) {
                if (s.chunk_type != 0x10 || s.cells_seq == 0) continue;
                foreach (var r in chunks) if (r.type == 0x63 && r.seq == s.cells_seq) parse_cells (r, s);
            }
            return doc;
        }

        private bool parse_document (PubChunkRef r) {
            var c = contents;
            int len = (int) r32 (c, r.offset);
            foreach (var b in blocks (c, r.offset + 4, r.offset + len)) {
                if (b.id == 0x12 && b.var_len) {
                    foreach (var s in children (c, b)) {
                        if (s.id == 0x01) width = s.data / EMU_PT;
                        else if (s.id == 0x02) height = s.data / EMU_PT;
                    }
                } else if (b.id == 0x02 && b.var_len) {
                    foreach (var s in children (c, b)) if (s.id == 0x00) page_order.add (s.data);
                }
            }
            return width > 0 && height > 0;
        }

        private void parse_page (PubChunkRef r) {
            var c = contents;
            int len = (int) r32 (c, r.offset);
            var pg = new PubPageInfo ();
            pg.seq = r.seq;
            foreach (var b in blocks (c, r.offset + 4, r.offset + len)) {
                if (b.id == 0x02 && b.var_len) {
                    foreach (var s in children (c, b)) {
                        if (s.type == 0x70) {
                            pg.shapes.add (s.data);
                            shape_page[s.data] = r.seq;
                        }
                    }
                } else if (b.id == 0x0E && b.type == 0xC0) {
                    for (int i = b.data_off + 4; i < b.end && i < c.length; i++) if (c[i] != 0) pg.master = true;
                } else if (b.id == 0x0D && !b.var_len) {
                    pg.applied = b.data;
                } else if (b.id == 0x0A && !b.var_len) {
                    pg.bg = b.data;
                    shape_page[b.data] = r.seq;
                }
            }
            pages[r.seq] = pg;
        }

        private void parse_palette (PubChunkRef r) {
            var c = contents;
            int len = (int) r32 (c, r.offset);
            foreach (var b in blocks (c, r.offset + 4, r.offset + len)) {
                if (b.type != 0xA0) continue;
                foreach (var s in children (c, b)) {
                    if (s.type == 0x88) {
                        uint32 v = 0;
                        foreach (var t in children (c, s)) if (t.id == 0x01) v = t.data;
                        palette.add (v & 0xFFFFFF);
                    } else if (s.type == 0x78) {
                        palette.add (0);
                    }
                }
            }
        }

        private void parse_shape (PubChunkRef r) {
            var c = contents;
            int len = (int) r32 (c, r.offset);
            var s = new PubShapeInfo ();
            s.seq = r.seq;
            s.chunk_type = r.type;
            foreach (var b in blocks (c, r.offset + 4, r.offset + len)) {
                switch (b.id) {
                    case 0x27:
                        s.text_id = (int) b.data;
                        break;
                    case 0x35:
                        if (r.type != 0x10) s.valign = (int) b.data;
                        break;
                    case 0x66:
                        if (r.type == 0x10) s.rows = (int) b.data;
                        break;
                    case 0x67:
                        if (r.type == 0x10) s.cols = (int) b.data;
                        break;
                    case 0x6B:
                        if (r.type == 0x10) s.cells_seq = b.data;
                        break;
                    case 0x6D:
                        if (r.type == 0x10) s.rowcol_off = b.data_off;
                        break;
                    default:
                        break;
                }
            }
            if (s.chunk_type == 0x10 && s.rowcol_off > 0 && s.rows > 0 && s.cols > 0 && s.rows < 1000 && s.cols < 1000) {
                int alen = (int) r32 (c, s.rowcol_off);
                foreach (var b in blocks (c, s.rowcol_off + 4, s.rowcol_off + alen)) {
                    if (b.id != 0 || !b.var_len) continue;
                    foreach (var sb in children (c, b)) {
                        if (sb.id != 0x02) continue;
                        if (s.col_w.size < s.cols) s.col_w.add (sb.data / EMU_PT);
                        else if (s.row_h.size < s.rows) s.row_h.add (sb.data / EMU_PT);
                    }
                }
            }
            shapes[r.seq] = s;
        }

        private void parse_cells (PubChunkRef r, PubShapeInfo s) {
            var c = contents;
            int len = (int) r32 (c, r.offset);
            foreach (var b in blocks (c, r.offset + 4, r.offset + len)) {
                if (b.id != 0x02 || !b.var_len) continue;
                foreach (var item in children (c, b)) {
                    if (item.id != 0 || !item.var_len) continue;
                    var ci = new PubCellInfo ();
                    foreach (var sb in children (c, item)) {
                        if (sb.id == 1) ci.r0 = (int) sb.data;
                        else if (sb.id == 2) ci.r1 = (int) sb.data;
                        else if (sb.id == 3) ci.c0 = (int) sb.data;
                        else if (sb.id == 4) ci.c1 = (int) sb.data;
                    }
                    s.cells.add (ci);
                }
            }
        }

        private PubCharStyle char_style (uint8[] d, int p) {
            var st = new PubCharStyle ();
            int len = (int) r32 (d, p);
            foreach (var b in blocks (d, p + 4, p + len)) {
                switch (b.id) {
                    case 0x02:
                        st.bold = 1;
                        break;
                    case 0x03:
                        st.italic = 1;
                        break;
                    case 0x1E:
                        st.underline = (b.data & 0xFF) != 0 ? 1 : 0;
                        break;
                    case 0x0C:
                        if (!b.var_len && b.data > 0) st.size = b.data / EMU_PT;
                        break;
                    case 0x2E:
                        if (!b.var_len) st.color = (int) b.data;
                        break;
                    case 0x44:
                        if (b.var_len) foreach (var s in children (d, b)) if (s.id == 0) {
                            st.color = (int) s.data;
                            break;
                        }
                        break;
                    case 0x24:
                        if (b.var_len) foreach (var s in children (d, b)) {
                            if (s.type == 0x88) {
                                var ss = block (d, s.data_off + 4);
                                if (ss.data_off < s.end) st.font = (int) ss.data;
                                break;
                            }
                        }
                        break;
                    case 0x0F:
                        if (!b.var_len) st.position = b.data == 1 ? 1 : (b.data == 2 ? 2 : 0);
                        break;
                    case 0x13:
                        st.caps = 2;
                        break;
                    case 0x14:
                        st.caps = 1;
                        break;
                    case 0x04:
                        st.outline = true;
                        break;
                    case 0x05:
                        st.shadow = true;
                        break;
                    case 0x16:
                    case 0x17:
                        st.emboss = true;
                        break;
                    default:
                        break;
                }
            }
            return st;
        }

        private PubParaStyle para_style (uint8[] d, int p) {
            var st = new PubParaStyle ();
            int len = (int) r32 (d, p);
            foreach (var b in blocks (d, p + 4, p + len)) {
                switch (b.id) {
                    case 0x04:
                        if (b.var_len) break;
                        switch (b.data & 0xFF) {
                            case 1: st.align = 2; break;
                            case 2: st.align = 1; break;
                            case 6: st.align = 3; break;
                            default: st.align = 0; break;
                        }
                        break;
                    case 0x19:
                        if (!b.var_len) st.default_char = (int) b.data;
                        break;
                    case 0x34:
                        if (b.var_len) break;
                        if ((b.data & 1) != 0) st.leading_pt = (b.data - 1) / 8.0 / EMU_PT;
                        else if ((b.data & 2) != 0) st.leading_mult = (b.data - 2) / 914400.0 * 72 / 96;
                        break;
                    case 0x12:
                        if (!b.var_len) st.before = b.data / EMU_PT;
                        break;
                    case 0x13:
                        if (!b.var_len) st.after = b.data / EMU_PT;
                        break;
                    case 0x0C:
                        if (!b.var_len) st.first = ((int32) b.data) / EMU_PT;
                        break;
                    case 0x0D:
                        if (!b.var_len) st.left = ((int32) b.data) / EMU_PT;
                        break;
                    case 0x0E:
                        if (!b.var_len) st.right = ((int32) b.data) / EMU_PT;
                        break;
                    case 0x08:
                        if (!b.var_len) st.drop_lines = (int) b.data;
                        break;
                    case 0x2D:
                        if (!b.var_len) st.drop_letters = (int) b.data;
                        break;
                    case 0x15:
                        if (!b.var_len) st.number_start = (int) b.data;
                        break;
                    case 0x57:
                        st.list = true;
                        if (b.var_len) foreach (var s in children (d, b)) if (s.id == 0x01 && !s.var_len) st.bullet = s.data;
                        break;
                    case 0x32:
                        if (b.var_len) foreach (var arr in children (d, b)) {
                            if (arr.id != 0x28 || !arr.var_len) continue;
                            foreach (var e in children (d, arr)) {
                                if (e.type != 0x88) continue;
                                var t = block (d, e.data_off + 4);
                                if (t.id == 0) st.tabs.add (((int32) t.data) / EMU_PT);
                            }
                        }
                        break;
                    default:
                        break;
                }
            }
            return st;
        }

        private class QRef {
            public string name;
            public int id;
            public int offset;
            public int length;
        }

        private void parse_quill () {
            var q = quill;
            var refs = new Gee.ArrayList<QRef> ();
            var seen = new Gee.HashSet<int> ();
            int lo = 0x18;
            while (lo >= 0 && lo + 8 <= q.length && !seen.contains (lo) && refs.size < 10000) {
                seen.add (lo);
                int n = r16 (q, lo + 2);
                uint32 next = r32 (q, lo + 4);
                int p = lo + 8;
                for (int i = 0; i < n && p + 24 <= q.length; i++) {
                    var r = new QRef ();
                    var sb = new StringBuilder ();
                    for (int k = 0; k < 4; k++) sb.append_c ((char) q[p + 2 + k]);
                    r.name = sb.str;
                    r.id = r16 (q, p + 6);
                    r.offset = (int) r32 (q, p + 16);
                    r.length = (int) r32 (q, p + 20);
                    if (r.offset >= 0 && r.offset <= q.length && r.length >= 0 && r.length <= q.length - r.offset) refs.add (r);
                    p += 24;
                }
                if (next == 0xFFFFFFFFu) break;
                lo = (int) next;
            }
            var lengths = new Gee.ArrayList<int> ();
            var ids = new Gee.ArrayList<uint32> ();
            var span_ends = new Gee.ArrayList<int> ();
            var span_styles = new Gee.ArrayList<PubCharStyle> ();
            var para_ends = new Gee.ArrayList<int> ();
            var para_styles = new Gee.ArrayList<PubParaStyle> ();
            QRef? text = null;
            int stsh = 0;
            var tcd = new Gee.HashMap<int, Gee.ArrayList<int>> ();
            foreach (var r in refs) {
                int o = r.offset;
                switch (r.name) {
                    case "TEXT":
                        text = r;
                        break;
                    case "STRS":
                        uint32 n = r32 (q, o);
                        int s = o + 4 + (int) r32 (q, o + 4);
                        for (uint32 j = 0; j < n && s + 4 <= q.length && j < 100000; j++) {
                            lengths.add ((int) r32 (q, s));
                            s += 4;
                        }
                        break;
                    case "SYID":
                        uint32 n = r32 (q, o + 4);
                        for (uint32 j = 0; j < n && o + 8 + 4 * (int) j + 4 <= q.length && j < 100000; j++) ids.add (r32 (q, o + 8 + 4 * (int) j));
                        break;
                    case "PL  ":
                        uint32 n = r32 (q, o);
                        int s = o + 12;
                        for (uint32 j = 0; j < n && s + 4 <= q.length && j < 10000; j++) {
                            int l = (int) r32 (q, s);
                            uint32 v = 0;
                            foreach (var b in blocks (q, s + 4, s + l)) if (b.id == 0x01) v = b.data;
                            text_colors.add (v);
                            if (l <= 0) break;
                            s += l;
                        }
                        break;
                    case "FDPC":
                    case "FDPP":
                        int n = r16 (q, o);
                        for (int j = 0; j < n && o + 8 + 4 * n + 2 * j + 2 <= q.length; j++) {
                            int end = (int) r32 (q, o + 8 + 4 * j);
                            int co = r16 (q, o + 8 + 4 * n + 2 * j);
                            if (r.name == "FDPC") {
                                span_ends.add (end);
                                span_styles.add (char_style (q, o + co));
                            } else {
                                para_ends.add (end);
                                para_styles.add (para_style (q, o + co));
                            }
                        }
                        break;
                    case "STSH":
                        if (stsh++ != 1) break;
                        uint32 n = uint32.min (r32 (q, o + 4), 10000);
                        for (uint32 j = 0; j < n; j++) {
                            int so = o + 20 + (int) r32 (q, o + 20 + 4 * (int) j) + 2;
                            if (so < 0 || so >= q.length) continue;
                            if (j % 2 == 0) default_chars.add (char_style (q, so));
                            else default_paras.add (para_style (q, so));
                        }
                        break;
                    case "FONT":
                        uint32 n = uint32.min (r32 (q, o + 4), 10000);
                        int s = o + 8 + 12 + 4 * (int) n;
                        for (uint32 j = 0; j < n && s + 2 <= q.length; j++) {
                            int nl = r16 (q, s);
                            s += 2;
                            fonts.add (nl > 0 ? PubReader.decode_utf16 (q, s, nl * 2) : "");
                            s += nl * 2 + 4;
                        }
                        break;
                    case "TCD ":
                        uint32 n = r32 (q, o) + 1;
                        var ends = new Gee.ArrayList<int> ();
                        for (uint32 j = 0; j < n && o + 0xC + 4 * (int) j + 4 <= q.length && j < 100000; j++) {
                            int v = (int) r32 (q, o + 0xC + 4 * (int) j);
                            if (j != n - 1) v += 2;
                            ends.add (v);
                        }
                        tcd[r.id] = ends;
                        break;
                    default:
                        break;
                }
            }
            if (text == null) return;
            int pos = text.offset;
            int bytes = 0;
            int si = 0, pi = 0;
            for (int j = 0; j < ids.size && j < lengths.size; j++) {
                var paras = new Gee.ArrayList<PubPara> ();
                var cur = new StringBuilder ();
                var spans = new Gee.ArrayList<PubSpan> ();
                for (int k = 0; k < lengths[j] && pos + 2 <= q.length; k++) {
                    uint u = (uint) q[pos] | ((uint) q[pos + 1] << 8);
                    pos += 2;
                    bytes += 2;
                    append_char (cur, u);
                    if (si < span_ends.size && bytes >= span_ends[si] - text.offset) {
                        if (cur.len > 0) spans.add (new PubSpan (cur.str, span_styles[si]));
                        cur.truncate (0);
                        si++;
                    }
                    if (pi < para_ends.size && bytes >= para_ends[pi] - text.offset) {
                        if (cur.len > 0) spans.add (new PubSpan (cur.str, si < span_styles.size ? span_styles[si] : new PubCharStyle ()));
                        cur.truncate (0);
                        var para = new PubPara (para_styles[pi]);
                        para.spans.add_all (spans);
                        paras.add (para);
                        spans = new Gee.ArrayList<PubSpan> ();
                        pi++;
                    }
                }
                if (cur.len > 0) spans.add (new PubSpan (cur.str, si < span_styles.size ? span_styles[si] : new PubCharStyle ()));
                if (spans.size > 0) {
                    var para = new PubPara (pi < para_styles.size ? para_styles[pi] : new PubParaStyle ());
                    para.spans.add_all (spans);
                    paras.add (para);
                }
                texts[ids[j]] = paras;
                if (tcd.has_key (j)) cell_ends[ids[j]] = tcd[j];
            }
            font_list = string.joinv (", ", fonts.to_array ());
        }

        private static void append_char (StringBuilder sb, uint u) {
            if (u == 0x0D) sb.append_c ('\r');
            else if (u == 0x0B || u == 0x0A) sb.append_unichar (0x2028);
            else if (u == 0x09) sb.append_c ('\t');
            else if (u == 0x1E) sb.append_unichar (0x2011);
            else if (u == 0x1F) sb.append_unichar (0x00AD);
            else if (u < 0x20 || (u >= 0xD800 && u <= 0xDFFF) || u == 0xFFFE || u == 0xFFFF) return;
            else sb.append_unichar ((unichar) u);
        }

        private void parse_escher_store () {
            var e = escher;
            int p = 0;
            while (p + 8 <= e.length) {
                uint16 t = r16 (e, p + 2);
                uint32 len = r32 (e, p + 4);
                if (t < 0xF000 || len > e.length - p - 8) return;
                if (t == 0xF000) {
                    int q = p + 8;
                    int end = p + 8 + (int) len;
                    while (q + 8 <= end) {
                        uint16 tt = r16 (e, q + 2);
                        uint32 ll = r32 (e, q + 4);
                        if (ll > end - q - 8) break;
                        if (tt == 0xF001) read_bstore (q + 8, q + 8 + (int) ll);
                        q += 8 + (int) ll;
                    }
                    return;
                }
                p += 8 + (int) len + (t == 0xF002 ? 4 : 0);
            }
        }

        private void read_bstore (int start, int end) {
            var e = escher;
            int p = start;
            int seq_delay = 0;
            while (p + 8 <= end) {
                uint16 t = r16 (e, p + 2);
                uint32 len = r32 (e, p + 4);
                if (len > end - p - 8) break;
                int body = p + 8;
                uint8[]? data = null;
                string ext = "";
                if (t == 0xF007 && len >= 36) {
                    uint32 size = r32 (e, body + 20);
                    uint32 fo = r32 (e, body + 28);
                    int name_len = e[body + 33];
                    bool has_uid = false;
                    for (int k = 2; k < 18; k++) if (e[body + k] != 0) has_uid = true;
                    int emb = body + 36 + name_len;
                    if (len > 36 + name_len && emb + 8 <= body + (int) len) {
                        data = blip_at (e, emb, out ext);
                    } else if (size > 0 && fo < delay.length) {
                        data = blip_at (delay, (int) fo, out ext);
                    } else if (has_uid) {
                        data = sequential_delay (seq_delay, out ext);
                    }
                    if (has_uid) seq_delay++;
                }
                blips.add (data != null ? new Bytes (data) : null);
                blip_ext.add (ext);
                p = body + (int) len;
            }
        }

        private uint8[]? sequential_delay (int index, out string ext) {
            ext = "";
            int p = 0, i = 0;
            while (p + 8 <= delay.length) {
                uint32 len = r32 (delay, p + 4);
                if (len > delay.length - p - 8) return null;
                if (i == index) return blip_at (delay, p, out ext);
                i++;
                p += 8 + (int) len;
            }
            return null;
        }

        private uint8[]? blip_at (uint8[] d, int p, out string ext) {
            ext = "";
            if (p + 8 > d.length) return null;
            uint16 inst = r16 (d, p) >> 4;
            uint16 t = r16 (d, p + 2);
            uint32 len = r32 (d, p + 4);
            if (len > d.length - p - 8) return null;
            int body = p + 8;
            int header = (inst & 1) == 1 ? 33 : 17;
            if (t == 0xF01A || t == 0xF01B || t == 0xF01C) {
                metafiles++;
                return null;
            }
            if (len <= header) return null;
            uint8[] payload = d[body + header:body + (int) len];
            switch (t) {
                case 0xF01D:
                case 0xF02A:
                    ext = "jpg";
                    return payload;
                case 0xF01E:
                    ext = "png";
                    return payload;
                case 0xF029:
                    ext = "tiff";
                    return payload;
                case 0xF01F:
                    var bmp = PubReader.dib_to_bmp (payload);
                    if (bmp.length == 0) return null;
                    ext = "bmp";
                    return bmp;
                default:
                    return null;
            }
        }

        private string? media_for (int pxid) {
            if (pxid <= 0 || pxid > blips.size) return null;
            if (media_ids.has_key (pxid)) return media_ids[pxid];
            var d = blips[pxid - 1];
            if (d == null) return null;
            string id = pub.add_media (d.get_data (), "picture." + blip_ext[pxid - 1]);
            media_ids[pxid] = id;
            return id;
        }

        private string color_ref (uint32 v) {
            uint type = (v >> 24) & 0xFF;
            uint32 rgb;
            if (type == 0x08) {
                uint idx = v & 0xFFFFFF;
                rgb = idx < palette.size ? palette[(int) idx] : 0;
            } else {
                rgb = v & 0xFFFFFF;
            }
            return "#%02x%02x%02x".printf (rgb & 0xFF, (rgb >> 8) & 0xFF, (rgb >> 16) & 0xFF);
        }

        private string text_color (int index) {
            if (index >= 0 && index < text_colors.size) return color_ref (text_colors[index]);
            return ColorRef.BLACK;
        }

        private class EscherRec {
            public int ver;
            public int inst;
            public int type;
            public int body;
            public int len;
            public int next;
        }

        private Gee.ArrayList<EscherRec> records (int start, int end) {
            var list = new Gee.ArrayList<EscherRec> ();
            var e = escher;
            int p = start;
            while (p + 8 <= end && p + 8 <= e.length) {
                var r = new EscherRec ();
                uint16 vi = r16 (e, p);
                r.ver = vi & 0xF;
                r.inst = vi >> 4;
                r.type = r16 (e, p + 2);
                r.len = (int) r32 (e, p + 4);
                r.body = p + 8;
                if (r.len < 0 || r.len > e.length - r.body) break;
                r.next = r.body + r.len + ((r.type == 0xF000 || r.type == 0xF002) ? 4 : 0);
                list.add (r);
                p = r.next;
            }
            return list;
        }

        private Gee.HashMap<int, uint32> values (EscherRec r, int skip) {
            var m = new Gee.HashMap<int, uint32> ();
            int p = r.body + skip;
            while (p + 6 <= r.body + r.len) {
                m[r16 (escher, p)] = r32 (escher, p + 2);
                p += 6;
            }
            return m;
        }

        private Gee.HashMap<int, uint32> fopt (EscherRec r, Gee.HashMap<int, int>? complex_at) {
            var m = new Gee.HashMap<int, uint32> ();
            int p = r.body;
            var cids = new Gee.ArrayList<int> ();
            for (int i = 0; i < r.inst && p + 6 <= r.body + r.len; i++) {
                int id = r16 (escher, p);
                m[id] = r32 (escher, p + 2);
                if ((id & 0x8000) != 0) cids.add (id);
                p += 6;
            }
            if (complex_at != null) {
                foreach (int id in cids) {
                    uint32 l = m[id];
                    if (l == 0) continue;
                    if (p + 6 > r.body + r.len) break;
                    complex_at[id] = p;
                    p += (int) l;
                }
            }
            return m;
        }

        private struct Coord {
            public int64 xs;
            public int64 ys;
            public int64 xe;
            public int64 ye;
        }

        public Publication build (DocSettings s) {
            pub = Publication.create (s, 0);
            var master = pub.masters[0];
            var ordered = new Gee.ArrayList<uint32> ();
            foreach (uint32 seq in page_order) if (pages.has_key (seq) && !ordered.contains (seq)) ordered.add (seq);
            foreach (uint32 seq in pages.keys) if (!ordered.contains (seq)) ordered.add (seq);
            var page_map = new Gee.HashMap<uint32, Page> ();
            uint32 master_seq = 0;
            foreach (uint32 seq in ordered) {
                var info = pages[seq];
                if (info.master) {
                    if (master_seq == 0) master_seq = seq;
                    continue;
                }
                if (seq == 0x10d || seq == 0x110 || seq == 0x113 || seq == 0x117) {
                    if (info.shapes.size == 0) continue;
                }
                page_map[seq] = pub.add_page (-1, "A");
            }
            if (page_map.size == 0) page_map[0] = pub.add_page (-1, "A");
            page_count = pub.pages.size;
            var placed = new Gee.HashMap<uint32, Item> ();
            var targets = new Gee.HashMap<uint32, Gee.ArrayList<Item>> ();
            foreach (var entry in page_map.entries) targets[entry.key] = entry.value.items;
            if (master_seq != 0) targets[master_seq] = master.items;
            foreach (var r in records (0, escher.length)) {
                if (r.type != 0xF002) continue;
                foreach (var g in records (r.body, r.body + r.len)) {
                    if (g.type != 0xF003) continue;
                    var parent_sys = Coord ();
                    var parent_abs = Coord ();
                    walk_group (g, parent_sys, parent_abs, targets, placed, 0);
                }
            }
            foreach (var entry in shapes.entries) {
                var si = entry.value;
                if (placed.has_key (si.seq) || !shape_page.has_key (si.seq)) continue;
                if (si.text_id >= 0 && texts.has_key (si.text_id) && !used_text.contains (si.text_id)) {
                    uint32 pseq = shape_page[si.seq];
                    if (!targets.has_key (pseq)) continue;
                    var mr = pub.margin_rect (0);
                    var t = make_text (si, mr.x, mr.y, mr.w, mr.h);
                    targets[pseq].add (t);
                }
            }
            foreach (var entry in texts.entries) {
                if (used_text.contains (entry.key)) continue;
                bool empty = true;
                foreach (var p in entry.value) foreach (var sp in p.spans) if (sp.text.strip () != "" && sp.text != "\r") empty = false;
                if (!empty) warnings.add (_("Some text stories are not placed on a page in the Publisher file and were left out."));
                if (!empty) break;
            }
            if (metafiles > 0) warnings.add (ngettext ("%d picture is a Windows metafile (EMF, WMF or PICT) and cannot be shown", "%d pictures are Windows metafiles (EMF, WMF or PICT) and cannot be shown", metafiles).printf (metafiles));
            if (custom_paths > 0) warnings.add (_("Freeform shapes are imported from their points; curved segments become straight lines."));
            return pub;
        }

        private void walk_group (EscherRec spgr, Coord parent_sys, Coord parent_abs, Gee.HashMap<uint32, Gee.ArrayList<Item>> targets, Gee.HashMap<uint32, Item> placed, int depth) {
            var sys = parent_sys;
            var abs = parent_abs;
            var kids = new Gee.ArrayList<Item> ();
            var kid_seqs = new Gee.ArrayList<uint32> ();
            foreach (var r in records (spgr.body, spgr.body + spgr.len)) {
                if (r.type == 0xF003) {
                    walk_group_into (r, sys, abs, targets, placed, depth + 1, kids, kid_seqs);
                } else if (r.type == 0xF004) {
                    uint32 seq;
                    bool leader;
                    var it = read_shape (r, ref sys, ref abs, out seq, out leader);
                    if (it != null) {
                        kids.add (it);
                        kid_seqs.add (seq);
                        placed[seq] = it;
                    }
                }
            }
            emit (kids, kid_seqs, targets);
        }

        private void walk_group_into (EscherRec spgr, Coord parent_sys, Coord parent_abs, Gee.HashMap<uint32, Gee.ArrayList<Item>> targets, Gee.HashMap<uint32, Item> placed, int depth, Gee.ArrayList<Item> out_items, Gee.ArrayList<uint32> out_seqs) {
            if (depth > 32) return;
            var recs = records (spgr.body, spgr.body + spgr.len);
            uint32 group_seq = 0;
            var sys = parent_sys;
            var abs = parent_abs;
            var kids = new Gee.ArrayList<Item> ();
            var kid_seqs = new Gee.ArrayList<uint32> ();
            bool first = true;
            foreach (var r in recs) {
                if (r.type == 0xF003) {
                    walk_group_into (r, sys, abs, targets, placed, depth + 1, kids, kid_seqs);
                } else if (r.type == 0xF004) {
                    uint32 seq;
                    bool leader;
                    var it = read_shape (r, ref sys, ref abs, out seq, out leader);
                    if (leader && first) {
                        group_seq = seq;
                        first = false;
                        continue;
                    }
                    first = false;
                    if (it != null) {
                        kids.add (it);
                        kid_seqs.add (seq);
                        placed[seq] = it;
                    }
                }
            }
            if (kids.size == 0) return;
            if (kids.size == 1) {
                out_items.add (kids[0]);
                out_seqs.add (group_seq != 0 ? group_seq : kid_seqs[0]);
                return;
            }
            var g = new GroupItem ();
            g.id = pub.next_id ();
            g.layer = pub.default_layer ().id;
            g.fill = new Fill ();
            g.stroke = new Stroke ();
            g.children.add_all (kids);
            g.fit_children ();
            out_items.add (g);
            out_seqs.add (group_seq != 0 ? group_seq : kid_seqs[0]);
        }

        private void emit (Gee.ArrayList<Item> items, Gee.ArrayList<uint32> seqs, Gee.HashMap<uint32, Gee.ArrayList<Item>> targets) {
            for (int i = 0; i < items.size; i++) {
                uint32 seq = seqs[i];
                if (!shape_page.has_key (seq)) continue;
                uint32 pseq = shape_page[seq];
                if (!targets.has_key (pseq)) continue;
                bool is_bg = false;
                if (pages.has_key (pseq) && pages[pseq].bg == seq) is_bg = true;
                if (is_bg) targets[pseq].insert (0, items[i]);
                else targets[pseq].add (items[i]);
            }
        }

        private Item? read_shape (EscherRec sp, ref Coord sys, ref Coord abs, out uint32 seq, out bool leader) {
            seq = 0;
            leader = false;
            int mso = 1;
            uint32 flags = 0;
            EscherRec? anchor = null, data = null, opt = null, tert = null;
            bool defines = false;
            var this_sys = sys;
            foreach (var r in records (sp.body, sp.body + sp.len)) {
                switch (r.type) {
                    case 0xF009:
                        sys.xs = (int32) r32 (escher, r.body);
                        sys.ys = (int32) r32 (escher, r.body + 4);
                        sys.xe = (int32) r32 (escher, r.body + 8);
                        sys.ye = (int32) r32 (escher, r.body + 12);
                        if (sys.xs > sys.xe) {
                            var t = sys.xs;
                            sys.xs = sys.xe;
                            sys.xe = t;
                        }
                        if (sys.ys > sys.ye) {
                            var t = sys.ys;
                            sys.ys = sys.ye;
                            sys.ye = t;
                        }
                        defines = true;
                        break;
                    case 0xF00A:
                        mso = r.inst;
                        flags = r32 (escher, r.body + 4);
                        leader = (flags & 0x1) != 0;
                        break;
                    case 0xF010:
                    case 0xF00F:
                        anchor = r;
                        break;
                    case 0xF011:
                        data = r;
                        break;
                    case 0xF00B:
                        opt = r;
                        break;
                    case 0xF122:
                        tert = r;
                        break;
                    default:
                        break;
                }
            }
            if (data == null) return null;
            var dv = values (data, 4);
            if (!dv.has_key (0x6801)) return null;
            seq = dv[0x6801];
            if (anchor == null && !leader) return null;
            var complex = new Gee.HashMap<int, int> ();
            var fo = opt != null ? fopt (opt, complex) : new Gee.HashMap<int, uint32> ();
            var tv = tert != null ? fopt (tert, null) : new Gee.HashMap<int, uint32> ();
            double rotation = 0;
            bool rot90 = false;
            if (fo.has_key (0x0004)) {
                rotation = ((int32) fo[0x0004]) / 65536.0;
                rotation = rotation - 360 * Math.floor (rotation / 360);
                rot90 = (rotation >= 45 && rotation < 135) || (rotation >= 225 && rotation < 315);
            }
            if (anchor == null) return null;
            Coord a = Coord ();
            if (anchor.type == 0xF010) {
                var av = values (anchor, 4);
                a.xs = av.has_key (0x2001) ? (int32) av[0x2001] : 0;
                a.ys = av.has_key (0x2002) ? (int32) av[0x2002] : 0;
                a.xe = av.has_key (0x2003) ? (int32) av[0x2003] : 0;
                a.ye = av.has_key (0x2004) ? (int32) av[0x2004] : 0;
            } else {
                int64 cw = this_sys.xe - this_sys.xs;
                int64 ch = this_sys.ye - this_sys.ys;
                if (cw == 0) cw = 1;
                if (ch == 0) ch = 1;
                double sx = (double) (abs.xe - abs.xs) / cw;
                double sy = (double) (abs.ye - abs.ys) / ch;
                a.xs = (int64) (((int32) r32 (escher, anchor.body) - this_sys.xs) * sx + abs.xs);
                a.ys = (int64) (((int32) r32 (escher, anchor.body + 4) - this_sys.ys) * sy + abs.ys);
                a.xe = (int64) (((int32) r32 (escher, anchor.body + 8) - this_sys.xs) * sx + abs.xs);
                a.ye = (int64) (((int32) r32 (escher, anchor.body + 12) - this_sys.ys) * sy + abs.ys);
            }
            if (rot90) {
                int64 w0 = a.xe - a.xs, h0 = a.ye - a.ys;
                int64 cx = a.xs + w0 / 2, cy = a.ys + h0 / 2;
                a.xs = cx - h0 / 2;
                a.ys = cy - w0 / 2;
                a.xe = a.xs + h0;
                a.ye = a.ys + w0;
            }
            if (defines) abs = a;
            if (leader) return null;
            double x = a.xs / EMU_PT + width / 2;
            double y = a.ys / EMU_PT + height / 2;
            double w = (a.xe - a.xs) / EMU_PT;
            double h = (a.ye - a.ys) / EMU_PT;
            if (w < 0) {
                x += w;
                w = -w;
            }
            if (h < 0) {
                y += h;
                h = -h;
            }
            PubShapeInfo? si = shapes.has_key (seq) ? shapes[seq] : null;
            Item item;
            int pxid = fo.has_key (0x4104) ? (int) fo[0x4104] : 0;
            if (si != null && si.chunk_type == 0x10 && si.rows > 0 && si.cols > 0) {
                item = make_table (si, x, y, w, h);
            } else if (si != null && si.text_id >= 0 && texts.has_key (si.text_id) && !used_text.contains (si.text_id)) {
                var t = make_text (si, x, y, w, h);
                if (fo.has_key (0x0081)) t.inset_left = fo[0x0081] / EMU_PT;
                if (fo.has_key (0x0082)) t.inset_top = fo[0x0082] / EMU_PT;
                if (fo.has_key (0x0083)) t.inset_right = fo[0x0083] / EMU_PT;
                if (fo.has_key (0x0084)) t.inset_bottom = fo[0x0084] / EMU_PT;
                if (tv.has_key (0x008C) && tv[0x008C] > 1 && tv[0x008C] < 64) t.columns = (int) tv[0x008C];
                if (tv.has_key (0x008D)) t.gutter = tv[0x008D] / EMU_PT;
                item = t;
            } else if (pxid > 0) {
                var im = new ImageFrame ();
                im.id = pub.next_id ();
                im.fit = FitMode.STRETCH;
                string? mid = media_for (pxid);
                if (mid != null) {
                    im.media = mid;
                    placed_images++;
                }
                if (fo.has_key (0x0109)) im.brightness = (((int32) fo[0x0109]) / 32768.0).clamp (-1, 1);
                if (fo.has_key (0x0108)) {
                    double cv = fo[0x0108] / 65536.0;
                    im.contrast = (cv >= 1 ? 1 - 1 / cv : cv - 1).clamp (-1, 1);
                }
                item = im;
            } else {
                item = make_shape (mso, fo, complex, w, h);
                placed_shapes++;
            }
            item.x = x;
            item.y = y;
            item.w = double.max (w, 0.01);
            item.h = double.max (h, 0.01);
            if (item.id == 0) item.id = pub.next_id ();
            item.layer = pub.default_layer ().id;
            item.rotation = Math.fabs (rotation) < 1e-6 ? 0 : rotation;
            if (!(item is ShapeItem && ((ShapeItem) item).shape == ShapeKind.LINE)) {
                item.flip_h = (flags & 0x40) != 0;
                item.flip_v = (flags & 0x80) != 0;
            }
            if (!(item is TableItem)) apply_fill_line (item, fo, tv);
            apply_shadow (item, fo);
            return item;
        }

        private void apply_fill_line (Item it, Gee.HashMap<int, uint32> fo, Gee.HashMap<int, uint32> tv) {
            uint32 fill_type = fo.has_key (0x0180) ? fo[0x0180] : 0;
            bool filled = true;
            if (fo.has_key (0x01BF) && (fo[0x01BF] & 0xF0) == 0 && fill_type == 0) filled = false;
            if (!fo.has_key (0x0181) && fill_type == 0) filled = false;
            if (filled && fill_type == 0) {
                it.fill = new Fill.solid (color_ref (fo[0x0181]));
                if (fo.has_key (0x0182)) {
                    double op = fo[0x0182] / 65536.0;
                    if (op < 0.999) it.opacity = op.clamp (0, 1);
                }
            } else if (filled && fill_type >= 4 && fill_type <= 8) {
                string c1 = fo.has_key (0x0181) ? color_ref (fo[0x0181]) : "#ffffff";
                string c2 = fo.has_key (0x0183) ? color_ref (fo[0x0183]) : "#ffffff";
                int angle = fo.has_key (0x018B) ? ((int32) fo[0x018B]) >> 16 : 0;
                int focus = fo.has_key (0x018C) ? (int) (int16) (fo[0x018C] & 0xFFFF) : 0;
                var f = new Fill.linear (focus == 100 ? c2 : c1, focus == 100 ? c1 : c2, 90 + angle);
                if (fill_type == 5 || fill_type == 6) f.kind = FillKind.RADIAL;
                it.fill = f;
            } else if (filled && (fill_type == 2 || fill_type == 3) && fo.has_key (0x4186)) {
                string? mid = media_for ((int) fo[0x4186]);
                if (mid != null) {
                    var f = new Fill ();
                    f.kind = FillKind.PICTURE;
                    f.media = mid;
                    f.tile = fill_type == 2;
                    it.fill = f;
                } else {
                    it.fill = new Fill ();
                }
            } else if (filled && fill_type == 1) {
                it.fill = new Fill.solid (fo.has_key (0x0181) ? color_ref (fo[0x0181]) : ColorRef.PAPER);
            } else {
                it.fill = new Fill ();
            }
            bool line = false;
            if (fo.has_key (0x01FF)) {
                uint32 lf = fo[0x01FF];
                line = !(((lf & (1 << 19)) != 0) && (lf & (1 << 3)) == 0);
                if (fo.has_key (0x017F)) {
                    uint32 gf = fo[0x017F];
                    if ((gf & (1 << 12)) != 0 && (gf & (1 << 28)) == 0) line = false;
                }
            }
            var s = new Stroke ();
            if (line && fo.has_key (0x01C0)) {
                s.color = color_ref (fo[0x01C0]);
                s.width = (fo.has_key (0x01CB) ? fo[0x01CB] : 9525) / EMU_PT;
            } else if (line && tv.has_key (0x01FF)) {
                uint32 tl = tv[0x01FF];
                bool any = !(((tl & (1 << 19)) != 0) && (tl & (1 << 3)) == 0);
                if (any) {
                    int[] colors = { 0x0580, 0x05C0, 0x0600, 0x0540 };
                    int[] widths = { 0x058B, 0x05CB, 0x060B, 0x054B };
                    int[] bools = { 0x05BF, 0x05FF, 0x063F, 0x057F };
                    for (int k = 0; k < 4; k++) {
                        if (!tv.has_key (colors[k])) continue;
                        if (tv.has_key (bools[k])) {
                            uint32 bf = tv[bools[k]];
                            if (((bf & (1 << 19)) != 0) && (bf & (1 << 3)) == 0) continue;
                        }
                        s.color = color_ref (tv[colors[k]]);
                        s.width = (tv.has_key (widths[k]) ? tv[widths[k]] : 9525) / EMU_PT;
                        break;
                    }
                }
            }
            if (s.color != ColorRef.NONE && s.width <= 0) s.width = 0.75;
            if (fo.has_key (0x01CE)) {
                switch (fo[0x01CE]) {
                    case 0: s.dash = DashKind.SOLID; break;
                    case 2:
                    case 5: s.dash = DashKind.DOT; break;
                    case 3:
                    case 4:
                    case 8:
                    case 9:
                    case 10: s.dash = DashKind.DASH_DOT; break;
                    default: s.dash = DashKind.DASH; break;
                }
            }
            if (fo.has_key (0x01D0) && fo[0x01D0] != 0) s.arrow_start = 1;
            if (fo.has_key (0x01D1) && fo[0x01D1] != 0) s.arrow_end = 1;
            it.stroke = s;
        }

        private void apply_shadow (Item it, Gee.HashMap<int, uint32> fo) {
            if (!fo.has_key (0x023F)) return;
            uint32 f = fo[0x023F];
            if ((f & (1 << 17)) == 0 || (f & (1 << 1)) == 0) return;
            it.shadow.enabled = true;
            it.shadow.dx = (fo.has_key (0x0205) ? (int32) fo[0x0205] : 0x6338) / EMU_PT;
            it.shadow.dy = (fo.has_key (0x0206) ? (int32) fo[0x0206] : 0x6338) / EMU_PT;
            it.shadow.blur = 0;
            it.shadow.color = fo.has_key (0x0201) ? color_ref (fo[0x0201]) : "#808080";
            it.shadow.opacity = fo.has_key (0x0204) ? (fo[0x0204] / 65536.0).clamp (0, 1) : 1;
        }

        private static string? preset_for (int mso) {
            switch (mso) {
                case 4: return "diamond";
                case 5: return "triangle";
                case 6: return "right-triangle";
                case 7: return "parallelogram";
                case 8: return "trapezoid";
                case 9: return "hexagon";
                case 10: return "octagon";
                case 11: return "cross";
                case 12: return "star-5";
                case 13: return "arrow-right";
                case 15: return "home-plate";
                case 16: return "cube";
                case 22: return "can";
                case 55: return "chevron";
                case 56: return "pentagon";
                case 58: return "star-8";
                case 59: return "star-16";
                case 60: return "star-32";
                case 61: return "callout-rect";
                case 62: return "callout-rounded";
                case 63: return "callout-oval";
                case 64: return "wave";
                case 66: return "arrow-left";
                case 67: return "arrow-down";
                case 68: return "arrow-up";
                case 69: return "arrow-left-right";
                case 70: return "arrow-up-down";
                case 71: return "explosion-1";
                case 72: return "explosion-2";
                case 73: return "lightning";
                case 74: return "heart";
                case 76: return "arrow-quad";
                case 92: return "star-24";
                case 94: return "arrow-notched";
                case 109: return "flow-process";
                case 110: return "flow-decision";
                case 111: return "flow-data";
                case 114: return "flow-document";
                case 116: return "flow-terminator";
                case 117: return "flow-preparation";
                case 118: return "flow-manual-input";
                case 119: return "flow-manual-operation";
                case 120: return "flow-connector";
                case 121: return "flow-card";
                case 127: return "flow-extract";
                case 128: return "flow-merge";
                case 134: return "flow-display";
                case 135: return "flow-delay";
                case 177: return "flow-off-page";
                case 183: return "sun";
                case 184: return "moon";
                case 187: return "star-4";
                case 188: return "double-wave";
                default: return null;
            }
        }

        private ShapeItem make_shape (int mso, Gee.HashMap<int, uint32> fo, Gee.HashMap<int, int> complex, double w, double h) {
            ShapeItem s;
            if (mso == 20 || mso == 32 || mso == 33 || mso == 34 || mso == 38) {
                s = new ShapeItem (ShapeKind.LINE);
                return s;
            }
            if (mso == 3) return new ShapeItem (ShapeKind.ELLIPSE);
            if (mso == 2) {
                s = new ShapeItem (ShapeKind.RECT);
                double adj = fo.has_key (0x0147) ? ((int32) fo[0x0147]) / 21600.0 : 3600 / 21600.0;
                s.corner = CornerKind.ROUNDED;
                s.corner_radius = double.min (w, h) * adj.clamp (0, 0.5);
                return s;
            }
            string? preset = preset_for (mso);
            if (preset != null) {
                s = new ShapeItem (ShapeKind.PATH);
                s.closed = true;
                s.points.add_all (ShapeLib.points (preset));
                return s;
            }
            if (complex.has_key (0xC145)) {
                var pts = vertices (complex[0xC145], fo.has_key (0x0142) ? (int) fo[0x0142] : 21600, fo.has_key (0x0143) ? (int) fo[0x0143] : 21600);
                if (pts.size >= 2) {
                    s = new ShapeItem (ShapeKind.PATH);
                    s.closed = fo.has_key (0x0180) || (fo.has_key (0x01BF) && (fo[0x01BF] & 0x10) != 0);
                    s.points.add_all (pts);
                    custom_paths++;
                    return s;
                }
            }
            return new ShapeItem (ShapeKind.RECT);
        }

        private Gee.ArrayList<Point?> vertices (int p, int gr, int gb) {
            var list = new Gee.ArrayList<Point?> ();
            int n = r16 (escher, p);
            int es = r16 (escher, p + 4);
            if (es == 0xFFF0) es = 4;
            if (es != 4 && es != 8) return list;
            if (gr <= 0) gr = 21600;
            if (gb <= 0) gb = 21600;
            int q = p + 6;
            for (int i = 0; i < n && q + es <= escher.length && i < 10000; i++) {
                double vx, vy;
                if (es == 4) {
                    vx = (int16) r16 (escher, q);
                    vy = (int16) r16 (escher, q + 2);
                } else {
                    vx = (int32) r32 (escher, q);
                    vy = (int32) r32 (escher, q + 4);
                }
                list.add (Point ((vx / gr).clamp (-1, 2), (vy / gb).clamp (-1, 2)));
                q += es;
            }
            return list;
        }

        private CharFormat char_format (PubCharStyle st, PubCharStyle? base_style) {
            var f = new CharFormat ();
            PubCharStyle[] layers = base_style != null ? new PubCharStyle[] { base_style, st } : new PubCharStyle[] { st };
            foreach (var l in layers) {
                if (l.bold >= 0) f.bold = l.bold;
                if (l.italic >= 0) f.italic = l.italic;
                if (l.underline >= 0) f.underline = l.underline;
                if (!l.size.is_nan ()) f.size = l.size;
                if (l.color >= 0) f.color = text_color (l.color);
                if (l.font >= 0 && l.font < fonts.size && fonts[l.font] != "") f.font = fonts[l.font];
                if (l.position >= 0) f.position = l.position;
                if (l.caps >= 0) f.caps = l.caps;
                if (l.outline) {
                    f.outline_color = ColorRef.BLACK;
                    f.outline_width = 0.5;
                }
                if (l.shadow) f.text_shadow = 1;
                if (l.emboss) f.emboss = 1;
            }
            if (f.bold < 0) f.bold = 0;
            if (f.italic < 0) f.italic = 0;
            if (f.color == null) f.color = ColorRef.BLACK;
            return f;
        }

        private ParaFormat para_format (PubParaStyle st, double size) {
            var f = new ParaFormat ();
            PubParaStyle[] layers = default_paras.size > 0 ? new PubParaStyle[] { default_paras[0], st } : new PubParaStyle[] { st };
            foreach (var l in layers) {
                if (l.align >= 0) f.align = l.align;
                if (!l.leading_pt.is_nan ()) f.leading = l.leading_pt;
                else if (!l.leading_mult.is_nan ()) f.leading = Math.fabs (l.leading_mult - 1) < 0.01 ? 0 : l.leading_mult * 1.2 * size;
                if (!l.before.is_nan ()) f.space_before = l.before;
                if (!l.after.is_nan ()) f.space_after = l.after;
                if (!l.left.is_nan ()) f.left_indent = l.left;
                if (!l.right.is_nan ()) f.right_indent = l.right;
                if (!l.first.is_nan ()) f.first_indent = l.first;
                if (l.drop_lines > 1) {
                    f.drop_lines = l.drop_lines;
                    f.drop_chars = int.max (1, l.drop_letters);
                }
                if (l.list) {
                    if (l.bullet != 0) {
                        f.list_type = 1;
                        f.bullet = ((unichar) l.bullet).to_string ();
                    } else {
                        f.list_type = 2;
                        if (l.number_start > 0) f.number_start = l.number_start;
                    }
                }
                if (l.tabs.size > 0) {
                    var ts = new Gee.ArrayList<TabStop> ();
                    foreach (var t in l.tabs) ts.add (new TabStop (t));
                    f.tabs = TabStop.serialize (ts);
                }
            }
            return f;
        }

        private void fill_story (Story story, Gee.List<PubPara> paras) {
            story.paras.clear ();
            foreach (var pp in paras) {
                var para = new Paragraph ();
                PubCharStyle? base_style = null;
                int dc = pp.style.default_char;
                if (dc >= 0 && dc < default_chars.size) base_style = default_chars[dc];
                else if (default_chars.size > 0) base_style = default_chars[0];
                double size = 10;
                var cur = new Gee.ArrayList<Run> ();
                foreach (var sp in pp.spans) {
                    string t = sp.text.replace ("\r", "");
                    if (t == "") continue;
                    var run = new Run (t);
                    run.fmt = char_format (sp.style, base_style);
                    if (!run.fmt.size.is_nan ()) size = run.fmt.size;
                    cur.add (run);
                }
                para.fmt = para_format (pp.style, size);
                para.runs.clear ();
                para.runs.add_all (cur);
                if (para.runs.size == 0) {
                    var r = new Run ("");
                    r.fmt = char_format (new PubCharStyle (), base_style);
                    para.runs.add (r);
                }
                story.paras.add (para);
            }
            if (story.paras.size == 0) story.paras.add (new Paragraph.with_text (""));
        }

        private TextFrame make_text (PubShapeInfo si, double x, double y, double w, double h) {
            var story = pub.new_story ();
            fill_story (story, texts[si.text_id]);
            used_text.add (si.text_id);
            var t = pub.add_text_frame (new Gee.ArrayList<Item> (), x, y, w, h, story);
            t.inset_left = 2.88;
            t.inset_right = 2.88;
            t.inset_top = 2.88;
            t.inset_bottom = 2.88;
            if (si.valign == 1) t.valign = 1;
            else if (si.valign == 2) t.valign = 2;
            placed_text++;
            return t;
        }

        private TableItem make_table (PubShapeInfo si, double x, double y, double w, double h) {
            var tb = new TableItem (si.rows, si.cols);
            tb.id = pub.next_id ();
            tb.x = x;
            tb.y = y;
            tb.w = w;
            tb.h = h;
            tb.cells.clear ();
            for (int r = 0; r < si.rows; r++) {
                var row = new Gee.ArrayList<Cell> ();
                for (int c = 0; c < si.cols; c++) row.add (new Cell (pub.next_id ()));
                tb.cells.add (row);
            }
            double sw = 0, sh = 0;
            foreach (var v in si.col_w) sw += v;
            foreach (var v in si.row_h) sh += v;
            for (int c = 0; c < si.cols; c++) tb.col_w.add (c < si.col_w.size && sw > 0 ? si.col_w[c] * w / sw : w / si.cols);
            for (int r = 0; r < si.rows; r++) tb.row_h.add (r < si.row_h.size && sh > 0 ? si.row_h[r] * h / sh : h / si.rows);
            tb.header_rows = 0;
            tb.border_color = ColorRef.BLACK;
            tb.border_width = 0.5;
            var cells = new Gee.ArrayList<PubCellInfo> ();
            if (si.cells.size > 0) {
                cells.add_all (si.cells);
            } else {
                for (int r = 0; r < si.rows; r++) for (int c = 0; c < si.cols; c++) {
                    var ci = new PubCellInfo ();
                    ci.r0 = ci.r1 = r;
                    ci.c0 = ci.c1 = c;
                    cells.add (ci);
                }
            }
            foreach (var ci in cells) {
                if (ci.r0 < 0 || ci.c0 < 0 || ci.r0 >= si.rows || ci.c0 >= si.cols) continue;
                int rs = int.max (1, int.min (si.rows, ci.r1 + 1) - ci.r0);
                int cs = int.max (1, int.min (si.cols, ci.c1 + 1) - ci.c0);
                if (rs > 1 || cs > 1) {
                    tb.cells[ci.r0][ci.c0].row_span = rs;
                    tb.cells[ci.r0][ci.c0].col_span = cs;
                    for (int r = ci.r0; r < ci.r0 + rs; r++) for (int c = ci.c0; c < ci.c0 + cs; c++) if (r != ci.r0 || c != ci.c0) tb.cells[r][c].covered = true;
                }
            }
            if (si.text_id >= 0 && texts.has_key (si.text_id)) {
                var paras = texts[si.text_id];
                used_text.add (si.text_id);
                var ends = cell_ends.has_key (si.text_id) ? cell_ends[si.text_id] : new Gee.ArrayList<int> ();
                int cell = 0, first = 0, offset = 1;
                for (int p = 0; p < paras.size; p++) {
                    foreach (var sp in paras[p].spans) offset += sp.text.char_count ();
                    bool close = ends.size > 0 ? (cell < ends.size && offset >= ends[cell]) : true;
                    if (close || p == paras.size - 1) {
                        if (cell < cells.size) {
                            var ci = cells[cell];
                            if (ci.r0 < si.rows && ci.c0 < si.cols && ci.r0 >= 0 && ci.c0 >= 0) fill_story (tb.cells[ci.r0][ci.c0].story, paras.slice (first, p + 1));
                        }
                        cell++;
                        first = p + 1;
                    }
                }
            }
            placed_tables++;
            return tb;
        }
    }
}
