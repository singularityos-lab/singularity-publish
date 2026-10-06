namespace Singularity.Apps.Publish {

    public class Effects {
        public bool glow = false;
        public string glow_color = "swatch:Yellow";
        public double glow_size = 8;
        public double glow_opacity = 0.6;
        public double soft_edges = 0;
        public bool reflection = false;
        public double reflection_size = 0.4;
        public double reflection_opacity = 0.45;
        public double reflection_distance = 2;
        public bool bevel = false;
        public double bevel_depth = 6;

        public Effects clone () {
            var e = new Effects ();
            e.glow = glow;
            e.glow_color = glow_color;
            e.glow_size = glow_size;
            e.glow_opacity = glow_opacity;
            e.soft_edges = soft_edges;
            e.reflection = reflection;
            e.reflection_size = reflection_size;
            e.reflection_opacity = reflection_opacity;
            e.reflection_distance = reflection_distance;
            e.bevel = bevel;
            e.bevel_depth = bevel_depth;
            return e;
        }

        public bool any () {
            return glow || soft_edges > 0 || reflection || bevel;
        }

        public void write (XmlOut x) {
            if (!any ()) return;
            x.start ("effects");
            if (glow) x.ai ("glow", 1).a ("glow-color", glow_color).ad ("glow-size", glow_size).ad ("glow-opacity", glow_opacity);
            if (soft_edges > 0) x.ad ("soft-edges", soft_edges);
            if (reflection) x.ai ("reflection", 1).ad ("reflection-size", reflection_size).ad ("reflection-opacity", reflection_opacity).ad ("reflection-distance", reflection_distance);
            if (bevel) x.ai ("bevel", 1).ad ("bevel-depth", bevel_depth);
            x.end ();
        }

        public static Effects read (Xml.Node* n) {
            var e = new Effects ();
            var en = XmlIn.child (n, "effects");
            if (en == null) return e;
            e.glow = XmlIn.int_attr (en, "glow", 0) == 1;
            e.glow_color = XmlIn.attr (en, "glow-color") ?? "swatch:Yellow";
            e.glow_size = XmlIn.double_attr (en, "glow-size", 8);
            e.glow_opacity = XmlIn.double_attr (en, "glow-opacity", 0.6);
            e.soft_edges = XmlIn.double_attr (en, "soft-edges", 0);
            e.reflection = XmlIn.int_attr (en, "reflection", 0) == 1;
            e.reflection_size = XmlIn.double_attr (en, "reflection-size", 0.4);
            e.reflection_opacity = XmlIn.double_attr (en, "reflection-opacity", 0.45);
            e.reflection_distance = XmlIn.double_attr (en, "reflection-distance", 2);
            e.bevel = XmlIn.int_attr (en, "bevel", 0) == 1;
            e.bevel_depth = XmlIn.double_attr (en, "bevel-depth", 6);
            return e;
        }
    }

    public class BorderArt {
        public string design = "";
        public double size = 18;
        public string color = "";

        public BorderArt clone () {
            var b = new BorderArt ();
            b.design = design;
            b.size = size;
            b.color = color;
            return b;
        }

        public bool visible () {
            return design != "" && size > 0;
        }
    }

    public class Bookmark {
        public string name;
        public int page;
        public double x;
        public double y;

        public Bookmark (string name, int page, double x = 0, double y = 0) {
            this.name = name;
            this.page = page;
            this.x = x;
            this.y = y;
        }

        public Bookmark clone () {
            return new Bookmark (name, page, x, y);
        }
    }

    public class BusinessInfo {
        public const string[] KEYS = { "name", "job-title", "organization", "address", "phone", "fax", "email", "website", "tagline", "logo" };
        public string set_name = "";
        public Gee.HashMap<string, string> values = new Gee.HashMap<string, string> ();

        public static string label (string key) {
            switch (key) {
                case "name": return _("Individual Name");
                case "job-title": return _("Job or Position Title");
                case "organization": return _("Organization Name");
                case "address": return _("Address");
                case "phone": return _("Phone");
                case "fax": return _("Fax");
                case "email": return _("Email");
                case "website": return _("Website");
                case "tagline": return _("Tagline or Motto");
                case "logo": return _("Logo");
                default: return key;
            }
        }

        public string get (string key) {
            return values.has_key (key) ? values[key] : "";
        }

        public void set (string key, string v) {
            values[key] = v;
        }

        public bool is_empty () {
            foreach (var v in values.values) if (v != "") return false;
            return true;
        }

        public BusinessInfo clone () {
            var b = new BusinessInfo ();
            b.set_name = set_name;
            foreach (var e in values.entries) b.values[e.key] = e.value;
            return b;
        }

        public void write (XmlOut x) {
            x.start ("business").a ("set", set_name);
            foreach (string k in KEYS) if (get (k) != "") x.start ("value").a ("key", k).a ("text", get (k)).end ();
            x.end ();
        }

        public static BusinessInfo read (Xml.Node* n) {
            var b = new BusinessInfo ();
            if (n == null) return b;
            b.set_name = XmlIn.attr (n, "set") ?? "";
            foreach (var vn in XmlIn.elements (n, "value")) b.values[XmlIn.attr (vn, "key") ?? ""] = XmlIn.attr (vn, "text") ?? "";
            return b;
        }
    }

    public class MacroDef {
        public string name;
        public string script;
        public string event = "";

        public MacroDef (string name, string script) {
            this.name = name;
            this.script = script;
        }

        public MacroDef clone () {
            var m = new MacroDef (name, script);
            m.event = event;
            return m;
        }
    }

    public enum FilterOp {
        EQUALS,
        NOT_EQUALS,
        CONTAINS,
        NOT_CONTAINS,
        STARTS_WITH,
        LESS,
        GREATER,
        EMPTY,
        NOT_EMPTY;

        public string to_string () {
            switch (this) {
                case NOT_EQUALS: return "ne";
                case CONTAINS: return "contains";
                case NOT_CONTAINS: return "not-contains";
                case STARTS_WITH: return "starts";
                case LESS: return "lt";
                case GREATER: return "gt";
                case EMPTY: return "empty";
                case NOT_EMPTY: return "not-empty";
                default: return "eq";
            }
        }

        public static FilterOp parse (string s) {
            switch (s) {
                case "ne": return NOT_EQUALS;
                case "contains": return CONTAINS;
                case "not-contains": return NOT_CONTAINS;
                case "starts": return STARTS_WITH;
                case "lt": return LESS;
                case "gt": return GREATER;
                case "empty": return EMPTY;
                case "not-empty": return NOT_EMPTY;
                default: return EQUALS;
            }
        }

        public string label () {
            switch (this) {
                case NOT_EQUALS: return _("Is Not");
                case CONTAINS: return _("Contains");
                case NOT_CONTAINS: return _("Does Not Contain");
                case STARTS_WITH: return _("Starts With");
                case LESS: return _("Less Than");
                case GREATER: return _("Greater Than");
                case EMPTY: return _("Is Blank");
                case NOT_EMPTY: return _("Is Not Blank");
                default: return _("Is");
            }
        }

        public static FilterOp[] all () {
            return { EQUALS, NOT_EQUALS, CONTAINS, NOT_CONTAINS, STARTS_WITH, LESS, GREATER, EMPTY, NOT_EMPTY };
        }
    }

    public class MergeFilter {
        public string field;
        public FilterOp op;
        public string value;
        public bool or_previous = false;

        public MergeFilter (string field, FilterOp op, string value, bool or_previous = false) {
            this.field = field;
            this.op = op;
            this.value = value;
            this.or_previous = or_previous;
        }

        public MergeFilter clone () {
            return new MergeFilter (field, op, value, or_previous);
        }

        private static bool as_number (string s, out double v) {
            string t = s.strip ().replace (",", ".");
            return double.try_parse (t, out v) && t != "";
        }

        public bool matches (string actual) {
            string a = actual.strip ().casefold ();
            string b = value.strip ().casefold ();
            switch (op) {
                case FilterOp.NOT_EQUALS: return a != b;
                case FilterOp.CONTAINS: return a.contains (b);
                case FilterOp.NOT_CONTAINS: return !a.contains (b);
                case FilterOp.STARTS_WITH: return a.has_prefix (b);
                case FilterOp.EMPTY: return a == "";
                case FilterOp.NOT_EMPTY: return a != "";
                case FilterOp.LESS:
                case FilterOp.GREATER:
                    double x = 0, y = 0;
                    int cmp;
                    if (as_number (actual, out x) && as_number (value, out y)) cmp = x < y ? -1 : (x > y ? 1 : 0);
                    else cmp = a.collate (b);
                    return op == FilterOp.LESS ? cmp < 0 : cmp > 0;
                default: return a == b;
            }
        }
    }

    public class MergeSort {
        public string field;
        public bool descending;

        public MergeSort (string field, bool descending = false) {
            this.field = field;
            this.descending = descending;
        }

        public MergeSort clone () {
            return new MergeSort (field, descending);
        }
    }

    public abstract class ColorOutput {
        public bool overprint = false;

        public abstract Rgba map (Publication pub, string spec, Rgba screen);

        public virtual Rgba map_raw (Rgba c) {
            return c;
        }

        public virtual Cairo.ImageSurface? map_image (Cairo.ImageSurface src) {
            return null;
        }
    }

    public class ThesaurusEntry {
        public string part;
        public Gee.ArrayList<string> words = new Gee.ArrayList<string> ();

        public ThesaurusEntry (string part) {
            this.part = part;
        }
    }

    public class Thesaurus {
        private static Gee.HashMap<string, Thesaurus>? loaded = null;
        public string idx_path;
        public string dat_path;
        public string lang;
        private Gee.HashMap<string, int64?> index = new Gee.HashMap<string, int64?> ();
        private string encoding = "UTF-8";

        private Thesaurus (string idx, string dat, string lang) {
            idx_path = idx;
            dat_path = dat;
            this.lang = lang;
        }

        public static Gee.ArrayList<string> search_dirs () {
            var l = new Gee.ArrayList<string> ();
            l.add (Path.build_filename (Environment.get_user_data_dir (), "mythes"));
            foreach (string d in Environment.get_system_data_dirs ()) {
                l.add (Path.build_filename (d, "mythes"));
                l.add (Path.build_filename (d, "thesaurus"));
            }
            string? extra = Environment.get_variable ("PUBLISH_THESAURUS_PATH");
            if (extra != null) foreach (string d in extra.split (":")) if (d != "") l.add (d);
            return l;
        }

        public static Gee.ArrayList<string> languages () {
            var l = new Gee.ArrayList<string> ();
            foreach (string d in search_dirs ()) {
                try {
                    var dir = Dir.open (d);
                    string? n;
                    while ((n = dir.read_name ()) != null) {
                        if (!n.has_prefix ("th_") || !n.has_suffix (".idx")) continue;
                        string code = n.substring (3, n.length - 7);
                        if (code.has_suffix ("_v2")) code = code.substring (0, code.length - 3);
                        if (!l.contains (code)) l.add (code);
                    }
                } catch (FileError e) {
                }
            }
            l.sort ();
            return l;
        }

        public static Thesaurus? for_language (string lang) {
            if (loaded == null) loaded = new Gee.HashMap<string, Thesaurus> ();
            string want = lang.replace ("-", "_");
            if (loaded.has_key (want)) return loaded[want];
            foreach (string d in search_dirs ()) {
                try {
                    var dir = Dir.open (d);
                    string? n;
                    string? best = null;
                    while ((n = dir.read_name ()) != null) {
                        if (!n.has_prefix ("th_") || !n.has_suffix (".idx")) continue;
                        string code = n.substring (3, n.length - 7).replace ("_v2", "");
                        if (code == want) {
                            best = n;
                            break;
                        }
                        if (code.has_prefix (want.split ("_")[0]) && best == null) best = n;
                    }
                    if (best == null) continue;
                    string idx = Path.build_filename (d, best);
                    string dat = idx.substring (0, idx.length - 4) + ".dat";
                    if (!FileUtils.test (dat, FileTest.EXISTS)) continue;
                    var t = new Thesaurus (idx, dat, want);
                    if (t.load ()) {
                        loaded[want] = t;
                        return t;
                    }
                } catch (FileError e) {
                }
            }
            return null;
        }

        private string decode (string s) {
            if (encoding.up () == "UTF-8" || encoding.up () == "UTF8") return s.make_valid ();
            try {
                return convert (s, s.length, "UTF-8", encoding);
            } catch (ConvertError e) {
                return s.make_valid ();
            }
        }

        private bool load () {
            try {
                string text;
                FileUtils.get_contents (idx_path, out text);
                string[] lines = text.split ("
");
                if (lines.length < 2) return false;
                encoding = lines[0].strip ();
                for (int i = 2; i < lines.length; i++) {
                    int bar = lines[i].last_index_of ("|");
                    if (bar <= 0) continue;
                    index[decode (lines[i].substring (0, bar)).down ()] = int64.parse (lines[i].substring (bar + 1).strip ());
                }
                return index.size > 0;
            } catch (Error e) {
                return false;
            }
        }

        public Gee.ArrayList<ThesaurusEntry> lookup (string word) {
            var result = new Gee.ArrayList<ThesaurusEntry> ();
            string key = word.strip ().down ();
            if (!index.has_key (key)) return result;
            try {
                var f = File.new_for_path (dat_path);
                var stream = f.read ();
                stream.seek (index[key], SeekType.SET);
                var ds = new DataInputStream (stream);
                string? head = ds.read_line ();
                if (head == null) return result;
                int bar = head.last_index_of ("|");
                int count = bar >= 0 ? int.parse (head.substring (bar + 1)) : 0;
                for (int i = 0; i < count && i < 200; i++) {
                    string? line = ds.read_line ();
                    if (line == null) break;
                    string[] parts = decode (line).split ("|");
                    if (parts.length == 0) continue;
                    var e = new ThesaurusEntry (parts[0].replace ("(", "").replace (")", "").strip ());
                    for (int k = 1; k < parts.length; k++) {
                        string w = parts[k].strip ();
                        int paren = w.index_of (" (");
                        if (paren > 0) w = w.substring (0, paren);
                        if (w != "" && !e.words.contains (w)) e.words.add (w);
                    }
                    if (e.words.size > 0) result.add (e);
                }
            } catch (Error e) {
            }
            return result;
        }
    }

    public class TextVariable {
        public string name;
        public string kind = "custom";
        public string text = "";
        public string style = "";
        public bool use_last = false;
        public string before = "";
        public string after = "";

        public TextVariable (string name, string kind) {
            this.name = name;
            this.kind = kind;
        }

        public static string[] kinds () {
            return { "custom", "running", "file", "modified", "created", "output", "chapter" };
        }

        public static string kind_label (string k) {
            switch (k) {
                case "running": return _("Running Header (Paragraph Style)");
                case "file": return _("File Name");
                case "modified": return _("Modification Date");
                case "created": return _("Creation Date");
                case "output": return _("Output Date");
                case "chapter": return _("Chapter Number");
                default: return _("Custom Text");
            }
        }

        public TextVariable clone () {
            var v = new TextVariable (name, kind);
            v.text = text;
            v.style = style;
            v.use_last = use_last;
            v.before = before;
            v.after = after;
            return v;
        }

        public void write (XmlOut x) {
            x.start ("variable").a ("name", name).a ("kind", kind).a ("text", text).a ("style", style).ai ("last", use_last ? 1 : 0).a ("before", before).a ("after", after).end ();
        }

        public static TextVariable read (Xml.Node* n) {
            var v = new TextVariable (XmlIn.attr (n, "name") ?? "", XmlIn.attr (n, "kind") ?? "custom");
            v.text = XmlIn.attr (n, "text") ?? "";
            v.style = XmlIn.attr (n, "style") ?? "";
            v.use_last = XmlIn.int_attr (n, "last", 0) == 1;
            v.before = XmlIn.attr (n, "before") ?? "";
            v.after = XmlIn.attr (n, "after") ?? "";
            return v;
        }
    }

    public class ObjectStyle {
        public string name;
        public string based_on = "";
        public bool use_fill = true;
        public bool use_stroke = true;
        public bool use_effects = true;
        public bool use_corner = true;
        public bool use_wrap = true;
        public bool use_frame = true;
        public bool use_para = false;
        public string para_style = "";
        public TextFrame proto = new TextFrame ();

        public ObjectStyle (string name) {
            this.name = name;
        }

        public ObjectStyle clone () {
            var o = new ObjectStyle (name);
            o.based_on = based_on;
            o.use_fill = use_fill;
            o.use_stroke = use_stroke;
            o.use_effects = use_effects;
            o.use_corner = use_corner;
            o.use_wrap = use_wrap;
            o.use_frame = use_frame;
            o.use_para = use_para;
            o.para_style = para_style;
            o.proto = (TextFrame) proto.clone ();
            return o;
        }

        public static ObjectStyle from_item (string name, Item it, Publication pub) {
            var o = new ObjectStyle (name);
            var p = o.proto;
            p.fill = it.fill.clone ();
            p.stroke = it.stroke.clone ();
            p.opacity = it.opacity;
            p.shadow = it.shadow.clone ();
            p.effects = it.effects.clone ();
            p.border_art = it.border_art.clone ();
            p.corner = it.corner;
            p.corner_radius = it.corner_radius;
            p.wrap = it.wrap;
            p.wrap_offset = it.wrap_offset;
            p.wrap_side = it.wrap_side;
            var t = it as TextFrame;
            o.use_frame = t != null;
            if (t != null) {
                p.inset_left = t.inset_left;
                p.inset_top = t.inset_top;
                p.inset_right = t.inset_right;
                p.inset_bottom = t.inset_bottom;
                p.columns = t.columns;
                p.gutter = t.gutter;
                p.valign = t.valign;
                var st = pub.story (t.story);
                if (st.paras.size > 0) o.para_style = st.paras[0].style;
            }
            return o;
        }

        private void apply_self (Publication pub, Item it) {
            var p = proto;
            if (use_fill) it.fill = p.fill.clone ();
            if (use_stroke) it.stroke = p.stroke.clone ();
            if (use_effects) {
                it.opacity = p.opacity;
                it.shadow = p.shadow.clone ();
                it.effects = p.effects.clone ();
                it.border_art = p.border_art.clone ();
            }
            if (use_corner) {
                it.corner = p.corner;
                it.corner_radius = p.corner_radius;
            }
            if (use_wrap) {
                it.wrap = p.wrap;
                it.wrap_offset = p.wrap_offset;
                it.wrap_side = p.wrap_side;
            }
            var t = it as TextFrame;
            if (t == null) return;
            if (use_frame) {
                t.inset_left = p.inset_left;
                t.inset_top = p.inset_top;
                t.inset_right = p.inset_right;
                t.inset_bottom = p.inset_bottom;
                t.columns = p.columns;
                t.gutter = p.gutter;
                t.valign = p.valign;
            }
            if (use_para && para_style != "" && pub.styles.find_paragraph (para_style) != null && pub.stories.has_key (t.story)) {
                foreach (var para in pub.story (t.story).paras) para.style = para_style;
            }
        }

        public void apply_to (Publication pub, Item it) {
            var chain = new Gee.ArrayList<ObjectStyle> ();
            ObjectStyle? cur = this;
            int guard = 0;
            while (cur != null && guard++ < 16 && !chain.contains (cur)) {
                chain.insert (0, cur);
                cur = cur.based_on != "" ? pub.object_style (cur.based_on) : null;
            }
            foreach (var s in chain) s.apply_self (pub, it);
            it.object_style = name;
        }

        public string flags () {
            var sb = new StringBuilder ();
            if (use_fill) sb.append ("fill ");
            if (use_stroke) sb.append ("stroke ");
            if (use_effects) sb.append ("effects ");
            if (use_corner) sb.append ("corner ");
            if (use_wrap) sb.append ("wrap ");
            if (use_frame) sb.append ("frame ");
            if (use_para) sb.append ("para ");
            return sb.str.strip ();
        }

        public void set_flags (string f) {
            var set = new Gee.HashSet<string> ();
            foreach (string w in f.split (" ")) if (w != "") set.add (w);
            use_fill = set.contains ("fill");
            use_stroke = set.contains ("stroke");
            use_effects = set.contains ("effects");
            use_corner = set.contains ("corner");
            use_wrap = set.contains ("wrap");
            use_frame = set.contains ("frame");
            use_para = set.contains ("para");
        }
    }

    public class AnchorSpec {
        public int mode = 0;
        public int x_ref = 0;
        public double x_offset = 0;
        public double y_offset = 0;

        public const string FIELD = "anchor";

        public AnchorSpec clone () {
            var a = new AnchorSpec ();
            a.mode = mode;
            a.x_ref = x_ref;
            a.x_offset = x_offset;
            a.y_offset = y_offset;
            return a;
        }

        public bool inline () {
            return mode == 0;
        }
    }

    public class TableFlow {
        public static TableItem head (Publication pub, TableItem t) {
            TableItem cur = t;
            int guard = 0;
            while (cur.continue_from != 0 && guard++ < 1000) {
                var r = pub.find_item (cur.continue_from);
                var prev = r != null ? r.item as TableItem : null;
                if (prev == null) break;
                cur = prev;
            }
            return cur;
        }

        public static Gee.ArrayList<TableItem> chain (Publication pub, TableItem t) {
            var list = new Gee.ArrayList<TableItem> ();
            TableItem? cur = head (pub, t);
            while (cur != null && !list.contains (cur) && list.size < 1000) {
                list.add (cur);
                if (cur.continue_to == 0) break;
                var r = pub.find_item (cur.continue_to);
                cur = r != null ? r.item as TableItem : null;
            }
            return list;
        }

        public static Gee.ArrayList<Gee.ArrayList<int>> assign (Publication pub, TableItem t, out bool overset) {
            var tables = chain (pub, t);
            var master = tables[0];
            var result = new Gee.ArrayList<Gee.ArrayList<int>> ();
            int hdr = master.header_rows.clamp (0, master.rows);
            double hdr_h = 0;
            for (int r = 0; r < hdr; r++) hdr_h += master.row_h[r];
            int next = hdr;
            for (int i = 0; i < tables.size; i++) {
                var rows = new Gee.ArrayList<int> ();
                double used = 0;
                if (i == 0 || master.repeat_header) {
                    for (int r = 0; r < hdr; r++) rows.add (r);
                    used = hdr_h;
                }
                bool placed_body = false;
                while (next < master.rows) {
                    int span = 1;
                    for (int c = 0; c < master.cols; c++) {
                        var cell = master.cells[next][c];
                        if (!cell.covered) span = int.max (span, cell.row_span);
                    }
                    double hh = 0;
                    for (int r = next; r < next + span && r < master.rows; r++) hh += master.row_h[r];
                    if (used + hh > tables[i].h + 0.01 && placed_body) break;
                    for (int r = next; r < next + span && r < master.rows; r++) rows.add (r);
                    used += hh;
                    next += span;
                    placed_body = true;
                }
                result.add (rows);
            }
            overset = next < master.rows;
            return result;
        }

        public static Gee.ArrayList<int> rows_for (Publication pub, TableItem t, out TableItem master, out bool overset) {
            master = head (pub, t);
            if (!t.flows ()) {
                overset = false;
                var all = new Gee.ArrayList<int> ();
                for (int r = 0; r < t.rows; r++) all.add (r);
                return all;
            }
            var tables = chain (pub, t);
            var parts = assign (pub, t, out overset);
            int idx = tables.index_of (t);
            if (idx < 0) return new Gee.ArrayList<int> ();
            if (idx < tables.size - 1) overset = false;
            return parts[idx];
        }
    }
}
