namespace Singularity.Apps.Publish {

    public class BlockInfo {
        public string id;
        public string name;
        public string category;
        public string path = "";

        public BlockInfo (string id, string name, string category) {
            this.id = id;
            this.name = name;
            this.category = category;
        }
    }

    public class BuildingBlocks {
        public const string USER_PREFIX = "user:";
        public static int calendar_year = 0;
        public static int calendar_month = 0;

        public static string cat_page_parts () {
            return _("Page Parts");
        }

        public static string cat_calendars () {
            return _("Calendars");
        }

        public static string cat_accents () {
            return _("Borders and Accents");
        }

        public static string cat_ads () {
            return _("Advertisements");
        }

        public static string cat_business () {
            return _("Business Information");
        }

        public static string cat_mine () {
            return _("My Building Blocks");
        }

        public static Gee.ArrayList<string> categories () {
            var l = new Gee.ArrayList<string> ();
            l.add (cat_page_parts ());
            l.add (cat_calendars ());
            l.add (cat_accents ());
            l.add (cat_ads ());
            l.add (cat_business ());
            l.add (cat_mine ());
            return l;
        }

        public static Gee.ArrayList<BlockInfo> builtins () {
            var l = new Gee.ArrayList<BlockInfo> ();
            string pp = cat_page_parts (), cal = cat_calendars (), acc = cat_accents (), ad = cat_ads (), biz = cat_business ();
            l.add (new BlockInfo ("heading-bar", _("Heading on a Bar"), pp));
            l.add (new BlockInfo ("heading-classic", _("Classic Heading"), pp));
            l.add (new BlockInfo ("heading-accent", _("Accent Heading"), pp));
            l.add (new BlockInfo ("heading-boxed", _("Boxed Heading"), pp));
            l.add (new BlockInfo ("pull-quote-lines", _("Pull Quote with Rules"), pp));
            l.add (new BlockInfo ("pull-quote-box", _("Pull Quote in a Box"), pp));
            l.add (new BlockInfo ("pull-quote-marks", _("Pull Quote with Marks"), pp));
            l.add (new BlockInfo ("sidebar-box", _("Sidebar"), pp));
            l.add (new BlockInfo ("sidebar-list", _("Sidebar List"), pp));
            l.add (new BlockInfo ("story-2col", _("Two Column Story"), pp));
            l.add (new BlockInfo ("contents", _("Table of Contents"), pp));
            l.add (new BlockInfo ("calendar-grid", _("Monthly Calendar"), cal));
            l.add (new BlockInfo ("calendar-banded", _("Banded Calendar"), cal));
            l.add (new BlockInfo ("calendar-compact", _("Compact Calendar"), cal));
            l.add (new BlockInfo ("accent-bar", _("Accent Bar"), acc));
            l.add (new BlockInfo ("accent-frame", _("Double Frame"), acc));
            l.add (new BlockInfo ("accent-corner", _("Corner Accent"), acc));
            l.add (new BlockInfo ("accent-divider", _("Divider"), acc));
            l.add (new BlockInfo ("accent-dots", _("Dotted Rule"), acc));
            l.add (new BlockInfo ("accent-stripes", _("Stripes"), acc));
            l.add (new BlockInfo ("border-stars", _("Star Border"), acc));
            l.add (new BlockInfo ("border-hearts", _("Heart Border"), acc));
            l.add (new BlockInfo ("ad-coupon", _("Coupon"), ad));
            l.add (new BlockInfo ("ad-burst", _("Sale Burst"), ad));
            l.add (new BlockInfo ("ad-classic", _("Classic Advertisement"), ad));
            l.add (new BlockInfo ("ad-banner", _("Banner Advertisement"), ad));
            l.add (new BlockInfo ("ad-attention", _("Attention Getter"), ad));
            l.add (new BlockInfo ("biz-contact", _("Contact Information"), biz));
            l.add (new BlockInfo ("biz-card", _("Name and Title"), biz));
            l.add (new BlockInfo ("biz-tagline", _("Tagline"), biz));
            l.add (new BlockInfo ("biz-logo", _("Organization Name"), biz));
            return l;
        }

        public static string user_dir () {
            return Path.build_filename (Environment.get_user_data_dir (), "singularity", "publish", "building-blocks");
        }

        public static Gee.ArrayList<BlockInfo> user_blocks () {
            var l = new Gee.ArrayList<BlockInfo> ();
            try {
                var d = Dir.open (user_dir ());
                string? n;
                while ((n = d.read_name ()) != null) {
                    if (!n.has_suffix (".xml")) continue;
                    string p = Path.build_filename (user_dir (), n);
                    string text;
                    FileUtils.get_contents (p, out text);
                    Xml.Doc* doc = XmlIn.parse (text);
                    var root = doc->get_root_element ();
                    var bi = new BlockInfo (USER_PREFIX + n.substring (0, n.length - 4), XmlIn.attr (root, "name") ?? n, cat_mine ());
                    bi.path = p;
                    delete doc;
                    l.add (bi);
                }
            } catch (Error e) {
            }
            l.sort ((a, b) => a.name.collate (b.name));
            return l;
        }

        public static Gee.ArrayList<BlockInfo> all () {
            var l = builtins ();
            l.add_all (user_blocks ());
            return l;
        }

        public static void ensure_scheme (Publication pub) {
            if (pub.swatch (ColorScheme.MAIN) != null) return;
            var cs = ColorScheme.find (pub.color_scheme != "" ? pub.color_scheme : "Bluebird") ?? ColorScheme.builtins ()[0];
            string saved = pub.color_scheme;
            cs.apply (pub);
            pub.color_scheme = saved != "" ? saved : cs.name;
        }

