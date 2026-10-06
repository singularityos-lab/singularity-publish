namespace Singularity.Apps.Publish {

    public class ImportedText {
        public Gee.ArrayList<Paragraph> paragraphs = new Gee.ArrayList<Paragraph> ();
        public StyleSheet styles = new StyleSheet ();
        public Gee.ArrayList<string> media_names = new Gee.ArrayList<string> ();
        public Gee.ArrayList<Bytes> media = new Gee.ArrayList<Bytes> ();
        public string format = "";

        public string plain_text () {
            var sb = new StringBuilder ();
            for (int i = 0; i < paragraphs.size; i++) {
                if (i > 0) sb.append ("\n");
                sb.append (paragraphs[i].text ());
            }
            return sb.str;
        }
    }

    public class TextImport {
        public static string[] suffixes () {
            return { "docx", "odt", "rtf", "txt", "text", "md", "csv" };
        }

        public static ImportedText read (string path) throws Error {
            uint8[] data;
            FileUtils.get_data (path, out data);
            return read_data (data, Path.get_basename (path));
        }

        public static ImportedText read_data (uint8[] data, string name) throws Error {
            string low = name.down ();
            if (data.length >= 8 && data[0] == 0xD0 && data[1] == 0xCF && data[2] == 0x11 && data[3] == 0xE0) throw new FormatError.UNSUPPORTED (_("This is a legacy binary Word document (.doc). Save it as .docx, .odt or .rtf and insert that file instead."));
            if (data.length >= 4 && data[0] == 'P' && data[1] == 'K') {
                var zip = new ZipReader (data);
                if (zip.has ("word/document.xml")) return read_docx (zip);
                if (zip.has ("content.xml")) return read_odt (zip);
                throw new FormatError.INVALID (_("The file is a ZIP archive but not a Word or OpenDocument text."));
            }
            string head = Bin.head (data, 16);
            if (head.has_prefix ("{\\rtf") || low.has_suffix (".rtf")) return read_rtf (decode_text (data));
            return read_txt (decode_text (data));
        }

        public static string decode_text (uint8[] data) {
            if (data.length >= 3 && data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF) return ((string) data[3:data.length]).make_valid ();
            if (data.length >= 2 && ((data[0] == 0xFF && data[1] == 0xFE) || (data[0] == 0xFE && data[1] == 0xFF))) {
                bool le = data[0] == 0xFF;
                var sb = new StringBuilder ();
                for (int i = 2; i + 1 < data.length; i += 2) {
                    uint u = le ? ((uint) data[i] | ((uint) data[i + 1] << 8)) : (((uint) data[i] << 8) | (uint) data[i + 1]);
                    if (u >= 0xD800 && u <= 0xDBFF && i + 3 < data.length) {
                        uint lo = le ? ((uint) data[i + 2] | ((uint) data[i + 3] << 8)) : (((uint) data[i + 2] << 8) | (uint) data[i + 3]);
                        sb.append_unichar ((unichar) (0x10000 + ((u - 0xD800) << 10) + (lo - 0xDC00)));
                        i += 2;
                        continue;
                    }
                    sb.append_unichar ((unichar) u);
                }
                return sb.str;
            }
            var copy = new uint8[data.length + 1];
            Memory.copy (copy, data, data.length);
            copy[data.length] = 0;
            string s = (string) copy;
            if (s.validate ()) return s;
            var sb = new StringBuilder ();
            foreach (uint8 b in data) sb.append_unichar (cp1252 (b));
            return sb.str;
        }

        public static unichar cp1252 (uint8 b) {
            unichar[] high = { 0x20AC, 0x81, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x8D, 0x017D, 0x8F, 0x90, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x9D, 0x017E, 0x0178 };
            if (b >= 0x80 && b < 0xA0) return high[b - 0x80];
            return (unichar) b;
        }

        public static ImportedText read_txt (string text) {
            var t = new ImportedText ();
            t.format = "txt";
            foreach (string line in text.replace ("\r\n", "\n").replace ("\r", "\n").split ("\n")) t.paragraphs.add (new Paragraph.with_text (line.replace ("\f", "")));
            while (t.paragraphs.size > 1 && t.paragraphs[t.paragraphs.size - 1].length () == 0) t.paragraphs.remove_at (t.paragraphs.size - 1);
            return t;
        }

        private static string style_name_fix (string n) {
            string l = n.down ();
            if (l.has_prefix ("heading ")) return "Heading " + n.substring (8);
            if (l == "title") return "Title";
            if (l == "subtitle") return "Subtitle";
            if (l == "caption") return "Caption";
            if (l == "list paragraph") return "List Paragraph";
            if (l == "normal") return "Normal";
            return n;
        }

        private static double twip (string? v, double fallback = double.NAN) {
            if (v == null) return fallback;
            return Units.parse_num (v, 0) / 20.0;
        }

        private static bool on_off (Xml.Node* n) {
            string? v = XmlIn.attr_any (n, "val");
            return v == null || (v != "0" && v != "false" && v != "off");
        }

        private static void docx_rpr (Xml.Node* rpr, CharFormat f) {
            if (rpr == null) return;
            foreach (var c in XmlIn.elements (rpr)) {
                switch (c->name) {
                    case "rFonts":
                        string? fnt = XmlIn.attr_any (c, "ascii") ?? XmlIn.attr_any (c, "hAnsi");
                        if (fnt != null) f.font = fnt;
                        break;
                    case "sz":
                        f.size = Units.parse_num (XmlIn.attr_any (c, "val") ?? "22", 22) / 2.0;
                        break;
                    case "b":
                        f.bold = on_off (c) ? 1 : 0;
                        break;
                    case "i":
                        f.italic = on_off (c) ? 1 : 0;
                        break;
                    case "u":
                        string u = XmlIn.attr_any (c, "val") ?? "single";
                        f.underline = u == "none" ? 0 : 1;
                        break;
                    case "strike":
                    case "dstrike":
                        f.strike = on_off (c) ? 1 : 0;
                        break;
                    case "caps":
                        if (on_off (c)) f.caps = 1;
                        break;
                    case "smallCaps":
                        if (on_off (c)) f.caps = 2;
                        break;
                    case "color":
                        string col = XmlIn.attr_any (c, "val") ?? "auto";
                        if (col != "auto" && col.length == 6) f.color = "#" + col.down ();
                        break;
                    case "vertAlign":
                        string va = XmlIn.attr_any (c, "val") ?? "";
                        f.position = va == "superscript" ? 1 : (va == "subscript" ? 2 : 0);
                        break;
                    case "spacing":
                        if (!f.size.is_nan () && f.size > 0) f.tracking = twip (XmlIn.attr_any (c, "val"), 0) / f.size * 1000;
                        break;
                    case "lang":
                        string? lg = XmlIn.attr_any (c, "val");
                        if (lg != null && lg.length >= 2) f.lang = lg.substring (0, 2);
                        break;
                    case "outline":
                        if (on_off (c)) {
                            f.outline_color = ColorRef.BLACK;
                            f.outline_width = 0.75;
                        }
                        break;
                    case "shadow":
                        if (on_off (c)) f.text_shadow = 1;
                        break;
                    case "emboss":
                        if (on_off (c)) f.emboss = 1;
                        break;
                    case "imprint":
                        if (on_off (c)) f.emboss = 2;
                        break;
                }
            }
        }

        private static void docx_ppr (Xml.Node* ppr, ParaFormat f) {
            if (ppr == null) return;
            foreach (var c in XmlIn.elements (ppr)) {
                switch (c->name) {
                    case "jc":
                        string jc = XmlIn.attr_any (c, "val") ?? "left";
                        f.align = jc == "center" ? 1 : ((jc == "right" || jc == "end") ? 2 : ((jc == "both" || jc == "distribute") ? 3 : 0));
                        break;
                    case "ind":
                        string? l = XmlIn.attr_any (c, "left") ?? XmlIn.attr_any (c, "start");
                        string? r = XmlIn.attr_any (c, "right") ?? XmlIn.attr_any (c, "end");
                        if (l != null) f.left_indent = twip (l);
                        if (r != null) f.right_indent = twip (r);
                        string? fl = XmlIn.attr_any (c, "firstLine");
                        string? hg = XmlIn.attr_any (c, "hanging");
                        if (fl != null) f.first_indent = twip (fl);
                        if (hg != null) f.first_indent = -twip (hg);
                        break;
                    case "spacing":
                        string? b = XmlIn.attr_any (c, "before");
                        string? a = XmlIn.attr_any (c, "after");
                        if (b != null) f.space_before = twip (b);
                        if (a != null) f.space_after = twip (a);
                        string? line = XmlIn.attr_any (c, "line");
                        string rule = XmlIn.attr_any (c, "lineRule") ?? "auto";
                        if (line != null && (rule == "exact" || rule == "atLeast")) f.leading = twip (line);
                        break;
                    case "keepNext":
                        f.keep_next = on_off (c) ? 1 : 0;
                        break;
                    case "keepLines":
                        f.keep_lines = on_off (c) ? 1 : 0;
                        break;
                    case "tabs":
                        var stops = new Gee.ArrayList<TabStop> ();
                        foreach (var tn in XmlIn.elements (c, "tab")) {
                            string v = XmlIn.attr_any (tn, "val") ?? "left";
                            if (v == "clear") continue;
                            var kind = v == "right" || v == "end" ? TabKind.RIGHT : (v == "center" ? TabKind.CENTER : (v == "decimal" ? TabKind.DECIMAL : TabKind.LEFT));
                            string ld = XmlIn.attr_any (tn, "leader") ?? "";
                            string leader = ld == "dot" ? "." : (ld == "hyphen" ? "-" : (ld == "underscore" ? "_" : ""));
                            stops.add (new TabStop (twip (XmlIn.attr_any (tn, "pos"), 0), kind, leader));
                        }
                        f.tabs = TabStop.serialize (stops);
                        break;
                }
            }
        }

        private class DocxCtx {
            public ZipReader zip;
            public Gee.HashMap<string, string> rels = new Gee.HashMap<string, string> ();
            public Gee.HashMap<string, string> style_names = new Gee.HashMap<string, string> ();
            public Gee.HashMap<string, bool> numbering_bullet = new Gee.HashMap<string, bool> ();
            public ImportedText result;
        }

        private static Xml.Node* child_ns (Xml.Node* n, string name) {
            return XmlIn.child (n, name);
        }

        private static ImportedText read_docx (ZipReader zip) throws Error {
            var ctx = new DocxCtx ();
            ctx.zip = zip;
            var t = new ImportedText ();
            t.format = "docx";
            ctx.result = t;
            string? rels = zip.read_text ("word/_rels/document.xml.rels");
            if (rels != null) {
                Xml.Doc* rd = XmlIn.parse (rels);
                foreach (var r in XmlIn.elements (rd->get_root_element (), "Relationship")) ctx.rels[XmlIn.attr_any (r, "Id") ?? ""] = XmlIn.attr_any (r, "Target") ?? "";
                delete rd;
            }
            string? numbering = zip.read_text ("word/numbering.xml");
            if (numbering != null) {
                Xml.Doc* nd = XmlIn.parse (numbering);
                var abstract_bullet = new Gee.HashMap<string, bool> ();
                foreach (var an in XmlIn.elements (nd->get_root_element (), "abstractNum")) {
                    string id = XmlIn.attr_any (an, "abstractNumId") ?? "";
                    bool bullet = false;
                    var lvl = XmlIn.child (an, "lvl");
                    if (lvl != null) {
                        var nf = XmlIn.child (lvl, "numFmt");
                        bullet = nf != null && (XmlIn.attr_any (nf, "val") ?? "") == "bullet";
                    }
                    abstract_bullet[id] = bullet;
                }
                foreach (var num in XmlIn.elements (nd->get_root_element (), "num")) {
                    string id = XmlIn.attr_any (num, "numId") ?? "";
                    var an = XmlIn.child (num, "abstractNumId");
                    string aid = an != null ? (XmlIn.attr_any (an, "val") ?? "") : "";
                    ctx.numbering_bullet[id] = abstract_bullet.has_key (aid) && abstract_bullet[aid];
                }
                delete nd;
            }
            string? styles = zip.read_text ("word/styles.xml");
            var defaults_c = new CharFormat ();
            var defaults_p = new ParaFormat ();
            if (styles != null) {
                Xml.Doc* sd = XmlIn.parse (styles);
                var root = sd->get_root_element ();
                var dd = XmlIn.child (root, "docDefaults");
                if (dd != null) {
                    var rd = XmlIn.child (dd, "rPrDefault");
                    if (rd != null) docx_rpr (XmlIn.child (rd, "rPr"), defaults_c);
                    var pd = XmlIn.child (dd, "pPrDefault");
                    if (pd != null) docx_ppr (XmlIn.child (pd, "pPr"), defaults_p);
                }
                foreach (var s in XmlIn.elements (root, "style")) {
                    string id = XmlIn.attr_any (s, "styleId") ?? "";
                    var nn = XmlIn.child (s, "name");
                    string name = style_name_fix (nn != null ? (XmlIn.attr_any (nn, "val") ?? id) : id);
                    ctx.style_names[id] = name;
                }
                foreach (var s in XmlIn.elements (root, "style")) {
                    string type = XmlIn.attr_any (s, "type") ?? "";
                    string id = XmlIn.attr_any (s, "styleId") ?? "";
                    string name = ctx.style_names[id];
                    var bo = XmlIn.child (s, "basedOn");
                    string based = bo != null ? (ctx.style_names[XmlIn.attr_any (bo, "val") ?? ""] ?? "") : "";
                    if (type == "paragraph") {
                        var ps = new ParagraphStyle (name, based);
                        var nx = XmlIn.child (s, "next");
                        if (nx != null) ps.next = ctx.style_names[XmlIn.attr_any (nx, "val") ?? ""] ?? "";
                        if (ps.next == name) ps.next = "";
                        if (based == "") {
                            ps.para.apply (defaults_p);
                            ps.chars.apply (defaults_c);
                        }
                        docx_ppr (XmlIn.child (s, "pPr"), ps.para);
                        docx_rpr (XmlIn.child (s, "rPr"), ps.chars);
                        var np = XmlIn.child (s, "pPr");
                        if (np != null && XmlIn.child (np, "numPr") != null) {
                            var ni = XmlIn.child (XmlIn.child (np, "numPr"), "numId");
                            string nid = ni != null ? (XmlIn.attr_any (ni, "val") ?? "") : "";
                            if (nid != "" && nid != "0") ps.para.list_type = ctx.numbering_bullet.has_key (nid) && !ctx.numbering_bullet[nid] ? 2 : 1;
                        }
                        t.styles.paragraph.add (ps);
                    } else if (type == "character") {
                        if (name.down ().has_suffix (" char")) continue;
                        var cs = new CharacterStyle (name, based);
                        docx_rpr (XmlIn.child (s, "rPr"), cs.chars);
                        t.styles.character.add (cs);
                    }
                }
                delete sd;
            }
            string? doc = zip.read_text ("word/document.xml");
            if (doc == null) throw new FormatError.INVALID (_("The Word document has no body."));
            Xml.Doc* dx = NativeFormat.parse_keep_space (doc);
            var body = XmlIn.child (dx->get_root_element (), "body");
            if (body != null) docx_block (ctx, body);
            delete dx;
            if (t.paragraphs.size == 0) t.paragraphs.add (new Paragraph.with_text (""));
            return t;
        }

        private static void docx_block (DocxCtx ctx, Xml.Node* parent) {
            foreach (var n in XmlIn.elements (parent)) {
                switch (n->name) {
                    case "p":
                        docx_para (ctx, n);
                        break;
                    case "tbl":
                        foreach (var tr in XmlIn.elements (n, "tr")) {
                            var p = new Paragraph ();
                            bool first = true;
                            foreach (var tc in XmlIn.elements (tr, "tc")) {
                                if (!first) p.runs.add (new Run ("\t"));
                                first = false;
                                var tmp = new DocxCtx ();
                                tmp.zip = ctx.zip;
                                tmp.rels = ctx.rels;
                                tmp.style_names = ctx.style_names;
                                tmp.numbering_bullet = ctx.numbering_bullet;
                                tmp.result = new ImportedText ();
                                docx_block (tmp, tc);
                                for (int i = 0; i < tmp.result.paragraphs.size; i++) {
                                    if (i > 0) p.runs.add (new Run (" "));
                                    foreach (var r in tmp.result.paragraphs[i].runs) p.runs.add (r);
                                }
                            }
                            if (p.runs.size == 0) p.runs.add (new Run (""));
                            p.normalize ();
                            ctx.result.paragraphs.add (p);
                        }
                        break;
                    case "sdt":
                        var content = XmlIn.child (n, "sdtContent");
                        if (content != null) docx_block (ctx, content);
                        break;
                }
            }
        }

        private static void docx_runs (DocxCtx ctx, Xml.Node* parent, Paragraph p, string? link) {
            foreach (var n in XmlIn.elements (parent)) {
                switch (n->name) {
                    case "r":
                        var f = new CharFormat ();
                        string cstyle = "";
                        var rpr = XmlIn.child (n, "rPr");
                        if (rpr != null) {
                            var rs = XmlIn.child (rpr, "rStyle");
                            if (rs != null) {
                                string sid = XmlIn.attr_any (rs, "val") ?? "";
                                string sname = ctx.style_names[sid] ?? "";
                                if (sname != "" && !sname.down ().has_suffix (" char")) cstyle = sname;
                            }
                            docx_rpr (rpr, f);
                        }
                        if (link != null) f.link = link;
                        foreach (var c in XmlIn.elements (n)) {
                            string text = "";
                            switch (c->name) {
                                case "t":
                                    text = XmlIn.text (c);
                                    break;
                                case "tab":
                                    text = "\t";
                                    break;
                                case "br":
                                case "cr":
                                    text = " ";
                                    break;
                                case "noBreakHyphen":
                                    text = "‑";
                                    break;
                                case "softHyphen":
                                    text = "­";
                                    break;
                                case "drawing":
                                case "pict":
                                    collect_images (ctx, c);
                                    break;
                            }
                            if (text == "") continue;
                            var run = new Run (text);
                            run.fmt = f.clone ();
                            run.cstyle = cstyle;
                            p.runs.add (run);
                        }
                        break;
                    case "hyperlink":
                        string? rid = XmlIn.attr_any (n, "id");
                        string? anchor = XmlIn.attr_any (n, "anchor");
                        string? target = rid != null && ctx.rels.has_key (rid) ? ctx.rels[rid] : (anchor != null ? "bookmark:" + anchor : null);
                        docx_runs (ctx, n, p, target);
                        break;
                    case "smartTag":
                    case "ins":
                    case "fldSimple":
                        docx_runs (ctx, n, p, link);
                        break;
                }
            }
        }

        private static void collect_images (DocxCtx ctx, Xml.Node* n) {
            if (n->name == "blip") {
                string? rid = XmlIn.attr_any (n, "embed");
                if (rid != null && ctx.rels.has_key (rid)) {
                    string target = ctx.rels[rid];
                    string p = target.has_prefix ("/") ? target.substring (1) : "word/" + target;
                    try {
                        var d = ctx.zip.read (p);
                        if (d != null) {
                            ctx.result.media.add (new Bytes (d));
                            ctx.result.media_names.add (Path.get_basename (p));
                        }
                    } catch (Error e) {
                    }
                }
                return;
            }
            foreach (var c in XmlIn.elements (n)) collect_images (ctx, c);
        }

        private static void docx_para (DocxCtx ctx, Xml.Node* n) {
            var p = new Paragraph ("");
            var ppr = XmlIn.child (n, "pPr");
            if (ppr != null) {
                var ps = XmlIn.child (ppr, "pStyle");
                if (ps != null) p.style = ctx.style_names[XmlIn.attr_any (ps, "val") ?? ""] ?? "";
                docx_ppr (ppr, p.fmt);
                var np = XmlIn.child (ppr, "numPr");
                if (np != null) {
                    var ni = XmlIn.child (np, "numId");
                    var il = XmlIn.child (np, "ilvl");
                    string nid = ni != null ? (XmlIn.attr_any (ni, "val") ?? "") : "";
                    if (nid != "" && nid != "0") {
                        p.fmt.list_type = ctx.numbering_bullet.has_key (nid) && !ctx.numbering_bullet[nid] ? 2 : 1;
                        if (il != null) p.fmt.list_level = int.parse (XmlIn.attr_any (il, "val") ?? "0");
                        if (p.fmt.left_indent.is_nan ()) p.fmt.left_indent = 18 * (p.fmt.list_level < 0 ? 1 : p.fmt.list_level + 1);
                        if (p.fmt.first_indent.is_nan ()) p.fmt.first_indent = -14;
                    }
                }
            }
            if (p.style == "") p.style = ctx.style_names.has_key ("Normal") ? ctx.style_names["Normal"] : "Normal";
            docx_runs (ctx, n, p, null);
            if (p.runs.size == 0) p.runs.add (new Run (""));
            p.normalize ();
            var boxes = new Gee.ArrayList<Xml.Node*> ();
            find_boxes (n, boxes);
            if (p.length () > 0 || boxes.size == 0) ctx.result.paragraphs.add (p);
            foreach (var b in boxes) docx_block (ctx, b);
        }

        private static void find_boxes (Xml.Node* n, Gee.ArrayList<Xml.Node*> out_list) {
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                if (c->name == "txbxContent") {
                    out_list.add (c);
                    continue;
                }
                if (c->name == "Fallback") continue;
                find_boxes (c, out_list);
            }
        }

        private class OdtStyle {
            public string parent = "";
            public string display = "";
            public ParaFormat para = new ParaFormat ();
            public CharFormat chars = new CharFormat ();
            public bool automatic = false;
            public string family = "";
        }

        private static double odf_len (string? v) {
            if (v == null) return double.NAN;
            double r = Units.parse_length (v, "pt");
            return r;
        }

        private static void odf_props (Xml.Node* s, OdtStyle st, Gee.HashMap<string, string> fonts) {
            var pp = XmlIn.child (s, "paragraph-properties");
            if (pp != null) {
                string? al = XmlIn.attr_any (pp, "text-align");
                if (al != null) st.para.align = al == "center" ? 1 : ((al == "end" || al == "right") ? 2 : (al == "justify" ? 3 : 0));
                st.para.left_indent = odf_len (XmlIn.attr_any (pp, "margin-left"));
                st.para.right_indent = odf_len (XmlIn.attr_any (pp, "margin-right"));
                st.para.first_indent = odf_len (XmlIn.attr_any (pp, "text-indent"));
                st.para.space_before = odf_len (XmlIn.attr_any (pp, "margin-top"));
                st.para.space_after = odf_len (XmlIn.attr_any (pp, "margin-bottom"));
                string? lh = XmlIn.attr_any (pp, "line-height");
                if (lh != null && !lh.has_suffix ("%")) st.para.leading = odf_len (lh);
                if ((XmlIn.attr_any (pp, "keep-with-next") ?? "") == "always") st.para.keep_next = 1;
            }
            var tp = XmlIn.child (s, "text-properties");
            if (tp != null) {
                string? fn = XmlIn.attr_any (tp, "font-name");
                string? ff = XmlIn.attr_any (tp, "font-family");
                if (fn != null) st.chars.font = fonts.has_key (fn) ? fonts[fn] : fn;
                else if (ff != null) st.chars.font = ff.replace ("'", "");
                string? fs = XmlIn.attr_any (tp, "font-size");
                if (fs != null && !fs.has_suffix ("%")) st.chars.size = odf_len (fs);
                string? fw = XmlIn.attr_any (tp, "font-weight");
                if (fw != null) st.chars.bold = fw == "bold" || (int.parse (fw) >= 600) ? 1 : 0;
                string? fst = XmlIn.attr_any (tp, "font-style");
                if (fst != null) st.chars.italic = fst == "italic" || fst == "oblique" ? 1 : 0;
                string? us = XmlIn.attr_any (tp, "text-underline-style");
                if (us != null) st.chars.underline = us == "none" ? 0 : 1;
                string? ls = XmlIn.attr_any (tp, "text-line-through-style");
                if (ls != null) st.chars.strike = ls == "none" ? 0 : 1;
                string? col = XmlIn.attr_any (tp, "color");
                if (col != null && col.has_prefix ("#")) st.chars.color = col.down ();
                string? fv = XmlIn.attr_any (tp, "font-variant");
                if (fv == "small-caps") st.chars.caps = 2;
                string? tt = XmlIn.attr_any (tp, "text-transform");
                if (tt == "uppercase") st.chars.caps = 1;
                string? pos = XmlIn.attr_any (tp, "text-position");
                if (pos != null) st.chars.position = pos.has_prefix ("super") ? 1 : (pos.has_prefix ("sub") ? 2 : (pos.has_prefix ("-") ? 2 : (pos.has_prefix ("0") ? 0 : 1)));
                string? lang = XmlIn.attr_any (tp, "language");
                if (lang != null) st.chars.lang = lang;
                string? outline = XmlIn.attr_any (tp, "text-outline");
                if (outline == "true") {
                    st.chars.outline_color = ColorRef.BLACK;
                    st.chars.outline_width = 0.75;
                }
                string? shadow = XmlIn.attr_any (tp, "text-shadow");
                if (shadow != null && shadow != "none") st.chars.text_shadow = 1;
            }
        }

        private class OdtCtx {
            public Gee.HashMap<string, OdtStyle> styles = new Gee.HashMap<string, OdtStyle> ();
            public ImportedText result;
            public ZipReader zip;
        }

        private static void odt_styles (Xml.Node* container, OdtCtx ctx, bool automatic, Gee.HashMap<string, string> fonts) {
            if (container == null) return;
            foreach (var s in XmlIn.elements (container, "style")) {
                string name = XmlIn.attr_any (s, "name") ?? "";
                var st = new OdtStyle ();
                st.parent = XmlIn.attr_any (s, "parent-style-name") ?? "";
                st.display = XmlIn.attr_any (s, "display-name") ?? name.replace ("_20_", " ");
                st.family = XmlIn.attr_any (s, "family") ?? "";
                st.automatic = automatic;
                odf_props (s, st, fonts);
                ctx.styles[name] = st;
            }
        }

        private static string odt_display (OdtCtx ctx, string name) {
            if (!ctx.styles.has_key (name)) return name.replace ("_20_", " ");
            return style_name_fix (ctx.styles[name].display);
        }

        private static ImportedText read_odt (ZipReader zip) throws Error {
            var ctx = new OdtCtx ();
            ctx.zip = zip;
            var t = new ImportedText ();
            t.format = "odt";
            ctx.result = t;
            var fonts = new Gee.HashMap<string, string> ();
            string? styles = zip.read_text ("styles.xml");
            string? content = zip.read_text ("content.xml");
            if (content == null) throw new FormatError.INVALID (_("The OpenDocument file has no content."));
            Xml.Doc* sd = styles != null ? XmlIn.parse (styles) : null;
            Xml.Doc* cd = NativeFormat.parse_keep_space (content);
            foreach (var d in new Xml.Doc*[] { sd, cd }) {
                if (d == null) continue;
                var ff = XmlIn.child (d->get_root_element (), "font-face-decls");
                if (ff != null) foreach (var f in XmlIn.elements (ff, "font-face")) fonts[XmlIn.attr_any (f, "name") ?? ""] = (XmlIn.attr_any (f, "font-family") ?? "").replace ("'", "");
            }
            if (sd != null) {
                odt_styles (XmlIn.child (sd->get_root_element (), "styles"), ctx, false, fonts);
                odt_styles (XmlIn.child (sd->get_root_element (), "automatic-styles"), ctx, true, fonts);
            }
            odt_styles (XmlIn.child (cd->get_root_element (), "automatic-styles"), ctx, true, fonts);
            foreach (var e in ctx.styles.entries) {
                var st = e.value;
                if (st.automatic) continue;
                string disp = odt_display (ctx, e.key);
                string parent = st.parent != "" ? odt_display (ctx, st.parent) : "";
                if (st.family == "paragraph") {
                    var ps = new ParagraphStyle (disp, parent);
                    ps.para = st.para.clone ();
                    ps.chars = st.chars.clone ();
                    t.styles.paragraph.add (ps);
                } else if (st.family == "text") {
                    var cs = new CharacterStyle (disp, parent);
                    cs.chars = st.chars.clone ();
                    t.styles.character.add (cs);
                }
            }
            var body = XmlIn.child (XmlIn.child (cd->get_root_element (), "body"), "text");
            if (body != null) odt_block (ctx, body, 0, 0);
            if (sd != null) delete sd;
            delete cd;
            if (t.paragraphs.size == 0) t.paragraphs.add (new Paragraph.with_text (""));
            return t;
        }

        private static void odt_block (OdtCtx ctx, Xml.Node* parent, int list_type, int level) {
            foreach (var n in XmlIn.elements (parent)) {
                switch (n->name) {
                    case "p":
                    case "h":
                        var p = new Paragraph ("");
                        string sname = XmlIn.attr_any (n, "style-name") ?? "";
                        if (ctx.styles.has_key (sname) && ctx.styles[sname].automatic) {
                            var st = ctx.styles[sname];
                            p.fmt = st.para.clone ();
                            p.style = st.parent != "" ? odt_display (ctx, st.parent) : "Standard";
                            odt_runs (ctx, n, p, st.chars, null);
                        } else {
                            p.style = sname != "" ? odt_display (ctx, sname) : "Standard";
                            odt_runs (ctx, n, p, new CharFormat (), null);
                        }
                        if (n->name == "h" && sname == "") p.style = "Heading " + (XmlIn.attr_any (n, "outline-level") ?? "1");
                        if (list_type > 0) {
                            p.fmt.list_type = list_type;
                            p.fmt.list_level = level;
                            if (p.fmt.left_indent.is_nan ()) p.fmt.left_indent = 18 * (level + 1);
                            if (p.fmt.first_indent.is_nan ()) p.fmt.first_indent = -14;
                        }
                        if (p.runs.size == 0) p.runs.add (new Run (""));
                        p.normalize ();
                        ctx.result.paragraphs.add (p);
                        break;
                    case "list":
                        string ls = XmlIn.attr_any (n, "style-name") ?? "";
                        int lt = list_type > 0 ? list_type : (ls.down ().contains ("num") ? 2 : 1);
                        foreach (var li in XmlIn.elements (n, "list-item")) odt_block (ctx, li, lt, list_type > 0 ? level + 1 : 0);
                        break;
                    case "section":
                    case "list-header":
                        odt_block (ctx, n, list_type, level);
                        break;
                    case "table":
                        foreach (var tr in XmlIn.elements (n, "table-row")) {
                            var p = new Paragraph ("");
                            bool first = true;
                            foreach (var tc in XmlIn.elements (tr, "table-cell")) {
                                if (!first) p.runs.add (new Run ("\t"));
                                first = false;
                                foreach (var cp in XmlIn.elements (tc, "p")) odt_runs (ctx, cp, p, new CharFormat (), null);
                            }
                            if (p.runs.size == 0) p.runs.add (new Run (""));
                            p.normalize ();
                            ctx.result.paragraphs.add (p);
                        }
                        break;
                }
            }
        }

        private static void odt_runs (OdtCtx ctx, Xml.Node* parent, Paragraph p, CharFormat inherited, string? link) {
            for (Xml.Node* c = parent->children; c != null; c = c->next) {
                if (c->type == Xml.ElementType.TEXT_NODE || c->type == Xml.ElementType.CDATA_SECTION_NODE) {
                    string txt = c->content ?? "";
                    txt = txt.replace ("\n", " ");
                    if (txt == "") continue;
                    var r = new Run (txt);
                    r.fmt = inherited.clone ();
                    if (link != null) r.fmt.link = link;
                    p.runs.add (r);
                    continue;
                }
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                switch (c->name) {
                    case "span":
                        string sname = XmlIn.attr_any (c, "style-name") ?? "";
                        var f = inherited.clone ();
                        string cstyle = "";
                        if (ctx.styles.has_key (sname)) {
                            var st = ctx.styles[sname];
                            if (st.automatic) {
                                f.apply (st.chars);
                                if (st.parent != "") cstyle = odt_display (ctx, st.parent);
                            } else {
                                cstyle = odt_display (ctx, sname);
                            }
                        }
                        int before = p.runs.size;
                        odt_runs (ctx, c, p, f, link);
                        if (cstyle != "") for (int i = before; i < p.runs.size; i++) p.runs[i].cstyle = cstyle;
                        break;
                    case "a":
                        odt_runs (ctx, c, p, inherited, XmlIn.attr_any (c, "href") ?? link);
                        break;
                    case "s":
                        int count = int.parse (XmlIn.attr_any (c, "c") ?? "1");
                        var r = new Run (string.nfill (int.max (1, count), ' '));
                        r.fmt = inherited.clone ();
                        p.runs.add (r);
                        break;
                    case "tab":
                        var tr = new Run ("\t");
                        tr.fmt = inherited.clone ();
                        p.runs.add (tr);
                        break;
                    case "line-break":
                        var br = new Run (" ");
                        br.fmt = inherited.clone ();
                        p.runs.add (br);
                        break;
                    case "note":
                    case "annotation":
                    case "bookmark":
                    case "bookmark-start":
                    case "bookmark-end":
                        break;
                    default:
                        odt_runs (ctx, c, p, inherited, link);
                        break;
                }
            }
        }

        private class RtfState {
            public CharFormat f = new CharFormat ();
            public ParaFormat p = new ParaFormat ();
            public bool skip = false;
            public int uc = 1;
            public int dest = 0;

            public RtfState copy () {
                var s = new RtfState ();
                s.f = f.clone ();
                s.p = p.clone ();
                s.skip = skip;
                s.uc = uc;
                s.dest = dest;
                return s;
            }
        }

        public static ImportedText read_rtf (string text) {
            var t = new ImportedText ();
            t.format = "rtf";
            var fonts = new Gee.HashMap<int, string> ();
            var colors = new Gee.ArrayList<string> ();
            var stack = new Gee.ArrayList<RtfState> ();
            var st = new RtfState ();
            var para = new Paragraph ("");
            var buf = new StringBuilder ();
            var fontname = new StringBuilder ();
            int cur_font = -1;
            int cr = 0, cg = 0, cb = 0;
            bool color_set = false;
            int skip_chars = 0;
            int i = 0;
            int n = text.length;
            unowned string s = text;
            while (i < n) {
                char ch = s[i];
                if (ch == '{') {
                    flush_rtf (buf, para, st);
                    stack.add (st.copy ());
                    i++;
                    if (i + 1 < n && s[i] == '\\' && s[i + 1] == '*') {
                        st.skip = true;
                        i += 2;
                    }
                    continue;
                }
                if (ch == '}') {
                    flush_rtf (buf, para, st);
                    if (st.dest == 1 && fontname.len > 0) {
                        fonts[cur_font] = fontname.str.replace (";", "").strip ();
                        fontname.truncate ();
                    }
                    if (stack.size > 0) st = stack.remove_at (stack.size - 1);
                    i++;
                    continue;
                }
                if (ch == '\\') {
                    i++;
                    if (i >= n) break;
                    char c2 = s[i];
                    if (c2 == '\\' || c2 == '{' || c2 == '}') {
                        if (!st.skip && st.dest == 0) buf.append_c (c2);
                        i++;
                        continue;
                    }
                    if (c2 == '\'') {
                        if (i + 2 < n) {
                            int v = 0;
                            int.try_parse (s.substring (i + 1, 2), out v, null, 16);
                            if (skip_chars > 0) skip_chars--;
                            else if (!st.skip && st.dest == 0) buf.append_unichar (cp1252 ((uint8) v));
                        }
                        i += 3;
                        continue;
                    }
                    if (c2 == '~') {
                        if (!st.skip) buf.append_unichar (0xA0);
                        i++;
                        continue;
                    }
                    if (c2 == '-') {
                        if (!st.skip) buf.append_unichar (0xAD);
                        i++;
                        continue;
                    }
                    if (c2 == '\n' || c2 == '\r') {
                        flush_rtf (buf, para, st);
                        if (!st.skip && st.dest == 0) finish_para (t, ref para, st);
                        i++;
                        continue;
                    }
                    int ws = i;
                    while (i < n && s[i].isalpha ()) i++;
                    string word = s.substring (ws, i - ws);
                    int ps = i;
                    if (i < n && (s[i] == '-' || s[i].isdigit ())) {
                        i++;
                        while (i < n && s[i].isdigit ()) i++;
                    }
                    bool has_param = i > ps;
                    int param = has_param ? int.parse (s.substring (ps, i - ps)) : 0;
                    if (i < n && s[i] == ' ') i++;
                    if (word == "u") {
                        if (!st.skip && st.dest == 0) {
                            flush_rtf (buf, para, st);
                            buf.append_unichar ((unichar) (param < 0 ? param + 65536 : param));
                        }
                        skip_chars = st.uc;
                        continue;
                    }
                    switch (word) {
                        case "fonttbl":
                            st.dest = 1;
                            break;
                        case "colortbl":
                            st.dest = 2;
                            break;
                        case "stylesheet":
                        case "info":
                        case "pict":
                        case "object":
                        case "header":
                        case "footer":
                        case "footnote":
                        case "field":
                        case "fldinst":
                            if (word == "fldinst") st.skip = true;
                            else if (word != "field") st.skip = true;
                            break;
                        case "f":
                            if (st.dest == 1) cur_font = param;
                            else if (fonts.has_key (param)) {
                                flush_rtf (buf, para, st);
                                st.f.font = fonts[param];
                            }
                            break;
                        case "red":
                            cr = param;
                            color_set = true;
                            break;
                        case "green":
                            cg = param;
                            color_set = true;
                            break;
                        case "blue":
                            cb = param;
                            color_set = true;
                            break;
                        case "uc":
                            st.uc = param;
                            break;
                        case "par":
                        case "sect":
                        case "page":
                            flush_rtf (buf, para, st);
                            if (!st.skip && st.dest == 0) finish_para (t, ref para, st);
                            break;
                        case "line":
                            if (!st.skip && st.dest == 0) buf.append_unichar (0x2028);
                            break;
                        case "tab":
                        case "cell":
                            if (!st.skip && st.dest == 0) buf.append_c ('\t');
                            break;
                        case "row":
                            flush_rtf (buf, para, st);
                            if (!st.skip && st.dest == 0) finish_para (t, ref para, st);
                            break;
                        case "emdash":
                            if (!st.skip) buf.append_unichar (0x2014);
                            break;
                        case "endash":
                            if (!st.skip) buf.append_unichar (0x2013);
                            break;
                        case "bullet":
                            if (!st.skip) buf.append_unichar (0x2022);
                            break;
                        case "lquote":
                            if (!st.skip) buf.append_unichar (0x2018);
                            break;
                        case "rquote":
                            if (!st.skip) buf.append_unichar (0x2019);
                            break;
                        case "ldblquote":
                            if (!st.skip) buf.append_unichar (0x201C);
                            break;
                        case "rdblquote":
                            if (!st.skip) buf.append_unichar (0x201D);
                            break;
                        default:
                            flush_rtf (buf, para, st);
                            rtf_format (st, word, has_param, param, colors);
                            break;
                    }
                    continue;
                }
                if (ch == ';' && st.dest == 2) {
                    colors.add (color_set ? "#%02x%02x%02x".printf (cr, cg, cb) : "");
                    cr = cg = cb = 0;
                    color_set = false;
                    i++;
                    continue;
                }
                if (ch == '\r' || ch == '\n') {
                    i++;
                    continue;
                }
                if (st.dest == 1) {
                    fontname.append_c (ch);
                    if (ch == ';') {
                        fonts[cur_font] = fontname.str.replace (";", "").strip ();
                        fontname.truncate ();
                    }
                    i++;
                    continue;
                }
                if (skip_chars > 0) {
                    skip_chars--;
                    i++;
                    continue;
                }
                if (!st.skip && st.dest == 0) {
                    unichar u;
                    int j = i;
                    if (s.get_next_char (ref j, out u)) {
                        buf.append_unichar (u);
                        i = j;
                        continue;
                    }
                }
                i++;
            }
            flush_rtf (buf, para, st);
            if (para.runs.size > 0 && para.length () > 0) finish_para (t, ref para, st);
            if (t.paragraphs.size == 0) t.paragraphs.add (new Paragraph.with_text (""));
            return t;
        }

        private static void rtf_format (RtfState st, string word, bool has_param, int param, Gee.ArrayList<string> colors) {
            bool on = !has_param || param != 0;
            switch (word) {
                case "b": st.f.bold = on ? 1 : 0; break;
                case "i": st.f.italic = on ? 1 : 0; break;
                case "ul": st.f.underline = on ? 1 : 0; break;
                case "ulnone": st.f.underline = 0; break;
                case "strike": st.f.strike = on ? 1 : 0; break;
                case "caps": st.f.caps = on ? 1 : 0; break;
                case "scaps": st.f.caps = on ? 2 : 0; break;
                case "super": st.f.position = 1; break;
                case "sub": st.f.position = 2; break;
                case "nosupersub": st.f.position = 0; break;
                case "fs": st.f.size = param / 2.0; break;
                case "cf":
                    if (param >= 0 && param < colors.size && colors[param] != "") st.f.color = colors[param];
                    else if (param == 0) st.f.color = null;
                    break;
                case "plain": st.f = new CharFormat (); break;
                case "pard": st.p = new ParaFormat (); break;
                case "ql": st.p.align = 0; break;
                case "qc": st.p.align = 1; break;
                case "qr": st.p.align = 2; break;
                case "qj": st.p.align = 3; break;
                case "li": st.p.left_indent = param / 20.0; break;
                case "ri": st.p.right_indent = param / 20.0; break;
                case "fi": st.p.first_indent = param / 20.0; break;
                case "sb": st.p.space_before = param / 20.0; break;
                case "sa": st.p.space_after = param / 20.0; break;
                case "keepn": st.p.keep_next = 1; break;
                case "keep": st.p.keep_lines = 1; break;
            }
        }

        private static void flush_rtf (StringBuilder buf, Paragraph para, RtfState st) {
            if (buf.len == 0) return;
            var r = new Run (buf.str);
            r.fmt = st.f.clone ();
            para.runs.add (r);
            buf.truncate ();
        }

        private static void finish_para (ImportedText t, ref Paragraph para, RtfState st) {
            para.fmt = st.p.clone ();
            para.style = StyleSheet.BASIC;
            if (para.runs.size == 0) para.runs.add (new Run (""));
            para.normalize ();
            t.paragraphs.add (para);
            para = new Paragraph ("");
        }

        public static int merge_styles (Publication pub, StyleSheet imported, bool overwrite) {
            int n = 0;
            foreach (var ps in imported.paragraph) {
                var existing = pub.styles.find_paragraph (ps.name);
                if (existing != null && !overwrite) continue;
                var copy = ps.clone ();
                if (copy.based_on != "" && pub.styles.find_paragraph (copy.based_on) == null && imported.find_paragraph (copy.based_on) == null) copy.based_on = "";
                if (existing != null) pub.styles.paragraph[pub.styles.paragraph.index_of (existing)] = copy;
                else pub.styles.paragraph.add (copy);
                n++;
            }
            foreach (var cs in imported.character) {
                var existing = pub.styles.find_character (cs.name);
                if (existing != null && !overwrite) continue;
                var copy = cs.clone ();
                if (existing != null) pub.styles.character[pub.styles.character.index_of (existing)] = copy;
                else pub.styles.character.add (copy);
                n++;
            }
            foreach (var ps in pub.styles.paragraph) {
                if (ps.based_on != "" && pub.styles.would_cycle (ps.name, ps.based_on)) ps.based_on = "";
            }
            return n;
        }

        public static TextPos insert_into_story (Publication pub, Story story, TextPos at, ImportedText t, bool keep_styles) {
            if (keep_styles) merge_styles (pub, t.styles, false);
            var frag = new Story (0);
            frag.paras.clear ();
            string fallback = story.paras[story.clamp (at).para].style;
            foreach (var p in t.paragraphs) {
                var c = p.clone ();
                if (!keep_styles) {
                    c.style = fallback;
                    c.fmt = new ParaFormat ();
                    foreach (var r in c.runs) {
                        string? link = r.fmt.link;
                        r.fmt = new CharFormat ();
                        r.fmt.link = link;
                        r.cstyle = link != null && link != "" && pub.styles.find_character (StyleSheet.HYPERLINK) != null ? StyleSheet.HYPERLINK : "";
                    }
                } else if (pub.styles.find_paragraph (c.style) == null) {
                    c.style = StyleSheet.BASIC;
                }
                frag.paras.add (c);
            }
            if (frag.paras.size == 0) return at;
            var pos = story.clamp (at);
            var target = story.paras[pos.para];
            if (target.length () == 0) {
                target.style = frag.paras[0].style;
                target.fmt = frag.paras[0].fmt.clone ();
            }
            return story.insert_story (pos, frag);
        }
    }
}
