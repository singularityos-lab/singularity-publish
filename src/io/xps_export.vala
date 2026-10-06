namespace Singularity.Apps.Publish {

    public errordomain XpsError {
        UNSUPPORTED
    }

    public class XpsFont {
        public string path;
        public int index;
        public string part;
        public uint8[] data;

        public XpsFont (string path, int index, string part, uint8[] data) {
            this.path = path;
            this.index = index;
            this.part = part;
            this.data = data;
        }
    }

    public class XpsResources {
        public Gee.HashMap<string, XpsFont> fonts = new Gee.HashMap<string, XpsFont> ();
        public Gee.ArrayList<string> image_parts = new Gee.ArrayList<string> ();
        public Gee.ArrayList<Bytes> image_data = new Gee.ArrayList<Bytes> ();
        public Gee.HashSet<string> page_parts = new Gee.HashSet<string> ();

        public static string new_guid () {
            var sb = new StringBuilder ();
            for (int i = 0; i < 32; i++) {
                if (i == 8 || i == 12 || i == 16 || i == 20) sb.append_c ('-');
                sb.append ("%X".printf (Random.int_range (0, 16)));
            }
            return sb.str;
        }

        public static uint8[] obfuscate (uint8[] font, string guid) {
            int[] map = { 6, 4, 2, 0, 11, 9, 16, 14, 19, 21, 24, 26, 28, 30, 32, 34 };
            var key = new uint8[16];
            for (int i = 0; i < 16; i++) key[i] = (uint8) uint64.parse ("0x" + guid.substring (map[i], 2));
            var out_data = new uint8[font.length];
            Memory.copy (out_data, font, font.length);
            for (int i = 0; i < 32 && i < out_data.length; i++) out_data[i] ^= key[15 - (i % 16)];
            return out_data;
        }

        public XpsFont? font_for (string path, int index) {
            string key = "%s#%d".printf (path, index);
            if (fonts.has_key (key)) {
                page_parts.add (fonts[key].part);
                return fonts[key];
            }
            string low = path.down ();
            if (!(low.has_suffix (".ttf") || low.has_suffix (".otf") || low.has_suffix (".ttc") || low.has_suffix (".otc"))) return null;
            uint8[] data;
            try {
                FileUtils.get_data (path, out data);
            } catch (Error e) {
                return null;
            }
            if (data.length < 12) return null;
            string guid = new_guid ();
            var f = new XpsFont (path, index, "/Resources/Fonts/%s.odttf".printf (guid), obfuscate (data, guid));
            fonts[key] = f;
            page_parts.add (f.part);
            return f;
        }

        public string add_image (uint8[] data, string ext) {
            string part = "/Resources/Images/%d.%s".printf (image_parts.size + 1, ext);
            image_parts.add (part);
            image_data.add (new Bytes (data));
            page_parts.add (part);
            return part;
        }
    }

    public class XpsGlyphSink : GlyphSink {
        public StringBuilder out_xml = new StringBuilder ();
        public XpsResources res;
        public double opacity = 1;
        public bool invisible = false;
        public int runs = 0;

        public XpsGlyphSink (XpsResources res) {
            this.res = res;
        }

        private static string n (double v) {
            return XmlOut.num (Math.round (v * 1000) / 1000);
        }

        private static string color (double r, double g, double b, double a) {
            return "#%02X%02X%02X%02X".printf ((int) Math.round (a.clamp (0, 1) * 255), (int) Math.round (r.clamp (0, 1) * 255), (int) Math.round (g.clamp (0, 1) * 255), (int) Math.round (b.clamp (0, 1) * 255));
        }

        private static string unicode_attr (string s) {
            string e = XmlOut.esc (s);
            return s.has_prefix ("{") ? "{}" + e : e;
        }

        public override bool line (Cairo.Context cr, Pango.LayoutLine line, double x, double y) {
            var src = cr.get_source ();
            double r = 0, g = 0, b = 0, a = 1;
            if (src.get_type () != Cairo.PatternType.SOLID) return false;
            src.get_rgba (out r, out g, out b, out a);
            unowned string text = line.layout.get_text ();
            var runs_list = new Gee.ArrayList<unowned Pango.GlyphItem> ();
            var fonts = new Gee.ArrayList<XpsFont> ();
            var sizes = new Gee.ArrayList<double?> ();
            var bolds = new Gee.ArrayList<bool> ();
            foreach (unowned Pango.GlyphItem run in line.runs) {
                if ((run.item.analysis.level & 1) == 1) return false;
                var font = run.item.analysis.font;
                if (font == null || !font.get_type ().is_a (PangoFc.font_type ())) return false;
                unowned Fc.Pattern? pat = PangoFc.font_pattern (font);
                if (pat == null) return false;
                unowned string file;
                if (pat.get_string ("file", 0, out file) != Fc.Result.Match || file == null) return false;
                int index = 0;
                pat.get_integer ("index", 0, out index);
                var xf = res.font_for (file, index & 0xFFFF);
                if (xf == null) return false;
                bool embolden = false;
                pat.get_bool ("embolden", 0, out embolden);
                double size = font.describe_with_absolute_size ().get_size () / (double) Pango.SCALE;
                if (size <= 0) return false;
                runs_list.add (run);
                fonts.add (xf);
                sizes.add (size);
                bolds.add (embolden);
            }
            var m = cr.get_matrix ();
            string transform = "%s,%s,%s,%s,%s,%s".printf (n (m.xx), n (m.yx), n (m.xy), n (m.yy), n (m.x0), n (m.y0));
            double pen = x;
            for (int ri = 0; ri < runs_list.size; ri++) {
                unowned Pango.GlyphItem run = runs_list[ri];
                double size = sizes[ri];
                unowned Pango.GlyphString gs = run.glyphs;
                int item_off = run.item.offset;
                int item_len = run.item.length;
                string item_text = text.substring (item_off, item_len);
                double run_x = pen;
                var ustr = new StringBuilder ();
                var gids = new Gee.ArrayList<uint> ();
                var advs = new Gee.ArrayList<double?> ();
                var xos = new Gee.ArrayList<double?> ();
                var yos = new Gee.ArrayList<double?> ();
                var prefix = new Gee.ArrayList<string> ();
                int gi = 0;
                int count = gs.num_glyphs;
                while (gi < count) {
                    int cstart = gs.log_clusters[gi];
                    int gj = gi;
                    while (gj < count && gs.log_clusters[gj] == cstart) gj++;
                    int cend = gj < count ? gs.log_clusters[gj] : item_len;
                    if (cend < cstart) return false;
                    string ctext = item_text.substring (cstart, cend - cstart);
                    int nchars = ctext.char_count ();
                    int real = 0;
                    for (int k = gi; k < gj; k++) if (gs.glyphs[k].glyph != 0x0FFFFFFF) real++;
                    if (real > 0) ustr.append (ctext);
                    bool first_in_cluster = true;
                    for (int k = gi; k < gj; k++) {
                        uint gid = gs.glyphs[k].glyph;
                        double adv = gs.glyphs[k].geometry.width / (double) Pango.SCALE;
                        if (gid == 0x0FFFFFFF) {
                            if (advs.size > 0) advs[advs.size - 1] = (double) advs[advs.size - 1] + adv;
                            else run_x += adv;
                            continue;
                        }
                        if ((gid & 0x10000000) != 0) gid = 0;
                        gids.add (gid);
                        advs.add (adv);
                        xos.add (gs.glyphs[k].geometry.x_offset / (double) Pango.SCALE);
                        yos.add (gs.glyphs[k].geometry.y_offset / (double) Pango.SCALE);
                        prefix.add (first_in_cluster && (nchars != 1 || real != 1) ? "(%d:%d)".printf (int.max (1, nchars), real) : "");
                        first_in_cluster = false;
                    }
                    gi = gj;
                }
                var idx = new StringBuilder ();
                for (int k = 0; k < gids.size; k++) {
                    if (k > 0) idx.append_c (';');
                    idx.append ("%s%u,%s".printf (prefix[k], gids[k], n (advs[k] / size * 100)));
                    double xo = xos[k], yo = yos[k];
                    if (Math.fabs (xo) > 0.001 || Math.fabs (yo) > 0.001) idx.append (",%s,%s".printf (n (xo / size * 100), n (-yo / size * 100)));
                }
                double run_w = 0;
                for (int k = 0; k < count; k++) run_w += gs.glyphs[k].geometry.width / (double) Pango.SCALE;
                pen += run_w;
                double fr = r, fg = g, fb = b, fa = a;
                int underline = 0;
                bool strike = false;
                foreach (void* ptr in run.item.analysis.extra_attrs) {
                    unowned Pango.Attribute at = (Pango.Attribute) ptr;
                    var t = at.klass.type;
                    if (t == Pango.AttrType.FOREGROUND) {
                        unowned Pango.AttrColor ac = (Pango.AttrColor) at;
                        fr = ac.color.red / 65535.0;
                        fg = ac.color.green / 65535.0;
                        fb = ac.color.blue / 65535.0;
                    } else if (t == Pango.AttrType.FOREGROUND_ALPHA) {
                        fa = a * ((Pango.AttrInt) at).value / 65535.0;
                    } else if (t == Pango.AttrType.UNDERLINE) {
                        underline = ((Pango.AttrInt) at).value;
                    } else if (t == Pango.AttrType.STRIKETHROUGH) {
                        strike = ((Pango.AttrInt) at).value != 0;
                    }
                }
                if ((underline != 0 || strike) && !invisible) {
                    var metrics = run.item.analysis.font.get_metrics (null);
                    string lc = color (fr, fg, fb, fa);
                    if (underline != 0) {
                        double th = double.max (0.3, metrics.get_underline_thickness () / (double) Pango.SCALE);
                        double uy = y - metrics.get_underline_position () / (double) Pango.SCALE + th / 2;
                        out_xml.append ("<Path RenderTransform=\"%s\" Data=\"M %s,%s L %s,%s\" Stroke=\"%s\" StrokeThickness=\"%s\"/>".printf (transform, n (run_x), n (uy), n (run_x + run_w), n (uy), lc, n (th)));
                        if (underline == (int) Pango.Underline.DOUBLE) out_xml.append ("<Path RenderTransform=\"%s\" Data=\"M %s,%s L %s,%s\" Stroke=\"%s\" StrokeThickness=\"%s\"/>".printf (transform, n (run_x), n (uy + 2 * th), n (run_x + run_w), n (uy + 2 * th), lc, n (th)));
                    }
                    if (strike) {
                        double th = double.max (0.3, metrics.get_strikethrough_thickness () / (double) Pango.SCALE);
                        double sy = y - metrics.get_strikethrough_position () / (double) Pango.SCALE + th / 2;
                        out_xml.append ("<Path RenderTransform=\"%s\" Data=\"M %s,%s L %s,%s\" Stroke=\"%s\" StrokeThickness=\"%s\"/>".printf (transform, n (run_x), n (sy), n (run_x + run_w), n (sy), lc, n (th)));
                    }
                }
                if (ustr.len == 0 || idx.len == 0) continue;
                string fill = invisible ? "#00000000" : color (fr, fg, fb, fa);
                out_xml.append ("<Glyphs RenderTransform=\"%s\" OriginX=\"%s\" OriginY=\"%s\" FontRenderingEmSize=\"%s\" FontUri=\"%s%s\" Fill=\"%s\" UnicodeString=\"%s\" Indices=\"%s\"%s%s/>".printf (
                    transform, n (run_x), n (y), n (size), fonts[ri].part, fonts[ri].index > 0 ? "#%d".printf (fonts[ri].index) : "", fill,
                    unicode_attr (ustr.str), idx.str, bolds[ri] ? " StyleSimulations=\"BoldSimulation\"" : "",
                    opacity < 0.999 && !invisible ? " Opacity=\"%s\"".printf (n (opacity)) : ""));
                runs++;
            }
            return true;
        }
    }

    public class SvgToXps {
        private Gee.HashMap<string, Xml.Node*> ids = new Gee.HashMap<string, Xml.Node*> ();
        private StringBuilder o = new StringBuilder ();
        private XpsResources res;
        private int depth = 0;

        public SvgToXps (XpsResources res) {
            this.res = res;
        }

        private static string n (double v) {
            return XmlOut.num (Math.round (v * 1000) / 1000);
        }

        private static XpsError unsupported (string what) {
            return new XpsError.UNSUPPORTED (what);
        }

        public static double[] numbers (string s) {
            double[] v = {};
            var sb = new StringBuilder ();
            for (int i = 0; i <= s.length; i++) {
                char c = i < s.length ? s[i] : ' ';
                bool part = c.isdigit () || c == '.' || c == 'e' || c == 'E' || ((c == '-' || c == '+') && (sb.len == 0 || sb.str[sb.len - 1] == 'e' || sb.str[sb.len - 1] == 'E'));
                if (part) {
                    sb.append_c (c);
                } else {
                    if (sb.len > 0) v += double.parse (sb.str);
                    sb.truncate ();
                    if (c == '-' || c == '+') sb.append_c (c);
                }
            }
            return v;
        }

        public static string path_data (string d) throws XpsError {
            var sb = new StringBuilder ();
            int i = 0;
            char cmd = 'M';
            while (i < d.length) {
                char c = d[i];
                if (c.isalpha () && c != 'e' && c != 'E') {
                    cmd = c;
                    int j = i + 1;
                    while (j < d.length && !(d[j].isalpha () && d[j] != 'e' && d[j] != 'E')) j++;
                    double[] v = numbers (d.substring (i + 1, j - i - 1));
                    switch (cmd) {
                        case 'M':
                        case 'L':
                        case 'C':
                        case 'Q':
                        case 'm':
                        case 'l':
                        case 'c':
                        case 'q':
                            if (v.length % 2 != 0) throw unsupported ("path");
                            sb.append_c (cmd);
                            for (int k = 0; k < v.length; k += 2) sb.append (" %s,%s".printf (n (v[k]), n (v[k + 1])));
                            sb.append_c (' ');
                            break;
                        case 'H':
                        case 'V':
                        case 'h':
                        case 'v':
                            sb.append_c (cmd);
                            foreach (double x in v) sb.append (" %s".printf (n (x)));
                            sb.append_c (' ');
                            break;
                        case 'Z':
                        case 'z':
                            sb.append ("Z ");
                            break;
                        default:
                            throw unsupported ("path command " + cmd.to_string ());
                    }
                    i = j;
                } else {
                    i++;
                }
            }
            return sb.str.strip ();
        }

        public static string matrix (string? t) throws XpsError {
            if (t == null || t.strip () == "") return "";
            double a = 1, b = 0, c = 0, d = 1, e = 0, f = 0;
            string s = t.strip ();
            int pos = 0;
            while (pos < s.length) {
                int open = s.index_of_char ('(', pos);
                if (open < 0) break;
                int close = s.index_of_char (')', open);
                if (close < 0) throw unsupported ("transform");
                string fn = s.substring (pos, open - pos).strip ().replace (",", "");
                double[] v = numbers (s.substring (open + 1, close - open - 1));
                double na = 1, nb = 0, nc = 0, nd = 1, ne = 0, nf = 0;
                switch (fn) {
                    case "matrix":
                        if (v.length != 6) throw unsupported ("matrix");
                        na = v[0]; nb = v[1]; nc = v[2]; nd = v[3]; ne = v[4]; nf = v[5];
                        break;
                    case "translate":
                        ne = v.length > 0 ? v[0] : 0;
                        nf = v.length > 1 ? v[1] : 0;
                        break;
                    case "scale":
                        na = v.length > 0 ? v[0] : 1;
                        nd = v.length > 1 ? v[1] : na;
                        break;
                    case "rotate":
                        double ang = (v.length > 0 ? v[0] : 0) * Math.PI / 180;
                        na = Math.cos (ang); nb = Math.sin (ang); nc = -Math.sin (ang); nd = Math.cos (ang);
                        break;
                    default:
                        throw unsupported ("transform " + fn);
                }
                double ra = a * na + c * nb, rb = b * na + d * nb, rc = a * nc + c * nd, rd = b * nc + d * nd;
                double re = a * ne + c * nf + e, rf = b * ne + d * nf + f;
                a = ra; b = rb; c = rc; d = rd; e = re; f = rf;
                pos = close + 1;
            }
            return "%s,%s,%s,%s,%s,%s".printf (n (a), n (b), n (c), n (d), n (e), n (f));
        }

        public static string? color (string? spec, double alpha) throws XpsError {
            if (spec == null || spec == "none") return null;
            double r = 0, g = 0, b = 0;
            string s = spec.strip ();
            if (s.has_prefix ("rgb(")) {
                string inner = s.substring (4, s.length - 5);
                string[] parts = inner.split (",");
                if (parts.length != 3) throw unsupported ("colour");
                double[] c = new double[3];
                for (int i = 0; i < 3; i++) {
                    string p = parts[i].strip ();
                    c[i] = p.has_suffix ("%") ? double.parse (p.substring (0, p.length - 1)) / 100 : double.parse (p) / 255;
                }
                r = c[0]; g = c[1]; b = c[2];
            } else if (s.has_prefix ("#") && s.length == 7) {
                r = uint64.parse ("0x" + s.substring (1, 2)) / 255.0;
                g = uint64.parse ("0x" + s.substring (3, 2)) / 255.0;
                b = uint64.parse ("0x" + s.substring (5, 2)) / 255.0;
            } else {
                throw unsupported ("colour " + s);
            }
            return "#%02X%02X%02X%02X".printf ((int) Math.round (alpha.clamp (0, 1) * 255), (int) Math.round (r.clamp (0, 1) * 255), (int) Math.round (g.clamp (0, 1) * 255), (int) Math.round (b.clamp (0, 1) * 255));
        }

        private static string? ref_id (string? v) {
            if (v == null) return null;
            string s = v.strip ();
            if (s.has_prefix ("url(#") && s.has_suffix (")")) return s.substring (5, s.length - 6);
            if (s.has_prefix ("#")) return s.substring (1);
            return null;
        }

        private static double num_attr (Xml.Node* e, string name, double fallback) {
            string? v = XmlIn.attr (e, name);
            if (v == null) return fallback;
            double[] a = numbers (v);
            return a.length > 0 ? a[0] : fallback;
        }

        private void collect (Xml.Node* e) {
            for (Xml.Node* c = e->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                string? id = XmlIn.attr (c, "id");
                if (id != null) ids[id] = c;
                collect (c);
            }
        }

        public string convert (string svg) throws Error {
            var doc = XmlIn.parse (svg);
            Xml.Node* root = doc->get_root_element ();
            collect (root);
            try {
                children (root);
            } finally {
                delete doc;
            }
            return o.str;
        }

        private void children (Xml.Node* e) throws Error {
            for (Xml.Node* c = e->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                element (c);
            }
        }

        private string gradient_brush (Xml.Node* g, double alpha) throws Error {
            string tag = g->name;
            string? units = XmlIn.attr (g, "gradientUnits");
            if (units != "userSpaceOnUse") throw unsupported ("gradient units");
            string? spread = XmlIn.attr (g, "spreadMethod");
            string sm = spread == "repeat" ? " SpreadMethod=\"Repeat\"" : (spread == "reflect" ? " SpreadMethod=\"Reflect\"" : "");
            string tr = matrix (XmlIn.attr (g, "gradientTransform"));
            var stops = new StringBuilder ();
            int count = 0;
            for (Xml.Node* s = g->children; s != null; s = s->next) {
                if (s->type != Xml.ElementType.ELEMENT_NODE || s->name != "stop") continue;
                double so = num_attr (s, "stop-opacity", 1) * alpha;
                stops.append ("<GradientStop Color=\"%s\" Offset=\"%s\"/>".printf (color (XmlIn.attr (s, "stop-color") ?? "rgb(0%,0%,0%)", so), n (num_attr (s, "offset", 0))));
                count++;
            }
            if (count < 2) throw unsupported ("gradient stops");
            if (tag == "linearGradient") {
                return "<LinearGradientBrush MappingMode=\"Absolute\" StartPoint=\"%s,%s\" EndPoint=\"%s,%s\"%s%s><LinearGradientBrush.GradientStops>%s</LinearGradientBrush.GradientStops></LinearGradientBrush>".printf (
                    n (num_attr (g, "x1", 0)), n (num_attr (g, "y1", 0)), n (num_attr (g, "x2", 1)), n (num_attr (g, "y2", 0)), sm, tr != "" ? " Transform=\"" + tr + "\"" : "", stops.str);
            }
            if (tag == "radialGradient") {
                double cx = num_attr (g, "cx", 0), cy = num_attr (g, "cy", 0), r = num_attr (g, "r", 1);
                double fx = num_attr (g, "fx", cx), fy = num_attr (g, "fy", cy);
                if (num_attr (g, "fr", 0) > 0.001) throw unsupported ("focal radius");
                return "<RadialGradientBrush MappingMode=\"Absolute\" Center=\"%s,%s\" GradientOrigin=\"%s,%s\" RadiusX=\"%s\" RadiusY=\"%s\"%s%s><RadialGradientBrush.GradientStops>%s</RadialGradientBrush.GradientStops></RadialGradientBrush>".printf (
                    n (cx), n (cy), n (fx), n (fy), n (r), n (r), sm, tr != "" ? " Transform=\"" + tr + "\"" : "", stops.str);
            }
            throw unsupported ("paint " + tag);
        }

        private string clip_geometry (string id) throws Error {
            if (!ids.has_key (id)) throw unsupported ("clip reference");
            Xml.Node* cp = ids[id];
            if (XmlIn.attr (cp, "clip-path") != null) throw unsupported ("nested clip");
            if (XmlIn.attr (cp, "clipPathUnits") != null && XmlIn.attr (cp, "clipPathUnits") != "userSpaceOnUse") throw unsupported ("clip units");
            var parts = new StringBuilder ();
            string rule = "F1 ";
            int count = 0;
            for (Xml.Node* c = cp->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                if (XmlIn.attr (c, "transform") != null) throw unsupported ("clip transform");
                if (c->name == "path") {
                    if (XmlIn.attr (c, "clip-rule") == "evenodd") rule = "F0 ";
                    parts.append (path_data (XmlIn.attr (c, "d") ?? "")).append_c (' ');
                } else if (c->name == "rect") {
                    double x = num_attr (c, "x", 0), y = num_attr (c, "y", 0), w = num_attr (c, "width", 0), h = num_attr (c, "height", 0);
                    parts.append ("M %s,%s L %s,%s %s,%s %s,%s Z ".printf (n (x), n (y), n (x + w), n (y), n (x + w), n (y + h), n (x), n (y + h)));
                } else {
                    throw unsupported ("clip " + c->name);
                }
                count++;
            }
            if (count > 1) throw unsupported ("clip union");
            return rule + parts.str.strip ();
        }

        private double mask_opacity (string id) throws Error {
            if (!ids.has_key (id)) throw unsupported ("mask reference");
            Xml.Node* mk = ids[id];
            Xml.Node* only = null;
            int count = 0;
            for (Xml.Node* c = mk->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                only = c;
                count++;
            }
            if (count != 1) throw unsupported ("mask");
            Xml.Node* shape = only;
            if (only->name == "g") {
                Xml.Node* inner = null;
                int ic = 0;
                for (Xml.Node* c = only->children; c != null; c = c->next) {
                    if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                    inner = c;
                    ic++;
                }
                if (ic != 1) throw unsupported ("mask group");
                shape = inner;
            }
            if (shape->name != "rect" || XmlIn.attr (shape, "transform") != null) throw unsupported ("mask shape");
            return num_attr (shape, "fill-opacity", 1) * num_attr (shape, "opacity", 1);
        }

        private string canvas_open (Xml.Node* e) throws Error {
            var sb = new StringBuilder ("<Canvas");
            string tr = matrix (XmlIn.attr (e, "transform"));
            if (tr != "") sb.append (" RenderTransform=\"%s\"".printf (tr));
            string? clip = ref_id (XmlIn.attr (e, "clip-path"));
            if (clip != null) sb.append (" Clip=\"%s\"".printf (clip_geometry (clip)));
            double op = num_attr (e, "opacity", 1);
            string? mask = ref_id (XmlIn.attr (e, "mask"));
            if (mask != null) op *= mask_opacity (mask);
            if (op < 0.999) sb.append (" Opacity=\"%s\"".printf (n (op)));
            if (XmlIn.attr (e, "filter") != null) throw unsupported ("filter");
            sb.append (">");
            return sb.str;
        }

        private void element (Xml.Node* e) throws Error {
            if (++depth > 200) throw unsupported ("depth");
            switch (e->name) {
                case "defs":
                case "title":
                case "desc":
                case "metadata":
                case "clipPath":
                case "mask":
                case "filter":
                case "linearGradient":
                case "radialGradient":
                case "symbol":
                    break;
                case "g":
                    o.append (canvas_open (e));
                    children (e);
                    o.append ("</Canvas>");
                    break;
                case "use":
                    string? id = ref_id (XmlIn.attr_any (e, "href"));
                    if (id == null || !ids.has_key (id)) throw unsupported ("use");
                    o.append (canvas_open (e));
                    double ux = num_attr (e, "x", 0), uy = num_attr (e, "y", 0);
                    o.append ("<Canvas RenderTransform=\"1,0,0,1,%s,%s\">".printf (n (ux), n (uy)));
                    Xml.Node* target = ids[id];
                    if (target->name == "symbol" || target->name == "g") {
                        o.append (canvas_open (target));
                        children (target);
                        o.append ("</Canvas>");
                    } else {
                        element (target);
                    }
                    o.append ("</Canvas></Canvas>");
                    break;
                case "path":
                    shape (e, path_data (XmlIn.attr (e, "d") ?? ""));
                    break;
                case "rect":
                    double x = num_attr (e, "x", 0), y = num_attr (e, "y", 0), w = num_attr (e, "width", 0), h = num_attr (e, "height", 0);
                    if (XmlIn.attr (e, "rx") != null || XmlIn.attr (e, "ry") != null) throw unsupported ("rounded rect");
                    shape (e, "M %s,%s L %s,%s %s,%s %s,%s Z".printf (n (x), n (y), n (x + w), n (y), n (x + w), n (y + h), n (x), n (y + h)));
                    break;
                case "image":
                    image (e);
                    break;
                default:
                    throw unsupported (e->name);
            }
            depth--;
        }

        private void shape (Xml.Node* e, string data) throws Error {
            if (data == "") return;
            string? clip = ref_id (XmlIn.attr (e, "clip-path"));
            string? mask = ref_id (XmlIn.attr (e, "mask"));
            if (XmlIn.attr (e, "filter") != null) throw unsupported ("filter");
            double op = num_attr (e, "opacity", 1);
            if (mask != null) op *= mask_opacity (mask);
            string rule = XmlIn.attr (e, "fill-rule") == "evenodd" ? "F0 " : "F1 ";
            var sb = new StringBuilder ("<Path Data=\"%s%s\"".printf (rule, data));
            string tr = matrix (XmlIn.attr (e, "transform"));
            if (tr != "") sb.append (" RenderTransform=\"%s\"".printf (tr));
            if (clip != null) sb.append (" Clip=\"%s\"".printf (clip_geometry (clip)));
            if (op < 0.999) sb.append (" Opacity=\"%s\"".printf (n (op)));
            string? fill = XmlIn.attr (e, "fill") ?? "rgb(0%,0%,0%)";
            string? fill_brush = null;
            string? fid = ref_id (fill);
            if (fid != null) {
                if (!ids.has_key (fid)) throw unsupported ("fill reference");
                fill_brush = gradient_brush (ids[fid], num_attr (e, "fill-opacity", 1));
            } else {
                string? fc = color (fill, num_attr (e, "fill-opacity", 1));
                if (fc != null) sb.append (" Fill=\"%s\"".printf (fc));
            }
            string? stroke = XmlIn.attr (e, "stroke");
            string? stroke_brush = null;
            if (stroke != null && stroke != "none") {
                string? sid = ref_id (stroke);
                if (sid != null) {
                    if (!ids.has_key (sid)) throw unsupported ("stroke reference");
                    stroke_brush = gradient_brush (ids[sid], num_attr (e, "stroke-opacity", 1));
                } else {
                    sb.append (" Stroke=\"%s\"".printf (color (stroke, num_attr (e, "stroke-opacity", 1))));
                }
                double sw = num_attr (e, "stroke-width", 1);
                sb.append (" StrokeThickness=\"%s\"".printf (n (sw)));
                string cap = XmlIn.attr (e, "stroke-linecap") ?? "butt";
                string xc = cap == "round" ? "Round" : (cap == "square" ? "Square" : "Flat");
                sb.append (" StrokeStartLineCap=\"%s\" StrokeEndLineCap=\"%s\" StrokeDashCap=\"%s\"".printf (xc, xc, xc));
                string join = XmlIn.attr (e, "stroke-linejoin") ?? "miter";
                sb.append (" StrokeLineJoin=\"%s\"".printf (join == "round" ? "Round" : (join == "bevel" ? "Bevel" : "Miter")));
                sb.append (" StrokeMiterLimit=\"%s\"".printf (n (double.max (1, num_attr (e, "stroke-miterlimit", 10)))));
                string? dash = XmlIn.attr (e, "stroke-dasharray");
                if (dash != null && dash != "none" && sw > 0) {
                    var ds = new StringBuilder ();
                    foreach (double d in numbers (dash)) {
                        if (ds.len > 0) ds.append_c (' ');
                        ds.append (n (d / sw));
                    }
                    if (ds.len > 0) sb.append (" StrokeDashArray=\"%s\"".printf (ds.str));
                    double off = num_attr (e, "stroke-dashoffset", 0);
                    if (Math.fabs (off) > 0.001) sb.append (" StrokeDashOffset=\"%s\"".printf (n (off / sw)));
                }
            }
            if (fill_brush == null && stroke_brush == null) {
                sb.append ("/>");
            } else {
                sb.append (">");
                if (fill_brush != null) sb.append ("<Path.Fill>%s</Path.Fill>".printf (fill_brush));
                if (stroke_brush != null) sb.append ("<Path.Stroke>%s</Path.Stroke>".printf (stroke_brush));
                sb.append ("</Path>");
            }
            o.append (sb.str);
        }

        private void image (Xml.Node* e) throws Error {
            string? href = XmlIn.attr_any (e, "href");
            if (href == null || !href.has_prefix ("data:image/")) throw unsupported ("image source");
            int comma = href.index_of_char (',');
            if (comma < 0 || !href.substring (0, comma).has_suffix (";base64")) throw unsupported ("image encoding");
            string mime = href.substring (5, href.index_of_char (';') - 5);
            uint8[] data = Base64.decode (href.substring (comma + 1));
            string ext = mime == "image/png" ? "png" : (mime == "image/jpeg" ? "jpg" : "");
            if (ext == "") throw unsupported ("image type");
            var loader = new Gdk.PixbufLoader ();
            loader.write (data);
            loader.close ();
            var pb = loader.get_pixbuf ();
            if (pb == null) throw unsupported ("image data");
            double x = num_attr (e, "x", 0), y = num_attr (e, "y", 0);
            double w = num_attr (e, "width", pb.width), h = num_attr (e, "height", pb.height);
            string part = res.add_image (data, ext);
            o.append (canvas_open (e));
            o.append ("<Path Data=\"M %s,%s L %s,%s %s,%s %s,%s Z\"><Path.Fill><ImageBrush ImageSource=\"%s\" Viewbox=\"0,0,%d,%d\" ViewboxUnits=\"Absolute\" Viewport=\"%s,%s,%s,%s\" ViewportUnits=\"Absolute\" TileMode=\"None\"/></Path.Fill></Path>".printf (
                n (x), n (y), n (x + w), n (y), n (x + w), n (y + h), n (x), n (y + h), part, pb.width, pb.height, n (x), n (y), n (w), n (h)));
            o.append ("</Canvas>");
        }
    }

    public class XpsExport {
        public const string NS = "http://schemas.microsoft.com/xps/2005/06";
        public int vector_items = 0;
        public int raster_items = 0;
        public int glyph_runs = 0;

        public static uint8[] surface_png (Cairo.ImageSurface surf) {
            uint8[] png = {};
            surf.write_to_png_stream ((data) => {
                uint8[] chunk = data;
                var joined = new uint8[png.length + chunk.length];
                Memory.copy (joined, png, png.length);
                Memory.copy (&joined[png.length], chunk, chunk.length);
                png = joined;
                return Cairo.Status.SUCCESS;
            });
            return png;
        }

        private static string n (double v) {
            return XmlOut.num (Math.round (v * 1000) / 1000);
        }

        private static string lang_tag () {
            string l = Intl.get_language_names ()[0];
            if (l == "C" || l == "POSIX" || l == "") return "en-US";
            return l.split (".")[0].split ("@")[0].replace ("_", "-");
        }

        private static bool needs_raster (Item it) {
            var fx = it.effects;
            if (fx.glow || fx.reflection || fx.bevel || fx.soft_edges > 0.01 || it.shadow.enabled) return true;
            if (it.border_art.visible ()) return true;
            if (it.fill.kind == FillKind.PATTERN || it.fill.kind == FillKind.TEXTURE) return true;
            var g = it as GroupItem;
            if (g != null) foreach (var c in g.children) if (needs_raster (c)) return true;
            return false;
        }

        private string svg_of (Renderer r, Item it, bool master, int page, double w, double h) throws Error {
            string tmp = Path.build_filename (Environment.get_tmp_dir (), "publish-xps-%s.svg".printf (XpsResources.new_guid ()));
            var s = new Cairo.SvgSurface (tmp, w, h);
            var cr = new Cairo.Context (s);
            r.draw_item (cr, it, master, page);
            s.finish ();
            string text;
            FileUtils.get_contents (tmp, out text);
            FileUtils.unlink (tmp);
            return text;
        }

        private string raster_of (Renderer r, Item it, bool master, int page, double dpi, XpsResources res) {
            var b = it.bounds ();
            double pad = 40;
            double x0 = b.x - pad, y0 = b.y - pad, bw = b.w + 2 * pad, bh = b.h + 2 * pad;
            double sc = dpi / 72.0;
            int pw = int.max (1, (int) Math.ceil (bw * sc)), ph = int.max (1, (int) Math.ceil (bh * sc));
            var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, pw, ph);
            var cr = new Cairo.Context (surf);
            cr.scale (sc, sc);
            cr.translate (-x0, -y0);
            r.draw_item (cr, it, master, page);
            surf.flush ();
            string part = res.add_image (surface_png (surf), "png");
            return "<Path Data=\"M %s,%s L %s,%s %s,%s %s,%s Z\"><Path.Fill><ImageBrush ImageSource=\"%s\" Viewbox=\"0,0,%d,%d\" ViewboxUnits=\"Absolute\" Viewport=\"%s,%s,%s,%s\" ViewportUnits=\"Absolute\" TileMode=\"None\"/></Path.Fill></Path>".printf (
                n (x0), n (y0), n (x0 + bw), n (y0), n (x0 + bw), n (y0 + bh), n (x0), n (y0 + bh), part, pw, ph, n (x0), n (y0), n (bw), n (bh));
        }

        public static int export (Publication pub, ExportOptions opts, string path) throws Error {
            return new XpsExport ().write (pub, opts, path);
        }

        public int write (Publication pub, ExportOptions opts, string path) throws Error {
            var pages = Exporter.parse_ranges (opts.ranges, pub.pages.size);
            if (pages.size == 0) throw new FormatError.INVALID (_("There are no pages to export."));
            var r = new Renderer (pub);
            r.opts.print = true;
            r.opts.overset_marks = false;
            r.opts.placeholders = false;
            r.opts.links = true;
            var page_map = new Gee.HashMap<int, int> ();
            for (int i = 0; i < pages.size; i++) page_map[pages[i]] = i + 1;
            r.opts.page_map = page_map;
            var res = new XpsResources ();
            var zip = new ZipWriter ();
            string ns = NS;
            double k = 96.0 / 72.0;
            double dpi = double.max (150, opts.dpi);
            double w = pub.settings.width, h = pub.settings.height;
            var fdoc = new StringBuilder ("<FixedDocument xmlns=\"%s\">".printf (ns));
            var page_xml = new Gee.ArrayList<string> ();
            var page_rels = new Gee.ArrayList<Gee.HashSet<string>> ();
            for (int pi = 0; pi < pages.size; pi++) {
                int page = pages[pi];
                fdoc.append ("<PageContent Source=\"/Documents/1/Pages/%d.fpage\" Width=\"%s\" Height=\"%s\"><PageContent.LinkTargets><LinkTarget Name=\"page%d\"/></PageContent.LinkTargets></PageContent>".printf (pi + 1, n (w * k), n (h * k), pi + 1));
                res.page_parts = new Gee.HashSet<string> ();
                var sb = new StringBuilder ();
                sb.append ("<FixedPage xmlns=\"%s\" Width=\"%s\" Height=\"%s\" xml:lang=\"%s\"><Canvas Name=\"page%d\" RenderTransform=\"%s,0,0,%s,0,0\">".printf (ns, n (w * k), n (h * k), lang_tag (), pi + 1, n (k), n (k)));
                sb.append ("<Path Data=\"M 0,0 L %s,0 %s,%s 0,%s Z\" Fill=\"#FFFFFFFF\"/>".printf (n (w), n (w), n (h), n (h)));
                var all = new Gee.ArrayList<Item> ();
                var masters = new Gee.HashSet<Item> ();
                foreach (var it in pub.master_items_for (page)) {
                    all.add (it);
                    masters.add (it);
                }
                all.add_all (pub.pages[page].items);
                var links = new Gee.ArrayList<LinkArea> ();
                foreach (var it in r.ordered (all)) {
                    if (!r.item_visible (it)) continue;
                    bool master = masters.contains (it);
                    var sink = new XpsGlyphSink (res);
                    sink.opacity = it.opacity;
                    string graphics;
                    if (needs_raster (it)) {
                        r.opts.glyph_sink = null;
                        r.opts.link_sink = null;
                        graphics = raster_of (r, it, master, page, dpi, res);
                        sink.invisible = true;
                        r.opts.glyph_sink = sink;
                        r.opts.link_sink = links;
                        svg_of (r, it, master, page, w, h);
                        raster_items++;
                    } else {
                        r.opts.glyph_sink = sink;
                        r.opts.link_sink = links;
                        string svg = svg_of (r, it, master, page, w, h);
                        try {
                            var conv = new SvgToXps (res);
                            graphics = conv.convert (svg);
                            vector_items++;
                        } catch (XpsError e) {
                            r.opts.glyph_sink = null;
                            r.opts.link_sink = null;
                            graphics = raster_of (r, it, master, page, dpi, res);
                            raster_items++;
                        }
                    }
                    r.opts.glyph_sink = null;
                    r.opts.link_sink = null;
                    sb.append (graphics);
                    sb.append (sink.out_xml.str);
                    glyph_runs += sink.runs;
                }
                foreach (var la in links) {
                    string? uri = null;
                    if (la.link.has_prefix ("page:")) {
                        int pg = int.parse (la.link.substring (5));
                        if (page_map.has_key (pg)) uri = "../FixedDoc.fdoc#page%d".printf (page_map[pg]);
                    } else if (la.link.has_prefix ("bookmark:")) {
                        var b = pub.bookmark (la.link.substring (9));
                        if (b != null && page_map.has_key (b.page)) uri = "../FixedDoc.fdoc#page%d".printf (page_map[b.page]);
                    } else {
                        uri = HtmlExport.link_href (la.link);
                    }
                    if (uri == null) continue;
                    double x0 = la.rect.x, y0 = la.rect.y, x1 = la.rect.x + la.rect.w, y1 = la.rect.y + la.rect.h;
                    sb.append ("<Path Data=\"M %s,%s L %s,%s %s,%s %s,%s Z\" Fill=\"#00FFFFFF\" FixedPage.NavigateUri=\"%s\"/>".printf (n (x0), n (y0), n (x1), n (y0), n (x1), n (y1), n (x0), n (y1), XmlOut.esc (uri)));
                }
                sb.append ("</Canvas></FixedPage>");
                page_xml.add (sb.str);
                page_rels.add (res.page_parts);
            }
            fdoc.append ("</FixedDocument>");
            var types = new StringBuilder ("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"fdseq\" ContentType=\"application/vnd.ms-package.xps-fixeddocumentsequence+xml\"/><Default Extension=\"fdoc\" ContentType=\"application/vnd.ms-package.xps-fixeddocument+xml\"/><Default Extension=\"fpage\" ContentType=\"application/vnd.ms-package.xps-fixedpage+xml\"/><Default Extension=\"png\" ContentType=\"image/png\"/><Default Extension=\"jpg\" ContentType=\"image/jpeg\"/><Default Extension=\"odttf\" ContentType=\"application/vnd.ms-package.obfuscated-opentype\"/><Override PartName=\"/docProps/core.xml\" ContentType=\"application/vnd.openxmlformats-package.core-properties+xml\"/></Types>");
            zip.add_text ("[Content_Types].xml", types.str);
            zip.add_text ("_rels/.rels", "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"R0\" Type=\"%s/fixedrepresentation\" Target=\"/FixedDocSeq.fdseq\"/><Relationship Id=\"R1\" Type=\"http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties\" Target=\"/docProps/core.xml\"/></Relationships>".printf (ns));
            var core = new XmlOut ();
            core.start ("cp:coreProperties").a ("xmlns:cp", "http://schemas.openxmlformats.org/package/2006/metadata/core-properties").a ("xmlns:dc", "http://purl.org/dc/elements/1.1/").a ("xmlns:dcterms", "http://purl.org/dc/terms/").a ("xmlns:xsi", "http://www.w3.org/2001/XMLSchema-instance");
            if (pub.meta.title != "") core.element ("dc:title", pub.meta.title);
            if (pub.meta.author != "") core.element ("dc:creator", pub.meta.author);
            if (pub.meta.subject != "") core.element ("dc:subject", pub.meta.subject);
            if (pub.meta.keywords != "") core.element ("cp:keywords", pub.meta.keywords);
            core.start ("dcterms:created").a ("xsi:type", "dcterms:W3CDTF").text (new DateTime.now_utc ().format ("%Y-%m-%dT%H:%M:%SZ")).end ();
            core.end ();
            zip.add_text ("docProps/core.xml", core.finish ());
            zip.add_text ("FixedDocSeq.fdseq", "<FixedDocumentSequence xmlns=\"%s\"><DocumentReference Source=\"/Documents/1/FixedDoc.fdoc\"/></FixedDocumentSequence>".printf (ns));
            zip.add_text ("Documents/1/FixedDoc.fdoc", fdoc.str);
            for (int i = 0; i < page_xml.size; i++) {
                zip.add_text ("Documents/1/Pages/%d.fpage".printf (i + 1), page_xml[i]);
                var rels = new StringBuilder ("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">");
                int rid = 1;
                foreach (string part in page_rels[i]) rels.append ("<Relationship Id=\"R%d\" Type=\"%s/required-resource\" Target=\"%s\"/>".printf (rid++, ns, part));
                rels.append ("</Relationships>");
                zip.add_text ("Documents/1/Pages/_rels/%d.fpage.rels".printf (i + 1), rels.str);
            }
            for (int i = 0; i < res.image_parts.size; i++) zip.add (res.image_parts[i].substring (1), res.image_data[i].get_data (), false);
            foreach (var f in res.fonts.values) zip.add (f.part.substring (1), f.data, true);
            FileUtils.set_data (path, zip.finish ());
            return pages.size;
        }
    }
}