        private static TextFrame text (Publication pub, Gee.ArrayList<Item> list, double x, double y, double w, double h, string txt, string style, double size = double.NAN, string? color = null, int align = -1, int bold = -1, int italic = -1) {
            var t = pub.add_text_frame (list, x, y, w, h);
            var st = pub.story (t.story);
            st.paras.clear ();
            foreach (string line in txt.split ("\n")) {
                var p = new Paragraph.with_text (line, pub.styles.find_paragraph (style) != null ? style : StyleSheet.BASIC);
                if (align >= 0) p.fmt.align = align;
                if (!size.is_nan ()) p.fmt.leading = 0;
                var r = p.runs[0];
                if (!size.is_nan ()) r.fmt.size = size;
                if (color != null) r.fmt.color = color;
                if (bold >= 0) r.fmt.bold = bold;
                if (italic >= 0) r.fmt.italic = italic;
                st.paras.add (p);
            }
            return t;
        }

        private static TextFrame field_text (Publication pub, Gee.ArrayList<Item> list, double x, double y, double w, double h, string[] keys, double size, string color, int align = 0, int bold = 0) {
            var t = pub.add_text_frame (list, x, y, w, h);
            var st = pub.story (t.story);
            st.paras.clear ();
            foreach (string k in keys) {
                var p = new Paragraph ();
                p.fmt.align = align;
                var run = new Run.field_run (Fields.biz (k));
                run.fmt.size = size;
                run.fmt.color = color;
                run.fmt.bold = bold;
                p.runs.add (run);
                st.paras.add (p);
            }
            if (st.paras.size == 0) st.paras.add (new Paragraph.with_text (""));
            return t;
        }

        private static ShapeItem box (Publication pub, Gee.ArrayList<Item> list, ShapeKind kind, double x, double y, double w, double h, string fill, string stroke = "", double width = 0) {
            var s = new ShapeItem (kind);
            s.id = pub.next_id ();
            s.x = x;
            s.y = y;
            s.w = w;
            s.h = h;
            s.layer = pub.default_layer ().id;
            s.fill = new Fill.solid (fill);
            if (stroke != "") s.stroke = new Stroke.with (stroke, width);
            list.add (s);
            return s;
        }

        private static string c (int slot, double tint = 100) {
            return ColorScheme.slot_spec (slot, tint);
        }

