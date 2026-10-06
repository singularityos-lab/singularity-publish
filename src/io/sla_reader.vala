namespace Singularity.Apps.Publish {

    public class SlaReader {
        public Gee.ArrayList<string> warnings = new Gee.ArrayList<string> ();
        public string base_dir = "";
        private Publication pub;
        private Gee.HashMap<int, int> layer_map = new Gee.HashMap<int, int> ();
        private Gee.ArrayList<double?> page_x = new Gee.ArrayList<double?> ();
        private Gee.ArrayList<double?> page_y = new Gee.ArrayList<double?> ();
        private Gee.HashMap<string, MasterPage> master_by_name = new Gee.HashMap<string, MasterPage> ();
        private Gee.HashMap<string, bool> master_left = new Gee.HashMap<string, bool> ();
        private Gee.HashMap<string, double?> master_x = new Gee.HashMap<string, double?> ();
        private Gee.HashMap<string, double?> master_y = new Gee.HashMap<string, double?> ();
        private Gee.ArrayList<string> master_names = new Gee.ArrayList<string> ();
        private Gee.ArrayList<FrameLink> links = new Gee.ArrayList<FrameLink> ();
        private Gee.HashSet<string> warned = new Gee.HashSet<string> ();
        private string default_para = "";
        private string default_char = "";
        private int object_index = 0;

        private class FrameLink {
            public TextFrame frame;
            public Story? story;
            public int item_id;
            public int index;
            public int next;
            public int back;
        }

        public string notes () {
            return string.joinv ("\n", warnings.to_array ());
        }

        private void warn (string msg) {
            if (warned.contains (msg)) return;
            warned.add (msg);
            warnings.add (msg);
        }

        public static uint8[] gunzip (uint8[] data) throws Error {
            var conv = new ZlibDecompressor (ZlibCompressorFormat.GZIP);
            var input = new MemoryInputStream.from_data (data, null);
            var stream = new ConverterInputStream (input, conv);
            var outp = new MemoryOutputStream.resizable ();
            outp.splice (stream, OutputStreamSpliceFlags.CLOSE_SOURCE | OutputStreamSpliceFlags.CLOSE_TARGET);
            var b = outp.steal_as_bytes ();
            return b.get_data ();
        }

        public static uint8[] qt_uncompress (uint8[] data) throws Error {
            if (data.length < 5) throw new FormatError.INVALID (_("The embedded image data is damaged."));
            var body = data[4:data.length];
            var conv = new ZlibDecompressor (ZlibCompressorFormat.ZLIB);
            var input = new MemoryInputStream.from_data (body, null);
            var stream = new ConverterInputStream (input, conv);
            var outp = new MemoryOutputStream.resizable ();
            outp.splice (stream, OutputStreamSpliceFlags.CLOSE_SOURCE | OutputStreamSpliceFlags.CLOSE_TARGET);
            return outp.steal_as_bytes ().get_data ();
        }

        private static double num (Xml.Node* n, string name, double fallback) {
            string? v = XmlIn.attr (n, name);
            if (v == null) return fallback;
            return Units.parse_num (v, fallback);
        }

        private static int inum (Xml.Node* n, string name, int fallback) {
            string? v = XmlIn.attr (n, name);
            if (v == null) return fallback;
            double d;
            if (double.try_parse (v.strip (), out d)) return (int) Math.round (d);
            return fallback;
        }

        public Publication read (uint8[] input) throws Error {
            uint8[] data = input;
            if (data.length >= 2 && data[0] == 0x1f && data[1] == 0x8b) data = gunzip (data);
            var sb = new StringBuilder.sized (data.length + 1);
            sb.append_len ((string) data, data.length);
            string text = sb.str;
            if (!text.validate ()) {
                try {
                    text = GLib.convert (text, data.length, "UTF-8", "ISO-8859-1");
                } catch (ConvertError e) {
                    throw new FormatError.INVALID (_("The file is not a Scribus document."));
                }
            }
            Xml.Doc* doc = XmlIn.parse (text);
            try {
                var root = doc->get_root_element ();
                if (!root->name.has_prefix ("SCRIBUS")) throw new FormatError.INVALID (_("The file is not a Scribus document."));
                if (root->name != "SCRIBUSUTF8NEW") warn (_("This is an old Scribus 1.2 or 1.3 document; only the basic content is imported."));
                var dn = XmlIn.child (root, "DOCUMENT");
                if (dn == null) throw new FormatError.INVALID (_("The Scribus document has no content."));
                return read_document (dn);
            } finally {
                delete doc;
            }
        }

        private Publication read_document (Xml.Node* dn) {
            pub = new Publication ();
            pub.base_dir = base_dir;
            pub.styles = new StyleSheet ();
            var s = pub.settings;
            s.width = num (dn, "PAGEWIDTH", s.width);
            s.height = num (dn, "PAGEHEIGHT", s.height);
            s.margin_inside = num (dn, "BORDERLEFT", s.margin_inside);
            s.margin_outside = num (dn, "BORDERRIGHT", s.margin_outside);
            s.margin_top = num (dn, "BORDERTOP", s.margin_top);
            s.margin_bottom = num (dn, "BORDERBOTTOM", s.margin_bottom);
            s.bleed_top = num (dn, "BleedTop", 0);
            s.bleed_bottom = num (dn, "BleedBottom", 0);
            s.bleed_inside = num (dn, "BleedLeft", 0);
            s.bleed_outside = num (dn, "BleedRight", 0);
            s.facing = inum (dn, "BOOK", 0) > 0;
            s.start_left = inum (dn, "FIRSTLEFT", 0) == 1;
            string[] units = { "pt", "mm", "in", "pc", "cm", "pt" };
            int u = inum (dn, "UNITS", 0);
            s.units = u >= 0 && u < units.length ? units[u] : "pt";
            string? ps = XmlIn.attr (dn, "PAGESIZE");
            var match = PageSize.match (s.width, s.height);
            s.page_size = match != null ? match.id : (ps != null ? ps.down () : "custom");
            s.cmyk = true;
            s.baseline_step = num (dn, "BaseGridSpace", s.baseline_step);
            s.baseline_start = num (dn, "BaseGridOffset", s.baseline_start);
            pub.meta.title = XmlIn.attr (dn, "TITLE") ?? "";
            pub.meta.author = XmlIn.attr (dn, "AUTHOR") ?? "";
            pub.meta.subject = XmlIn.attr (dn, "SUBJECT") ?? "";
            pub.meta.keywords = XmlIn.attr (dn, "KEYWORDS") ?? "";

            foreach (var cn in XmlIn.elements (dn, "COLOR")) read_color (cn);
            foreach (string std in new string[] { "Paper", "Black", "Registration" }) {
                if (pub.swatch (std) != null) continue;
                if (std == "Paper") pub.swatches.add (new Swatch.cmyk ("Paper", 0, 0, 0, 0));
                else if (std == "Black") pub.swatches.add (new Swatch.cmyk ("Black", 0, 0, 0, 1));
                else pub.swatches.add (new Swatch.cmyk ("Registration", 1, 1, 1, 1));
            }

            var layer_nodes = XmlIn.elements (dn, "LAYERS");
            layer_nodes.sort ((a, b) => inum (a, "LEVEL", 0) - inum (b, "LEVEL", 0));
            foreach (var ln in layer_nodes) {
                var l = new Layer (pub.next_id (), XmlIn.attr (ln, "NAME") ?? _("Layer"));
                l.visible = inum (ln, "SICHTBAR", 1) == 1;
                l.printable = inum (ln, "DRUCKEN", 1) == 1;
                l.locked = inum (ln, "EDIT", 1) == 0;
                string? lc = XmlIn.attr (ln, "LAYERC");
                if (lc != null && lc.has_prefix ("#")) l.color = lc;
                layer_map[inum (ln, "NUMMER", pub.layers.size)] = l.id;
                pub.layers.add (l);
            }
            if (pub.layers.size == 0) {
                var l = new Layer (pub.next_id (), _("Layer 1"));
                layer_map[0] = l.id;
                pub.layers.add (l);
            }

            read_styles (dn);

            foreach (var mn in XmlIn.elements (dn, "MASTERPAGE")) read_master (mn);
            var page_nodes = XmlIn.elements (dn, "PAGE");
            page_nodes.sort ((a, b) => inum (a, "NUM", 0) - inum (b, "NUM", 0));
            bool guides_done = false;
            foreach (var pn in page_nodes) {
                var pg = new Page (pub.next_id ());
                string mname = XmlIn.attr (pn, "MNAM") ?? "";
                pg.master = master_id_for (mname);
                page_x.add (num (pn, "PAGEXPOS", 0));
                page_y.add (num (pn, "PAGEYPOS", 0));
                read_guides (pn, pg.guides);
                if (!guides_done) {
                    int cols = inum (pn, "AGverticalAutoCount", 0);
                    if (cols > 1) {
                        s.columns = cols;
                        s.gutter = num (pn, "AGverticalAutoGap", s.gutter);
                    }
                    guides_done = true;
                }
                pub.pages.add (pg);
            }
            if (pub.pages.size == 0) {
                var pg = new Page (pub.next_id ());
                pg.master = pub.masters.size > 0 ? pub.masters[0].id : "";
                pub.pages.add (pg);
                page_x.add (0);
                page_y.add (0);
            }
            if (pub.masters.size == 0) pub.masters.add (new MasterPage ("A", _("Master")));

            read_sections (dn);

            object_index = 0;
            for (Xml.Node* c = dn->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                if (c->name == "PAGEOBJECT") place_page_object (c);
                else if (c->name == "MASTEROBJECT") place_master_object (c);
                else if (c->name == "FRAMEOBJECT") warn (_("Inline objects anchored in text are not imported."));
                else if (c->name == "PDF" || c->name == "Printer") continue;
            }
            resolve_threads ();
            foreach (var st in pub.stories.values) {
                foreach (var p in st.paras) p.normalize ();
            }
            if (pub.sections.size == 0) pub.sections.add (new Section (0));
            return pub;
        }

        private void read_guides (Xml.Node* n, Gee.ArrayList<Guide> guides) {
            string? v = XmlIn.attr (n, "VerticalGuides");
            if (v != null) foreach (string p in v.split (" ")) if (p.strip () != "") guides.add (new Guide (true, Units.parse_num (p, 0)));
            string? h = XmlIn.attr (n, "HorizontalGuides");
            if (h != null) foreach (string p in h.split (" ")) if (p.strip () != "") guides.add (new Guide (false, Units.parse_num (p, 0)));
        }

        private void read_sections (Xml.Node* dn) {
            var sn = XmlIn.child (dn, "Sections");
            if (sn == null) return;
            foreach (var sec in XmlIn.elements (sn, "Section")) {
                if (inum (sec, "Active", 1) == 0) continue;
                var s = new Section (inum (sec, "From", 0).clamp (0, int.max (0, pub.pages.size - 1)));
                s.name = XmlIn.attr (sec, "Name") ?? "";
                s.start_number = inum (sec, "Start", 1);
                switch (XmlIn.attr (sec, "Type") ?? "") {
                    case "Type_i_ii_iii": s.style = NumberStyle.ROMAN_LOWER; break;
                    case "Type_I_II_III": s.style = NumberStyle.ROMAN_UPPER; break;
                    case "Type_a_b_c": s.style = NumberStyle.ALPHA_LOWER; break;
                    case "Type_A_B_C": s.style = NumberStyle.ALPHA_UPPER; break;
                    default: s.style = NumberStyle.ARABIC; break;
                }
                bool dup = false;
                foreach (var o in pub.sections) if (o.start_page == s.start_page) dup = true;
                if (!dup) pub.sections.add (s);
            }
            pub.sections.sort ((a, b) => a.start_page - b.start_page);
            if (pub.sections.size > 0 && pub.sections[0].start_page != 0) pub.sections.insert (0, new Section (0));
        }

        private static string base_master_name (string name, out bool left, out bool paired) {
            left = false;
            paired = false;
            if (name.has_suffix (" Left")) {
                left = true;
                paired = true;
                return name.substring (0, name.length - 5);
            }
            if (name.has_suffix (" Right")) {
                paired = true;
                return name.substring (0, name.length - 6);
            }
            return name;
        }

        private void read_master (Xml.Node* mn) {
            string name = XmlIn.attr (mn, "NAM") ?? _("Master");
            bool left, paired;
            string base_name = base_master_name (name, out left, out paired);
            if (!pub.settings.facing) {
                paired = false;
                base_name = name;
                left = false;
            }
            if (inum (mn, "LEFT", 0) == 1 && pub.settings.facing) left = true;
            MasterPage? m = null;
            foreach (var e in master_by_name.entries) {
                if (e.value.name == base_name && paired) m = e.value;
            }
            if (m == null) {
                m = new MasterPage (pub.next_master_id (), base_name);
                pub.masters.add (m);
                read_guides (mn, m.guides);
            }
            master_by_name[name] = m;
            master_left[name] = left;
            master_x[name] = num (mn, "PAGEXPOS", 0);
            master_y[name] = num (mn, "PAGEYPOS", 0);
            master_names.add (name);
        }

        private string master_id_for (string mname) {
            if (mname == "") return "";
            if (master_by_name.has_key (mname)) return master_by_name[mname].id;
            return pub.masters.size > 0 ? pub.masters[0].id : "";
        }

        private void read_color (Xml.Node* cn) {
            string? name = XmlIn.attr (cn, "NAME");
            if (name == null || name == "" || name == "None") return;
            if (name.has_prefix ("FromPublish ")) return;
            Swatch sw;
            string space = XmlIn.attr (cn, "SPACE") ?? "";
            string? cmyk_hex = XmlIn.attr (cn, "CMYK");
            string? rgb_hex = XmlIn.attr (cn, "RGB");
            bool spot = inum (cn, "Spot", 0) == 1;
            if (space == "CMYK") {
                sw = new Swatch.cmyk (name, num (cn, "C", 0) / 100, num (cn, "M", 0) / 100, num (cn, "Y", 0) / 100, num (cn, "K", 0) / 100, spot);
            } else if (space == "RGB") {
                sw = new Swatch.rgb (name, num (cn, "R", 0) / 255, num (cn, "G", 0) / 255, num (cn, "B", 0) / 255);
                sw.spot = spot;
            } else if (space == "Lab") {
                warn (_("Lab colours are converted to CMYK."));
                sw = new Swatch.cmyk (name, 0, 0, 0, 1 - num (cn, "L", 0) / 100, spot);
            } else if (cmyk_hex != null && cmyk_hex.has_prefix ("#") && cmyk_hex.length >= 9) {
                uint64 v;
                uint64.try_parse (cmyk_hex.substring (1, 8), out v, null, 16);
                sw = new Swatch.cmyk (name, ((v >> 24) & 0xff) / 255.0, ((v >> 16) & 0xff) / 255.0, ((v >> 8) & 0xff) / 255.0, (v & 0xff) / 255.0, spot);
            } else if (rgb_hex != null) {
                sw = new Swatch.hex (name, rgb_hex);
                sw.spot = spot;
            } else {
                return;
            }
            if (pub.swatch (name) != null) return;
            pub.swatches.add (sw);
        }

        private string color_spec (string? name, double shade) {
            if (name == null || name == "" || name == "None") return ColorRef.NONE;
            if (name.has_prefix ("#")) return name;
            if (name.has_prefix ("FromPublish ")) {
                string v = name.substring (12);
                if (v.has_prefix ("#")) return v;
                return "cmyk:" + v;
            }
            return ColorRef.swatch (name, shade.clamp (0, 100));
        }

        private static void apply_font (string font, CharFormat f) {
            string[] words = font.strip ().split (" ");
            int end = words.length;
            bool bold = false, italic = false;
            while (end > 1) {
                string w = words[end - 1].down ();
                if (w == "bold" || w == "semibold" || w == "black" || w == "heavy" || w == "extrabold") {
                    bold = true;
                } else if (w == "italic" || w == "oblique") {
                    italic = true;
                } else if (w == "regular" || w == "roman" || w == "book" || w == "normal" || w == "medium") {
                } else {
                    break;
                }
                end--;
            }
            f.font = string.joinv (" ", words[0:end]);
            f.bold = bold ? 1 : 0;
            f.italic = italic ? 1 : 0;
        }

        private void read_char (Xml.Node* n, CharFormat f) {
            string? font = XmlIn.attr (n, "FONT");
            if (font != null && font != "") apply_font (font, f);
            string? size = XmlIn.attr (n, "FONTSIZE");
            if (size != null) f.size = Units.parse_num (size, 12);
            string? col = XmlIn.attr (n, "FCOLOR");
            if (col != null) f.color = color_spec (col, num (n, "FSHADE", 100));
            string? feats = XmlIn.attr (n, "FEATURES");
            if (feats != null) {
                bool inherit = false;
                var set = new Gee.HashSet<string> ();
                foreach (string w in feats.split (" ")) {
                    if (w == "inherit") inherit = true;
                    else if (w != "") set.add (w);
                }
                if (!inherit) {
                    f.underline = 0;
                    f.strike = 0;
                    f.caps = 0;
                    f.position = 0;
                }
                if (set.contains ("underline") || set.contains ("underlinewords")) f.underline = 1;
                if (set.contains ("strike")) f.strike = 1;
                if (set.contains ("superscript")) f.position = 1;
                if (set.contains ("subscript")) f.position = 2;
                if (set.contains ("allcaps")) f.caps = 1;
                if (set.contains ("smallcaps")) f.caps = 2;
                if (set.contains ("outline") || set.contains ("shadowed")) warn (_("Outlined and shadowed text effects are not supported."));
            }
            string? kern = XmlIn.attr (n, "KERN");
            if (kern != null) f.tracking = Units.parse_num (kern, 0) * 10;
            string? baseo = XmlIn.attr (n, "BASEO");
            if (baseo != null) {
                double v = Units.parse_num (baseo, 0);
                if (v != 0) f.baseline_shift = v / 1000 * (f.size.is_nan () ? 12 : f.size);
            }
            string? lang = XmlIn.attr (n, "LANGUAGE");
            if (lang != null && lang != "") f.lang = lang.replace ("_", "-").split ("-")[0];
            string? scale = XmlIn.attr (n, "SCALEH");
            if (scale != null && Math.fabs (Units.parse_num (scale, 100) - 100) > 0.5) warn (_("Horizontal and vertical character scaling is not supported."));
        }

        private void read_para (Xml.Node* n, ParaFormat p) {
            string? al = XmlIn.attr (n, "ALIGN");
            if (al != null) p.align = inum (n, "ALIGN", 0).clamp (0, 4);
            string? mode = XmlIn.attr (n, "LINESPMode");
            string? ls = XmlIn.attr (n, "LINESP");
            if (mode != null) {
                int m = inum (n, "LINESPMode", 0);
                if (m == 1) p.leading = 0;
                else if (m == 2) {
                    p.align_grid = 1;
                    if (ls != null) p.leading = Units.parse_num (ls, 0);
                } else {
                    p.align_grid = 0;
                    if (ls != null) p.leading = Units.parse_num (ls, 0);
                }
            } else if (ls != null) {
                p.leading = Units.parse_num (ls, 0);
            }
            if (XmlIn.attr (n, "INDENT") != null) p.left_indent = num (n, "INDENT", 0);
            if (XmlIn.attr (n, "RMARGIN") != null) p.right_indent = num (n, "RMARGIN", 0);
            if (XmlIn.attr (n, "FIRST") != null) p.first_indent = num (n, "FIRST", 0);
            if (XmlIn.attr (n, "VOR") != null) p.space_before = num (n, "VOR", 0);
            if (XmlIn.attr (n, "NACH") != null) p.space_after = num (n, "NACH", 0);
            if (XmlIn.attr (n, "DROP") != null) {
                if (inum (n, "DROP", 0) == 1) {
                    p.drop_lines = int.max (2, inum (n, "DROPLIN", 2));
                    p.drop_chars = 1;
                } else {
                    p.drop_lines = 0;
                }
            }
            if (XmlIn.attr (n, "KeepWithNext") != null) p.keep_next = inum (n, "KeepWithNext", 0);
            if (XmlIn.attr (n, "KeepTogether") != null) p.keep_lines = inum (n, "KeepTogether", 0);
            if (XmlIn.attr (n, "Bullet") != null && inum (n, "Bullet", 0) == 1) {
                p.list_type = 1;
                string? b = XmlIn.attr (n, "BulletStr");
                if (b != null && b != "") p.bullet = b;
            }
            if (XmlIn.attr (n, "Numeration") != null && inum (n, "Numeration", 0) == 1) {
                p.list_type = 2;
                if (XmlIn.attr (n, "NumerationStart") != null) p.number_start = inum (n, "NumerationStart", 1);
                if (XmlIn.attr (n, "NumerationLevel") != null) p.list_level = inum (n, "NumerationLevel", 0);
                switch (inum (n, "NumerationFormat", 0)) {
                    case 1: p.number_format = 5; break;
                    case 2: p.number_format = 4; break;
                    case 3: p.number_format = 3; break;
                    case 4: p.number_format = 2; break;
                    default: p.number_format = 0; break;
                }
            }
            if ((XmlIn.attr (n, "Bullet") != null && inum (n, "Bullet", 0) == 0) && (XmlIn.attr (n, "Numeration") == null || inum (n, "Numeration", 0) == 0)) p.list_type = 0;
            var tabs = XmlIn.elements (n, "Tabs");
            if (tabs.size > 0) {
                var list = new Gee.ArrayList<TabStop> ();
                foreach (var t in tabs) {
                    TabKind k;
                    switch (inum (t, "Type", 0)) {
                        case 1: k = TabKind.RIGHT; break;
                        case 2:
                        case 3: k = TabKind.DECIMAL; break;
                        case 4: k = TabKind.CENTER; break;
                        default: k = TabKind.LEFT; break;
                    }
                    string fill = XmlIn.attr (t, "Fill") ?? "";
                    if (fill == " ") fill = "";
                    list.add (new TabStop (num (t, "Pos", 0), k, fill));
                }
                p.tabs = TabStop.serialize (list);
            }
        }

        private string map_para_name (string? name) {
            if (name == null || name == "" || name == default_para) return StyleSheet.BASIC;
            return name;
        }

        private string map_char_name (string? name) {
            if (name == null || name == "" || name == default_char) return "";
            return name;
        }

        private void read_styles (Xml.Node* dn) {
            var cstyles = XmlIn.elements (dn, "CHARSTYLE");
            CharFormat? default_chars = null;
            foreach (var cn in cstyles) {
                string name = XmlIn.attr (cn, "CNAME") ?? XmlIn.attr (cn, "NAME") ?? "";
                if (inum (cn, "DefaultStyle", 0) == 1 || name == "Default Character Style") {
                    default_char = name;
                    default_chars = new CharFormat ();
                    read_char (cn, default_chars);
                }
            }
            foreach (var cn in cstyles) {
                string name = XmlIn.attr (cn, "CNAME") ?? XmlIn.attr (cn, "NAME") ?? "";
                if (name == "" || name == default_char) continue;
                var cs = new CharacterStyle (name, map_char_name (XmlIn.attr (cn, "CPARENT")));
                read_char (cn, cs.chars);
                pub.styles.character.add (cs);
            }
            var pstyles = XmlIn.elements (dn, "STYLE");
            foreach (var sn in pstyles) {
                string name = XmlIn.attr (sn, "NAME") ?? "";
                if (inum (sn, "DefaultStyle", 0) == 1 || name == "Default Paragraph Style") default_para = name;
            }
            var basic = new ParagraphStyle (StyleSheet.BASIC);
            var std = StyleSheet.standard ().find_paragraph (StyleSheet.BASIC);
            basic.chars = std.chars.clone ();
            basic.para = std.para.clone ();
            pub.styles.paragraph.add (basic);
            foreach (var sn in pstyles) {
                string name = XmlIn.attr (sn, "NAME") ?? "";
                if (name == default_para && default_para != "") {
                    read_para (sn, basic.para);
                    read_char (sn, basic.chars);
                    continue;
                }
                if (name == "") continue;
                var ps = new ParagraphStyle (name, map_para_name (XmlIn.attr (sn, "PARENT")));
                read_para (sn, ps.para);
                read_char (sn, ps.chars);
                pub.styles.paragraph.add (ps);
            }
            if (default_chars != null) {
                var merged = default_chars.clone ();
                merged.apply (basic.chars);
                basic.chars = merged;
            }
            foreach (var ps in pub.styles.paragraph) {
                if (ps.based_on != "" && pub.styles.find_paragraph (ps.based_on) == null) ps.based_on = StyleSheet.BASIC;
                if (ps.name != StyleSheet.BASIC && pub.styles.would_cycle (ps.name, ps.based_on)) ps.based_on = StyleSheet.BASIC;
            }
        }

        private Story read_story (Xml.Node* st) {
            var story = new Story (pub.next_id ());
            story.paras.clear ();
            string default_style = StyleSheet.BASIC;
            var def = XmlIn.child (st, "DefaultStyle");
            ParaFormat? def_fmt = null;
            if (def != null) {
                default_style = map_para_name (XmlIn.attr (def, "PARENT"));
                def_fmt = new ParaFormat ();
                read_para (def, def_fmt);
            }
            var cur = new Paragraph (default_style);
            if (def_fmt != null) cur.fmt = def_fmt.clone ();
            foreach (var c in XmlIn.elements (st)) {
                switch (c->name) {
                    case "ITEXT":
                        string ch = (XmlIn.attr (c, "CH") ?? "").replace ("\r\n", "\n").replace ("\r", "\n");
                        string[] parts = ch.split ("\n");
                        for (int k = 0; k < parts.length; k++) {
                            if (k > 0) {
                                story.paras.add (cur);
                                cur = new Paragraph (default_style);
                                if (def_fmt != null) cur.fmt = def_fmt.clone ();
                            }
                            var r = new Run (parts[k]);
                            r.cstyle = map_char_name (XmlIn.attr (c, "CPARENT"));
                            read_char (c, r.fmt);
                            if (r.text != "") cur.runs.add (r);
                        }
                        break;
                    case "tab":
                        cur.runs.add (special_run (cur, c, "\t"));
                        break;
                    case "breakline":
                        cur.runs.add (special_run (cur, c, "\u2028"));
                        break;
                    case "nbspace":
                        cur.runs.add (special_run (cur, c, "\u00A0"));
                        break;
                    case "nbhyphen":
                        cur.runs.add (special_run (cur, c, "\u2011"));
                        break;
                    case "zwspace":
                        cur.runs.add (special_run (cur, c, "\u200B"));
                        break;
                    case "zwnbspace":
                        cur.runs.add (special_run (cur, c, "\u2060"));
                        break;
                    case "var":
                        string vn = XmlIn.attr (c, "name") ?? "";
                        if (vn == "pgno") cur.runs.add (new Run.field_run (Fields.PAGE));
                        else if (vn == "pgco") cur.runs.add (new Run.field_run (Fields.PAGES));
                        else warn (_("Some Scribus text variables are not supported."));
                        break;
                    case "para":
                        apply_para_node (cur, c, default_style);
                        story.paras.add (cur);
                        cur = new Paragraph (default_style);
                        if (def_fmt != null) cur.fmt = def_fmt.clone ();
                        break;
                    case "trail":
                        apply_para_node (cur, c, default_style);
                        break;
                    case "column":
                    case "frame":
                        warn (_("Column and frame breaks become paragraph breaks."));
                        story.paras.add (cur);
                        cur = new Paragraph (default_style);
                        break;
                    case "DefaultStyle":
                    case "MARK":
                        break;
                    default:
                        break;
                }
            }
            story.paras.add (cur);
            foreach (var p in story.paras) {
                if (p.runs.size == 0) p.runs.add (new Run (""));
                p.normalize ();
            }
            pub.stories[story.id] = story;
            return story;
        }

        private Run special_run (Paragraph p, Xml.Node* n, string t) {
            var r = new Run (t);
            if (n->properties != null) {
                read_char (n, r.fmt);
                string? cp = XmlIn.attr (n, "CPARENT");
                if (cp != null) r.cstyle = map_char_name (cp);
            }
            return r;
        }

        private void apply_para_node (Paragraph p, Xml.Node* n, string default_style) {
            string? parent = XmlIn.attr (n, "PARENT");
            if (parent != null) p.style = map_para_name (parent);
            else p.style = default_style;
            read_para (n, p.fmt);
        }

        private int layer_id (Xml.Node* n) {
            int l = inum (n, "LAYER", 0);
            if (layer_map.has_key (l)) return layer_map[l];
            return pub.layers[0].id;
        }

        private void place_page_object (Xml.Node* n) {
            int idx = object_index++;
            int own = inum (n, "OwnPage", 0);
            double cx = num (n, "XPOS", 0), cy = num (n, "YPOS", 0);
            if (own < 0 || own >= pub.pages.size) {
                own = 0;
                for (int i = 0; i < pub.pages.size; i++) {
                    if (cx >= page_x[i] - 1 && cx < page_x[i] + pub.settings.width && cy >= page_y[i] - 1 && cy < page_y[i] + pub.settings.height) own = i;
                }
            }
            var it = convert (n, page_x[own], page_y[own], idx);
            if (it != null) pub.pages[own].items.add (it);
        }

        private void place_master_object (Xml.Node* n) {
            int idx = object_index++;
            string? on = XmlIn.attr (n, "OnMasterPage");
            string name = on ?? "";
            if (!master_by_name.has_key (name)) {
                int own = inum (n, "OwnPage", 0);
                name = own >= 0 && own < master_names.size ? master_names[own] : (master_names.size > 0 ? master_names[0] : "");
            }
            if (!master_by_name.has_key (name)) {
                warn (_("Some master page objects could not be placed."));
                return;
            }
            var m = master_by_name[name];
            var it = convert (n, master_x[name], master_y[name], idx);
            if (it == null) return;
            if (master_left[name]) m.left_items.add (it);
            else m.items.add (it);
        }

        private Gee.ArrayList<Point?> parse_path (string d) {
            var pts = new Gee.ArrayList<Point?> ();
            var toks = new Gee.ArrayList<string> ();
            var sb = new StringBuilder ();
            for (int i = 0; i < d.length; i++) {
                char c = d[i];
                if (c.isalpha () && c != 'e' && c != 'E') {
                    if (sb.len > 0) toks.add (sb.str);
                    sb.truncate ();
                    toks.add (c.to_string ());
                } else if (c == ' ' || c == ',' || c == '\n' || c == '\t') {
                    if (sb.len > 0) toks.add (sb.str);
                    sb.truncate ();
                } else if (c == '-' && sb.len > 0 && sb.str[sb.len - 1] != 'e' && sb.str[sb.len - 1] != 'E') {
                    toks.add (sb.str);
                    sb.truncate ();
                    sb.append_c (c);
                } else {
                    sb.append_c (c);
                }
            }
            if (sb.len > 0) toks.add (sb.str);
            string cmd = "M";
            double px = 0, py = 0;
            int i = 0;
            while (i < toks.size) {
                string t = toks[i];
                if (t.length == 1 && t[0].isalpha ()) {
                    cmd = t;
                    i++;
                    if (cmd == "Z" || cmd == "z") continue;
                }
                bool rel = cmd.down () == cmd;
                string up = cmd.up ();
                double ox = rel ? px : 0, oy = rel ? py : 0;
                if (up == "M" || up == "L" || up == "T") {
                    if (i + 1 >= toks.size) break;
                    px = ox + Units.parse_num (toks[i], 0);
                    py = oy + Units.parse_num (toks[i + 1], 0);
                    pts.add (Point (px, py));
                    i += 2;
                    if (up == "M") cmd = rel ? "l" : "L";
                } else if (up == "H") {
                    px = ox + Units.parse_num (toks[i], 0);
                    pts.add (Point (px, py));
                    i++;
                } else if (up == "V") {
                    py = oy + Units.parse_num (toks[i], 0);
                    pts.add (Point (px, py));
                    i++;
                } else if (up == "C") {
                    if (i + 5 >= toks.size) break;
                    double x1 = ox + Units.parse_num (toks[i], 0), y1 = oy + Units.parse_num (toks[i + 1], 0);
                    double x2 = ox + Units.parse_num (toks[i + 2], 0), y2 = oy + Units.parse_num (toks[i + 3], 0);
                    double x3 = ox + Units.parse_num (toks[i + 4], 0), y3 = oy + Units.parse_num (toks[i + 5], 0);
                    for (int k = 1; k <= 8; k++) {
                        double t2 = k / 8.0, mt = 1 - t2;
                        pts.add (Point (mt * mt * mt * px + 3 * mt * mt * t2 * x1 + 3 * mt * t2 * t2 * x2 + t2 * t2 * t2 * x3, mt * mt * mt * py + 3 * mt * mt * t2 * y1 + 3 * mt * t2 * t2 * y2 + t2 * t2 * t2 * y3));
                    }
                    px = x3;
                    py = y3;
                    i += 6;
                } else if (up == "Q" || up == "S") {
                    if (i + 3 >= toks.size) break;
                    px = ox + Units.parse_num (toks[i + 2], 0);
                    py = oy + Units.parse_num (toks[i + 3], 0);
                    pts.add (Point (px, py));
                    i += 4;
                } else {
                    i++;
                }
            }
            var clean = new Gee.ArrayList<Point?> ();
            foreach (var p in pts) {
                if (clean.size > 0) {
                    var l = clean[clean.size - 1];
                    if (Math.fabs (l.x - p.x) < 0.001 && Math.fabs (l.y - p.y) < 0.001) continue;
                }
                clean.add (p);
            }
            if (clean.size > 2) {
                var a = clean[0];
                var b = clean[clean.size - 1];
                if (Math.fabs (a.x - b.x) < 0.001 && Math.fabs (a.y - b.y) < 0.001) clean.remove_at (clean.size - 1);
            }
            return clean;
        }

        private void set_geometry (Item it, Xml.Node* n, double ox, double oy) {
            double xp = num (n, "XPOS", 0) - ox, yp = num (n, "YPOS", 0) - oy;
            double w = num (n, "WIDTH", 1), h = num (n, "HEIGHT", 1);
            double rot = num (n, "ROT", 0);
            double a = rot * Math.PI / 180;
            double cxp = xp + Math.cos (a) * w / 2 - Math.sin (a) * h / 2;
            double cyp = yp + Math.sin (a) * w / 2 + Math.cos (a) * h / 2;
            it.w = w;
            it.h = h;
            it.x = cxp - w / 2;
            it.y = cyp - h / 2;
            it.rotation = Math.fabs (rot) < 1e-9 ? 0 : rot;
        }

        private void read_common (Item it, Xml.Node* n) {
            it.id = pub.next_id ();
            it.layer = layer_id (n);
            it.name = XmlIn.attr (n, "ANNAME") ?? "";
            it.locked = inum (n, "LOCK", 0) == 1;
            it.nonprinting = inum (n, "PRINTABLE", 1) == 0;
            it.flip_h = inum (n, "FLIPPEDH", 0) == 1;
            it.flip_v = inum (n, "FLIPPEDV", 0) == 1;
            double trans = num (n, "TransValue", 0);
            it.opacity = (1 - trans).clamp (0, 1);
            string fill = XmlIn.attr (n, "PCOLOR") ?? "None";
            int grtyp = inum (n, "GRTYP", 0);
            var stops = XmlIn.elements (n, "CSTOP");
            if ((grtyp == 6 || grtyp == 7 || grtyp == 1 || grtyp == 2) && stops.size >= 2) {
                var f = new Fill ();
                f.kind = grtyp == 7 ? FillKind.RADIAL : FillKind.LINEAR;
                foreach (var sn in stops) f.stops.add (new GradientStop (num (sn, "RAMP", 0), color_spec (XmlIn.attr (sn, "NAME"), num (sn, "SHADE", 100)), num (sn, "TRANS", 1)));
                f.color = f.stops[0].color;
                double sx = num (n, "GRSTARTX", 0), sy = num (n, "GRSTARTY", 0), ex = num (n, "GRENDX", it.w), ey = num (n, "GRENDY", 0);
                f.angle = Math.atan2 (ey - sy, ex - sx) * 180 / Math.PI;
                it.fill = f;
            } else {
                if (grtyp != 0) warn (_("Some Scribus gradients and patterns are imported as solid fills."));
                it.fill = new Fill.solid (color_spec (fill, num (n, "SHADE", 100)));
            }
            string stroke = XmlIn.attr (n, "PCOLOR2") ?? "None";
            var s = new Stroke.with (color_spec (stroke, num (n, "SHADE2", 100)), num (n, "PWIDTH", 1));
            switch (inum (n, "PLINEART", 1)) {
                case 2: s.dash = DashKind.DASH; break;
                case 3: s.dash = DashKind.DOT; break;
                case 4:
                case 5: s.dash = DashKind.DASH_DOT; break;
                default: s.dash = DashKind.SOLID; break;
            }
            int cap = inum (n, "PLINEEND", 0);
            s.cap = cap == 32 ? 1 : (cap == 16 ? 2 : 0);
            int join = inum (n, "PLINEJOIN", 0);
            s.join = join == 128 ? 1 : (join == 64 ? 2 : 0);
            s.arrow_start = inum (n, "startArrowIndex", 0) > 0 ? 1 : 0;
            s.arrow_end = inum (n, "endArrowIndex", 0) > 0 ? 1 : 0;
            if (s.width <= 0 && s.color != ColorRef.NONE) s.width = 0.1;
            it.stroke = s;
            switch (inum (n, "TEXTFLOWMODE", 0)) {
                case 1:
                case 2:
                    it.wrap = WrapMode.BOUNDING_BOX;
                    it.wrap_offset = 0;
                    break;
                case 3:
                case 4:
                    it.wrap = WrapMode.CONTOUR;
                    it.wrap_offset = 0;
                    break;
                default:
                    it.wrap = WrapMode.NONE;
                    break;
            }
            if (XmlIn.attr (n, "WRAPOFFSET") != null) it.wrap_offset = num (n, "WRAPOFFSET", 0);
            if (inum (n, "HASSOFTSHADOW", 0) == 1) {
                it.shadow.enabled = true;
                it.shadow.dx = num (n, "SOFTSHADOWXOFFSET", 3);
                it.shadow.dy = num (n, "SOFTSHADOWYOFFSET", 3);
                it.shadow.blur = num (n, "SOFTSHADOWBLURRADIUS", 6);
                string sc = XmlIn.attr (n, "SOFTSHADOWCOLOR") ?? "Black";
                it.shadow.color = color_spec (sc, num (n, "SOFTSHADOWSHADE", 100));
                if (it.shadow.color == ColorRef.NONE) it.shadow.color = ColorRef.BLACK;
                it.shadow.opacity = (1 - num (n, "SOFTSHADOWOPACITY", 0.65)).clamp (0, 1);
            }
            int frtype = inum (n, "FRTYPE", 0);
            if (frtype == 1) it.shape_ellipse = true;
            if (frtype == 2) {
                double r = num (n, "RADRECT", 0);
                if (r > 0) {
                    it.corner = CornerKind.ROUNDED;
                    it.corner_radius = r;
                }
            }
        }

        private Item? convert (Xml.Node* n, double ox, double oy, int index) {
            int ptype = inum (n, "PTYPE", 6);
            switch (ptype) {
                case 4:
                    var t = new TextFrame ();
                    set_geometry (t, n, ox, oy);
                    read_common (t, n);
                    t.fill = new Fill.solid (color_spec (XmlIn.attr (n, "PCOLOR") ?? "None", num (n, "SHADE", 100)));
                    t.columns = int.max (1, inum (n, "COLUMNS", 1));
                    t.gutter = num (n, "COLGAP", 0);
                    t.inset_left = num (n, "EXTRA", 0);
                    t.inset_top = num (n, "TEXTRA", 0);
                    t.inset_bottom = num (n, "BEXTRA", 0);
                    t.inset_right = num (n, "REXTRA", 0);
                    t.valign = inum (n, "VAlign", 0).clamp (0, 3);
                    var link = new FrameLink ();
                    link.frame = t;
                    link.item_id = inum (n, "ItemID", -1);
                    link.index = index;
                    link.next = inum (n, "NEXTITEM", -1);
                    link.back = inum (n, "BACKITEM", -1);
                    var stn = XmlIn.child (n, "StoryText");
                    if (stn != null && link.back < 0) {
                        link.story = read_story (stn);
                    } else if (stn != null && link.back >= 0) {
                        link.story = null;
                    } else {
                        link.story = null;
                        read_legacy_text (n, link);
                    }
                    links.add (link);
                    return t;
                case 2:
                    var im = new ImageFrame ();
                    set_geometry (im, n, ox, oy);
                    read_common (im, n);
                    read_image (im, n);
                    return im;
                case 5:
                    var line = new ShapeItem (ShapeKind.LINE);
                    read_common (line, n);
                    line.fill = new Fill ();
                    double xp = num (n, "XPOS", 0) - ox, yp = num (n, "YPOS", 0) - oy;
                    double len = num (n, "WIDTH", 1);
                    double a = num (n, "ROT", 0) * Math.PI / 180;
                    double x2 = xp + Math.cos (a) * len, y2 = yp + Math.sin (a) * len;
                    line.x = double.min (xp, x2);
                    line.y = double.min (yp, y2);
                    line.w = Math.fabs (x2 - xp);
                    line.h = Math.fabs (y2 - yp);
                    line.line_reverse = (x2 - xp) * (y2 - yp) < 0;
                    line.flip_h = false;
                    line.flip_v = false;
                    return line;
                case 12:
                    var g = new GroupItem ();
                    read_common (g, n);
                    g.fill = new Fill ();
                    g.stroke = new Stroke ();
                    double gx = num (n, "XPOS", 0) - ox, gy = num (n, "YPOS", 0) - oy;
                    if (Math.fabs (num (n, "ROT", 0)) > 0.001) warn (_("Rotated groups are imported without their rotation."));
                    foreach (var cn in XmlIn.elements (n, "PAGEOBJECT")) {
                        var c = convert (cn, -gx, -gy, object_index++);
                        if (c != null) g.children.add (c);
                    }
                    if (g.children.size == 0) {
                        warn (_("Groups stored in the old Scribus format are imported as separate objects."));
                        return null;
                    }
                    g.fit_children ();
                    return g;
                case 16:
                    return read_table (n, ox, oy);
                case 6:
                case 7:
                case 13:
                case 14:
                case 15:
                    int frtype = inum (n, "FRTYPE", 0);
                    ShapeItem s;
                    if (ptype == 6 && frtype == 1) s = new ShapeItem (ShapeKind.ELLIPSE);
                    else if (ptype == 6 && (frtype == 0 || frtype == 2)) s = new ShapeItem (ShapeKind.RECT);
                    else s = new ShapeItem (ShapeKind.PATH);
                    set_geometry (s, n, ox, oy);
                    read_common (s, n);
                    if (s.shape == ShapeKind.PATH) {
                        s.shape_ellipse = false;
                        s.closed = ptype != 7 && ptype != 15;
                        var pts = parse_path (XmlIn.attr (n, "path") ?? "");
                        if (pts.size < 2) {
                            s.shape = ShapeKind.RECT;
                        } else {
                            foreach (var p in pts) s.points.add (Point (s.w > 0 ? p.x / s.w : 0, s.h > 0 ? p.y / s.h : 0));
                        }
                        if (!s.closed) s.fill = new Fill ();
                    }
                    return s;
                case 8:
                    warn (_("Text on a path is imported as a plain text frame."));
                    var tp = new TextFrame ();
                    set_geometry (tp, n, ox, oy);
                    read_common (tp, n);
                    var pl = new FrameLink ();
                    pl.frame = tp;
                    pl.item_id = inum (n, "ItemID", -1);
                    pl.index = index;
                    pl.next = -1;
                    pl.back = -1;
                    var pst = XmlIn.child (n, "StoryText");
                    pl.story = pst != null ? read_story (pst) : null;
                    links.add (pl);
                    return tp;
                case 9:
                    warn (_("Scribus render frames are not supported."));
                    return null;
                case 11:
                    warn (_("Scribus symbols are not supported."));
                    return null;
                default:
                    warn (_("Some Scribus object types are not supported."));
                    return null;
            }
        }

        private void read_legacy_text (Xml.Node* n, FrameLink link) {
            if (XmlIn.elements (n, "ITEXT").size == 0) return;
            link.story = read_story (n);
        }

        private void read_image (ImageFrame im, Xml.Node* n) {
            if (inum (n, "isInlineImage", 0) == 1) {
                string? data = XmlIn.attr (n, "ImageData");
                string ext = XmlIn.attr (n, "inlineImageExt") ?? "png";
                if (data != null && data != "") {
                    try {
                        var raw = qt_uncompress (Base64.decode (data));
                        im.media = pub.add_media (raw, "image." + ext);
                    } catch (Error e) {
                        warn (_("An embedded image could not be decoded."));
                    }
                }
            } else {
                string file = XmlIn.attr (n, "PFILE") ?? "";
                if (file != "") {
                    string full = !Path.is_absolute (file) && base_dir != "" ? Path.build_filename (base_dir, file) : file;
                    im.link = File.new_for_path (full).get_path () ?? full;
                    if (FileUtils.test (im.link, FileTest.IS_REGULAR)) im.link_stamp = ImageStore.stamp_for (im.link);
                    else warn (_("Some linked images are missing."));
                }
            }
            bool free = inum (n, "SCALETYPE", 1) == 1;
            bool ratio = inum (n, "RATIO", 1) == 1;
            if (free) {
                im.fit = FitMode.MANUAL;
                double sx = num (n, "LOCALSCX", 1), sy = num (n, "LOCALSCY", sx);
                if (Math.fabs (sx - sy) > 1e-6) warn (_("Non-proportional image scaling is imported as proportional."));
                im.img_scale = sx;
                im.img_x = num (n, "LOCALX", 0) * sx;
                im.img_y = num (n, "LOCALY", 0) * sy;
            } else {
                im.fit = ratio ? FitMode.FIT : FitMode.STRETCH;
            }
            if (Math.fabs (num (n, "LOCALROT", 0)) > 0.001) warn (_("Rotated images inside frames are imported without the inner rotation."));
        }

        private Item? read_table (Xml.Node* n, double ox, double oy) {
            var rh = new Gee.ArrayList<double?> ();
            var cw = new Gee.ArrayList<double?> ();
            string? rs = XmlIn.attr (n, "RowHeights");
            string? cs = XmlIn.attr (n, "ColumnWidths");
            if (rs != null) foreach (string p in rs.split (" ")) if (p.strip () != "") rh.add (Units.parse_num (p, 20));
            if (cs != null) foreach (string p in cs.split (" ")) if (p.strip () != "") cw.add (Units.parse_num (p, 60));
            int rows = int.max (1, inum (n, "Rows", rh.size));
            int cols = int.max (1, inum (n, "Columns", cw.size));
            var tb = new TableItem (rows, cols);
            set_geometry (tb, n, ox, oy);
            read_common (tb, n);
            tb.cells.clear ();
            for (int r = 0; r < rows; r++) {
                var row = new Gee.ArrayList<Cell> ();
                for (int c = 0; c < cols; c++) row.add (new Cell (pub.next_id ()));
                tb.cells.add (row);
            }
            for (int r = 0; r < rows; r++) tb.row_h.add (r < rh.size ? rh[r] : tb.h / rows);
            for (int c = 0; c < cols; c++) tb.col_w.add (c < cw.size ? cw[c] : tb.w / cols);
            tb.header_rows = 0;
            tb.border_color = ColorRef.BLACK;
            tb.border_width = 0.5;
            var data = XmlIn.child (n, "TableData");
            if (data != null) {
                string? fc = XmlIn.attr (data, "FillColor");
                if (fc != null && fc != "None") tb.fill = new Fill.solid (color_spec (fc, 100));
                foreach (var cn in XmlIn.elements (data, "Cell")) {
                    int r = inum (cn, "Row", 0), c = inum (cn, "Column", 0);
                    if (r < 0 || r >= rows || c < 0 || c >= cols) continue;
                    var cell = tb.cells[r][c];
                    string? cf = XmlIn.attr (cn, "FillColor");
                    if (cf != null && cf != "None") cell.fill = color_spec (cf, num (cn, "FillShade", 100));
                    int rsp = inum (cn, "RowSpan", 1), csp = inum (cn, "ColumnSpan", 1);
                    var stn = XmlIn.child (cn, "StoryText");
                    if (stn != null) {
                        var st = read_story (stn);
                        pub.stories.unset (st.id);
                        cell.story = st;
                    }
                    if (rsp > 1 || csp > 1) {
                        cell.row_span = int.min (rsp, rows - r);
                        cell.col_span = int.min (csp, cols - c);
                    }
                }
                for (int r = 0; r < rows; r++) for (int c = 0; c < cols; c++) {
                    var cell = tb.cells[r][c];
                    if (cell.row_span > 1 || cell.col_span > 1) {
                        for (int i = r; i < r + cell.row_span; i++) for (int j = c; j < c + cell.col_span; j++) if (i != r || j != c) tb.cells[i][j].covered = true;
                    }
                }
            }
            return tb;
        }

        private void resolve_threads () {
            var by_id = new Gee.HashMap<int, FrameLink> ();
            var by_index = new Gee.HashMap<int, FrameLink> ();
            foreach (var l in links) {
                if (l.item_id >= 0) by_id[l.item_id] = l;
                by_index[l.index] = l;
            }
            bool id_mode = true;
            foreach (var l in links) {
                if (l.next >= 0 && !by_id.has_key (l.next)) id_mode = false;
                if (l.back >= 0 && !by_id.has_key (l.back)) id_mode = false;
            }
            var done = new Gee.HashSet<FrameLink> ();
            foreach (var l in links) {
                bool known = id_mode ? by_id.has_key (l.back) : by_index.has_key (l.back);
                bool head = l.back < 0 || !known;
                if (!head) continue;
                var story = l.story;
                if (story == null) {
                    story = new Story (pub.next_id ());
                    pub.stories[story.id] = story;
                }
                var cur = l;
                int guard = 0;
                while (cur != null && !done.contains (cur) && guard++ < 10000) {
                    done.add (cur);
                    cur.frame.story = story.id;
                    story.frames.add (cur.frame.id);
                    if (cur != l && cur.story != null && !cur.story.is_empty ()) {
                        warn (_("Text found in a linked frame after the first one was appended to its story."));
                        var end = story.end_pos ();
                        end = story.split_paragraph (end);
                        story.insert_story (end, cur.story);
                        pub.stories.unset (cur.story.id);
                    }
                    if (cur.next < 0) break;
                    FrameLink? nx = id_mode ? (by_id.has_key (cur.next) ? by_id[cur.next] : null) : (by_index.has_key (cur.next) ? by_index[cur.next] : null);
                    cur = nx;
                }
            }
            foreach (var l in links) {
                if (done.contains (l)) continue;
                var story = l.story ?? new Story (pub.next_id ());
                pub.stories[story.id] = story;
                l.frame.story = story.id;
                story.frames.add (l.frame.id);
            }
        }
    }
}
