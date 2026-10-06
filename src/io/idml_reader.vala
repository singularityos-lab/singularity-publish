namespace Singularity.Apps.Publish {

    public struct IdmlMatrix {
        public double a;
        public double b;
        public double c;
        public double d;
        public double tx;
        public double ty;

        public static IdmlMatrix ident () {
            IdmlMatrix m = { 1, 0, 0, 1, 0, 0 };
            return m;
        }

        public static IdmlMatrix translate (double x, double y) {
            IdmlMatrix m = { 1, 0, 0, 1, x, y };
            return m;
        }

        public static IdmlMatrix parse (string? s) {
            var m = ident ();
            if (s == null) return m;
            var v = new Gee.ArrayList<double?> ();
            foreach (string p in s.strip ().split_set (" \t\n")) {
                if (p == "") continue;
                v.add (Units.parse_num (p, 0));
            }
            if (v.size != 6) return m;
            m.a = v[0];
            m.b = v[1];
            m.c = v[2];
            m.d = v[3];
            m.tx = v[4];
            m.ty = v[5];
            return m;
        }

        public IdmlMatrix mul (IdmlMatrix o) {
            IdmlMatrix r = {
                a * o.a + c * o.b,
                b * o.a + d * o.b,
                a * o.c + c * o.d,
                b * o.c + d * o.d,
                a * o.tx + c * o.ty + tx,
                b * o.tx + d * o.ty + ty
            };
            return r;
        }

        public Point apply (double x, double y) {
            return Point (a * x + c * y + tx, b * x + d * y + ty);
        }

        public IdmlMatrix invert () {
            double det = a * d - b * c;
            if (Math.fabs (det) < 1e-12) return ident ();
            IdmlMatrix r = {
                d / det,
                -b / det,
                -c / det,
                a / det,
                (c * ty - d * tx) / det,
                (b * tx - a * ty) / det
            };
            return r;
        }
    }

    public class IdmlReader {
        public Gee.ArrayList<string> warnings = new Gee.ArrayList<string> ();
        private Publication pub;
        private ZipReader zip;
        private Gee.HashMap<string, string> colors = new Gee.HashMap<string, string> ();
        private Gee.HashMap<string, Fill> gradients = new Gee.HashMap<string, Fill> ();
        private Gee.HashMap<string, string> pstyles = new Gee.HashMap<string, string> ();
        private Gee.HashMap<string, string> cstyles = new Gee.HashMap<string, string> ();
        private Gee.HashMap<string, string> ostyles = new Gee.HashMap<string, string> ();
        private Gee.HashMap<string, string> tstyles = new Gee.HashMap<string, string> ();
        private Gee.HashMap<string, string> cellstyles = new Gee.HashMap<string, string> ();
        private Gee.HashMap<string, int> layers = new Gee.HashMap<string, int> ();
        private Gee.HashMap<string, MasterPage> masters = new Gee.HashMap<string, MasterPage> ();
        private Gee.HashMap<string, Story> stories = new Gee.HashMap<string, Story> ();
        private Gee.HashMap<string, Page> page_ids = new Gee.HashMap<string, Page> ();
        private Gee.ArrayList<FrameLink> links = new Gee.ArrayList<FrameLink> ();
        private Gee.ArrayList<PendingTable> tables = new Gee.ArrayList<PendingTable> ();
        private Gee.HashSet<string> warned = new Gee.HashSet<string> ();
        private string current_story = "";
        private Gee.ArrayList<MasterPage> single_masters = new Gee.ArrayList<MasterPage> ();

        private class FrameLink {
            public TextFrame frame;
            public string self;
            public string story;
            public string prev;
            public string next;
        }

        private class PendingTable {
            public string story;
            public TableItem table;
        }

        private class PageGeom {
            public IdmlMatrix to_page;
            public Rect spread_rect;
            public Page? page;
            public MasterPage? master;
            public bool left;
        }

        private void warn (string key, string message) {
            if (warned.contains (key)) return;
            warned.add (key);
            warnings.add (message);
        }

        public string notes () {
            return string.joinv ("\n", warnings.to_array ());
        }

        private Xml.Doc* load (string name, bool keep_space = false) throws Error {
            string? text = zip.read_text (name);
            if (text == null) throw new FormatError.INVALID (_("The InDesign package is missing \"%s\".").printf (name));
            return keep_space ? NativeFormat.parse_keep_space (text) : XmlIn.parse (text);
        }

        private static Xml.Node* find_desc (Xml.Node* n, string name) {
            if (n == null) return null;
            if (n->type == Xml.ElementType.ELEMENT_NODE && n->name == name) return n;
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                var r = find_desc (c, name);
                if (r != null) return r;
            }
            return null;
        }

        private static Xml.Node* find_inner (Xml.Node* root, string name) {
            for (Xml.Node* c = root->children; c != null; c = c->next) {
                var r = find_desc (c, name);
                if (r != null) return r;
            }
            return root->name == name ? root : null;
        }

        private static void all_desc (Xml.Node* n, string name, Gee.ArrayList<Xml.Node*> list) {
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                if (c->name == name) list.add (c);
                else all_desc (c, name, list);
            }
        }

        private static string? prop (Xml.Node* n, string name) {
            string? v = XmlIn.attr (n, name);
            if (v != null) return v;
            var props = XmlIn.child (n, "Properties");
            if (props == null) return null;
            var c = XmlIn.child (props, name);
            if (c == null) return null;
            return XmlIn.text (c).strip ();
        }

        private static bool truthy (string? v) {
            return v != null && (v == "true" || v == "1");
        }

        private static double num (string? v, double fallback) {
            if (v == null) return fallback;
            return Units.parse_num (v, fallback);
        }

        private static string clean_name (string? name, string fallback) {
            if (name == null || name == "") return fallback;
            string n = name;
            if (n.has_prefix ("$ID/")) n = n.substring (4);
            return n == "" ? fallback : n;
        }

        public Publication read (uint8[] data) throws Error {
            zip = new ZipReader (data);
            if (!zip.has ("designmap.xml")) throw new FormatError.INVALID (_("The file is not an InDesign Markup (IDML) package."));
            pub = new Publication ();
            pub.swatches.add_all (Publication.standard_swatches ());
            Xml.Doc* dm = load ("designmap.xml");
            try {
                var root = dm->get_root_element ();
                string graphic = "Resources/Graphic.xml", styles = "Resources/Styles.xml", prefs = "Resources/Preferences.xml";
                var spreads = new Gee.ArrayList<string> ();
                var master_files = new Gee.ArrayList<string> ();
                var story_files = new Gee.ArrayList<string> ();
                var layer_nodes = new Gee.ArrayList<Xml.Node*> ();
                var section_nodes = new Gee.ArrayList<Xml.Node*> ();
                foreach (var c in XmlIn.elements (root)) {
                    string src = XmlIn.attr (c, "src") ?? "";
                    switch (c->name) {
                        case "Graphic": graphic = src; break;
                        case "Styles": styles = src; break;
                        case "Preferences": prefs = src; break;
                        case "Spread": spreads.add (src); break;
                        case "MasterSpread": master_files.add (src); break;
                        case "Story": story_files.add (src); break;
                        case "Layer": layer_nodes.add (c); break;
                        case "Section": section_nodes.add (c); break;
                        case "Tags": break;
                        case "BackingStory": break;
                        default: break;
                    }
                }
                read_metadata ();
                read_layers (layer_nodes);
                if (zip.has (prefs)) read_preferences (prefs);
                if (zip.has (graphic)) read_graphic (graphic);
                else warn ("graphic", _("The package has no colour definitions; colours fall back to black."));
                if (zip.has (styles)) read_styles (styles);
                foreach (string f in master_files) read_master (f);
                foreach (string f in spreads) read_spread (f);
                foreach (string f in story_files) read_story_file (f);
                link_frames ();
                place_tables ();
                foreach (var m in single_masters) {
                    foreach (var it in m.items) {
                        var copy = it.clone ();
                        pub.reassign (copy);
                        m.left_items.add (copy);
                    }
                }
                read_sections (section_nodes);
            } finally {
                delete dm;
            }
            if (pub.masters.size == 0) {
                foreach (var pg in pub.pages) pg.master = "";
            }
            if (pub.pages.size == 0) pub.add_page (-1, pub.masters.size > 0 ? pub.masters[0].id : "");
            bool has_first = false;
            foreach (var sec in pub.sections) if (sec.start_page == 0) has_first = true;
            if (!has_first) pub.sections.insert (0, new Section (0));
            foreach (var s in pub.stories.values) foreach (var p in s.paras) p.normalize ();
            pub.prune_stories ();
            return pub;
        }

        private void read_metadata () {
            if (!zip.has ("META-INF/metadata.xml")) return;
            try {
                Xml.Doc* doc = load ("META-INF/metadata.xml");
                var t = find_desc (doc->get_root_element (), "title");
                if (t != null) {
                    var li = find_desc (t, "li");
                    pub.meta.title = XmlIn.text (li ?? t).strip ();
                }
                var cr = find_desc (doc->get_root_element (), "creator");
                if (cr != null) {
                    var li = find_desc (cr, "li");
                    pub.meta.author = XmlIn.text (li ?? cr).strip ();
                }
                delete doc;
            } catch (Error e) {
            }
        }

        private void read_layers (Gee.ArrayList<Xml.Node*> nodes) {
            for (int i = nodes.size - 1; i >= 0; i--) {
                var n = nodes[i];
                var l = new Layer (pub.next_id (), clean_name (XmlIn.attr (n, "Name"), _("Layer %d").printf (nodes.size - i)));
                l.visible = XmlIn.attr (n, "Visible") != "false";
                l.locked = truthy (XmlIn.attr (n, "Locked"));
                l.printable = XmlIn.attr (n, "Printable") != "false";
                pub.layers.add (l);
                layers[XmlIn.attr (n, "Self") ?? ""] = l.id;
            }
            if (pub.layers.size == 0) pub.layers.add (new Layer (pub.next_id (), _("Layer 1")));
        }

        private void read_preferences (string file) throws Error {
            Xml.Doc* doc = load (file);
            try {
                var root = doc->get_root_element ();
                var s = pub.settings;
                s.units = "pt";
                var dp = find_desc (root, "DocumentPreference");
                if (dp != null) {
                    s.width = num (XmlIn.attr (dp, "PageWidth"), s.width);
                    s.height = num (XmlIn.attr (dp, "PageHeight"), s.height);
                    s.facing = truthy (XmlIn.attr (dp, "FacingPages"));
                    s.bleed_top = num (XmlIn.attr (dp, "DocumentBleedTopOffset"), 0);
                    s.bleed_bottom = num (XmlIn.attr (dp, "DocumentBleedBottomOffset"), 0);
                    s.bleed_inside = num (XmlIn.attr (dp, "DocumentBleedInsideOrLeftOffset"), 0);
                    s.bleed_outside = num (XmlIn.attr (dp, "DocumentBleedOutsideOrRightOffset"), 0);
                    s.slug = double.max (num (XmlIn.attr (dp, "SlugTopOffset"), 0), num (XmlIn.attr (dp, "SlugBottomOffset"), 0));
                    var match = PageSize.match (s.width, s.height);
                    s.page_size = match != null ? match.id : "custom";
                }
                var mp = find_desc (root, "MarginPreference");
                if (mp != null) apply_margins (mp);
                var gp = find_desc (root, "GridPreference");
                if (gp != null) {
                    s.baseline_start = num (XmlIn.attr (gp, "BaselineStart"), s.baseline_start);
                    s.baseline_step = num (XmlIn.attr (gp, "BaselineDivision"), s.baseline_step);
                }
            } finally {
                delete doc;
            }
        }

        private void apply_margins (Xml.Node* mp) {
            var s = pub.settings;
            s.margin_top = num (XmlIn.attr (mp, "Top"), s.margin_top);
            s.margin_bottom = num (XmlIn.attr (mp, "Bottom"), s.margin_bottom);
            s.margin_inside = num (XmlIn.attr (mp, "Left"), s.margin_inside);
            s.margin_outside = num (XmlIn.attr (mp, "Right"), s.margin_outside);
            s.columns = (int) num (XmlIn.attr (mp, "ColumnCount"), s.columns);
            s.gutter = num (XmlIn.attr (mp, "ColumnGutter"), s.gutter);
        }

        private static double[] values (string? v) {
            double[] r = {};
            if (v == null) return r;
            foreach (string p in v.strip ().split_set (" \t")) if (p != "") r += Units.parse_num (p, 0);
            return r;
        }

        private static Rgba lab_to_rgb (double l, double a, double b) {
            double fy = (l + 16) / 116.0, fx = fy + a / 500.0, fz = fy - b / 200.0;
            double x = 0.95047 * (fx > 0.206897 ? fx * fx * fx : (fx - 16.0 / 116) / 7.787);
            double y = 1.0 * (fy > 0.206897 ? fy * fy * fy : (fy - 16.0 / 116) / 7.787);
            double z = 1.08883 * (fz > 0.206897 ? fz * fz * fz : (fz - 16.0 / 116) / 7.787);
            double r = 3.2406 * x - 1.5372 * y - 0.4986 * z;
            double g = -0.9689 * x + 1.8758 * y + 0.0415 * z;
            double bb = 0.0557 * x - 0.2040 * y + 1.0570 * z;
            return Rgba (gamma (r), gamma (g), gamma (bb), 1);
        }

        private static double gamma (double v) {
            v = v.clamp (0, 1);
            return v > 0.0031308 ? 1.055 * Math.pow (v, 1 / 2.4) - 0.055 : 12.92 * v;
        }

        private void read_graphic (string file) throws Error {
            Xml.Doc* doc = load (file);
            try {
                var root = doc->get_root_element ();
                colors["Swatch/None"] = ColorRef.NONE;
                foreach (var c in XmlIn.elements (root, "Color")) {
                    string self = XmlIn.attr (c, "Self") ?? "";
                    string raw = XmlIn.attr (c, "Name") ?? "";
                    string name = clean_name (raw, self.has_prefix ("Color/") ? self.substring (6) : self);
                    if (name == "Paper" || name == "Black" || name == "Registration") {
                        colors[self] = ColorRef.swatch (name);
                        continue;
                    }
                    string space = XmlIn.attr (c, "Space") ?? "CMYK";
                    double[] v = values (XmlIn.attr (c, "ColorValue"));
                    bool spot = XmlIn.attr (c, "Model") == "Spot";
                    Swatch sw;
                    if (space == "RGB" && v.length >= 3) {
                        sw = new Swatch.rgb (name, v[0] / 255.0, v[1] / 255.0, v[2] / 255.0);
                        sw.spot = spot;
                    } else if (space == "LAB" && v.length >= 3) {
                        var rgb = lab_to_rgb (v[0], v[1], v[2]);
                        sw = new Swatch.rgb (name, rgb.r, rgb.g, rgb.b);
                        sw.spot = spot;
                        warn ("lab", _("Lab colours were converted to RGB approximations."));
                    } else if (v.length >= 4) {
                        sw = new Swatch.cmyk (name, v[0] / 100, v[1] / 100, v[2] / 100, v[3] / 100, spot);
                    } else {
                        sw = new Swatch.cmyk (name, 0, 0, 0, 1, spot);
                        warn ("colorvalue", _("Some colours had no readable values and were set to black."));
                    }
                    var existing = pub.swatch (name);
                    if (existing != null) pub.swatches[pub.swatches.index_of (existing)] = sw;
                    else pub.swatches.add (sw);
                    colors[self] = ColorRef.swatch (name);
                }
                foreach (var t in XmlIn.elements (root, "Tint")) {
                    string self = XmlIn.attr (t, "Self") ?? "";
                    string base_ref = colors[XmlIn.attr (t, "BaseColor") ?? ""] ?? ColorRef.BLACK;
                    double tint = num (XmlIn.attr (t, "TintValue"), 100);
                    colors[self] = ColorRef.with_tint (base_ref, tint);
                }
                foreach (var g in XmlIn.elements (root, "Gradient")) {
                    var f = new Fill ();
                    f.kind = XmlIn.attr (g, "Type") == "Radial" ? FillKind.RADIAL : FillKind.LINEAR;
                    f.angle = 0;
                    foreach (var st in XmlIn.elements (g, "GradientStop")) {
                        string col = colors[XmlIn.attr (st, "StopColor") ?? ""] ?? ColorRef.BLACK;
                        if (col == ColorRef.NONE) col = ColorRef.PAPER;
                        f.stops.add (new GradientStop (num (XmlIn.attr (st, "Location"), 0) / 100.0, col));
                    }
                    if (f.stops.size > 0) f.color = f.stops[0].color;
                    gradients[XmlIn.attr (g, "Self") ?? ""] = f;
                }
                if (XmlIn.elements (root, "MixedInk").size > 0) warn ("mixedink", _("Mixed ink swatches are not supported and were skipped."));
            } finally {
                delete doc;
            }
        }

        private string color_ref (string? r, double tint = -1) {
            if (r == null) return ColorRef.NONE;
            string spec;
            if (colors.has_key (r)) spec = colors[r];
            else if (r.has_prefix ("Color/")) spec = ColorRef.swatch (clean_name (r.substring (6), "Black"));
            else return ColorRef.NONE;
            if (tint >= 0 && tint < 100 && spec != ColorRef.NONE) spec = ColorRef.with_tint (spec, ColorRef.tint_of (spec) * tint / 100);
            return spec;
        }

        private Fill fill_for (Xml.Node* n) {
            string? r = XmlIn.attr (n, "FillColor");
            if (r == null || r == "Swatch/None") return new Fill ();
            if (gradients.has_key (r)) {
                var f = gradients[r].clone ();
                f.angle = num (XmlIn.attr (n, "GradientFillAngle"), 0);
                return f;
            }
            string spec = color_ref (r, num (XmlIn.attr (n, "FillTint"), -1));
            return new Fill.solid (spec);
        }

        private string language (string? v) {
            if (v == null) return "";
            string l = v.down ();
            if (l.contains ("english")) return l.contains ("uk") ? "en-GB" : "en";
            if (l.contains ("german")) return "de";
            if (l.contains ("italian")) return "it";
            if (l.contains ("french")) return "fr";
            if (l.contains ("spanish")) return "es";
            if (l.contains ("portuguese")) return "pt";
            if (l.contains ("dutch")) return "nl";
            if (l.contains ("swedish")) return "sv";
            if (l.contains ("danish")) return "da";
            if (l.contains ("norwegian")) return "nb";
            if (l.contains ("finnish")) return "fi";
            if (l.contains ("polish")) return "pl";
            if (l.contains ("no_language") || l.contains ("[no language]")) return "";
            return "";
        }

        private CharFormat char_from (Xml.Node* n) {
            var f = new CharFormat ();
            string? font = prop (n, "AppliedFont");
            if (font != null && font != "") f.font = font.split ("\t")[0];
            string? style = XmlIn.attr (n, "FontStyle");
            if (style != null) {
                string s = style.down ();
                f.bold = s.contains ("bold") || s.contains ("black") || s.contains ("heavy") || s.contains ("semibold") ? 1 : 0;
                f.italic = s.contains ("italic") || s.contains ("oblique") ? 1 : 0;
            }
            string? size = XmlIn.attr (n, "PointSize");
            if (size != null) f.size = num (size, 12);
            string? fill = XmlIn.attr (n, "FillColor");
            if (fill != null) {
                string spec = color_ref (fill, num (XmlIn.attr (n, "FillTint"), -1));
                f.color = spec == ColorRef.NONE ? ColorRef.PAPER : spec;
            }
            string? tr = XmlIn.attr (n, "Tracking");
            if (tr != null) f.tracking = num (tr, 0);
            string? bs = XmlIn.attr (n, "BaselineShift");
            if (bs != null) f.baseline_shift = num (bs, 0);
            string? caps = XmlIn.attr (n, "Capitalization");
            if (caps != null) f.caps = caps == "AllCaps" ? 1 : (caps == "SmallCaps" || caps == "CapToSmallCap" ? 2 : 0);
            string? pos = XmlIn.attr (n, "Position");
            if (pos != null) f.position = pos.has_suffix ("Superscript") ? 1 : (pos.has_suffix ("Subscript") ? 2 : 0);
            string? ul = XmlIn.attr (n, "Underline");
            if (ul != null) f.underline = truthy (ul) ? 1 : 0;
            string? st = XmlIn.attr (n, "StrikeThru");
            if (st != null) f.strike = truthy (st) ? 1 : 0;
            string? lig = XmlIn.attr (n, "Ligatures");
            if (lig != null) f.ligatures = truthy (lig) ? 1 : 0;
            string? kern = XmlIn.attr (n, "KerningMethod");
            if (kern != null) f.kerning = kern.has_suffix ("None") ? 0 : 1;
            string? lang = prop (n, "AppliedLanguage");
            if (lang != null) {
                string l = language (lang);
                if (l != "") f.lang = l;
            }
            var feats = new Gee.ArrayList<string> ();
            string? fig = XmlIn.attr (n, "OTFFigureStyle");
            if (fig != null) {
                if (fig.contains ("Oldstyle")) feats.add ("onum=1");
                if (fig.has_prefix ("Tabular")) feats.add ("tnum=1");
                if (fig.has_prefix ("Proportional")) feats.add ("pnum=1");
            }
            if (truthy (XmlIn.attr (n, "OTFDiscretionaryLigature"))) feats.add ("dlig=1");
            if (truthy (XmlIn.attr (n, "OTFSwash"))) feats.add ("swsh=1");
            if (truthy (XmlIn.attr (n, "OTFOrdinal"))) feats.add ("ordn=1");
            if (truthy (XmlIn.attr (n, "OTFFraction"))) feats.add ("frac=1");
            if (truthy (XmlIn.attr (n, "OTFSlashedZero"))) feats.add ("zero=1");
            if (feats.size > 0) f.features = string.joinv (", ", feats.to_array ());
            return f;
        }

        private ParaFormat para_from (Xml.Node* n) {
            var f = new ParaFormat ();
            string? j = XmlIn.attr (n, "Justification");
            if (j != null) {
                switch (j) {
                    case "CenterAlign": f.align = (int) TextAlign.CENTER; break;
                    case "RightAlign": f.align = (int) TextAlign.RIGHT; break;
                    case "AwayFromBindingSide": f.align = (int) TextAlign.RIGHT; break;
                    case "FullyJustified": f.align = (int) TextAlign.JUSTIFY_ALL; break;
                    case "LeftJustified":
                    case "CenterJustified":
                    case "RightJustified":
                        f.align = (int) TextAlign.JUSTIFY;
                        break;
                    default: f.align = (int) TextAlign.LEFT; break;
                }
            }
            string? v;
            if ((v = XmlIn.attr (n, "FirstLineIndent")) != null) f.first_indent = num (v, 0);
            if ((v = XmlIn.attr (n, "LeftIndent")) != null) f.left_indent = num (v, 0);
            if ((v = XmlIn.attr (n, "RightIndent")) != null) f.right_indent = num (v, 0);
            if ((v = XmlIn.attr (n, "SpaceBefore")) != null) f.space_before = num (v, 0);
            if ((v = XmlIn.attr (n, "SpaceAfter")) != null) f.space_after = num (v, 0);
            if ((v = prop (n, "Leading")) != null) f.leading = v == "Auto" ? 0 : num (v, 0);
            if ((v = XmlIn.attr (n, "DropCapLines")) != null) f.drop_lines = (int) num (v, 0);
            if ((v = XmlIn.attr (n, "DropCapCharacters")) != null) f.drop_chars = (int) num (v, 0);
            if ((v = XmlIn.attr (n, "Hyphenation")) != null) f.hyphenate = truthy (v) ? 1 : 0;
            if ((v = XmlIn.attr (n, "GridAlignment")) != null) f.align_grid = v == "None" ? 0 : 1;
            if ((v = XmlIn.attr (n, "KeepWithNext")) != null) f.keep_next = num (v, 0) > 0 ? 1 : 0;
            if ((v = XmlIn.attr (n, "KeepAllLinesTogether")) != null) f.keep_lines = truthy (v) ? 1 : 0;
            if ((v = XmlIn.attr (n, "BulletsAndNumberingListType")) != null) f.list_type = v == "BulletList" ? 1 : (v == "NumberedList" ? 2 : 0);
            var props = XmlIn.child (n, "Properties");
            var bc = XmlIn.child (props, "BulletChar");
            if (bc != null) {
                int cv = (int) num (XmlIn.attr (bc, "BulletCharacterValue"), 8226);
                if (cv > 0) f.bullet = ((unichar) cv).to_string ();
            }
            if ((v = prop (n, "NumberingFormat")) != null) {
                if (v.has_prefix ("a")) f.number_format = 2;
                else if (v.has_prefix ("A")) f.number_format = 3;
                else if (v.has_prefix ("i")) f.number_format = 4;
                else if (v.has_prefix ("I")) f.number_format = 5;
                else f.number_format = 0;
            }
            if ((v = XmlIn.attr (n, "NumberingStartAt")) != null) f.number_start = (int) num (v, 1);
            if ((v = XmlIn.attr (n, "RuleAbove")) != null) f.rule_above = truthy (v) ? "%s;%s;%s".printf (XmlOut.num (num (XmlIn.attr (n, "RuleAboveLineWeight"), 1)), color_ref (XmlIn.attr (n, "RuleAboveColor") ?? "Color/Black"), XmlOut.num (num (XmlIn.attr (n, "RuleAboveOffset"), 0))) : "";
            if ((v = XmlIn.attr (n, "RuleBelow")) != null) f.rule_below = truthy (v) ? "%s;%s;%s".printf (XmlOut.num (num (XmlIn.attr (n, "RuleBelowLineWeight"), 1)), color_ref (XmlIn.attr (n, "RuleBelowColor") ?? "Color/Black"), XmlOut.num (num (XmlIn.attr (n, "RuleBelowOffset"), 0))) : "";
            var tl = XmlIn.child (props, "TabList");
            if (tl != null) {
                var tabs = new Gee.ArrayList<TabStop> ();
                foreach (var li in XmlIn.elements (tl, "ListItem")) {
                    double p = num (XmlIn.text (XmlIn.child (li, "Position")), -1);
                    if (p < 0) continue;
                    string al = XmlIn.text (XmlIn.child (li, "Alignment")).strip ();
                    TabKind k = TabKind.LEFT;
                    if (al == "RightAlign") k = TabKind.RIGHT;
                    else if (al == "CenterAlign") k = TabKind.CENTER;
                    else if (al == "CharacterAlign") k = TabKind.DECIMAL;
                    string leader = XmlIn.text (XmlIn.child (li, "Leader")).strip ();
                    tabs.add (new TabStop (p, k, leader));
                }
                f.tabs = TabStop.serialize (tabs);
            }
            return f;
        }

        private string style_ref_name (string? self, bool paragraph) {
            if (self == null || self == "") return paragraph ? StyleSheet.BASIC : "";
            var map = paragraph ? pstyles : cstyles;
            if (map.has_key (self)) return map[self];
            if (self.contains ("[No paragraph style]") || self.contains ("NormalParagraphStyle")) return StyleSheet.BASIC;
            if (self.contains ("[No character style]")) return "";
            return paragraph ? StyleSheet.BASIC : "";
        }

        private void read_styles (string file) throws Error {
            Xml.Doc* doc = load (file);
            try {
                var root = doc->get_root_element ();
                var pnodes = new Gee.ArrayList<Xml.Node*> ();
                var cnodes = new Gee.ArrayList<Xml.Node*> ();
                all_desc (root, "ParagraphStyle", pnodes);
                all_desc (root, "CharacterStyle", cnodes);
                foreach (var n in pnodes) {
                    string self = XmlIn.attr (n, "Self") ?? "";
                    string raw = XmlIn.attr (n, "Name") ?? "";
                    string name;
                    if (raw.contains ("NormalParagraphStyle") || self.has_suffix ("NormalParagraphStyle")) name = StyleSheet.BASIC;
                    else if (raw.contains ("[No paragraph style]")) name = "";
                    else name = clean_name (raw, self);
                    pstyles[self] = name == "" ? StyleSheet.BASIC : name;
                }
                foreach (var n in cnodes) {
                    string self = XmlIn.attr (n, "Self") ?? "";
                    string raw = XmlIn.attr (n, "Name") ?? "";
                    cstyles[self] = raw.contains ("[No character style]") ? "" : clean_name (raw, self);
                }
                foreach (var n in pnodes) {
                    string self = XmlIn.attr (n, "Self") ?? "";
                    string raw = XmlIn.attr (n, "Name") ?? "";
                    if (raw.contains ("[No paragraph style]")) continue;
                    string name = pstyles[self];
                    var ps = pub.styles.find_paragraph (name);
                    if (ps == null) {
                        ps = new ParagraphStyle (name);
                        pub.styles.paragraph.add (ps);
                    }
                    string? based = prop (n, "BasedOn");
                    string bname = based != null && !based.contains ("[No paragraph style]") ? style_ref_name (based, true) : "";
                    if (bname == name) bname = "";
                    if (name != StyleSheet.BASIC && bname == "") bname = "";
                    ps.based_on = bname;
                    if (!pub.styles.would_cycle (name, bname)) ps.based_on = bname;
                    else ps.based_on = "";
                    string? next = prop (n, "NextStyle");
                    ps.next = next != null ? style_ref_name (next, true) : "";
                    if (ps.next == name) ps.next = "";
                    var pf = para_from (n);
                    var cf = char_from (n);
                    if (name == StyleSheet.BASIC) {
                        ps.para.apply (pf);
                        ps.chars.apply (cf);
                    } else {
                        ps.para = pf;
                        ps.chars = cf;
                    }
                    var props = XmlIn.child (n, "Properties");
                    ps.nested.clear ();
                    ps.grep.clear ();
                    var nested = XmlIn.child (props, "AllNestedStyles");
                    if (nested != null) foreach (var li in XmlIn.elements (nested, "ListItem")) {
                        var ns = nested_from (li);
                        if (ns != null) ps.nested.add (ns);
                    }
                    var grep = XmlIn.child (props, "AllGREPStyles");
                    if (grep != null) foreach (var li in XmlIn.elements (grep, "ListItem")) {
                        string cs = style_ref_name (record_value (li, "AppliedCharacterStyle"), false);
                        string expr = record_value (li, "GrepExpression") ?? "";
                        if (cs != "" && expr != "") ps.grep.add (new GrepStyle (cs, expr));
                    }
                    var lines = XmlIn.child (props, "AllLineStyles");
                    if (lines != null && XmlIn.elements (lines).size > 0) warn ("linestyles", _("Line styles are not supported; their formatting was not applied."));
                }
                foreach (var n in cnodes) {
                    string self = XmlIn.attr (n, "Self") ?? "";
                    string name = cstyles[self];
                    if (name == "") continue;
                    var cs = pub.styles.find_character (name);
                    if (cs == null) {
                        cs = new CharacterStyle (name);
                        pub.styles.character.add (cs);
                    }
                    string? based = prop (n, "BasedOn");
                    string bname = based != null ? style_ref_name (based, false) : "";
                    cs.based_on = bname == name ? "" : bname;
                    cs.chars = char_from (n);
                }
                read_object_styles (root);
                read_table_styles (root);
            } finally {
                delete doc;
            }
        }

        private static string? record_value (Xml.Node* li, string name) {
            var c = XmlIn.child (li, name);
            return c != null ? XmlIn.text (c).strip () : null;
        }

        private NestedStyle? nested_from (Xml.Node* li) {
            string cs = style_ref_name (record_value (li, "AppliedCharacterStyle"), false);
            if (cs == "") return null;
            var ns = new NestedStyle (cs);
            ns.through = (record_value (li, "Inclusive") ?? "true") != "false";
            ns.count = int.max (1, (int) num (record_value (li, "Repetition"), 1));
            var dn = XmlIn.child (li, "Delimiter");
            string d = dn != null ? XmlIn.text (dn).strip () : "AnyWord";
            string kind = dn != null ? (XmlIn.attr (dn, "type") ?? "enumeration") : "enumeration";
            if (kind == "string") {
                ns.unit = NestedUnit.CHARACTER;
                ns.character = d;
                return ns;
            }
            switch (d) {
                case "AnyCharacter": ns.unit = NestedUnit.CHARACTERS; break;
                case "Sentence": ns.unit = NestedUnit.SENTENCES; break;
                case "Tabs": ns.unit = NestedUnit.TABS; break;
                case "Digits": ns.unit = NestedUnit.DIGITS; break;
                case "Letters": ns.unit = NestedUnit.LETTERS; break;
                case "EmSpace":
                    ns.unit = NestedUnit.CHARACTER;
                    ns.character = "\u2003";
                    break;
                case "EnSpace":
                    ns.unit = NestedUnit.CHARACTER;
                    ns.character = "\u2002";
                    break;
                case "Repeat":
                    return null;
                default: ns.unit = NestedUnit.WORDS; break;
            }
            return ns;
        }

        private static string strip_ref (string? self, string prefix) {
            if (self == null || self == "" || self == "n") return "";
            string s = self;
            if (s.has_prefix (prefix)) s = s.substring (prefix.length);
            if (s.has_prefix ("$ID/")) s = s.substring (4);
            return s;
        }

        private void read_object_styles (Xml.Node* root) {
            var nodes = new Gee.ArrayList<Xml.Node*> ();
            all_desc (root, "ObjectStyle", nodes);
            foreach (var n in nodes) {
                string self = XmlIn.attr (n, "Self") ?? "";
                string raw = clean_name (XmlIn.attr (n, "Name"), self);
                if (raw == "[None]") continue;
                ostyles[self] = raw.has_prefix ("[") && raw.has_suffix ("]") ? raw.substring (1, raw.length - 2) : raw;
            }
            foreach (var n in nodes) {
                string self = XmlIn.attr (n, "Self") ?? "";
                if (!ostyles.has_key (self)) continue;
                var os = new ObjectStyle (ostyles[self]);
                var proto = new TextFrame ();
                common (proto, n);
                os.proto = proto;
                string? based = prop (n, "BasedOn");
                if (based != null && ostyles.has_key (based) && ostyles[based] != os.name) os.based_on = ostyles[based];
                string? ap = XmlIn.attr (n, "AppliedParagraphStyle");
                if (ap != null && ap != "") {
                    os.use_para = true;
                    os.para_style = style_ref_name (ap, true);
                }
                pub.object_styles.add (os);
            }
        }

        private void read_table_styles (Xml.Node* root) {
            var cnodes = new Gee.ArrayList<Xml.Node*> ();
            all_desc (root, "CellStyle", cnodes);
            foreach (var n in cnodes) {
                string self = XmlIn.attr (n, "Self") ?? "";
                string raw = clean_name (XmlIn.attr (n, "Name"), self);
                if (raw == "[None]") continue;
                cellstyles[self] = raw;
            }
            foreach (var n in cnodes) {
                string self = XmlIn.attr (n, "Self") ?? "";
                if (!cellstyles.has_key (self)) continue;
                var cs = new CellStyle (cellstyles[self]);
                string? fc = XmlIn.attr (n, "FillColor");
                if (fc != null && fc != "") cs.fill = color_ref (fc, num (XmlIn.attr (n, "FillTint"), -1));
                string? va = XmlIn.attr (n, "VerticalJustification");
                if (va != null) cs.valign = va == "CenterAlign" ? 1 : (va == "BottomAlign" ? 2 : 0);
                string? ap = XmlIn.attr (n, "AppliedParagraphStyle");
                if (ap != null && ap != "") cs.para_style = style_ref_name (ap, true);
                string? based = prop (n, "BasedOn");
                if (based != null && cellstyles.has_key (based) && cellstyles[based] != cs.name) cs.based_on = cellstyles[based];
                if (num (XmlIn.attr (n, "LeftToRightDiagonalLineStrokeWeight"), 0) > 0) cs.diagonal = 1;
                pub.cell_styles.add (cs);
            }
            var tnodes = new Gee.ArrayList<Xml.Node*> ();
            all_desc (root, "TableStyle", tnodes);
            foreach (var n in tnodes) {
                string self = XmlIn.attr (n, "Self") ?? "";
                string raw = clean_name (XmlIn.attr (n, "Name"), self);
                if (raw == "[No Table Style]") continue;
                tstyles[self] = raw.has_prefix ("[") && raw.has_suffix ("]") ? raw.substring (1, raw.length - 2) : raw;
            }
            foreach (var n in tnodes) {
                string self = XmlIn.attr (n, "Self") ?? "";
                if (!tstyles.has_key (self)) continue;
                var ts = new TableStyle (tstyles[self]);
                string hc = XmlIn.attr (n, "HeaderRegionCellStyle") ?? "";
                string bc = XmlIn.attr (n, "BodyRegionCellStyle") ?? "";
                string lc = XmlIn.attr (n, "LeftColumnRegionCellStyle") ?? "";
                if (cellstyles.has_key (hc)) ts.header_cell = cellstyles[hc];
                if (cellstyles.has_key (bc)) ts.body_cell = cellstyles[bc];
                if (cellstyles.has_key (lc)) ts.first_col_cell = cellstyles[lc];
                string? alt = XmlIn.attr (n, "EndRowFillColor");
                if (alt != null && alt != "" && !alt.has_suffix ("None")) ts.alt_fill = color_ref (alt, num (XmlIn.attr (n, "EndRowFillTint"), -1));
                string? bcol = XmlIn.attr (n, "TopBorderStrokeColor");
                if (bcol != null && bcol != "") ts.border_color = color_ref (bcol, -1);
                string? bw = XmlIn.attr (n, "TopBorderStrokeWeight");
                if (bw != null) ts.border_width = num (bw, 0.5);
                string? based = prop (n, "BasedOn");
                if (based != null && tstyles.has_key (based) && tstyles[based] != ts.name) ts.based_on = tstyles[based];
                pub.table_styles.add (ts);
            }
        }

        private PageGeom page_geom (Xml.Node* pn, IdmlMatrix spread_t) {
            var g = new PageGeom ();
            var pt = spread_t.mul (IdmlMatrix.parse (XmlIn.attr (pn, "ItemTransform")));
            double[] gb = values (XmlIn.attr (pn, "GeometricBounds"));
            double top = 0, left = 0, bottom = pub.settings.height, right = pub.settings.width;
            if (gb.length == 4) {
                top = gb[0];
                left = gb[1];
                bottom = gb[2];
                right = gb[3];
            }
            g.to_page = IdmlMatrix.translate (-left, -top).mul (pt.invert ());
            var p0 = pt.apply (left, top);
            var p1 = pt.apply (right, bottom);
            g.spread_rect = Rect (double.min (p0.x, p1.x), double.min (p0.y, p1.y), Math.fabs (p1.x - p0.x), Math.fabs (p1.y - p0.y));
            return g;
        }

        private void read_master (string file) throws Error {
            Xml.Doc* doc = load (file);
            try {
                var ms = find_inner (doc->get_root_element (), "MasterSpread");
                if (ms == null) return;
                string self = XmlIn.attr (ms, "Self") ?? "";
                string prefix = XmlIn.attr (ms, "NamePrefix") ?? pub.next_master_id ();
                if (pub.master (prefix) != null) prefix = pub.next_master_id ();
                var m = new MasterPage (prefix, clean_name (XmlIn.attr (ms, "BaseName"), _("Master")));
                pub.masters.add (m);
                masters[self] = m;
                var geoms = new Gee.ArrayList<PageGeom> ();
                var pnodes = XmlIn.elements (ms, "Page");
                for (int i = 0; i < pnodes.size; i++) {
                    var g = page_geom (pnodes[i], IdmlMatrix.ident ());
                    g.master = m;
                    g.left = pub.settings.facing && pnodes.size > 1 && i == 0;
                    geoms.add (g);
                    string? applied = XmlIn.attr (pnodes[i], "AppliedMaster");
                    if (applied != null && applied != "n") m.based_on = applied;
                }
                foreach (var c in XmlIn.elements (ms)) {
                    PageGeom? used;
                    var it = convert (c, IdmlMatrix.ident (), geoms, null, out used);
                    if (it == null || used == null) continue;
                    m.items_for (used.left).add (it);
                }
                if (pub.settings.facing && pnodes.size == 1) single_masters.add (m);
            } finally {
                delete doc;
            }
        }

        private void resolve_master_bases () {
            foreach (var m in pub.masters) {
                if (m.based_on == "") continue;
                var b = masters.has_key (m.based_on) ? masters[m.based_on] : null;
                m.based_on = b != null && b != m ? b.id : "";
            }
        }

        private void read_spread (string file) throws Error {
            resolve_master_bases_once ();
            Xml.Doc* doc = load (file);
            try {
                var sp = find_inner (doc->get_root_element (), "Spread");
                if (sp == null) return;
                var geoms = new Gee.ArrayList<PageGeom> ();
                var pnodes = XmlIn.elements (sp, "Page");
                if (pub.pages.size == 0 && pub.settings.facing && pnodes.size > 1) pub.settings.start_left = true;
                foreach (var pn in pnodes) {
                    var g = page_geom (pn, IdmlMatrix.ident ());
                    string applied = XmlIn.attr (pn, "AppliedMaster") ?? "n";
                    var pg = pub.add_page (-1, masters.has_key (applied) ? masters[applied].id : "");
                    g.page = pg;
                    page_ids[XmlIn.attr (pn, "Self") ?? ""] = pg;
                    geoms.add (g);
                    if (pub.pages.size == 1) {
                        var mp = XmlIn.child (pn, "MarginPreference");
                        if (mp != null) {
                            apply_margins (mp);
                            if (pub.settings.facing && pub.is_left_page (0)) {
                                double t = pub.settings.margin_inside;
                                pub.settings.margin_inside = pub.settings.margin_outside;
                                pub.settings.margin_outside = t;
                            }
                        }
                    }
                }
                if (geoms.size == 0) return;
                foreach (var c in XmlIn.elements (sp)) {
                    PageGeom? used;
                    var it = convert (c, IdmlMatrix.ident (), geoms, null, out used);
                    if (it == null || used == null || used.page == null) continue;
                    used.page.items.add (it);
                }
            } finally {
                delete doc;
            }
        }

        private bool bases_done = false;

        private void resolve_master_bases_once () {
            if (bases_done) return;
            bases_done = true;
            resolve_master_bases ();
        }

        private static void anchors (Xml.Node* n, Gee.ArrayList<Point?> pts, out int paths) {
            paths = 0;
            var pg = find_desc (n, "PathGeometry");
            if (pg == null) return;
            foreach (var gp in XmlIn.elements (pg, "GeometryPathType")) {
                paths++;
                if (paths > 1) continue;
                var arr = XmlIn.child (gp, "PathPointArray");
                foreach (var pp in XmlIn.elements (arr, "PathPointType")) {
                    double[] a = values (XmlIn.attr (pp, "Anchor"));
                    if (a.length == 2) pts.add (Point (a[0], a[1]));
                }
            }
        }

        private static bool path_open (Xml.Node* n) {
            var gp = find_desc (n, "GeometryPathType");
            return gp != null && XmlIn.attr (gp, "PathOpen") == "true";
        }

        private void spread_bounds (Xml.Node* n, IdmlMatrix parent, ref double x0, ref double y0, ref double x1, ref double y1) {
            var m = parent.mul (IdmlMatrix.parse (XmlIn.attr (n, "ItemTransform")));
            if (n->name == "Group") {
                foreach (var c in XmlIn.elements (n)) {
                    if (is_item (c->name)) spread_bounds (c, m, ref x0, ref y0, ref x1, ref y1);
                }
                return;
            }
            var pts = new Gee.ArrayList<Point?> ();
            int paths;
            anchors (n, pts, out paths);
            foreach (var p in pts) {
                var q = m.apply (p.x, p.y);
                x0 = double.min (x0, q.x);
                y0 = double.min (y0, q.y);
                x1 = double.max (x1, q.x);
                y1 = double.max (y1, q.y);
            }
        }

        private static bool is_item (string name) {
            return name == "TextFrame" || name == "Rectangle" || name == "Oval" || name == "Polygon" || name == "GraphicLine" || name == "Group";
        }

        private PageGeom pick (Gee.ArrayList<PageGeom> geoms, double cx, double cy) {
            PageGeom best = geoms[0];
            double bd = double.MAX;
            foreach (var g in geoms) {
                var r = g.spread_rect;
                if (r.contains (cx, cy)) return g;
                double dx = cx < r.x ? r.x - cx : (cx > r.x2 () ? cx - r.x2 () : 0);
                double dy = cy < r.y ? r.y - cy : (cy > r.y2 () ? cy - r.y2 () : 0);
                double d = dx * dx + dy * dy;
                if (d < bd) {
                    bd = d;
                    best = g;
                }
            }
            return best;
        }

        private void geometry (Item it, IdmlMatrix m, Rect r) {
            double sx = Math.sqrt (m.a * m.a + m.b * m.b);
            double det = m.a * m.d - m.b * m.c;
            double sy = sx > 1e-12 ? det / sx : 1;
            double rot = Math.atan2 (m.b, m.a) * 180 / Math.PI;
            if (Math.fabs (rot) < 1e-6) rot = 0;
            if (sy < 0) it.flip_v = true;
            double w = r.w * sx, h = r.h * Math.fabs (sy);
            var c = m.apply (r.x + r.w / 2, r.y + r.h / 2);
            it.w = double.max (w, 0.01);
            it.h = double.max (h, 0.01);
            it.x = c.x - it.w / 2;
            it.y = c.y - it.h / 2;
            it.rotation = rot;
            double shear = m.a * m.c + m.b * m.d;
            if (Math.fabs (shear) > 1e-6 * sx * sx) warn ("skew", _("Skewed objects were imported without their skew."));
        }

        private Item? convert (Xml.Node* n, IdmlMatrix parent, Gee.ArrayList<PageGeom> geoms, PageGeom? forced, out PageGeom? used) {
            used = null;
            string name = n->name;
            if (!is_item (name)) {
                switch (name) {
                    case "Page":
                    case "Properties":
                    case "FlattenerPreference":
                    case "Guide":
                        if (name == "Guide") read_guide (n, parent, geoms);
                        return null;
                    case "TextPath":
                        warn ("textpath", _("Text on a path is not supported and was skipped."));
                        return null;
                    case "Button":
                    case "FormField":
                    case "MultiStateObject":
                    case "CheckBox":
                    case "RadioButton":
                    case "TextBox":
                    case "ListBox":
                    case "ComboBox":
                        warn ("interactive", _("Interactive objects such as buttons and form fields were skipped."));
                        return null;
                    case "EPSText":
                    case "HtmlItem":
                    case "Sound":
                    case "Movie":
                        warn ("media", _("Placed media, HTML items and EPS text were skipped."));
                        return null;
                    default:
                        return null;
                }
            }
            var ms = parent.mul (IdmlMatrix.parse (XmlIn.attr (n, "ItemTransform")));
            if (name == "Group") {
                double x0 = double.MAX, y0 = double.MAX, x1 = -double.MAX, y1 = -double.MAX;
                spread_bounds (n, parent, ref x0, ref y0, ref x1, ref y1);
                if (x0 > x1) return null;
                var g = forced ?? pick (geoms, (x0 + x1) / 2, (y0 + y1) / 2);
                var grp = new GroupItem ();
                grp.id = pub.next_id ();
                foreach (var c in XmlIn.elements (n)) {
                    PageGeom? cu;
                    var ci = convert (c, ms, geoms, g, out cu);
                    if (ci != null) grp.children.add (ci);
                }
                if (grp.children.size == 0) return null;
                grp.fit_children ();
                common (grp, n);
                used = g;
                return grp;
            }
            var pts = new Gee.ArrayList<Point?> ();
            int paths;
            anchors (n, pts, out paths);
            if (pts.size == 0) return null;
            if (paths > 1) warn ("compound", _("Compound paths were imported as their first sub-path only."));
            double sx0 = double.MAX, sy0 = double.MAX, sx1 = -double.MAX, sy1 = -double.MAX;
            double ix0 = double.MAX, iy0 = double.MAX, ix1 = -double.MAX, iy1 = -double.MAX;
            foreach (var p in pts) {
                var q = ms.apply (p.x, p.y);
                sx0 = double.min (sx0, q.x);
                sy0 = double.min (sy0, q.y);
                sx1 = double.max (sx1, q.x);
                sy1 = double.max (sy1, q.y);
                ix0 = double.min (ix0, p.x);
                iy0 = double.min (iy0, p.y);
                ix1 = double.max (ix1, p.x);
                iy1 = double.max (iy1, p.y);
            }
            var geom = forced ?? pick (geoms, (sx0 + sx1) / 2, (sy0 + sy1) / 2);
            used = geom;
            var m = geom.to_page.mul (ms);
            var inner = Rect (ix0, iy0, ix1 - ix0, iy1 - iy0);
            Item it;
            switch (name) {
                case "TextFrame":
                    it = text_frame (n, m, inner);
                    break;
                case "GraphicLine":
                    var a = m.apply (pts[0].x, pts[0].y);
                    var b = m.apply (pts[pts.size - 1].x, pts[pts.size - 1].y);
                    var line = new ShapeItem (ShapeKind.LINE);
                    line.x = double.min (a.x, b.x);
                    line.y = double.min (a.y, b.y);
                    line.w = double.max (Math.fabs (b.x - a.x), 0.01);
                    line.h = double.max (Math.fabs (b.y - a.y), 0.01);
                    line.line_reverse = (b.x - a.x) * (b.y - a.y) < 0;
                    it = line;
                    break;
                default:
                    var img = find_image (n);
                    if (img != null) {
                        var fr = new ImageFrame ();
                        geometry (fr, m, inner);
                        fr.shape_ellipse = name == "Oval";
                        image_content (fr, img, m, inner);
                        it = fr;
                    } else if (name == "Oval") {
                        var s = new ShapeItem (ShapeKind.ELLIPSE);
                        geometry (s, m, inner);
                        it = s;
                    } else if (name == "Polygon" || (pts.size != 4 && name == "Rectangle")) {
                        var s = new ShapeItem (ShapeKind.PATH);
                        geometry (s, m, inner);
                        s.closed = !path_open (n);
                        foreach (var p in pts) s.points.add (Point (inner.w > 0 ? (p.x - inner.x) / inner.w : 0, inner.h > 0 ? (p.y - inner.y) / inner.h : 0));
                        it = s;
                    } else {
                        var s = new ShapeItem (ShapeKind.RECT);
                        geometry (s, m, inner);
                        it = s;
                    }
                    break;
            }
            if (it.id == 0) it.id = pub.next_id ();
            common (it, n);
            return it;
        }

        private void read_guide (Xml.Node* n, IdmlMatrix parent, Gee.ArrayList<PageGeom> geoms) {
            string orient = XmlIn.attr (n, "Orientation") ?? "Horizontal";
            double loc = num (XmlIn.attr (n, "Location"), 0);
            var g = geoms[0];
            if (geoms.size > 1 && orient == "Vertical") {
                g = pick (geoms, loc, geoms[0].spread_rect.y + 1);
            }
            bool vertical = orient == "Vertical";
            if (g.page != null) g.page.guides.add (new Guide (vertical, loc));
            else if (g.master != null) g.master.guides.add (new Guide (vertical, loc));
        }

        private TextFrame text_frame (Xml.Node* n, IdmlMatrix m, Rect inner) {
            var t = new TextFrame ();
            t.id = pub.next_id ();
            geometry (t, m, inner);
            var tp = find_desc (n, "TextFramePreference");
            if (tp != null) {
                t.columns = int.max (1, (int) num (XmlIn.attr (tp, "TextColumnCount"), 1));
                t.gutter = num (XmlIn.attr (tp, "TextColumnGutter"), 12);
                string vj = XmlIn.attr (tp, "VerticalJustification") ?? "TopAlign";
                t.valign = vj == "CenterAlign" ? 1 : (vj == "BottomAlign" ? 2 : (vj == "JustifyAlign" ? 3 : 0));
                t.ignore_wrap = truthy (XmlIn.attr (tp, "IgnoreWrap"));
                string? inset = prop (tp, "InsetSpacing");
                double[] iv = {};
                var props = XmlIn.child (tp, "Properties");
                var isn = XmlIn.child (props, "InsetSpacing");
                if (isn != null) foreach (var li in XmlIn.elements (isn, "ListItem")) iv += num (XmlIn.text (li), 0);
                else if (inset != null) iv = values (inset);
                if (iv.length == 1) t.inset_top = t.inset_left = t.inset_bottom = t.inset_right = iv[0];
                else if (iv.length >= 4) {
                    t.inset_top = iv[0];
                    t.inset_left = iv[1];
                    t.inset_bottom = iv[2];
                    t.inset_right = iv[3];
                }
                string? auto = XmlIn.attr (tp, "AutoSizingType");
                if (auto != null && auto != "Off") t.auto_height = auto.contains ("Height");
            }
            var link = new FrameLink ();
            link.frame = t;
            link.self = XmlIn.attr (n, "Self") ?? "";
            link.story = XmlIn.attr (n, "ParentStory") ?? "";
            link.prev = XmlIn.attr (n, "PreviousTextFrame") ?? "n";
            link.next = XmlIn.attr (n, "NextTextFrame") ?? "n";
            links.add (link);
            return t;
        }

        private static Xml.Node* find_image (Xml.Node* n) {
            foreach (var c in XmlIn.elements (n)) {
                switch (c->name) {
                    case "Image":
                    case "PDF":
                    case "EPS":
                    case "WMF":
                    case "PICT":
                    case "ImportedPage":
                        return c;
                    default:
                        break;
                }
            }
            return null;
        }

        private void image_content (ImageFrame fr, Xml.Node* img, IdmlMatrix m, Rect inner) {
            if (img->name != "Image") warn ("vectorplaced", _("Placed PDF, EPS and other vector files are linked but cannot be previewed or printed by Publish."));
            var it = IdmlMatrix.parse (XmlIn.attr (img, "ItemTransform"));
            double gl = 0, gt = 0;
            var gb = find_desc (img, "GraphicBounds");
            if (gb != null) {
                gl = num (XmlIn.attr (gb, "Left"), 0);
                gt = num (XmlIn.attr (gb, "Top"), 0);
            }
            double sx = Math.sqrt (m.a * m.a + m.b * m.b);
            double det = m.a * m.d - m.b * m.c;
            double sy = sx > 1e-12 ? Math.fabs (det / sx) : 1;
            var o = it.apply (gl, gt);
            fr.fit = FitMode.MANUAL;
            fr.img_x = (o.x - inner.x) * sx;
            fr.img_y = (o.y - inner.y) * sy;
            fr.img_scale = Math.sqrt (it.a * it.a + it.b * it.b) * sx;
            if (Math.fabs (it.b) > 1e-6 || Math.fabs (it.c) > 1e-6) warn ("imgrot", _("Rotated images inside frames were imported without their rotation."));
            var ln = XmlIn.child (img, "Link");
            if (ln != null) {
                string uri = XmlIn.attr (ln, "LinkResourceURI") ?? "";
                fr.link = uri_to_path (uri);
            }
            var props = XmlIn.child (img, "Properties");
            var contents = XmlIn.child (props, "Contents");
            if (contents != null) {
                var data = Base64.decode (XmlIn.text (contents).strip ());
                if (data.length > 0) {
                    string ext = ImageStore.sniff (data);
                    fr.media = pub.add_media (data, "image." + (ext == "" ? "bin" : ext));
                    fr.link = "";
                }
            }
        }

        public static string uri_to_path (string uri) {
            if (uri == "") return "";
            string u = uri;
            if (u.has_prefix ("file://")) u = u.substring (7);
            else if (u.has_prefix ("file:")) u = u.substring (5);
            string? dec = Uri.unescape_string (u);
            u = dec ?? u;
            if (u.length > 2 && u[0] == '/' && u[2] == ':') u = u.substring (1);
            return u;
        }

        private void common (Item it, Xml.Node* n) {
            string? nm = XmlIn.attr (n, "Name");
            if (nm != null && !nm.has_prefix ("$ID/")) it.name = nm;
            string? layer = XmlIn.attr (n, "ItemLayer");
            it.layer = layer != null && layers.has_key (layer) ? layers[layer] : pub.layers[pub.layers.size - 1].id;
            it.locked = truthy (XmlIn.attr (n, "Locked"));
            it.hidden = XmlIn.attr (n, "Visible") == "false";
            it.nonprinting = truthy (XmlIn.attr (n, "Nonprinting"));
            string? aos = XmlIn.attr (n, "AppliedObjectStyle");
            if (aos != null && ostyles.has_key (aos)) it.object_style = ostyles[aos];
            if (!(it is GroupItem)) {
                it.fill = fill_for (n);
                string sc = color_ref (XmlIn.attr (n, "StrokeColor"), num (XmlIn.attr (n, "StrokeTint"), -1));
                double sw = num (XmlIn.attr (n, "StrokeWeight"), 1);
                if (sc != ColorRef.NONE && sw > 0) {
                    var s = new Stroke.with (sc, sw);
                    string st = XmlIn.attr (n, "StrokeType") ?? "";
                    if (st.contains ("Dashed")) s.dash = DashKind.DASH;
                    else if (st.contains ("Dotted")) s.dash = DashKind.DOT;
                    else if (st != "" && !st.contains ("Solid")) warn ("stroketype", _("Striped and custom stroke types were imported as solid strokes."));
                    s.arrow_start = arrow (XmlIn.attr (n, "LeftLineEnd"));
                    s.arrow_end = arrow (XmlIn.attr (n, "RightLineEnd"));
                    string cap = XmlIn.attr (n, "EndCap") ?? "";
                    s.cap = cap == "RoundEndCap" ? 1 : (cap == "ProjectingEndCap" ? 2 : 0);
                    string join = XmlIn.attr (n, "EndJoin") ?? "";
                    s.join = join == "RoundEndJoin" ? 1 : (join == "BevelEndJoin" ? 2 : 0);
                    it.stroke = s;
                }
                string corner = XmlIn.attr (n, "CornerOption") ?? XmlIn.attr (n, "TopLeftCornerOption") ?? "None";
                double radius = num (XmlIn.attr (n, "CornerRadius") ?? XmlIn.attr (n, "TopLeftCornerRadius"), 0);
                switch (corner) {
                    case "RoundedCorner": it.corner = CornerKind.ROUNDED; break;
                    case "BevelCorner": it.corner = CornerKind.BEVEL; break;
                    case "InsetCorner": it.corner = CornerKind.INSET; break;
                    case "InverseRoundedCorner": it.corner = CornerKind.INVERSE_ROUNDED; break;
                    case "FancyCorner":
                        it.corner = CornerKind.ROUNDED;
                        warn ("fancy", _("Fancy corners were imported as rounded corners."));
                        break;
                    default: break;
                }
                if (it.corner != CornerKind.NONE) it.corner_radius = radius;
            }
            var tr = XmlIn.child (n, "TransparencySetting");
            if (tr != null) {
                var bl = XmlIn.child (tr, "BlendingSetting");
                if (bl != null) {
                    it.opacity = num (XmlIn.attr (bl, "Opacity"), 100) / 100.0;
                    string mode = XmlIn.attr (bl, "BlendMode") ?? "Normal";
                    if (mode != "Normal") warn ("blend", _("Blending modes other than Normal are not supported."));
                }
                var ds = XmlIn.child (tr, "DropShadowSetting");
                if (ds != null && (XmlIn.attr (ds, "Mode") ?? "None") != "None") {
                    it.shadow.enabled = true;
                    it.shadow.dx = num (XmlIn.attr (ds, "XOffset"), 7);
                    it.shadow.dy = num (XmlIn.attr (ds, "YOffset"), 7);
                    it.shadow.blur = num (XmlIn.attr (ds, "Size"), 5);
                    it.shadow.opacity = num (XmlIn.attr (ds, "Opacity"), 75) / 100.0;
                    string ec = color_ref (XmlIn.attr (ds, "EffectColor") ?? "Color/Black");
                    it.shadow.color = ec == ColorRef.NONE ? ColorRef.BLACK : ec;
                }
                foreach (var e in XmlIn.elements (tr)) {
                    if (e->name == "BlendingSetting" || e->name == "DropShadowSetting") continue;
                    string? applied = XmlIn.attr (e, "Applied");
                    string? mode = XmlIn.attr (e, "Mode");
                    if (truthy (applied) || (mode != null && mode != "None")) warn ("effects", _("Effects other than drop shadows (glows, bevels, feathering) were not imported."));
                }
            }
            var wp = XmlIn.child (n, "TextWrapPreference");
            if (wp != null) {
                string mode = XmlIn.attr (wp, "TextWrapMode") ?? "None";
                switch (mode) {
                    case "BoundingBoxTextWrap": it.wrap = WrapMode.BOUNDING_BOX; break;
                    case "Contour": it.wrap = WrapMode.CONTOUR; break;
                    case "JumpObjectTextWrap": it.wrap = WrapMode.JUMP; break;
                    case "NextColumnTextWrap":
                        it.wrap = WrapMode.JUMP;
                        warn ("nextcol", _("Jump to next column wrap was imported as jump object wrap."));
                        break;
                    default: it.wrap = WrapMode.NONE; break;
                }
                string side = XmlIn.attr (wp, "TextWrapSide") ?? "BothSides";
                switch (side) {
                    case "LeftSide": it.wrap_side = WrapSide.LEFT; break;
                    case "RightSide": it.wrap_side = WrapSide.RIGHT; break;
                    case "LargestArea": it.wrap_side = WrapSide.LARGEST; break;
                    default: it.wrap_side = WrapSide.BOTH; break;
                }
                var off = find_desc (wp, "TextWrapOffset");
                if (off != null) {
                    double o = 0;
                    foreach (string k in new string[] { "Top", "Left", "Bottom", "Right" }) o = double.max (o, num (XmlIn.attr (off, k), 0));
                    it.wrap_offset = o;
                } else {
                    it.wrap_offset = 0;
                }
                if (truthy (XmlIn.attr (wp, "Inverse"))) warn ("inverse", _("Inverted text wrap is not supported."));
            }
        }

        private static int arrow (string? v) {
            if (v == null || v == "None") return 0;
            if (v.contains ("Circle")) return 2;
            return 1;
        }

        private void read_story_file (string file) throws Error {
            Xml.Doc* doc = load (file, true);
            try {
                var sn = find_inner (doc->get_root_element (), "Story");
                if (sn == null) return;
                string self = XmlIn.attr (sn, "Self") ?? file;
                var st = new Story (pub.next_id ());
                current_story = self;
                parse_text (sn, st);
                pub.stories[st.id] = st;
                stories[self] = st;
            } finally {
                delete doc;
            }
        }

        private class TextState {
            public Paragraph cur;
            public string pstyle = StyleSheet.BASIC;
            public ParaFormat pfmt = new ParaFormat ();
            public CharFormat pchar = new CharFormat ();
            public bool fresh = true;
        }

        private void parse_text (Xml.Node* container, Story st) {
            st.paras.clear ();
            var s = new TextState ();
            s.cur = new Paragraph (StyleSheet.BASIC);
            st.paras.add (s.cur);
            walk_text (container, st, s, "", new CharFormat ());
            foreach (var p in st.paras) {
                if (p.runs.size == 0) p.runs.add (new Run (""));
                p.normalize ();
            }
        }

        private void add_run (TextState s, string text, string field, string cstyle, CharFormat cf) {
            Run r = field != "" ? new Run.field_run (field) : new Run (text);
            r.cstyle = cstyle;
            var f = s.pchar.clone ();
            f.apply (cf);
            r.fmt = f;
            s.cur.runs.add (r);
            s.fresh = false;
        }

        private void new_paragraph (Story st, TextState s) {
            s.cur = new Paragraph (s.pstyle);
            s.cur.fmt = s.pfmt.clone ();
            st.paras.add (s.cur);
            s.fresh = true;
        }

        private void walk_text (Xml.Node* node, Story st, TextState s, string cstyle, CharFormat cf) {
            for (Xml.Node* c = node->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                switch (c->name) {
                    case "ParagraphStyleRange":
                        string saved_style = s.pstyle;
                        var saved_fmt = s.pfmt;
                        var saved_char = s.pchar;
                        s.pstyle = style_ref_name (XmlIn.attr (c, "AppliedParagraphStyle"), true);
                        s.pfmt = para_from (c);
                        s.pchar = char_from (c);
                        if (s.fresh) {
                            s.cur.style = s.pstyle;
                            s.cur.fmt = s.pfmt.clone ();
                        }
                        walk_text (c, st, s, "", new CharFormat ());
                        s.pstyle = saved_style;
                        s.pfmt = saved_fmt;
                        s.pchar = saved_char;
                        break;
                    case "CharacterStyleRange":
                        string cs = style_ref_name (XmlIn.attr (c, "AppliedCharacterStyle"), false);
                        var f = cf.clone ();
                        f.apply (char_from (c));
                        string? cond = XmlIn.attr (c, "AppliedConditions");
                        if (cond != null && cond != "") warn ("conditions", _("Conditional text was imported as regular text."));
                        walk_text (c, st, s, cs, f);
                        break;
                    case "Content":
                        for (Xml.Node* t = c->children; t != null; t = t->next) {
                            if (t->type == Xml.ElementType.TEXT_NODE || t->type == Xml.ElementType.CDATA_SECTION_NODE) {
                                string text = t->content ?? "";
                                string[] parts = text.split ("\u2029");
                                for (int i = 0; i < parts.length; i++) {
                                    if (i > 0) new_paragraph (st, s);
                                    if (parts[i] != "") add_run (s, parts[i], "", cstyle, cf);
                                }
                            } else if (t->type == Xml.ElementType.PI_NODE) {
                                string code = (t->content ?? "").strip ();
                                switch (code) {
                                    case "18":
                                        add_run (s, "", Fields.PAGE, cstyle, cf);
                                        break;
                                    case "19":
                                        add_run (s, "", Fields.SECTION, cstyle, cf);
                                        break;
                                    case "3":
                                        add_run (s, "\t", "", cstyle, cf);
                                        break;
                                    case "4":
                                        break;
                                    default:
                                        warn ("special", _("Some special characters (markers and indent-to-here) were dropped."));
                                        break;
                                }
                            }
                        }
                        break;
                    case "Br":
                        new_paragraph (st, s);
                        break;
                    case "TextVariableInstance":
                        string var_name = (XmlIn.attr (c, "AssociatedTextVariable") ?? "").down ();
                        if (var_name.contains ("page") && var_name.contains ("count")) add_run (s, "", Fields.PAGES, cstyle, cf);
                        else add_run (s, XmlIn.attr (c, "ResultText") ?? "", "", cstyle, cf);
                        break;
                    case "Table":
                        read_table (c);
                        warn ("tables", _("Tables anchored in text were placed as table objects at the top of their text frame, with text wrapping around them."));
                        break;
                    case "Footnote":
                        var note = new Story (0);
                        parse_text (c, note);
                        foreach (var np in note.paras) {
                            if (np.style == StyleSheet.BASIC) np.style = pub.footnotes.para_style;
                            if (np.runs.size > 0 && np.runs[0].text.has_prefix ("\t")) np.runs[0].text = np.runs[0].text.substring (1);
                        }
                        Footnotes.ensure_style (pub);
                        var fr = new Run.field_run (FootnoteOptions.FIELD);
                        fr.note = note;
                        fr.cstyle = cstyle;
                        s.cur.runs.add (fr);
                        s.fresh = false;
                        break;
                    case "Note":
                        warn ("notes", _("Editorial notes were left out."));
                        break;
                    case "XMLElement":
                        warn ("xml", _("XML tags were dropped; their tagged text was kept."));
                        walk_text (c, st, s, cstyle, cf);
                        break;
                    case "HyperlinkTextSource":
                    case "HyperlinkTextDestination":
                    case "CrossReferenceSource":
                    case "Change":
                        if (c->name == "Change" && XmlIn.attr (c, "ChangeType") == "DeletedText") break;
                        if (c->name == "Change") warn ("changes", _("Tracked changes were accepted during import."));
                        walk_text (c, st, s, cstyle, cf);
                        break;
                    case "TextFrame":
                    case "Rectangle":
                    case "Oval":
                    case "Polygon":
                    case "GraphicLine":
                    case "Group":
                        var anchored = anchored_item (c);
                        if (anchored != null) {
                            var ar = new Run.anchored (anchored, anchor_spec_of (c));
                            ar.cstyle = cstyle;
                            s.cur.runs.add (ar);
                            s.fresh = false;
                        } else {
                            warn ("anchored", _("Some anchored objects could not be read and were left out."));
                        }
                        break;
                    default:
                        break;
                }
            }
        }

        private Item? anchored_item (Xml.Node* n) {
            var geom = new PageGeom ();
            geom.to_page = IdmlMatrix.ident ();
            geom.spread_rect = Rect (-100000, -100000, 200000, 200000);
            geom.page = null;
            geom.master = null;
            var geoms = new Gee.ArrayList<PageGeom> ();
            geoms.add (geom);
            PageGeom? used;
            var own = IdmlMatrix.parse (XmlIn.attr (n, "ItemTransform"));
            var it = convert (n, own.invert (), geoms, geom, out used);
            if (it == null) return null;
            var b = it.bounds ();
            if (it is GroupItem) ((GroupItem) it).move_by (-b.x, -b.y);
            else {
                it.x -= b.x;
                it.y -= b.y;
            }
            return it;
        }

        private AnchorSpec anchor_spec_of (Xml.Node* n) {
            var spec = new AnchorSpec ();
            var props = XmlIn.child (n, "AnchoredObjectSetting");
            if (props == null) props = XmlIn.child (XmlIn.child (n, "Properties"), "AnchoredObjectSetting");
            if (props == null) return spec;
            string pos = XmlIn.attr (props, "AnchoredPosition") ?? "InlinePosition";
            if (pos == "Anchored") {
                spec.mode = 1;
                spec.x_ref = (XmlIn.attr (props, "HorizontalReferencePoint") ?? "") == "TextFrame" ? 1 : 0;
                spec.x_offset = num (XmlIn.attr (props, "AnchorXoffset"), 0);
                spec.y_offset = num (XmlIn.attr (props, "AnchorYoffset"), 0);
            } else {
                spec.y_offset = -num (XmlIn.attr (props, "AnchorYoffset"), 0);
            }
            return spec;
        }

        private void read_table (Xml.Node* n) {
            var rows = XmlIn.elements (n, "Row");
            var cols = XmlIn.elements (n, "Column");
            int nr = int.max (1, (int) num (XmlIn.attr (n, "HeaderRowCount"), 0) + (int) num (XmlIn.attr (n, "BodyRowCount"), 0) + (int) num (XmlIn.attr (n, "FooterRowCount"), 0));
            int nc = int.max (1, (int) num (XmlIn.attr (n, "ColumnCount"), 0));
            nr = int.max (nr, rows.size);
            nc = int.max (nc, cols.size);
            var t = new TableItem (nr, nc);
            t.id = pub.next_id ();
            t.layer = pub.layers[pub.layers.size - 1].id;
            t.header_rows = (int) num (XmlIn.attr (n, "HeaderRowCount"), 0);
            string ats = XmlIn.attr (n, "AppliedTableStyle") ?? "";
            for (int c = 0; c < nc; c++) t.col_w.add (c < cols.size ? num (XmlIn.attr (cols[c], "SingleColumnWidth"), 72) : 72);
            for (int r = 0; r < nr; r++) {
                double h = 20;
                if (r < rows.size) h = num (XmlIn.attr (rows[r], "SingleRowHeight") ?? XmlIn.attr (rows[r], "MinimumHeight"), 20);
                t.row_h.add (h);
            }
            for (int r = 0; r < nr; r++) {
                var row = new Gee.ArrayList<Cell> ();
                for (int c = 0; c < nc; c++) row.add (new Cell (pub.next_id ()));
                t.cells.add (row);
            }
            double w = 0, h = 0;
            foreach (var v in t.col_w) w += v;
            foreach (var v in t.row_h) h += v;
            t.w = w;
            t.h = h;
            foreach (var cn in XmlIn.elements (n, "Cell")) {
                string[] parts = (XmlIn.attr (cn, "Name") ?? "0:0").split (":");
                if (parts.length != 2) continue;
                int c = int.parse (parts[0]), r = int.parse (parts[1]);
                if (r < 0 || r >= nr || c < 0 || c >= nc) continue;
                var cell = t.cells[r][c];
                cell.row_span = int.max (1, (int) num (XmlIn.attr (cn, "RowSpan"), 1));
                cell.col_span = int.max (1, (int) num (XmlIn.attr (cn, "ColumnSpan"), 1));
                string fc = color_ref (XmlIn.attr (cn, "FillColor"), num (XmlIn.attr (cn, "FillTint"), -1));
                cell.fill = fc;
                string va = XmlIn.attr (cn, "VerticalJustification") ?? "TopAlign";
                cell.valign = va == "CenterAlign" ? 1 : (va == "BottomAlign" ? 2 : 0);
                string acs = XmlIn.attr (cn, "AppliedCellStyle") ?? "";
                if (cellstyles.has_key (acs)) cell.cell_style = cellstyles[acs];
                parse_text (cn, cell.story);
                for (int rr = r; rr < r + cell.row_span && rr < nr; rr++) for (int cc = c; cc < c + cell.col_span && cc < nc; cc++) {
                    if (rr != r || cc != c) t.cells[rr][cc].covered = true;
                }
            }
            if (tstyles.has_key (ats)) {
                string keep_border = t.border_color;
                TableStyles.apply_table (pub, t, tstyles[ats]);
                if (t.border_color == "") t.border_color = keep_border;
            }
            var pt = new PendingTable ();
            pt.story = current_story;
            pt.table = t;
            tables.add (pt);
        }

        private void link_frames () {
            var by_self = new Gee.HashMap<string, FrameLink> ();
            foreach (var l in links) by_self[l.self] = l;
            foreach (var st in pub.stories.values) st.frames.clear ();
            foreach (var l in links) {
                if (!stories.has_key (l.story)) {
                    var ns = pub.new_story ();
                    ns.frames.add (l.frame.id);
                    l.frame.story = ns.id;
                    warn ("nostory", _("Some text frames referred to missing stories and were imported empty."));
                    continue;
                }
                l.frame.story = stories[l.story].id;
            }
            var done = new Gee.HashSet<FrameLink> ();
            foreach (var l in links) {
                if (!stories.has_key (l.story) || done.contains (l)) continue;
                bool head = l.prev == "n" || !by_self.has_key (l.prev);
                if (!head) continue;
                var st = stories[l.story];
                FrameLink? cur = l;
                int guard = 0;
                while (cur != null && !done.contains (cur) && guard++ < 10000) {
                    done.add (cur);
                    cur.frame.story = st.id;
                    st.frames.add (cur.frame.id);
                    cur = cur.next != "n" && by_self.has_key (cur.next) ? by_self[cur.next] : null;
                }
            }
            foreach (var l in links) {
                if (done.contains (l) || !stories.has_key (l.story)) continue;
                stories[l.story].frames.add (l.frame.id);
            }
        }

        private void place_tables () {
            foreach (var pt in tables) {
                if (!stories.has_key (pt.story)) continue;
                var st = stories[pt.story];
                if (st.frames.size == 0) continue;
                var r = pub.find_item (st.frames[0]);
                if (r == null) continue;
                var f = (TextFrame) r.item;
                var t = pt.table;
                t.x = f.x + f.inset_left;
                t.y = f.y + f.inset_top;
                t.layer = f.layer;
                t.wrap = WrapMode.JUMP;
                t.wrap_offset = 6;
                int idx = r.list.index_of (f);
                r.list.insert (idx + 1, t);
            }
        }

        private void read_sections (Gee.ArrayList<Xml.Node*> nodes) {
            foreach (var n in nodes) {
                string ps = XmlIn.attr (n, "PageStart") ?? "";
                if (!page_ids.has_key (ps)) continue;
                int idx = pub.pages.index_of (page_ids[ps]);
                if (idx < 0) continue;
                var s = new Section (idx);
                s.continue_numbering = XmlIn.attr (n, "ContinueNumbering") != "false";
                s.start_number = (int) num (XmlIn.attr (n, "PageNumberStart"), 1);
                s.prefix = XmlIn.attr (n, "SectionPrefix") ?? "";
                if (!truthy (XmlIn.attr (n, "IncludeSectionPrefix"))) s.prefix = "";
                s.name = XmlIn.attr (n, "Marker") ?? XmlIn.attr (n, "Name") ?? "";
                string style = XmlIn.attr (n, "PageNumberStyle") ?? "Arabic";
                if (style == "LowerRoman") s.style = NumberStyle.ROMAN_LOWER;
                else if (style == "UpperRoman") s.style = NumberStyle.ROMAN_UPPER;
                else if (style == "LowerLetters") s.style = NumberStyle.ALPHA_LOWER;
                else if (style == "UpperLetters") s.style = NumberStyle.ALPHA_UPPER;
                pub.sections.add (s);
            }
        }
    }
}