        public static GroupItem? build (Publication pub, string id, double x, double y) {
            ensure_scheme (pub);
            var items = new Gee.ArrayList<Item> ();
            double cx = 0, cy = 0;
            switch (id) {
                case "heading-bar":
                    box (pub, items, ShapeKind.RECT, cx, cy, 360, 44, c (1));
                    var hb = text (pub, items, cx + 12, cy + 8, 336, 30, _("Heading"), "Heading 1", 22, ColorRef.PAPER, 0, 1);
                    hb.valign = 1;
                    break;
                case "heading-classic":
                    text (pub, items, cx, cy, 360, 36, _("Heading"), "Heading 1", 26, c (0), 0, 1);
                    box (pub, items, ShapeKind.LINE, cx, cy + 40, 360, 0, ColorRef.NONE, c (1), 2);
                    text (pub, items, cx, cy + 46, 360, 20, _("A short summary of the story that follows"), StyleSheet.BASIC, 10.5, c (0, 70), 0, 0, 1);
                    break;
                case "heading-accent":
                    box (pub, items, ShapeKind.RECT, cx, cy, 8, 44, c (2));
                    text (pub, items, cx + 16, cy + 2, 344, 40, _("Heading"), "Heading 1", 24, c (0), 0, 1);
                    break;
                case "heading-boxed":
                    var hbx = box (pub, items, ShapeKind.RECT, cx, cy, 360, 50, c (5, 60), c (1), 1.5);
                    hbx.corner = CornerKind.ROUNDED;
                    hbx.corner_radius = 8;
                    var ht = text (pub, items, cx + 10, cy + 6, 340, 38, _("Heading"), "Heading 1", 22, c (0), 1, 1);
                    ht.valign = 1;
                    break;
                case "pull-quote-lines":
                    box (pub, items, ShapeKind.LINE, cx, cy, 220, 0, ColorRef.NONE, c (1), 2);
                    text (pub, items, cx, cy + 8, 220, 70, _("\"Place a memorable sentence from the story here to draw the reader in.\""), StyleSheet.BASIC, 15, c (1), 1, 0, 1);
                    box (pub, items, ShapeKind.LINE, cx, cy + 84, 220, 0, ColorRef.NONE, c (1), 2);
                    break;
                case "pull-quote-box":
                    box (pub, items, ShapeKind.RECT, cx, cy, 220, 100, c (1));
                    var pq = text (pub, items, cx + 12, cy + 10, 196, 80, _("\"Place a memorable sentence from the story here to draw the reader in.\""), StyleSheet.BASIC, 14, ColorRef.PAPER, 0, 1);
                    pq.valign = 1;
                    break;
                case "pull-quote-marks":
                    text (pub, items, cx - 6, cy - 16, 44, 84, "“", StyleSheet.BASIC, 60, c (2), 0, 1);
                    text (pub, items, cx + 30, cy + 10, 190, 80, _("Place a memorable sentence from the story here to draw the reader in."), StyleSheet.BASIC, 14, c (0), 0, 0, 1);
                    break;
                case "sidebar-box":
                    box (pub, items, ShapeKind.RECT, cx, cy, 170, 260, c (5, 50));
                    box (pub, items, ShapeKind.RECT, cx, cy, 170, 30, c (1));
                    text (pub, items, cx + 8, cy + 5, 154, 22, _("Sidebar Heading"), "Heading 2", 13, ColorRef.PAPER, 0, 1);
                    text (pub, items, cx + 8, cy + 38, 154, 214, _("Use a sidebar for a related short story, a list of highlights or a note to the reader."), StyleSheet.BASIC, 10);
                    break;
                case "sidebar-list":
                    box (pub, items, ShapeKind.RECT, cx, cy, 170, 220, ColorRef.NONE, c (1), 1.5);
                    text (pub, items, cx + 10, cy + 8, 150, 22, _("Inside This Issue"), "Heading 2", 13, c (1), 0, 1);
                    var sl = text (pub, items, cx + 10, cy + 34, 150, 176, _("First story\nSecond story\nThird story\nFourth story\nFifth story"), "Bulleted List", 10);
                    sl.valign = 0;
                    break;
                case "story-2col":
                    text (pub, items, cx, cy, 380, 30, _("Story Heading"), "Heading 1", 20, c (0), 0, 1);
                    var body = text (pub, items, cx, cy + 36, 380, 220, _("This story can fit 150 to 200 words. Replace this text with your own content. Use short paragraphs and a clear heading so readers can scan the page quickly."), "Body Text", 10);
                    body.columns = 2;
                    body.gutter = 14;
                    break;
                case "contents":
                    box (pub, items, ShapeKind.RECT, cx, cy, 200, 30, c (0));
                    text (pub, items, cx + 8, cy + 6, 184, 20, _("Contents"), "Heading 2", 13, ColorRef.PAPER, 0, 1);
                    var toc = text (pub, items, cx, cy + 36, 200, 150, _("Welcome\t2\nNews\t3\nFeature Story\t4\nCalendar\t6\nContact Us\t8"), StyleSheet.BASIC, 10.5);
                    foreach (var p in pub.story (toc.story).paras) p.fmt.tabs = TabStop.serialize (new Gee.ArrayList<TabStop>.wrap ({ new TabStop (196, TabKind.RIGHT, ".") }));
                    break;
                case "calendar-grid":
                case "calendar-banded":
                case "calendar-compact":
                    build_calendar (pub, items, id);
                    break;
                case "accent-bar":
                    box (pub, items, ShapeKind.RECT, cx, cy, 400, 14, c (1));
                    box (pub, items, ShapeKind.RECT, cx, cy + 18, 400, 4, c (2));
                    break;
                case "accent-frame":
                    box (pub, items, ShapeKind.RECT, cx, cy, 300, 200, ColorRef.NONE, c (1), 3);
                    box (pub, items, ShapeKind.RECT, cx + 8, cy + 8, 284, 184, ColorRef.NONE, c (2), 1);
                    break;
                case "accent-corner":
                    var tri = ShapeLib.make (pub, "right-triangle", cx, cy, 120, 120);
                    tri.fill = new Fill.solid (c (1));
                    tri.stroke = new Stroke ();
                    tri.flip_v = true;
                    items.add (tri);
                    var tri2 = ShapeLib.make (pub, "right-triangle", cx, cy, 70, 70);
                    tri2.fill = new Fill.solid (c (2));
                    tri2.stroke = new Stroke ();
                    tri2.flip_v = true;
                    items.add (tri2);
                    break;
                case "accent-divider":
                    box (pub, items, ShapeKind.LINE, cx, cy + 10, 170, 0, ColorRef.NONE, c (1), 1);
                    var dm = ShapeLib.make (pub, "diamond", cx + 178, cy + 2, 16, 16);
                    dm.fill = new Fill.solid (c (2));
                    dm.stroke = new Stroke ();
                    items.add (dm);
                    box (pub, items, ShapeKind.LINE, cx + 202, cy + 10, 170, 0, ColorRef.NONE, c (1), 1);
                    break;
                case "accent-dots":
                    for (int i = 0; i < 20; i++) box (pub, items, ShapeKind.ELLIPSE, cx + i * 18, cy, 8, 8, c (i % 2 == 0 ? 1 : 2));
                    break;
                case "accent-stripes":
                    for (int i = 0; i < 4; i++) box (pub, items, ShapeKind.RECT, cx, cy + i * 10, 400, 6, c (1, 100 - i * 20));
                    break;
                case "border-stars":
                case "border-hearts":
                    var fr = box (pub, items, ShapeKind.RECT, cx, cy, 300, 220, ColorRef.NONE);
                    fr.border_art.design = id == "border-stars" ? "stars" : "hearts";
                    fr.border_art.size = 18;
                    fr.border_art.color = id == "border-stars" ? c (1) : "";
                    break;
                case "ad-coupon":
                    var cp = box (pub, items, ShapeKind.RECT, cx, cy, 240, 130, ColorRef.PAPER, c (0), 1.5);
                    cp.stroke.dash = DashKind.DASH;
                    text (pub, items, cx + 12, cy + 10, 216, 26, _("Organization Name"), StyleSheet.BASIC, 12, c (0), 1, 1);
                    text (pub, items, cx + 12, cy + 34, 216, 46, _("00% OFF"), "Heading 1", 30, c (1), 1, 1);
                    text (pub, items, cx + 12, cy + 82, 216, 40, _("Describe your product or service here.\nExpires: 00/00/00"), StyleSheet.BASIC, 9, c (0, 80), 1);
                    break;
                case "ad-burst":
                    var burst = ShapeLib.make (pub, "explosion-2", cx, cy, 180, 150);
                    burst.fill = new Fill.solid (c (2));
                    burst.stroke = new Stroke.with (c (1), 2);
                    items.add (burst);
                    var bt = text (pub, items, cx + 45, cy + 50, 90, 50, _("SALE!"), "Heading 1", 26, c (0), 1, 1);
                    bt.valign = 1;
                    break;
                case "ad-classic":
                    box (pub, items, ShapeKind.RECT, cx, cy, 260, 180, c (5, 40), c (1), 2);
                    text (pub, items, cx + 14, cy + 12, 232, 36, _("Product or Service"), "Heading 1", 22, c (1), 1, 1);
                    text (pub, items, cx + 14, cy + 54, 232, 70, _("Describe what makes your offer special. List a key benefit or two."), StyleSheet.BASIC, 11, c (0), 1);
                    field_text (pub, items, cx + 14, cy + 128, 232, 40, { "organization", "phone" }, 10, c (0), 1, 1);
                    break;
                case "ad-banner":
                    box (pub, items, ShapeKind.RECT, cx, cy, 420, 70, c (1));
                    var ab = text (pub, items, cx + 14, cy + 10, 300, 50, _("Grand Opening"), "Heading 1", 26, ColorRef.PAPER, 0, 1);
                    ab.valign = 1;
                    var ab2 = text (pub, items, cx + 314, cy + 10, 96, 50, _("This Weekend"), StyleSheet.BASIC, 12, c (2), 2, 1);
                    ab2.valign = 1;
                    break;
                case "ad-attention":
                    var at = ShapeLib.make (pub, "arrow-callout", cx, cy, 200, 80);
                    at.fill = new Fill.solid (c (2));
                    at.stroke = new Stroke ();
                    items.add (at);
                    var att = text (pub, items, cx + 10, cy + 20, 110, 40, _("New!"), "Heading 1", 22, c (0), 1, 1);
                    att.valign = 1;
                    break;
                case "biz-contact":
                    field_text (pub, items, cx, cy, 220, 20, { "organization" }, 13, c (1), 0, 1);
                    field_text (pub, items, cx, cy + 22, 220, 110, { "address", "phone", "fax", "email", "website" }, 9.5, c (0));
                    break;
                case "biz-card":
                    field_text (pub, items, cx, cy, 220, 22, { "name" }, 14, c (0), 0, 1);
                    field_text (pub, items, cx, cy + 22, 220, 18, { "job-title" }, 10, c (1));
                    break;
                case "biz-tagline":
                    field_text (pub, items, cx, cy, 300, 24, { "tagline" }, 13, c (1), 1);
                    break;
                case "biz-logo":
                    box (pub, items, ShapeKind.ELLIPSE, cx, cy, 44, 44, c (1));
                    field_text (pub, items, cx + 54, cy + 10, 220, 26, { "organization" }, 16, c (0), 0, 1);
                    break;
                default:
                    if (id.has_prefix (USER_PREFIX)) return load_user (pub, id, x, y);
                    return null;
            }
            if (items.size == 0) return null;
            var g = new GroupItem ();
            g.id = pub.next_id ();
            g.layer = pub.default_layer ().id;
            g.children.add_all (items);
            g.fit_children ();
            g.name = find_name (id);
            g.move_by (x - g.x, y - g.y);
            return g;
        }

        private static string find_name (string id) {
            foreach (var b in builtins ()) if (b.id == id) return b.name;
            return "";
        }

        private static void build_calendar (Publication pub, Gee.ArrayList<Item> items, string id) {
            var now = new DateTime.now_local ();
            int year = calendar_year > 0 ? calendar_year : now.get_year ();
            int month = calendar_month > 0 ? calendar_month : now.get_month ();
            var first = new DateTime.local (year, month, 1, 0, 0, 0);
            int days = (int) Date.get_days_in_month ((DateMonth) month, (DateYear) year);
            int offset = first.get_day_of_week () - 1;
            int weeks = (offset + days + 6) / 7;
            bool compact = id == "calendar-compact";
            double cw = compact ? 26 : 50, rh = compact ? 18 : 40;
            text (pub, items, 0, 0, cw * 7, compact ? 22 : 34, first.format ("%B %Y"), "Heading 1", compact ? 13 : 22, c (id == "calendar-banded" ? 1 : 0), 1, 1);
            var tb = new TableItem (weeks + 1, 7);
            tb.id = pub.next_id ();
            tb.x = 0;
            tb.y = compact ? 24 : 38;
            tb.w = cw * 7;
            tb.h = rh * weeks + (compact ? 16 : 22);
            tb.layer = pub.default_layer ().id;
            tb.init_cells (pub);
            tb.row_h[0] = compact ? 16 : 22;
            for (int r = 1; r <= weeks; r++) tb.row_h[r] = rh;
            tb.sync_size ();
            tb.header_rows = 1;
            tb.header_fill = c (1);
            tb.alt_fill = id == "calendar-banded" ? c (5, 40) : ColorRef.NONE;
            tb.border_color = id == "calendar-compact" ? ColorRef.NONE : c (1, 60);
            tb.border_width = id == "calendar-compact" ? 0 : 0.5;
            tb.cell_inset = compact ? 2 : 4;
            var monday = new DateTime.local (2024, 1, 1, 0, 0, 0);
            for (int d = 0; d < 7; d++) {
                var cell = tb.cells[0][d];
                string label = monday.add_days (d).format (compact ? "%a" : "%a");
                cell.story.paras.clear ();
                var p = new Paragraph.with_text (compact ? label.substring (0, label.index_of_nth_char (int.min (2, label.char_count ()))) : label);
                p.fmt.align = 1;
                p.runs[0].fmt.color = ColorRef.PAPER;
                p.runs[0].fmt.bold = 1;
                p.runs[0].fmt.size = compact ? 7 : 9;
                cell.story.paras.add (p);
            }
            for (int day = 1; day <= days; day++) {
                int idx = offset + day - 1;
                var cell = tb.cells[1 + idx / 7][idx % 7];
                cell.story.paras.clear ();
                var p = new Paragraph.with_text (day.to_string ());
                p.fmt.align = compact ? 1 : 2;
                p.runs[0].fmt.size = compact ? 8 : 10;
                if (idx % 7 >= 5) p.runs[0].fmt.color = c (1);
                cell.story.paras.add (p);
            }
            items.add (tb);
        }

        public static string save_user (Publication pub, Gee.List<Item> items, string name) throws Error {
            var x = new XmlOut ();
            x.start ("block").a ("name", name);
            x.start ("stories");
            var done = new Gee.HashSet<int> ();
            foreach (var it in items) write_stories (pub, it, x, done);
            x.end ();
            x.start ("items");
            foreach (var it in items) NativeFormat.write_item (x, it);
            x.end ();
            x.end ();
            DirUtils.create_with_parents (user_dir (), 0700);
            string slug = "%lld".printf (get_real_time ());
            string p = Path.build_filename (user_dir (), slug + ".xml");
            FileUtils.set_contents (p, x.finish ());
            return USER_PREFIX + slug;
        }

        private static void write_stories (Publication pub, Item it, XmlOut x, Gee.HashSet<int> done) {
            var t = it as TextFrame;
            if (t != null && !done.contains (t.story) && pub.stories.has_key (t.story)) {
                done.add (t.story);
                x.start ("story").ai ("id", t.story);
                NativeFormat.write_paras (x, pub.stories[t.story]);
                x.end ();
            }
            var g = it as GroupItem;
            if (g != null) foreach (var ch in g.children) write_stories (pub, ch, x, done);
        }

        public static void delete_user (string id) {
            if (!id.has_prefix (USER_PREFIX)) return;
            FileUtils.unlink (Path.build_filename (user_dir (), id.substring (USER_PREFIX.length) + ".xml"));
        }

        private static void adopt (Publication pub, Item it, Gee.HashMap<int, Story> stories, Gee.HashMap<int, int> map) {
            it.id = pub.next_id ();
            it.layer = pub.default_layer ().id;
            var t = it as TextFrame;
            if (t != null) {
                if (!map.has_key (t.story)) {
                    var s = stories.has_key (t.story) ? stories[t.story].clone () : new Story (0);
                    s.id = pub.next_id ();
                    s.frames.clear ();
                    pub.stories[s.id] = s;
                    map[t.story] = s.id;
                }
                t.story = map[t.story];
                pub.stories[t.story].frames.add (t.id);
            }
            var tb = it as TableItem;
            if (tb != null) foreach (var row in tb.cells) foreach (var cell in row) cell.story.id = pub.next_id ();
            var g = it as GroupItem;
            if (g != null) foreach (var ch in g.children) adopt (pub, ch, stories, map);
        }

        public static GroupItem? load_user (Publication pub, string id, double x, double y) {
            string p = Path.build_filename (user_dir (), id.substring (USER_PREFIX.length) + ".xml");
            try {
                string text;
                FileUtils.get_contents (p, out text);
                Xml.Doc* doc = NativeFormat.parse_keep_space (text);
                var root = doc->get_root_element ();
                var stories = new Gee.HashMap<int, Story> ();
                foreach (var sn in XmlIn.elements (XmlIn.child (root, "stories"), "story")) {
                    var st = new Story (XmlIn.int_attr (sn, "id", 0));
                    NativeFormat.read_paras (sn, st);
                    stories[st.id] = st;
                }
                var g = new GroupItem ();
                foreach (var n in XmlIn.elements (XmlIn.child (root, "items"))) {
                    var it = NativeFormat.read_item (n);
                    if (it != null) g.children.add (it);
                }
                string name = XmlIn.attr (root, "name") ?? "";
                delete doc;
                if (g.children.size == 0) return null;
                var map = new Gee.HashMap<int, int> ();
                foreach (var ch in g.children) adopt (pub, ch, stories, map);
                if (g.children.size == 1 && g.children[0] is GroupItem) g = (GroupItem) g.children[0];
                else {
                    g.id = pub.next_id ();
                    g.layer = pub.default_layer ().id;
                    g.fit_children ();
                }
                g.name = name;
                g.move_by (x - g.x, y - g.y);
                return g;
            } catch (Error e) {
                return null;
            }
        }
    }

    public class Captions {
        public static string[] ids () {
            return { "below", "above", "overlay-bottom", "overlay-top", "right", "left", "band", "boxed" };
        }

        public static string label (string id) {
            switch (id) {
                case "below": return _("Below");
                case "above": return _("Above");
                case "overlay-bottom": return _("Overlay Bottom");
                case "overlay-top": return _("Overlay Top");
                case "right": return _("Beside, Right");
                case "left": return _("Beside, Left");
                case "band": return _("Colour Band Below");
                case "boxed": return _("Boxed Below");
                default: return id;
            }
        }

        public static GroupItem add (Publication pub, Gee.ArrayList<Item> list, ImageFrame im, string style, string caption) {
            BuildingBlocks.ensure_scheme (pub);
            double h = 30, gap = 4;
            Rect r;
            switch (style) {
                case "above": r = Rect (im.x, im.y - h - gap, im.w, h); break;
                case "overlay-bottom": r = Rect (im.x, im.y + im.h - h, im.w, h); break;
                case "overlay-top": r = Rect (im.x, im.y, im.w, h); break;
                case "right": r = Rect (im.x + im.w + gap * 2, im.y, double.max (60, im.w * 0.45), im.h); break;
                case "left":
                    double lw = double.max (60, im.w * 0.45);
                    r = Rect (im.x - lw - gap * 2, im.y, lw, im.h);
                    break;
                default: r = Rect (im.x, im.y + im.h + gap, im.w, h); break;
            }
            int idx = list.index_of (im);
            var t = pub.add_text_frame (list, r.x, r.y, r.w, r.h);
            list.remove (t);
            var st = pub.story (t.story);
            st.paras.clear ();
            var p = new Paragraph.with_text (caption != "" ? caption : _("Caption describing the picture"), pub.styles.find_paragraph ("Caption") != null ? "Caption" : StyleSheet.BASIC);
            st.paras.add (p);
            t.inset_left = t.inset_right = 4;
            t.inset_top = t.inset_bottom = 3;
            if (style.has_prefix ("overlay")) {
                t.fill = new Fill.solid (ColorScheme.slot_spec (0));
                t.opacity = 0.85;
                p.runs[0].fmt.color = ColorRef.PAPER;
                t.valign = 1;
            } else if (style == "band") {
                t.fill = new Fill.solid (ColorScheme.slot_spec (1));
                p.runs[0].fmt.color = ColorRef.PAPER;
                t.valign = 1;
            } else if (style == "boxed") {
                t.stroke = new Stroke.with (ColorScheme.slot_spec (1), 1);
                t.valign = 1;
            }
            if (style == "right" || style == "left") t.valign = 2;
            list.remove (im);
            var g = new GroupItem ();
            g.id = pub.next_id ();
            g.layer = im.layer;
            g.name = _("Picture with Caption");
            g.children.add (im);
            g.children.add (t);
            g.fit_children ();
            list.insert (idx.clamp (0, list.size), g);
            return g;
        }
    }

    public class PictureStyles {
        public static string[] ids () {
            return { "simple-white", "simple-black", "thick-matte", "drop-shadow", "rounded", "soft-edge", "reflected", "oval", "metal-oval", "beveled", "center-shadow", "rotated-white", "glow-edge", "moderate-black", "snip-corner", "heart" };
        }

        public static string label (string id) {
            switch (id) {
                case "simple-white": return _("Simple Frame, White");
                case "simple-black": return _("Simple Frame, Black");
                case "thick-matte": return _("Thick Matte, Black");
                case "drop-shadow": return _("Drop Shadow Rectangle");
                case "rounded": return _("Rounded Rectangle");
                case "soft-edge": return _("Soft Edge Rectangle");
                case "reflected": return _("Reflected Rounded Rectangle");
                case "oval": return _("Oval");
                case "metal-oval": return _("Metal Oval");
                case "beveled": return _("Beveled Matte, White");
                case "center-shadow": return _("Center Shadow Rectangle");
                case "rotated-white": return _("Rotated, White");
                case "glow-edge": return _("Glow Edge");
                case "moderate-black": return _("Moderate Frame, Black");
                case "snip-corner": return _("Snip Corner");
                case "heart": return _("Heart");
                default: return id;
            }
        }

        public static void apply (ImageFrame im, string id) {
            im.stroke = new Stroke ();
            im.shadow = new Shadow ();
            im.effects = new Effects ();
            im.corner = CornerKind.NONE;
            im.corner_radius = 0;
            im.clip_shape = "";
            im.shape_ellipse = false;
            switch (id) {
                case "simple-white":
                    im.stroke = new Stroke.with (ColorRef.PAPER, 6);
                    im.shadow.enabled = true;
                    im.shadow.blur = 4;
                    im.shadow.dx = im.shadow.dy = 2;
                    break;
                case "simple-black":
                    im.stroke = new Stroke.with (ColorRef.BLACK, 5);
                    break;
                case "thick-matte":
                    im.stroke = new Stroke.with (ColorRef.BLACK, 14);
                    break;
                case "drop-shadow":
                    im.shadow.enabled = true;
                    im.shadow.dx = im.shadow.dy = 5;
                    im.shadow.blur = 8;
                    im.shadow.opacity = 0.45;
                    break;
                case "rounded":
                    im.clip_shape = "rounded-rect";
                    im.shadow.enabled = true;
                    break;
                case "soft-edge":
                    im.effects.soft_edges = 10;
                    break;
                case "reflected":
                    im.clip_shape = "rounded-rect";
                    im.effects.reflection = true;
                    break;
                case "oval":
                    im.clip_shape = "ellipse";
                    break;
                case "metal-oval":
                    im.clip_shape = "ellipse";
                    im.stroke = new Stroke.with ("#8a8f96", 7);
                    im.effects.bevel = true;
                    im.effects.bevel_depth = 5;
                    break;
                case "beveled":
                    im.stroke = new Stroke.with (ColorRef.PAPER, 8);
                    im.effects.bevel = true;
                    im.effects.bevel_depth = 4;
                    break;
                case "center-shadow":
                    im.shadow.enabled = true;
                    im.shadow.dx = im.shadow.dy = 0;
                    im.shadow.blur = 14;
                    im.shadow.opacity = 0.55;
                    break;
                case "rotated-white":
                    im.stroke = new Stroke.with (ColorRef.PAPER, 8);
                    im.shadow.enabled = true;
                    im.rotation = -3;
                    break;
                case "glow-edge":
                    im.effects.glow = true;
                    im.effects.glow_color = ColorScheme.slot_spec (2);
                    im.effects.glow_size = 10;
                    break;
                case "moderate-black":
                    im.stroke = new Stroke.with (ColorRef.BLACK, 3);
                    im.shadow.enabled = true;
                    im.shadow.blur = 4;
                    break;
                case "snip-corner":
                    im.clip_shape = "snip-rect";
                    break;
                case "heart":
                    im.clip_shape = "heart";
                    break;
            }
        }

        public static void swap (ImageFrame a, ImageFrame b) {
            string link = a.link, media = a.media, stamp = a.link_stamp, mf = a.merge_field;
            double br = a.brightness, ct = a.contrast;
            int rc = a.recolor;
            string rcc = a.recolor_color, tc = a.transparent_color, alt = a.alt_text;
            a.link = b.link;
            a.media = b.media;
            a.link_stamp = b.link_stamp;
            a.merge_field = b.merge_field;
            a.brightness = b.brightness;
            a.contrast = b.contrast;
            a.recolor = b.recolor;
            a.recolor_color = b.recolor_color;
            a.transparent_color = b.transparent_color;
            a.alt_text = b.alt_text;
            b.link = link;
            b.media = media;
            b.link_stamp = stamp;
            b.merge_field = mf;
            b.brightness = br;
            b.contrast = ct;
            b.recolor = rc;
            b.recolor_color = rcc;
            b.transparent_color = tc;
            b.alt_text = alt;
            foreach (var f in new ImageFrame[] { a, b }) {
                if (f.fit == FitMode.MANUAL) f.fit = FitMode.FILL;
                f.focus_x = 0.5;
                f.focus_y = 0.5;
            }
        }
    }

    public class TableFormats {
        public static string[] ids () {
            return { "plain", "grid", "light-1", "light-2", "medium-1", "medium-2", "dark", "banded-rows", "banded-accent", "list-1", "list-2", "checkerboard", "header-only", "boxed", "minimal", "ledger", "invoice", "price-list", "column-emphasis", "outline" };
        }

        public static string label (string id) {
            switch (id) {
                case "plain": return _("Plain");
                case "grid": return _("Grid");
                case "light-1": return _("Light 1");
                case "light-2": return _("Light 2");
                case "medium-1": return _("Medium 1");
                case "medium-2": return _("Medium 2");
                case "dark": return _("Dark");
                case "banded-rows": return _("Banded Rows");
                case "banded-accent": return _("Banded Accent");
                case "list-1": return _("List 1");
                case "list-2": return _("List 2");
                case "checkerboard": return _("Checkerboard");
                case "header-only": return _("Header Only");
                case "boxed": return _("Boxed");
                case "minimal": return _("Minimal");
                case "ledger": return _("Ledger");
                case "invoice": return _("Invoice");
                case "price-list": return _("Price List");
                case "column-emphasis": return _("First Column Emphasis");
                case "outline": return _("Outline");
                default: return id;
            }
        }

        private static void header_text (TableItem t, string color, int bold) {
            for (int r = 0; r < t.header_rows && r < t.rows; r++) foreach (var cell in t.cells[r]) cell.story.apply_chars (TextPos (0, 0), cell.story.end_pos (), (run) => {
                run.fmt.color = color;
                run.fmt.bold = bold;
            });
        }

        public static void apply (Publication pub, TableItem t, string id) {
            BuildingBlocks.ensure_scheme (pub);
            foreach (var row in t.cells) foreach (var cell in row) cell.fill = ColorRef.NONE;
            if (t.header_rows == 0 && id != "plain" && id != "outline") t.header_rows = 1;
            t.border_color = ColorRef.swatch ("Black", 50);
            t.border_width = 0.5;
            t.header_fill = ColorRef.NONE;
            t.alt_fill = ColorRef.NONE;
            string main = ColorScheme.slot_spec (0), acc = ColorScheme.slot_spec (1), acc2 = ColorScheme.slot_spec (2);
            string head_color = ColorRef.BLACK;
            int head_bold = 1;
            switch (id) {
                case "plain":
                    t.border_color = ColorRef.NONE;
                    t.border_width = 0;
                    head_bold = 0;
                    break;
                case "grid":
                    t.border_color = ColorRef.BLACK;
                    break;
                case "light-1":
                    t.header_fill = ColorScheme.slot_spec (1, 25);
                    t.border_color = ColorScheme.slot_spec (1, 60);
                    break;
                case "light-2":
                    t.header_fill = ColorScheme.slot_spec (2, 30);
                    t.alt_fill = ColorScheme.slot_spec (2, 10);
                    t.border_color = ColorScheme.slot_spec (2, 60);
                    break;
                case "medium-1":
                    t.header_fill = acc;
                    t.alt_fill = ColorScheme.slot_spec (1, 15);
                    t.border_color = ColorRef.PAPER;
                    t.border_width = 1;
                    head_color = ColorRef.PAPER;
                    break;
                case "medium-2":
                    t.header_fill = acc2;
                    t.alt_fill = ColorScheme.slot_spec (2, 15);
                    t.border_color = ColorRef.PAPER;
                    t.border_width = 1;
                    head_color = ColorRef.PAPER;
                    break;
                case "dark":
                    t.header_fill = main;
                    t.alt_fill = ColorScheme.slot_spec (0, 15);
                    t.border_color = main;
                    head_color = ColorRef.PAPER;
                    break;
                case "banded-rows":
                    t.alt_fill = ColorRef.swatch ("Black", 8);
                    t.border_color = ColorRef.NONE;
                    t.border_width = 0;
                    break;
                case "banded-accent":
                    t.header_fill = acc;
                    t.alt_fill = ColorScheme.slot_spec (1, 12);
                    t.border_color = ColorRef.NONE;
                    t.border_width = 0;
                    head_color = ColorRef.PAPER;
                    break;
                case "list-1":
                    t.border_color = ColorScheme.slot_spec (1, 50);
                    head_color = acc;
                    break;
                case "list-2":
                    t.header_fill = ColorRef.swatch ("Black", 80);
                    t.border_color = ColorRef.swatch ("Black", 20);
                    head_color = ColorRef.PAPER;
                    break;
                case "checkerboard":
                    t.header_fill = main;
                    head_color = ColorRef.PAPER;
                    for (int r = t.header_rows; r < t.rows; r++) for (int col = 0; col < t.cols; col++) if ((r + col) % 2 == 0) t.cells[r][col].fill = ColorScheme.slot_spec (1, 15);
                    break;
                case "header-only":
                    t.header_fill = acc;
                    t.border_color = ColorRef.NONE;
                    t.border_width = 0;
                    head_color = ColorRef.PAPER;
                    break;
                case "boxed":
                    t.border_color = acc;
                    t.border_width = 1.5;
                    t.header_fill = ColorScheme.slot_spec (1, 20);
                    break;
                case "minimal":
                    t.border_color = ColorRef.swatch ("Black", 25);
                    t.border_width = 0.25;
                    head_bold = 1;
                    break;
                case "ledger":
                    t.alt_fill = ColorScheme.slot_spec (3, 12);
                    t.header_fill = ColorScheme.slot_spec (3, 40);
                    t.border_color = ColorScheme.slot_spec (3, 50);
                    break;
                case "invoice":
                    t.header_fill = main;
                    head_color = ColorRef.PAPER;
                    t.border_color = ColorRef.swatch ("Black", 30);
                    for (int col = 0; col < t.cols; col++) t.cells[t.rows - 1][col].fill = ColorScheme.slot_spec (1, 15);
                    break;
                case "price-list":
                    t.header_rows = 0;
                    t.border_color = ColorRef.NONE;
                    t.border_width = 0;
                    t.alt_fill = ColorScheme.slot_spec (2, 12);
                    break;
                case "column-emphasis":
                    t.header_fill = acc;
                    head_color = ColorRef.PAPER;
                    for (int r = t.header_rows; r < t.rows; r++) t.cells[r][0].fill = ColorScheme.slot_spec (1, 20);
                    break;
                case "outline":
                    t.border_color = main;
                    t.border_width = 1;
                    head_bold = 0;
                    break;
            }
            header_text (t, head_color, head_bold);
        }
    }

    public class Autoflow {
        public static int run (Publication pub, int story_id, int max_pages = 500) {
            var frames = pub.thread_frames (story_id);
            if (frames.size == 0) return 0;
            var engine = new TextEngine (pub);
            var res = engine.layout_story (story_id);
            if (!res.overset) return 0;
            var last = frames[frames.size - 1];
            var r = pub.find_item (last.id);
            if (r == null || r.page == null) return 0;
            int page_index = pub.pages.index_of (r.page);
            string master = r.page.master;
            int added = 0;
            var prev = last;
            while (res.overset && added < max_pages) {
                int at = page_index + 1 + added;
                var pg = pub.add_page (at, master);
                var m = pub.margin_rect (at);
                var nf = pub.add_text_frame (pg.items, m.x, m.y, m.w, m.h);
                nf.columns = int.max (1, pub.settings.columns);
                nf.gutter = pub.settings.gutter;
                pub.link_frames (prev, nf);
                prev = nf;
                added++;
                res = engine.layout_story (story_id);
            }
            return added;
        }
    }

    public class BusinessSets {
        public static string path () {
            return Path.build_filename (Environment.get_user_data_dir (), "singularity", "publish", "business-information.ini");
        }

        public static Gee.ArrayList<BusinessInfo> load () {
            var l = new Gee.ArrayList<BusinessInfo> ();
            var kf = new KeyFile ();
            try {
                kf.load_from_file (path (), KeyFileFlags.NONE);
                foreach (string g in kf.get_groups ()) {
                    var b = new BusinessInfo ();
                    b.set_name = g;
                    foreach (string k in BusinessInfo.KEYS) if (kf.has_key (g, k)) b.values[k] = kf.get_string (g, k);
                    l.add (b);
                }
            } catch (Error e) {
            }
            return l;
        }

        public static BusinessInfo? find (string name) {
            foreach (var b in load ()) if (b.set_name == name) return b;
            return null;
        }

        public static void save (BusinessInfo info) throws Error {
            var kf = new KeyFile ();
            try {
                kf.load_from_file (path (), KeyFileFlags.NONE);
            } catch (Error e) {
            }
            if (kf.has_group (info.set_name)) kf.remove_group (info.set_name);
            foreach (string k in BusinessInfo.KEYS) kf.set_string (info.set_name, k, info.get (k));
            DirUtils.create_with_parents (Path.get_dirname (path ()), 0700);
            kf.save_to_file (path ());
        }

        public static void remove (string name) throws Error {
            var kf = new KeyFile ();
            kf.load_from_file (path (), KeyFileFlags.NONE);
            if (kf.has_group (name)) kf.remove_group (name);
            kf.save_to_file (path ());
        }
    }
    public class PicturePlacement {
        public const double SLOT = 120;
        public const double GAP = 12;

        public static Gee.ArrayList<ImageFrame> empty_frames (Gee.List<Item> items) {
            var list = new Gee.ArrayList<ImageFrame> ();
            foreach (var it in items) {
                var im = it as ImageFrame;
                if (im != null && im.media == "" && im.link == "" && im.merge_field == "" && !im.locked) list.add (im);
                var g = it as GroupItem;
                if (g != null) list.add_all (empty_frames (g.children));
            }
            list.sort ((a, b) => {
                if (Math.fabs (a.y - b.y) > 6) return a.y < b.y ? -1 : 1;
                return a.x < b.x ? -1 : (a.x > b.x ? 1 : 0);
            });
            return list;
        }

        public static Rect scratch_slot (Publication pub, Gee.List<Item> items, int n) {
            double x0 = pub.settings.width + 36;
            int used = 0;
            foreach (var it in items) if (it.x >= pub.settings.width) used++;
            int k = used + n;
            return Rect (x0 + (k % 2) * (SLOT + GAP), 36 + (k / 2) * (SLOT + GAP), SLOT, SLOT);
        }
    }
}
